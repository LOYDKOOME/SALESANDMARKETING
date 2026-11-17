# =====================================================================
# HYSSOP PERFORMANCE DASHBOARD v4 (Marketing + Sales RMs + Sales pipeline)
# Read-only. Reads the Google Sheet written by the web forms (Code.gs).
# Money and plots are reported separately, so a week with money in and
# no new plot is shown exactly as it happened.
#
# Environment variables (Posit Connect > Vars, or a local .Renviron):
#   HYSSOP_SHEET_ID  the Google Sheet ID (from its URL)
#   HYSSOP_SA_JSON   service-account key pasted as text (Connect),
#                    or a path to the .json file (local)
# =====================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(shinydashboard)
  library(googlesheets4)
  library(dplyr)
  library(tidyr)
  library(plotly)
  library(DT)
  library(scales)
  library(lubridate)
  library(stringr)
})

# ---------------------------------------------------------------------
# 1. Connection
# ---------------------------------------------------------------------
SHEET_ID <- Sys.getenv("HYSSOP_SHEET_ID", "")
if (!nzchar(SHEET_ID)) stop("Set HYSSOP_SHEET_ID to the Google Sheet ID (see docs/DEPLOYMENT.md).")

SA <- Sys.getenv("HYSSOP_SA_JSON", "")
if (nzchar(SA)) {
  if (file.exists(SA)) {
    gs4_auth(path = SA)
  } else {
    key_file <- tempfile(fileext = ".json")
    writeLines(SA, key_file)
    gs4_auth(path = key_file)
  }
} else if (interactive()) {
  gs4_auth(cache = ".secrets")
} else {
  stop("Set HYSSOP_SA_JSON (service-account key). Share the sheet with that account as Viewer.")
}

# ---------------------------------------------------------------------
# 2. Palette and company rules
# ---------------------------------------------------------------------
NAVY <- "#1F3A5F"; GREEN <- "#2E8B57"; AMBER <- "#E0A100"; RED <- "#C0392B"; GREY <- "#6B7A90"; TEAL <- "#3FA7A3"
PALETTE <- c("#1F3A5F", "#2E8B57", "#E0A100", "#C0392B", "#5B8DB8", "#8E6C8A", "#3FA7A3", "#D17A22", "#7F8C8D")
SCENARIO_COL <- c("Plots and money in" = GREEN, "Plots booked, money not yet in" = NAVY,
                  "Money in, no new plot" = AMBER, "No sales activity" = "#D5DBE3")
NO_PLOT <- "Money in, no new plot"

CAT_WEIGHTS <- list(
  "Faith"                 = c("Leads and site visits" = 40, "Reach and brand growth" = 20, "Engagement" = 20, "Process discipline" = 20),
  "Chege"                 = c("Leads and site visits" = 40, "Reach and brand growth" = 20, "Engagement" = 20, "Process discipline" = 20),
  "Derrick"               = c("Leads and site visits" = 40, "Reach and brand growth" = 20, "Engagement" = 20, "Process discipline" = 20),
  "Dan - Ads"             = c("Leads and site visits" = 40, "Process discipline" = 20),
  "Dan - Website"         = c("Leads and site visits" = 40, "Reach and brand growth" = 20, "Engagement" = 20, "Process discipline" = 20),
  "Marketing Coordinator" = c("Lead handoff" = 30, "Influencer and collaboration" = 20,
                              "Branding assets and sales materials" = 20, "Campaign and content execution" = 15,
                              "Reporting and events" = 15)
)
# KPIs calculated from the lead and visit records. All others are typed in by the admin.
AUTO_RULES <- tribble(
  ~Scorecard,              ~KPI,                           ~Rule,
  "Faith",                 "Leads",                        "leads",
  "Faith",                 "Site visits",                  "visits",
  "Chege",                 "Leads",                        "leads",
  "Chege",                 "Site visits",                  "visits",
  "Derrick",               "Organic leads",                "leads",
  "Derrick",               "Site visits",                  "visits",
  "Dan - Ads",             "Leads (Meta Ads)",             "leads",
  "Dan - Ads",             "Leads qualified",              "qualified_pct",
  "Dan - Ads",             "Site visits (Meta Ads leads)", "visits",
  "Dan - Website",         "Leads (Website)",              "leads",
  "Dan - Website",         "Visitor-to-enquiry rate",      "visitor_rate",
  "Marketing Coordinator", "Leads logged with source",     "source_logged_pct",
  "Marketing Coordinator", "Influencer leads",             "influencer"
)

# ---------------------------------------------------------------------
# 3. Helpers
# ---------------------------------------------------------------------
read_tab <- function(tab) {
  x <- tryCatch(read_sheet(SHEET_ID, sheet = tab, col_types = "c"), error = function(e) NULL)
  if (is.null(x)) tibble() else as_tibble(x)
}
ensure <- function(x, cols) {
  for (cc in cols) if (!cc %in% names(x)) x[[cc]] <- rep(NA_character_, nrow(x))
  x
}
to_date <- function(x) {
  x <- substr(trimws(as.character(x)), 1, 10)
  d <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
  miss <- is.na(d) & !is.na(x) & nzchar(x)
  d[miss] <- suppressWarnings(as.Date(x[miss], tryFormats = c("%d/%m/%Y", "%m/%d/%Y", "%d-%m-%Y")))
  d
}
to_num <- function(x) suppressWarnings(as.numeric(gsub("[^0-9.-]", "", as.character(x))))
blank_to <- function(x, rep) { x <- trimws(as.character(x)); ifelse(is.na(x) | x == "", rep, x) }
canon <- function(x) { x <- trimws(as.character(x)); as.character(ifelse(tolower(x) == "nahasion", "Chege", x)) }
week_of <- function(d) floor_date(d, "week", week_start = 1)
pct <- function(n, d) ifelse(is.na(d) | d == 0, NA_real_, 100 * n / d)
cap120 <- function(x) pmin(120, x)
status_of <- function(att, green = 100, amber = 70) {
  case_when(is.na(att) ~ "No data", att >= green ~ "Green", att >= amber ~ "Amber", TRUE ~ "Red")
}
band_of <- function(score) case_when(is.na(score) ~ "No data", score >= 85 ~ "Green", score >= 70 ~ "Amber", TRUE ~ "Red")
fmt_kes <- function(x) paste("KES", comma(round(x)))
plot_theme <- function(p) {
  p %>%
    layout(font = list(family = "Arial", size = 12, color = "#1f2d3d"),
           paper_bgcolor = "white", plot_bgcolor = "white",
           legend = list(orientation = "h", y = -0.2), margin = list(t = 30, b = 40)) %>%
    config(displaylogo = FALSE, modeBarButtonsToRemove = c("lasso2d", "select2d"))
}
status_style <- function(dt, col) {
  formatStyle(dt, col,
    backgroundColor = styleEqual(c("Green", "Amber", "Red", "No data"), c("#d8f0e1", "#fff1c2", "#f8d7d3", "#eef1f5")),
    color = styleEqual(c("Green", "Amber", "Red", "No data"), c("#1e6b43", "#8a6100", "#9b2a1f", "#6b7a90")),
    fontWeight = "bold")
}
dt_base <- function(x, options = list(), ...) {
  datatable(x, rownames = FALSE, class = "stripe hover compact",
            options = modifyList(list(pageLength = 15, scrollX = TRUE, dom = "tip"), options), ...)
}
empty_plot <- function(msg) plot_ly() %>% layout(annotations = list(text = msg, showarrow = FALSE, font = list(size = 14, color = GREY)))

# Scenario of a set of sales rows (one RM, one company, one week).
scenario_of <- function(plots, collected) {
  case_when(plots > 0 & collected > 0 ~ "Plots and money in",
            plots > 0 ~ "Plots booked, money not yet in",
            collected > 0 ~ NO_PLOT,
            TRUE ~ "No sales activity")
}

# ---------------------------------------------------------------------
# 4. Load and clean every tab
# ---------------------------------------------------------------------
load_all <- function() {
  cfg_t <- read_tab("CONFIG")
  cfg <- if (nrow(cfg_t)) setNames(as.list(cfg_t$Value), cfg_t$Key) else list()
  cv <- function(k, d) { v <- cfg[[k]]; if (is.null(v) || is.na(v) || !nzchar(v)) d else v }
  settings <- list(
    prog_start   = to_date(cv("ProgramStart", NA)),
    rev_target   = as.numeric(cv("RM_Revenue_Target_KES", 1000000)),
    plot_target  = as.numeric(cv("RM_Plots_Target", 3)),
    basis        = cv("Target_Basis", "Best of both"),
    alert_weeks  = as.integer(cv("Alert_Weeks_In_Row", 2)),
    green_min    = as.numeric(cv("Green_Min_Pct", 100)),
    amber_min    = as.numeric(cv("Amber_Min_Pct", 70)),
    program_name = cv("ProgramName", "Hyssop Performance")
  )

  roster <- ensure(read_tab("ROSTER"), c("Name", "Alias", "Group", "Active"))
  rms <- roster %>% filter(Group == "Sales", tolower(Active) != "no") %>% pull(Name)

  smap <- ensure(read_tab("SOURCE_MAP"), c("Lead Source", "Owning Scorecard"))
  src_owner <- setNames(blank_to(smap[["Owning Scorecard"]], "Sales"), blank_to(smap[["Lead Source"]], ""))
  owner_of <- function(src) { o <- unname(src_owner[src]); ifelse(is.na(o) | o == "", "Sales", o) }

  lib <- ensure(read_tab("KPI_LIBRARY"), c("Scorecard", "Employee", "KPI", "Category", "Frequency",
    "Month 1 Target", "Month 2 Target", "Month 3 Target", "Unit", "Direction", "Source"))
  lib <- lib %>% transmute(Scorecard, Employee, KPI, Category, Frequency, Unit,
    M1 = to_num(`Month 1 Target`), M2 = to_num(`Month 2 Target`), M3 = to_num(`Month 3 Target`),
    Lower = str_detect(tolower(Direction), "lower"), Source = blank_to(Source, ""))

  # Sales entries: new bookings (plots) and collections (money with no plot). One row per event.
  se <- ensure(read_tab("SALES_ENTRIES"), c("Entry Date", "Entry Type", "RM", "Client Name", "Project", "Lead Source",
    "Tribe", "Gender", "New Plots Booked", "Booked Value (KES)", "Amount Received (KES)"))
  sales <- tibble(
    Date = to_date(se[["Entry Date"]]), Type = blank_to(se[["Entry Type"]], "New booking"),
    RM = canon(se[["RM"]]), Client = blank_to(se[["Client Name"]], ""),
    Project = blank_to(se[["Project"]], "Unassigned"), Source = blank_to(se[["Lead Source"]], "Other"),
    Tribe = blank_to(se[["Tribe"]], "Not stated"), Gender = blank_to(se[["Gender"]], "Not stated"),
    Plots = replace_na(to_num(se[["New Plots Booked"]]), 0),
    Revenue = replace_na(to_num(se[["Booked Value (KES)"]]), 0),      # booked value of plots
    Collected = replace_na(to_num(se[["Amount Received (KES)"]]), 0)  # money received
  ) %>% filter(!is.na(Date)) %>%
    mutate(Week = week_of(Date), Owner = owner_of(Source),
           Type = ifelse(Plots > 0, "New booking", "Collection (no new plot)"))

  ld <- ensure(read_tab("LEADS"), c("Lead Date", "Lead Name", "Lead Source / Advert", "Project",
    "Lead Status", "Tribe", "Gender", "Assigned RM"))
  leads <- tibble(
    Date = to_date(ld[["Lead Date"]]), Name = tolower(trimws(blank_to(ld[["Lead Name"]], ""))),
    Source = blank_to(ld[["Lead Source / Advert"]], "Other"),
    HasSource = !is.na(ld[["Lead Source / Advert"]]) & nzchar(trimws(ld[["Lead Source / Advert"]])),
    Project = blank_to(ld[["Project"]], "Unassigned"), Status = blank_to(ld[["Lead Status"]], "Amber"),
    Tribe = blank_to(ld[["Tribe"]], "Not stated"), Gender = blank_to(ld[["Gender"]], "Not stated"),
    RM = canon(ld[["Assigned RM"]])
  ) %>% filter(!is.na(Date)) %>%
    mutate(Week = week_of(Date), Owner = owner_of(Source),
           Qualified = Status %in% c("Site visited", "SALES ASSIGNED (RM)", "Sale Closed"),
           Duplicate = duplicated(paste(Name, Project)) & Name != "")

  vs <- ensure(read_tab("SITE_VISITS"), c("Visit Date", "Client Name", "Project", "Lead Source", "Location",
    "RM", "Logistics Person", "Outcome"))
  visits <- tibble(
    Date = to_date(vs[["Visit Date"]]), Client = blank_to(vs[["Client Name"]], ""),
    Project = blank_to(vs[["Project"]], "Unassigned"), Source = blank_to(vs[["Lead Source"]], "Other"),
    Location = blank_to(vs[["Location"]], "Not stated"), RM = canon(vs[["RM"]]),
    Logistics = blank_to(vs[["Logistics Person"]], ""), Outcome = blank_to(vs[["Outcome"]], "Scheduled")
  ) %>% filter(!is.na(Date)) %>%
    mutate(Week = week_of(Date), Owner = owner_of(Source),
           Completed = Outcome %in% c("Completed", "Converted to booking"))

  pr <- ensure(read_tab("PROJECTIONS"), c("Week Starting", "Group", "Employee", "Scorecard", "KPI", "Projected Value", "Unit"))
  proj <- tibble(Week = to_date(pr[["Week Starting"]]), Group = pr[["Group"]], Employee = canon(pr[["Employee"]]),
                 Scorecard = blank_to(pr[["Scorecard"]], ""), KPI = blank_to(pr[["KPI"]], ""),
                 Value = to_num(pr[["Projected Value"]]), Unit = blank_to(pr[["Unit"]], "")) %>%
    filter(!is.na(Week)) %>% mutate(Week = week_of(Week))

  am <- ensure(read_tab("ACTUALS_MARKETING"), c("Week Starting", "Employee", "Scorecard", "KPI", "Actual Value", "Unit"))
  mk_act <- tibble(Week = week_of(to_date(am[["Week Starting"]])), Employee = canon(am[["Employee"]]),
                   Scorecard = blank_to(am[["Scorecard"]], ""), KPI = blank_to(am[["KPI"]], ""),
                   Value = to_num(am[["Actual Value"]]), Unit = blank_to(am[["Unit"]], "")) %>% filter(!is.na(Week))

  asl <- ensure(read_tab("ACTUALS_SALES"), c("Week Starting", "RM", "Calls Made"))
  calls <- tibble(Week = week_of(to_date(asl[["Week Starting"]])), RM = canon(asl[["RM"]]),
                  Calls = to_num(asl[["Calls Made"]])) %>% filter(!is.na(Week))

  mo <- ensure(read_tab("MARKETING_OUTPUT"), c("Week Starting", "Employee", "Platform", "Videos Posted",
    "Pictures Posted", "Reach", "Engagement Rate (%)", "New Followers"))
  output_tbl <- tibble(Week = week_of(to_date(mo[["Week Starting"]])), Employee = canon(mo[["Employee"]]),
                   Platform = blank_to(mo[["Platform"]], "Other"), Videos = replace_na(to_num(mo[["Videos Posted"]]), 0),
                   Pictures = replace_na(to_num(mo[["Pictures Posted"]]), 0), Reach = replace_na(to_num(mo[["Reach"]]), 0),
                   Engagement = to_num(mo[["Engagement Rate (%)"]]), Followers = replace_na(to_num(mo[["New Followers"]]), 0)) %>%
    filter(!is.na(Week))

  al <- ensure(read_tab("ACTION_LOG"), c("Date", "Person", "Issue", "Action Agreed", "Owner", "Due Date", "Status", "Outcome"))
  actions <- tibble(Date = to_date(al[["Date"]]), Person = canon(al[["Person"]]), Issue = al[["Issue"]],
                    Action = al[["Action Agreed"]], Owner = al[["Owner"]], Due = to_date(al[["Due Date"]]),
                    Status = blank_to(al[["Status"]], "Open"), Outcome = al[["Outcome"]]) %>% filter(!is.na(Person))

  list(settings = settings, rms = rms, lib = lib, bookings = sales, leads = leads, visits = visits,
       proj = proj, mk_act = mk_act, calls = calls, output = output_tbl, actions = actions,
       raw_counts = c(sales_entries = nrow(se), leads = nrow(ld), visits = nrow(vs), projections = nrow(pr)),
       src_owner = src_owner)
}

# Calculated KPI for one scorecard over a window of leads and visits.
auto_value <- function(sc, kpi, L, V, visitors = NA) {
  rule <- AUTO_RULES %>% filter(Scorecard == sc, KPI == kpi) %>% pull(Rule)
  if (!length(rule)) return(NA_real_)
  Lo <- L %>% filter(Owner == sc)
  Vo <- V %>% filter(Owner == sc, Completed)
  switch(rule,
    leads = nrow(Lo),
    visits = nrow(Vo),
    qualified_pct = pct(sum(Lo$Qualified), nrow(Lo)),
    visitor_rate = pct(nrow(Lo), visitors),
    source_logged_pct = pct(sum(L$HasSource), nrow(L)),
    influencer = sum(L$Source == "Influencer"),
    NA_real_)
}

agg_manual <- function(vals, unit) {
  if (!length(vals) || all(is.na(vals))) return(NA_real_)
  if (unit %in% c("%", "hours", "KES", "per week", "per day")) mean(vals, na.rm = TRUE) else sum(vals, na.rm = TRUE)
}

# ---------------------------------------------------------------------
# 5. Core calculations
# ---------------------------------------------------------------------
# RM by week. Revenue = the money measure chosen in CONFIG (Booked value, Collected, or the higher of both).
rm_weekly <- function(D, weeks, project = "All") {
  B <- D$bookings; L <- D$leads %>% filter(!Duplicate); V <- D$visits
  if (project != "All") { B <- B %>% filter(Project == project); L <- L %>% filter(Project == project); V <- V %>% filter(Project == project) }
  grid <- expand_grid(RM = D$rms, Week = weeks)
  act <- B %>% group_by(RM, Week) %>% summarise(Booked = sum(Revenue), Collected = sum(Collected), Plots = sum(Plots), .groups = "drop")
  lh  <- L %>% filter(RM != "") %>% group_by(RM, Week) %>% summarise(Leads = n(), .groups = "drop")
  vi  <- V %>% filter(Completed) %>% group_by(RM, Week) %>% summarise(Visits = n(), .groups = "drop")
  ca  <- D$calls %>% group_by(RM, Week) %>% summarise(Calls = sum(Calls), .groups = "drop")
  pj  <- D$proj %>% filter(Group == "Sales") %>% group_by(Employee, Week, KPI) %>%
           summarise(Value = max(Value, na.rm = TRUE), .groups = "drop") %>%
           pivot_wider(names_from = KPI, values_from = Value) %>% rename(RM = Employee)
  out <- grid %>% left_join(act, by = c("RM", "Week")) %>% left_join(lh, by = c("RM", "Week")) %>%
    left_join(vi, by = c("RM", "Week")) %>% left_join(ca, by = c("RM", "Week")) %>% left_join(pj, by = c("RM", "Week"))
  for (cc in c("Booked", "Collected", "Plots", "Leads", "Visits", "Calls")) out[[cc]] <- replace_na(out[[cc]], 0)
  for (cc in c("Money collected (KES)", "Booked value (KES)", "Plots booked", "Calls made",
               "Site visits conducted", "Personal leads handled")) {
    if (!cc %in% names(out)) out[[cc]] <- NA_real_
  }
  basis <- D$settings$basis
  out %>% mutate(
    Revenue = if (basis == "Collected") Collected else if (basis == "Booked value") Booked else pmax(Booked, Collected),
    NoPlotCollected = ifelse(Plots == 0, Collected, 0),
    Attainment = pmin(120, 100 * pmax(Revenue / D$settings$rev_target, Plots / D$settings$plot_target)),
    Status = status_of(Attainment, D$settings$green_min, D$settings$amber_min),
    Scenario = scenario_of(Plots, Collected),
    Complete = Week < week_of(Sys.Date()),
    RedWeek = Complete & Status == "Red"
  ) %>% arrange(RM, Week) %>% group_by(RM) %>%
    mutate(RedRun = { r <- as.integer(RedWeek); o <- integer(length(r))
                      for (i in seq_along(r)) o[i] <- if (r[i] == 1) (if (i > 1) o[i - 1] else 0L) + 1L else 0L
                      o }) %>% ungroup()
}

# Company week by week: what happened (plots, booked value, money in, money with no plot).
week_story <- function(B, weeks) {
  # NoPlot must come first: later summarise() columns would overwrite Plots and Collected before it is evaluated.
  s <- B %>% group_by(Week) %>% summarise(NoPlot = sum(Collected[Plots == 0]), Plots = sum(Plots),
                                          Booked = sum(Revenue), Collected = sum(Collected), .groups = "drop")
  rm_money_only <- B %>% group_by(RM, Week) %>% summarise(p = sum(Plots), c = sum(Collected), .groups = "drop") %>%
    filter(p == 0, c > 0) %>% count(Week, name = "RMsMoneyOnly")
  tibble(Week = weeks) %>% left_join(s, by = "Week") %>% left_join(rm_money_only, by = "Week") %>%
    replace_na(list(Plots = 0, Booked = 0, Collected = 0, NoPlot = 0, RMsMoneyOnly = 0)) %>%
    mutate(Scenario = scenario_of(Plots, Collected), Complete = Week < week_of(Sys.Date()))
}

# Monthly marketing scorecards (measure A).
marketing_scores <- function(D, month_idx, from, to) {
  L <- D$leads %>% filter(!Duplicate, Date >= from, Date <= to)
  V <- D$visits %>% filter(Date >= from, Date <= to)
  acts <- D$mk_act %>% filter(Week >= week_of(from), Week <= to)
  tgt_col <- c("M1", "M2", "M3")[min(month_idx, 3)]
  visitors <- sum(acts$Value[acts$Scorecard == "Dan - Website" & acts$KPI == "Website visitors"], na.rm = TRUE)
  rows <- list()
  for (sc in names(CAT_WEIGHTS)) {
    lib_sc <- D$lib %>% filter(Scorecard == sc)
    for (i in seq_len(nrow(lib_sc))) {
      k <- lib_sc[i, ]
      tgt <- k[[tgt_col]]
      if (is.na(tgt)) next
      if (grepl("^auto", k$Source, ignore.case = TRUE)) {
        vis <- if (sc == "Dan - Website" && k$KPI == "Visitor-to-enquiry rate") visitors else NA
        act_val <- auto_value(sc, k$KPI, L, V, visitors = vis)
      } else {
        act_val <- agg_manual(acts$Value[acts$Scorecard == sc & acts$KPI == k$KPI], k$Unit)
      }
      att <- if (is.na(act_val)) 0 else if (k$Lower) { if (act_val == 0) 120 else cap120(100 * tgt / act_val) } else cap120(pct(act_val, tgt))
      rows[[length(rows) + 1]] <- tibble(Scorecard = sc, Category = k$Category, KPI = k$KPI, Unit = k$Unit,
        Target = tgt, Actual = act_val, Attainment = round(att, 1), HasData = !is.na(act_val))
    }
  }
  kpi <- bind_rows(rows)
  if (!nrow(kpi)) return(list(kpi = kpi, scores = tibble()))
  cat_att <- kpi %>% group_by(Scorecard, Category) %>% summarise(CatAtt = mean(Attainment), .groups = "drop")
  scores <- cat_att %>% rowwise() %>% mutate(W = CAT_WEIGHTS[[Scorecard]][Category]) %>% ungroup() %>%
    group_by(Scorecard) %>% summarise(Score = sum(CatAtt * W, na.rm = TRUE) / sum(W, na.rm = TRUE), .groups = "drop")
  nodata <- kpi %>% group_by(Scorecard) %>% summarise(KPIs = n(), `No data` = sum(!HasData), .groups = "drop")
  scores <- scores %>% left_join(nodata, by = "Scorecard") %>% mutate(Band = band_of(Score), Score = round(Score, 1))
  if (all(c("Dan - Ads", "Dan - Website") %in% scores$Scorecard)) {
    a <- scores$Score[scores$Scorecard == "Dan - Ads"]; w <- scores$Score[scores$Scorecard == "Dan - Website"]
    comb <- round(0.7 * a + 0.3 * w, 1)
    scores <- bind_rows(scores, tibble(Scorecard = "Dan (combined 70/30)", Score = comb, KPIs = NA_integer_,
                                       `No data` = NA_integer_, Band = band_of(comb)))
  }
  list(kpi = kpi, scores = scores)
}

# ---------------------------------------------------------------------
# 6. UI
# ---------------------------------------------------------------------
ui <- dashboardPage(
  skin = "blue",
  dashboardHeader(title = "Hyssop Performance", titleWidth = 260),
  dashboardSidebar(width = 260,
    dateRangeInput("period", "Period", start = Sys.Date() - 90, end = Sys.Date(), format = "dd M yyyy"),
    selectInput("project", "Project", choices = "All"),
    selectInput("grain", "Compare by", choices = c("Week", "Month", "Quarter"), selected = "Week"),
    actionButton("refresh", "Refresh data", icon = icon("sync"), width = "90%"),
    tags$hr(),
    sidebarMenu(id = "tabs",
      menuItem("Executive dashboard", tabName = "exec", icon = icon("tachometer-alt")),
      menuItem("Sales and collections", tabName = "sales", icon = icon("handshake")),
      menuItem("RM profiles", tabName = "profiles", icon = icon("id-card")),
      menuItem("Projects and analysis", tabName = "projects", icon = icon("building")),
      menuItem("Marketing dashboard", tabName = "mkt", icon = icon("bullhorn")),
      menuItem("Alerts and actions", tabName = "alerts", icon = icon("exclamation-triangle")),
      menuItem("Data health and library", tabName = "health", icon = icon("stethoscope"))
    )
  ),
  dashboardBody(
    tags$head(tags$style(HTML("
      .content-wrapper, .right-side { background: #f3f6fa; }
      .box { border-radius: 10px; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
      .small-box h3 { font-size: 26px; }
      .alert-red { background:#fbeaea; border-left:5px solid #C0392B; padding:10px 14px; margin-bottom:8px; border-radius:6px; }
      .alert-amber { background:#fff6dc; border-left:5px solid #E0A100; padding:10px 14px; margin-bottom:8px; border-radius:6px; }
      .alert-green { background:#e7f5ec; border-left:5px solid #2E8B57; padding:10px 14px; margin-bottom:8px; border-radius:6px; }
      .stamp { color:#6b7a90; font-size:12px; margin:4px 0 10px; }
    "))),
    textOutput("stamp"),
    tabItems(
      # ---------------- Executive ----------------
      tabItem("exec",
        fluidRow(valueBoxOutput("vb_collected", 3), valueBoxOutput("vb_booked", 3),
                 valueBoxOutput("vb_plots", 3), valueBoxOutput("vb_nomoney", 3)),
        fluidRow(valueBoxOutput("vb_leads", 3), valueBoxOutput("vb_visits", 3),
                 valueBoxOutput("vb_conv", 3), valueBoxOutput("vb_flags", 3)),
        fluidRow(
          box(title = "Weekly performance: booked value and money collected (bars), new plots (line), projected money (dashed)",
              width = 8, status = "primary", solidHeader = TRUE, plotlyOutput("p_trend", height = 340)),
          box(title = "Alerts: underperforming 2+ weeks in a row", width = 4, status = "danger", solidHeader = TRUE,
              uiOutput("alert_panel"))),
        fluidRow(
          box(title = "What happened each week (company)", width = 7, status = "primary", solidHeader = TRUE,
              DTOutput("t_story")),
          box(title = "Each RM's week: scenario count", width = 5, plotlyOutput("p_scen", height = 380))),
        fluidRow(
          box(title = "Leads by project", width = 4, plotlyOutput("p_leads_proj", height = 280)),
          box(title = "New plots booked by project", width = 4, plotlyOutput("p_plots_proj", height = 280)),
          box(title = "Money collected by project", width = 4, plotlyOutput("p_money_proj", height = 280))),
        fluidRow(
          box(title = "Booked value and money collected by RM (selected period)", width = 6, plotlyOutput("p_rm_rev", height = 340)),
          box(title = "Funnel: leads, visits and plots", width = 6, plotlyOutput("p_funnel", height = 340)))
      ),
      # ---------------- Sales ----------------
      tabItem("sales",
        fluidRow(box(title = "RM league table (status uses the target measure set in CONFIG)", width = 12,
                     status = "primary", solidHeader = TRUE, DTOutput("t_league"))),
        fluidRow(box(title = "Attainment heatmap: each RM by completed week", width = 12, plotlyOutput("p_heat", height = 460))),
        fluidRow(box(title = "Projection against actual by RM (selected period)", width = 12, DTOutput("t_proj_vs_act")))
      ),
      # ---------------- Profiles ----------------
      tabItem("profiles",
        fluidRow(box(title = "Choose an RM", width = 12, selectInput("rm_pick", NULL, choices = NULL, width = "360px"))),
        fluidRow(valueBoxOutput("pf_collected", 3), valueBoxOutput("pf_booked", 3),
                 valueBoxOutput("pf_plots", 3), valueBoxOutput("pf_status", 3)),
        fluidRow(
          box(title = "Weekly booked value, money collected and plots against projection", width = 7, plotlyOutput("p_pf_trend", height = 340)),
          box(title = "Funnel for this RM", width = 5, plotlyOutput("p_pf_funnel", height = 340))),
        fluidRow(box(title = "Weekly record (what happened, actual, projected, status)", width = 12, DTOutput("t_pf_weeks"))),
        fluidRow(box(title = "Follow-up history (ACTION_LOG)", width = 12, DTOutput("t_pf_actions")))
      ),
      # ---------------- Projects ----------------
      tabItem("projects",
        fluidRow(box(title = "Money collected by project per week (stacked)", width = 12, plotlyOutput("p_proj_week", height = 320))),
        fluidRow(box(title = "Project summary (plots, booked value, money in, money with no plot)", width = 12, DTOutput("t_proj"))),
        fluidRow(
          box(title = "Plots by tribe", width = 4, plotlyOutput("p_tribe", height = 300)),
          box(title = "Plots by gender", width = 4, plotlyOutput("p_gender", height = 300)),
          box(title = "Plots by lead source", width = 4, plotlyOutput("p_src", height = 300))),
        fluidRow(
          box(title = "Money collected by tribe", width = 6, plotlyOutput("p_tribe_money", height = 300)),
          box(title = "Money collected by gender", width = 6, plotlyOutput("p_gender_money", height = 300))),
        fluidRow(box(title = "Completed site visits by location", width = 12, plotlyOutput("p_loc", height = 260)))
      ),
      # ---------------- Marketing ----------------
      tabItem("mkt",
        fluidRow(
          box(title = "Monthly scorecard (approved KPIs). Green 85+ bonus-eligible, amber 70 to 84, red below 70",
              width = 6, plotlyOutput("p_mk_scores", height = 300)),
          box(title = "Choose month and scorecard", width = 6,
              selectInput("mk_month", "Program month", choices = 1:3, selected = 1),
              selectInput("mk_who", "Scorecard", choices = "All"))),
        fluidRow(box(title = "KPI detail against approved targets", width = 12, DTOutput("t_mk_kpi"))),
        fluidRow(box(title = "Weekly commitment vs actual (measure B, kept separate)", width = 12, plotlyOutput("p_mk_commit", height = 300))),
        fluidRow(
          box(title = "Sales from each digital source owner (plots and money collected)", width = 6, plotlyOutput("p_mk_sales", height = 300)),
          box(title = "Marketing output by platform (videos and reach)", width = 6, plotlyOutput("p_mk_output", height = 300))),
        fluidRow(box(title = "Leads by owning source", width = 12, plotlyOutput("p_mk_leads", height = 260)))
      ),
      # ---------------- Alerts ----------------
      tabItem("alerts",
        fluidRow(box(title = "RMs below target in each completed week (red = below 70%)", width = 12,
                     status = "danger", solidHeader = TRUE, DTOutput("t_alerts"))),
        fluidRow(box(title = "Action log (agreed actions and outcomes)", width = 12, DTOutput("t_actions")))
      ),
      # ---------------- Health ----------------
      tabItem("health",
        fluidRow(box(title = "Data checks", width = 12, DTOutput("t_health"))),
        fluidRow(box(title = "Approved KPI library (read-only)", width = 12, DTOutput("t_lib")))
      )
    )
  )
)

# ---------------------------------------------------------------------
# 7. Server
# ---------------------------------------------------------------------
server <- function(input, output, session) {

  D <- reactive({
    input$refresh
    tryCatch(load_all(), error = function(e) { showNotification(paste("Load failed:", e$message), type = "error", duration = NULL); NULL })
  })

  observe({
    d <- D(); req(d)
    projs <- sort(unique(c(d$bookings$Project, d$leads$Project, d$visits$Project)))
    updateSelectInput(session, "project", choices = c("All", projs[projs != "Unassigned"]))
    updateSelectInput(session, "rm_pick", choices = d$rms, selected = d$rms[1])
    updateSelectInput(session, "mk_who", choices = c("All", unique(d$lib$Scorecard)))
    all_dates <- c(d$bookings$Date, d$leads$Date, d$visits$Date)
    if (length(all_dates)) {
      updateDateRangeInput(session, "period",
        start = if (!is.na(d$settings$prog_start)) d$settings$prog_start else min(all_dates, na.rm = TRUE),
        end = max(max(all_dates, na.rm = TRUE), Sys.Date()))
    }
  })

  output$stamp <- renderText({
    d <- D(); req(d)
    paste0("Refreshed ", format(Sys.time(), "%d %b %Y %H:%M"), " | ", d$settings$program_name,
           " | Money measure for RM targets: ", d$settings$basis, " | Source: Google Sheet (written by the forms).")
  })

  F <- reactive({
    d <- D(); req(d, input$period)
    from <- as.Date(input$period[1]); to <- as.Date(input$period[2])
    p <- input$project
    fl <- function(x, col = "Date") {
      x <- x %>% filter(.data[[col]] >= from, .data[[col]] <= to)
      if (p != "All" && "Project" %in% names(x)) x <- x %>% filter(Project == p)
      x
    }
    B <- fl(d$bookings); L <- fl(d$leads) %>% filter(!Duplicate); V <- fl(d$visits)
    weeks <- seq(week_of(from), week_of(to), by = "week")
    list(d = d, B = B, L = L, V = V, from = from, to = to, project = p, weeks = weeks,
         rmw = rm_weekly(list(bookings = d$bookings, leads = d$leads, visits = d$visits, calls = d$calls,
                              proj = d$proj, rms = d$rms, settings = d$settings), weeks, p),
         story = week_story(B, weeks))
  })

  period_key <- function(x, grain) switch(grain, Week = week_of(x), Month = floor_date(x, "month"), Quarter = floor_date(x, "quarter"))

  flagged_rms <- reactive({
    f <- F()
    latest <- f$rmw %>% filter(Complete) %>% group_by(RM) %>% slice_tail(n = 1) %>% ungroup()
    latest %>% filter(RedRun >= f$d$settings$alert_weeks)
  })

  # ---------- Executive ----------
  output$vb_collected <- renderValueBox(valueBox(fmt_kes(sum(F()$B$Collected)), "Money collected (all sources)",
                                                 icon = icon("money-bill-wave"), color = "green"))
  output$vb_booked <- renderValueBox(valueBox(fmt_kes(sum(F()$B$Revenue)), "Booked value of new plots",
                                              icon = icon("file-invoice-dollar"), color = "blue"))
  output$vb_plots <- renderValueBox(valueBox(sum(F()$B$Plots), "New plots booked", icon = icon("map"), color = "navy"))
  output$vb_nomoney <- renderValueBox({
    x <- sum(F()$B$Collected[F()$B$Plots == 0])
    valueBox(fmt_kes(x), "Money in with no new plot (existing clients)", icon = icon("hand-holding-usd"), color = "yellow")
  })
  output$vb_leads <- renderValueBox(valueBox(nrow(F()$L), "Leads (duplicates excluded)", icon = icon("users"), color = "aqua"))
  output$vb_visits <- renderValueBox(valueBox(sum(F()$V$Completed), "Site visits completed", icon = icon("map-marker-alt"), color = "yellow"))
  output$vb_conv <- renderValueBox({
    v <- replace_na(pct(sum(F()$B$Plots), nrow(F()$L)), 0)
    valueBox(paste0(round(v, 1), "%"), "Plots per lead (target 1 in 15 = 6.7%)", icon = icon("bullseye"), color = "purple")
  })
  output$vb_flags <- renderValueBox({
    n <- nrow(flagged_rms())
    valueBox(n, paste0("RMs underperforming ", F()$d$settings$alert_weeks, "+ weeks in a row"),
             icon = icon("exclamation-triangle"), color = if (n > 0) "red" else "green")
  })

  output$p_trend <- renderPlotly({
    f <- F(); grain <- input$grain
    b <- f$B %>% mutate(P = period_key(Date, grain)) %>% group_by(P) %>%
      summarise(Booked = sum(Revenue), Collected = sum(Collected), Plots = sum(Plots), .groups = "drop")
    pr <- f$d$proj %>% filter(Group == "Sales", KPI == "Money collected (KES)", Week >= week_of(f$from), Week <= f$to) %>%
      group_by(P = period_key(Week, grain)) %>% summarise(Projected = sum(Value), .groups = "drop")
    x <- full_join(b, pr, by = "P") %>% arrange(P) %>% replace_na(list(Booked = 0, Collected = 0, Plots = 0))
    if (!nrow(x)) return(empty_plot("No sales in this period."))
    plot_ly(x, x = ~P) %>%
      add_bars(y = ~Booked, name = "Booked value (KES)", marker = list(color = NAVY)) %>%
      add_bars(y = ~Collected, name = "Money collected (KES)", marker = list(color = GREEN)) %>%
      add_lines(y = ~Projected, name = "Projected money (KES)", line = list(color = AMBER, dash = "dash")) %>%
      add_lines(y = ~Plots, name = "New plots", yaxis = "y2", line = list(color = "#8E6C8A", width = 3), marker = list(size = 8)) %>%
      layout(barmode = "group", yaxis = list(title = "KES", tickformat = ","),
             yaxis2 = list(title = "Plots", overlaying = "y", side = "right"), xaxis = list(title = NULL)) %>% plot_theme()
  })

  output$alert_panel <- renderUI({
    f <- F(); flags <- flagged_rms()
    if (!nrow(flags)) return(tags$div(class = "alert-green", "No RM is red for 2 or more completed weeks in a row."))
    lapply(seq_len(nrow(flags)), function(i) {
      r <- flags[i, ]
      tags$div(class = "alert-red", tags$b(r$RM),
        paste0(" is below target for ", r$RedRun, " weeks in a row. Plots ", r$Plots, " (target ", f$d$settings$plot_target,
               "); booked KES ", comma(round(r$Booked)), "; collected KES ", comma(round(r$Collected)), "."))
    })
  })

  output$t_story <- renderDT({
    s <- F()$story %>% arrange(desc(Week)) %>%
      transmute(Week = format(Week, "%d %b %Y"), `New plots` = Plots, `Booked value (KES)` = round(Booked),
                `Money collected (KES)` = round(Collected),
                `Of which: no new plot (KES)` = round(NoPlot),
                `RMs with money but no new plot` = RMsMoneyOnly, `What happened` = Scenario,
                Complete = ifelse(Complete, "Yes", "In progress"))
    dt_base(s, options = list(pageLength = 12, dom = "tip")) %>%
      formatCurrency(c("Booked value (KES)", "Money collected (KES)", "Of which: no new plot (KES)"), currency = "KES ", digits = 0) %>%
      formatStyle("What happened", color = styleEqual(names(SCENARIO_COL), c("#1e6b43", "#1F3A5F", "#8a6100", "#6b7a90")), fontWeight = "bold")
  })

  output$p_scen <- renderPlotly({
    x <- F()$rmw %>% filter(Complete) %>% count(Week, Scenario, name = "RMs")
    if (!nrow(x)) return(empty_plot("No completed weeks in this period."))
    plot_ly(x, x = ~Week, y = ~RMs, color = ~Scenario, type = "bar", colors = SCENARIO_COL) %>%
      layout(barmode = "stack", xaxis = list(title = NULL), yaxis = list(title = "RMs")) %>% plot_theme()
  })

  output$p_leads_proj <- renderPlotly({
    x <- F()$L %>% count(Project, name = "V") %>% arrange(desc(V)); if (!nrow(x)) return(empty_plot("No leads."))
    plot_ly(x, x = ~V, y = ~reorder(Project, V), type = "bar", orientation = "h", marker = list(color = NAVY)) %>%
      layout(xaxis = list(title = "Leads"), yaxis = list(title = NULL)) %>% plot_theme()
  })
  output$p_plots_proj <- renderPlotly({
    x <- F()$B %>% group_by(Project) %>% summarise(V = sum(Plots), .groups = "drop") %>% arrange(desc(V))
    if (!nrow(x)) return(empty_plot("No plots booked."))
    plot_ly(x, x = ~V, y = ~reorder(Project, V), type = "bar", orientation = "h", marker = list(color = GREEN)) %>%
      layout(xaxis = list(title = "Plots"), yaxis = list(title = NULL)) %>% plot_theme()
  })
  output$p_money_proj <- renderPlotly({
    x <- F()$B %>% group_by(Project) %>% summarise(V = sum(Collected), .groups = "drop") %>% arrange(desc(V))
    if (!nrow(x)) return(empty_plot("No money collected."))
    plot_ly(x, x = ~V, y = ~reorder(Project, V), type = "bar", orientation = "h", marker = list(color = AMBER)) %>%
      layout(xaxis = list(title = "KES", tickformat = ","), yaxis = list(title = NULL)) %>% plot_theme()
  })
  output$p_rm_rev <- renderPlotly({
    x <- F()$B %>% group_by(RM) %>% summarise(Booked = sum(Revenue), Collected = sum(Collected), .groups = "drop") %>%
      arrange(desc(Booked + Collected))
    if (!nrow(x)) return(empty_plot("No sales in this period."))
    plot_ly(x, x = ~RM, y = ~Booked, type = "bar", name = "Booked value", marker = list(color = NAVY)) %>%
      add_bars(y = ~Collected, name = "Money collected", marker = list(color = GREEN)) %>%
      layout(barmode = "group", xaxis = list(title = NULL), yaxis = list(title = "KES", tickformat = ",")) %>% plot_theme()
  })
  output$p_funnel <- renderPlotly({
    f <- F()
    st <- data.frame(Stage = c("Leads", "Visits completed", "Plots booked"),
                     N = c(nrow(f$L), sum(f$V$Completed), sum(f$B$Plots)))
    plot_ly(st, type = "funnel", y = ~Stage, x = ~N, textinfo = "value+percent initial",
            marker = list(color = c(NAVY, AMBER, GREEN))) %>% plot_theme()
  })

  # ---------- Sales ----------
  output$t_league <- renderDT({
    r <- F()$rmw %>% filter(Complete) %>% group_by(RM) %>%
      summarise(`Weeks reported` = n(), `New plots` = sum(Plots), `Booked value (KES)` = round(sum(Booked)),
                `Money collected (KES)` = round(sum(Collected)), `Money with no plot (KES)` = round(sum(NoPlotCollected)),
                Leads = sum(Leads), Visits = sum(Visits), `Latest status` = last(Status),
                `Latest scenario` = last(Scenario), `Red streak (weeks)` = last(RedRun), .groups = "drop") %>%
      arrange(desc(`Money collected (KES)`))
    dt_base(r, options = list(pageLength = 25)) %>%
      formatCurrency(c("Booked value (KES)", "Money collected (KES)", "Money with no plot (KES)"), currency = "KES ", digits = 0) %>%
      status_style("Latest status")
  })
  output$p_heat <- renderPlotly({
    x <- F()$rmw %>% filter(Complete) %>% select(RM, Week, Attainment)
    if (!nrow(x)) return(empty_plot("No completed weeks in this period."))
    m <- x %>% pivot_wider(names_from = Week, values_from = Attainment) %>% arrange(RM)
    z <- as.matrix(m[, -1]); rownames(z) <- m$RM
    plot_ly(x = colnames(z), y = rownames(z), z = z, type = "heatmap",
            colorscale = list(list(0, RED), list(0.5833, RED), list(0.5834, AMBER), list(0.8333, AMBER),
                              list(0.8334, GREEN), list(1, GREEN)), zmin = 0, zmax = 120,
            colorbar = list(title = "% of target"), hovertemplate = "%{y}, week %{x}: %{z:.0f}%<extra></extra>") %>%
      layout(xaxis = list(title = "Week starting"), yaxis = list(title = NULL, autorange = "reversed")) %>% plot_theme()
  })
  output$t_proj_vs_act <- renderDT({
    r <- F()$rmw %>% group_by(RM) %>%
      summarise(`Projected money (KES)` = sum(`Money collected (KES)`, na.rm = TRUE), `Actual money collected (KES)` = sum(Collected),
                `Projected booked (KES)` = sum(`Booked value (KES)`, na.rm = TRUE), `Actual booked (KES)` = sum(Booked),
                `Projected plots` = sum(`Plots booked`, na.rm = TRUE), `Actual plots` = sum(Plots),
                `Projected calls` = sum(`Calls made`, na.rm = TRUE), `Actual calls` = sum(Calls), .groups = "drop") %>%
      mutate(`Money vs projection %` = round(pct(`Actual money collected (KES)`, `Projected money (KES)`), 1),
             `Plots vs projection %` = round(pct(`Actual plots`, `Projected plots`), 1))
    dt_base(r, options = list(pageLength = 25)) %>%
      formatCurrency(c("Projected money (KES)", "Actual money collected (KES)", "Projected booked (KES)", "Actual booked (KES)"),
                     currency = "KES ", digits = 0)
  })

  # ---------- Profiles ----------
  PF <- reactive({
    f <- F(); req(input$rm_pick); rm <- input$rm_pick
    list(B = f$B %>% filter(RM == rm), V = f$V %>% filter(RM == rm), w = f$rmw %>% filter(RM == rm))
  })
  output$pf_collected <- renderValueBox(valueBox(fmt_kes(sum(PF()$B$Collected)), "Money collected in period", color = "green", icon = icon("money-bill")))
  output$pf_booked <- renderValueBox(valueBox(fmt_kes(sum(PF()$B$Revenue)), "Booked value of new plots", color = "blue", icon = icon("file-invoice-dollar")))
  output$pf_plots <- renderValueBox(valueBox(sum(PF()$B$Plots), "New plots booked", color = "navy", icon = icon("map")))
  output$pf_status <- renderValueBox({
    r <- PF()$w %>% filter(Complete) %>% slice_tail(n = 1)
    st <- if (nrow(r)) r$Status else "No data"
    colr <- switch(st, Green = "green", Amber = "yellow", Red = "red", "light-blue")
    valueBox(paste0(st, if (nrow(r)) paste0(" (", round(r$Attainment), "%)") else ""),
             if (nrow(r)) paste("Latest week:", r$Scenario) else "Latest completed week", color = colr, icon = icon("flag"))
  })
  output$p_pf_trend <- renderPlotly({
    w <- PF()$w; if (!nrow(w)) return(empty_plot("No data for this RM."))
    plot_ly(w, x = ~Week) %>%
      add_bars(y = ~Booked, name = "Booked value", marker = list(color = NAVY)) %>%
      add_bars(y = ~Collected, name = "Money collected", marker = list(color = GREEN)) %>%
      add_lines(y = ~`Money collected (KES)`, name = "Projected money", line = list(color = AMBER, dash = "dash")) %>%
      add_lines(y = ~Plots, name = "New plots", yaxis = "y2", line = list(color = "#8E6C8A", width = 3)) %>%
      add_lines(y = ~`Plots booked`, name = "Projected plots", yaxis = "y2", line = list(color = GREY, dash = "dot")) %>%
      layout(barmode = "group", yaxis = list(title = "KES", tickformat = ","),
             yaxis2 = list(title = "Plots", overlaying = "y", side = "right"), xaxis = list(title = NULL)) %>% plot_theme()
  })
  output$p_pf_funnel <- renderPlotly({
    p <- PF()
    st <- data.frame(Stage = c("Leads handled", "Visits completed", "Plots booked"),
                     N = c(sum(p$w$Leads), sum(p$V$Completed), sum(p$B$Plots)))
    plot_ly(st, type = "funnel", y = ~Stage, x = ~N, textinfo = "value+percent initial",
            marker = list(color = c(NAVY, AMBER, GREEN))) %>% plot_theme()
  })
  output$t_pf_weeks <- renderDT({
    w <- PF()$w %>% arrange(desc(Week)) %>%
      transmute(Week = format(Week, "%d %b %Y"), `What happened` = Scenario, `New plots` = Plots,
                `Plots projected` = `Plots booked`, `Booked value (KES)` = round(Booked),
                `Money collected (KES)` = round(Collected), `Money projected (KES)` = `Money collected (KES)`,
                Leads, Visits, Calls, `Attainment %` = round(Attainment, 1), Status, Complete)
    dt_base(w, options = list(pageLength = 15)) %>%
      formatCurrency(c("Booked value (KES)", "Money collected (KES)", "Money projected (KES)"), currency = "KES ", digits = 0) %>%
      status_style("Status")
  })
  output$t_pf_actions <- renderDT({
    dt_base(F()$d$actions %>% filter(Person == input$rm_pick) %>% arrange(desc(Date)), options = list(pageLength = 10))
  })

  # ---------- Projects ----------
  output$p_proj_week <- renderPlotly({
    x <- F()$B %>% group_by(Week, Project) %>% summarise(Money = sum(Collected), .groups = "drop")
    if (!nrow(x)) return(empty_plot("No money collected in this period."))
    plot_ly(x, x = ~Week, y = ~Money, color = ~Project, type = "bar", colors = PALETTE) %>%
      layout(barmode = "stack", yaxis = list(title = "Money collected (KES)", tickformat = ","), xaxis = list(title = NULL)) %>% plot_theme()
  })
  output$t_proj <- renderDT({
    f <- F()
    x <- f$B %>% group_by(Project) %>%
      summarise(`New plots` = sum(Plots), `Booked value (KES)` = sum(Revenue), `Money collected (KES)` = sum(Collected),
                `Money with no plot (KES)` = sum(Collected[Plots == 0]), .groups = "drop") %>%
      left_join(f$L %>% count(Project, name = "Leads"), by = "Project") %>%
      left_join(f$V %>% filter(Completed) %>% count(Project, name = "Visits"), by = "Project") %>%
      replace_na(list(Leads = 0, Visits = 0)) %>% arrange(desc(`Money collected (KES)`))
    dt_base(x, options = list(pageLength = 15)) %>%
      formatCurrency(c("Booked value (KES)", "Money collected (KES)", "Money with no plot (KES)"), currency = "KES ", digits = 0)
  })
  output$p_tribe <- renderPlotly({
    x <- F()$B %>% group_by(Tribe) %>% summarise(Plots = sum(Plots), .groups = "drop") %>% filter(Plots > 0)
    if (!nrow(x)) return(empty_plot("No plots booked."))
    plot_ly(x, labels = ~Tribe, values = ~Plots, type = "pie", hole = 0.5, marker = list(colors = PALETTE)) %>% plot_theme()
  })
  output$p_gender <- renderPlotly({
    x <- F()$B %>% group_by(Gender) %>% summarise(Plots = sum(Plots), .groups = "drop") %>% filter(Plots > 0)
    if (!nrow(x)) return(empty_plot("No plots booked."))
    plot_ly(x, labels = ~Gender, values = ~Plots, type = "pie", hole = 0.5, marker = list(colors = c(NAVY, GREEN, AMBER))) %>% plot_theme()
  })
  output$p_src <- renderPlotly({
    x <- F()$B %>% group_by(Source) %>% summarise(Plots = sum(Plots), Money = sum(Collected), .groups = "drop") %>%
      arrange(desc(Plots + Money / 1e6))
    if (!nrow(x)) return(empty_plot("No sales."))
    plot_ly(x, x = ~Plots, y = ~reorder(Source, Plots), type = "bar", orientation = "h", marker = list(color = NAVY)) %>%
      layout(xaxis = list(title = "New plots"), yaxis = list(title = NULL)) %>% plot_theme()
  })
  output$p_tribe_money <- renderPlotly({
    x <- F()$B %>% group_by(Tribe) %>% summarise(Money = sum(Collected), .groups = "drop") %>% filter(Money > 0)
    if (!nrow(x)) return(empty_plot("No money collected."))
    plot_ly(x, x = ~Tribe, y = ~Money, type = "bar", marker = list(color = GREEN)) %>%
      layout(yaxis = list(title = "KES", tickformat = ",")) %>% plot_theme()
  })
  output$p_gender_money <- renderPlotly({
    x <- F()$B %>% group_by(Gender) %>% summarise(Money = sum(Collected), .groups = "drop") %>% filter(Money > 0)
    if (!nrow(x)) return(empty_plot("No money collected."))
    plot_ly(x, labels = ~Gender, values = ~Money, type = "pie", hole = 0.5, marker = list(colors = c(GREEN, NAVY, AMBER))) %>% plot_theme()
  })
  output$p_loc <- renderPlotly({
    x <- F()$V %>% filter(Completed) %>% count(Location, name = "Visits")
    if (!nrow(x)) return(empty_plot("No completed visits."))
    plot_ly(x, x = ~Location, y = ~Visits, type = "bar", marker = list(color = AMBER)) %>% plot_theme()
  })

  # ---------- Marketing ----------
  mk <- reactive({
    d <- F()$d; m <- as.integer(input$mk_month)
    start <- d$settings$prog_start
    if (is.na(start)) start <- min(c(d$leads$Date, Sys.Date()), na.rm = TRUE)
    from <- as.Date(start) %m+% months(m - 1); to <- (from %m+% months(1)) - 1
    marketing_scores(d, m, from, to)
  })
  output$p_mk_scores <- renderPlotly({
    s <- mk()$scores; if (!nrow(s)) return(empty_plot("No marketing data for this month yet."))
    s <- s %>% filter(!is.na(Score)) %>% mutate(Colour = c(Green = GREEN, Amber = AMBER, Red = RED)[Band])
    plot_ly(s, x = ~Score, y = ~reorder(Scorecard, Score), type = "bar", orientation = "h",
            marker = list(color = ~Colour), text = ~paste0(Score, " (", Band, ")"), textposition = "outside") %>%
      layout(xaxis = list(title = "Score out of 100", range = c(0, 130)), yaxis = list(title = NULL)) %>% plot_theme()
  })
  output$t_mk_kpi <- renderDT({
    k <- mk()$kpi
    if (input$mk_who != "All") k <- k %>% filter(Scorecard == input$mk_who)
    if (!nrow(k)) return(dt_base(tibble(Message = "No KPIs yet.")))
    k <- k %>% mutate(Status = status_of(Attainment), Actual = round(Actual, 2), Target = round(Target, 2))
    dt_base(k %>% select(Scorecard, Category, KPI, Unit, Target, Actual, `Attainment %` = Attainment, Status, HasData),
            filter = "top", options = list(pageLength = 25)) %>% status_style("Status")
  })
  output$p_mk_commit <- renderPlotly({
    d <- F()$d
    pr <- d$proj %>% filter(Group == "Marketing") %>% select(Week, Scorecard, KPI, Committed = Value)
    if (!nrow(pr)) return(empty_plot("No weekly commitments yet."))
    pr$Actual <- mapply(function(w, sc, k) {
      src <- d$lib$Source[d$lib$Scorecard == sc & d$lib$KPI == k]
      if (length(src) && grepl("^auto", src[1], ignore.case = TRUE)) {
        v <- auto_value(sc, k, d$leads %>% filter(!Duplicate, Week == w), d$visits %>% filter(Week == w))
        if (is.na(v)) 0 else v
      } else {
        sum(d$mk_act$Value[d$mk_act$Week == w & d$mk_act$Scorecard == sc & d$mk_act$KPI == k], na.rm = TRUE)
      }
    }, pr$Week, pr$Scorecard, pr$KPI)
    x <- pr %>% mutate(Delivery = round(pmin(120, pct(Actual, Committed)), 1)) %>%
      group_by(Week, Scorecard) %>% summarise(Delivery = mean(Delivery, na.rm = TRUE), .groups = "drop")
    plot_ly(x, x = ~Week, y = ~Delivery, color = ~Scorecard, type = "scatter", mode = "lines+markers", colors = PALETTE) %>%
      layout(yaxis = list(title = "Commitment delivery (%)"), xaxis = list(title = NULL)) %>% plot_theme()
  })
  output$p_mk_sales <- renderPlotly({
    x <- F()$B %>% group_by(Owner) %>% summarise(Plots = sum(Plots), Money = sum(Collected), .groups = "drop") %>% arrange(desc(Plots))
    if (!nrow(x)) return(empty_plot("No sales in this period."))
    plot_ly(x, x = ~Owner, y = ~Plots, name = "New plots", type = "bar", marker = list(color = NAVY)) %>%
      add_bars(y = ~Money / 1e6, name = "Money collected (KES millions)", marker = list(color = GREEN)) %>%
      layout(barmode = "group", xaxis = list(title = "Owning source (Sales = TV, existing clients, referrals, walk-ins)"),
             yaxis = list(title = "Plots / KES millions")) %>% plot_theme()
  })
  output$p_mk_output <- renderPlotly({
    x <- F()$d$output %>% group_by(Platform) %>% summarise(Videos = sum(Videos), Pictures = sum(Pictures), Reach = sum(Reach), .groups = "drop")
    if (!nrow(x)) return(empty_plot("No marketing output yet."))
    plot_ly(x, x = ~Platform, y = ~Videos, name = "Videos", type = "bar", marker = list(color = NAVY)) %>%
      add_bars(y = ~Pictures, name = "Pictures", marker = list(color = AMBER)) %>%
      add_lines(y = ~Reach, name = "Reach", yaxis = "y2", line = list(color = GREEN, width = 3)) %>%
      layout(barmode = "group", yaxis2 = list(title = "Reach", overlaying = "y", side = "right")) %>% plot_theme()
  })
  output$p_mk_leads <- renderPlotly({
    x <- F()$L %>% count(Owner, name = "Leads") %>% arrange(desc(Leads))
    if (!nrow(x)) return(empty_plot("No leads."))
    plot_ly(x, x = ~reorder(Owner, Leads), y = ~Leads, type = "bar", marker = list(color = GREEN)) %>%
      layout(xaxis = list(title = NULL)) %>% plot_theme()
  })

  # ---------- Alerts ----------
  output$t_alerts <- renderDT({
    x <- F()$rmw %>% filter(Complete, Status != "Green") %>%
      transmute(Week = format(Week, "%d %b %Y"), RM, `What happened` = Scenario, `New plots` = Plots,
                `Booked (KES)` = round(Booked), `Collected (KES)` = round(Collected),
                `Attainment %` = round(Attainment, 1), Status, `Red streak (weeks)` = RedRun,
                Flag = ifelse(RedRun >= F()$d$settings$alert_weeks, "UNDERPERFORMING", ""))
    dt_base(x, options = list(pageLength = 25)) %>%
      formatCurrency(c("Booked (KES)", "Collected (KES)"), currency = "KES ", digits = 0) %>%
      status_style("Status") %>% formatStyle("Flag", color = styleEqual("UNDERPERFORMING", RED), fontWeight = "bold")
  })
  output$t_actions <- renderDT(dt_base(F()$d$actions %>% arrange(desc(Date)), options = list(pageLength = 15)))

  # ---------- Health ----------
  output$t_health <- renderDT({
    d <- F()$d
    b <- d$bookings
    checks <- tibble(
      Check = c("Sales entries with no project", "Sales entries with no RM", "New bookings with zero plots",
                "Collections with plots entered (should be 0)", "Entries with neither plots nor money",
                "Money in with no new plot (count of entries)", "Sales KPIs without a target (scored once set)",
                "Projections for RMs with no matching RM name", "Rows read: sales entries, leads, visits, projections"),
      Result = c(sum(b$Project == "Unassigned"), sum(b$RM == "" | is.na(b$RM)),
                 sum(b$Type == "New booking" & b$Plots == 0),
                 sum(b$Type != "New booking" & b$Plots > 0),
                 sum(b$Plots == 0 & b$Revenue == 0 & b$Collected == 0),
                 sum(b$Plots == 0 & b$Collected > 0),
                 sum(is.na(d$lib$M1[d$lib$Scorecard == "Sales RM"])),
                 sum(!d$proj$Employee %in% d$rms & d$proj$Group == "Sales"),
                 paste(d$raw_counts, collapse = " / ")),
      Action = c("Pick a project on the sales form", "Pick the RM on the sales form",
                 "Use 'Collection' if no plot was sold, or add the plots",
                 "Edit the row: a collection must have 0 plots",
                 "Usually a mistake: delete or complete the row",
                 "Information: these are the no-plot collections the dashboard reports",
                 "Set the targets in KPI_LIBRARY (calls, visits, money)",
                 "Check the RM name spelling or ROSTER", "Information only")
    )
    dt_base(checks, options = list(pageLength = 15, dom = "t"))
  })
  output$t_lib <- renderDT(dt_base(F()$d$lib, options = list(pageLength = 25)))
}

shinyApp(ui, server)
