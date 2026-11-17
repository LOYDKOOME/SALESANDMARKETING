from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.utils import get_column_letter

F = "Arial"
HDR_FILL = PatternFill("solid", start_color="1F3A5F")
HDR_FONT = Font(name=F, bold=True, color="FFFFFF", size=10)
BODY = Font(name=F, size=10)
NOTE = Font(name=F, size=9, italic=True, color="555555")
INPUT_FILL = PatternFill("solid", start_color="FFF9E6")
thin = Side(style="thin", color="D0D7E2")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)

wb = Workbook()
wb.remove(wb.active)

PROJECTS = ["Project A (rename me)", "Project B (rename me)", "Project C (rename me)", "Project D (rename me)"]
MKT_PEOPLE = ["Dan", "Faith", "Derrick", "Chege"]
RMS = ["Mlai", "Ian", "Emmy", "Peninah", "Beatrice", "Catherine", "George", "Jemima", "Eunice",
       "Simon", "Angeline", "Sheila", "Loyce", "Grace", "Karanja", "Robert", "Monica", "Ebenezer", "Esther"]
SOURCES = [("TikTok", "Faith"), ("Instagram", "Chege"), ("Facebook", "Derrick"), ("Meta Ads", "Dan - Ads"),
           ("Website", "Dan - Website"), ("Influencer", "Marketing Coordinator"),
           ("Inooro TV", "Sales"), ("Citizen TV", "Sales"), ("Existing client", "Sales"),
           ("Referral", "Sales"), ("Walk-in", "Sales"), ("Other", "Sales")]
ENTRY_TYPES = ["New booking", "Collection (no new plot)"]
STATUSES = ["Amber", "Unreachable", "Site visited", "Sale Closed", "SALES ASSIGNED (RM)"]
TRIBES = ["Kikuyu", "Luhya", "Luo", "Kalenjin", "Kamba", "Kisii", "Meru", "Mijikenda", "Somali", "Maasai", "Other"]
GENDERS = ["Female", "Male", "Other / prefer not to say"]
OUTCOMES = ["Scheduled", "Completed", "No show", "Converted to booking"]
PLATFORMS = ["TikTok", "Instagram", "Facebook", "YouTube", "Website", "Google Ads", "Meta Ads"]
LOCATIONS = ["Site A (rename me)", "Site B (rename me)", "Office", "Other"]
LOGISTICS = ["Logistics person 1 (rename me)", "Logistics person 2 (rename me)"]

def sheet(name, headers, widths=None, note=None):
    ws = wb.create_sheet(name)
    ws.sheet_view.showGridLines = False
    for i, h in enumerate(headers, 1):
        c = ws.cell(row=1, column=i, value=h)
        c.font, c.fill, c.border = HDR_FONT, HDR_FILL, BORDER
        c.alignment = Alignment(wrap_text=True, vertical="center")
        ws.column_dimensions[get_column_letter(i)].width = (widths[i-1] if widths else 18)
        ws.row_dimensions[1].height = 42
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    if note:
        ws.cell(row=1, column=len(headers)+2, value=note).font = NOTE
    return ws

def list_tab(name, cols):
    """LISTS-style tab: one column per list. Returns dict name -> range string."""
    ws = sheet(name, [c[0] for c in cols], [28]*len(cols))
    refs = {}
    for i, (h, vals) in enumerate(cols, 1):
        for r, v in enumerate(vals, 2):
            ws.cell(row=r, column=i, value=v).font = BODY
        col = get_column_letter(i)
        refs[h] = f"'{name}'!${col}$2:${col}${max(len(vals)+1, 2)+60}"
    return ws, refs

def dv_list(ws, col, ref_range, rows=1000):
    dv = DataValidation(type="list", formula1=f"={ref_range}", allow_blank=True, showDropDown=False)
    dv.error = "Please pick a value from the list."; dv.errorTitle = "Invalid choice"
    ws.add_data_validation(dv)
    dv.add(f"{col}2:{col}{rows}")

def dv_whole(ws, col, rows=1000):
    dv = DataValidation(type="whole", operator="greaterThanOrEqual", formula1="0", allow_blank=True)
    dv.error = "Whole number 0 or more."; ws.add_data_validation(dv); dv.add(f"{col}2:{col}{rows}")

def dv_date(ws, col, rows=1000):
    dv = DataValidation(type="date", operator="greaterThan", formula1="36526", allow_blank=True)
    dv.error = "Enter a valid date (YYYY-MM-DD)."; ws.add_data_validation(dv); dv.add(f"{col}2:{col}{rows}")

# ---------------- START_HERE ----------------
ws = wb.create_sheet("START_HERE")
ws.sheet_view.showGridLines = False
ws.column_dimensions["A"].width = 26; ws.column_dimensions["B"].width = 110
ws["A1"] = "HYSSOP PROPERTIES LTD | PERFORMANCE SYSTEM (MARKETING + SALES)"
ws["A1"].font = Font(name=F, bold=True, size=14, color="1F3A5F")
rows = [
 ("Purpose", "One database for marketing KPIs, sales RM performance, leads, site visits, bookings and revenue. Data is entered ONLY through the web forms. The dashboard (R Shiny) and the weekly email read this sheet."),
 ("Rule 1: no direct typing", "Do not type into the data tabs (PROJECTIONS, ACTUALS_*, MARKETING_OUTPUT, LEADS, SITE_VISITS, SALES_ENTRIES). Use the web forms so every row is validated. Direct edits are for corrections by the administrator only."),
 ("Rule 2: one name per person", "Chege and Nahasion are the same person. Every record is stored under 'Chege'. 'Nahasion' is an alias in ROSTER and is converted automatically."),
 ("Week definition", "A week starts on Monday. Any date is assigned to the Monday on or before it. Projections are due Monday before 9:00. Actuals are due Friday close of business."),
 ("Tab: CONFIG", "Program start date, report recipients, admin and staff emails, RM targets, and the alert rule. Change values here, not in the code."),
 ("Tab: LISTS", "Dropdown options: projects, lead statuses, tribes, genders, visit outcomes, locations, logistics persons. Rename the placeholder projects to your real project names before go-live."),
 ("Tab: ACTION_LOG", "Management follow-up log for underperformers (issue, agreed action, owner, due date, outcome). Admin adds rows here directly; the dashboard shows them beside each flagged person."),
 ("Tab: SOURCE_MAP", "Which scorecard owns each lead source. Leads from TikTok count for Faith, Instagram for Chege, and so on."),
 ("Tab: ROSTER", "Everyone who appears in forms and dashboards: 4 marketers and 19 RMs. Set Active = No to hide someone without deleting history."),
 ("Tab: KPI_LIBRARY", "All approved KPIs with Month 1 / 2 / 3 targets, unit and direction. Includes the RM weekly KPIs and the three KPIs that were missing in v1 (Chege posts, Derrick inbox reply time, Marketing Coordinator monthly report)."),
 ("Data tab: PROJECTIONS", "Weekly plans. Marketers: commitments per KPI from their role form. RMs: projected money collected, booked value, plots, calls, site visits, personal leads."),
 ("Data tab: ACTUALS_MARKETING", "Admin enters actual KPI results per marketer per week (from platform exports), with an evidence link."),
 ("Data tab: ACTUALS_SALES", "Admin enters RM calls made per week (plots, booked value and money collected come from SALES_ENTRIES automatically)."),
 ("Data tab: MARKETING_OUTPUT", "Videos, pictures, reach, engagement and followers per platform per marketer per week."),
 ("Data tab: LEADS", "Every lead the same day. Status, feedback, tribe and gender are captured for analytics."),
 ("Data tab: SITE_VISITS", "Every site visit: date, client, project, source, location, RM and logistics person, outcome."),
 ("Data tab: SALES_ENTRIES", "Every sales event. Entry Type 'New booking' records plots sold and their booked value (plus any deposit received). Entry Type 'Collection (no new plot)' records money received from an existing or new client with no plot booked. Both feed the dashboard, which reports money and plots separately."),
 ("Sales rules", "New booking: enter plots (1 or more), booked value (KES) and any amount received now. Collection: leave plots at 0, enter the amount received. Do not enter plots on a collection. Inooro TV, Citizen TV and Existing client are sources, so sales from them show on the dashboard too."),
 ("Setup (Apps Script)", "Extensions > Apps Script. Paste Code.gs, add an HTML file named Index with Index.html, save, run setupHyssopSystem once and authorise. Then Deploy > Web app. See README.md for the full steps."),
 ("Colour key (dashboard)", "Green = 100% of target or more. Amber = 70 to 99%. Red = below 70%, or underperforming for 2 or more weeks in a row (flagged in the alert panel)."),
 ("Access", "Give employees NO edit access to this sheet. Forms write on their behalf. Admin emails are listed in CONFIG. Dashboard uses a read-only service account."),
 ("Privacy", "Client contact details are not used in the dashboard. Names are shown only to managers in the profiles and tables. Keep the sheet private."),
]
for i, (a, b) in enumerate(rows, 3):
    ws.cell(row=i, column=1, value=a).font = Font(name=F, bold=True, size=10)
    c = ws.cell(row=i, column=2, value=b); c.font = BODY; c.alignment = Alignment(wrap_text=True, vertical="top")
    ws.cell(row=i, column=1).alignment = Alignment(vertical="top")
    ws.row_dimensions[i].height = 42

# ---------------- CONFIG ----------------
ws = sheet("CONFIG", ["Key", "Value", "Notes"], [30, 36, 70])
cfg = [
 ("ProgramStart", "", "First Monday of Month 1 (YYYY-MM-DD). Month 2 and 3 follow by calendar month. Set before go-live."),
 ("ProgramName", "Hyssop Properties Performance Programme", "Shown in dashboard header and emails."),
 ("AdminEmails", "", "Comma-separated Google accounts that may open the admin (actuals) form and receive all reports."),
 ("StaffEmails", "", "Optional. If filled, only these accounts can use the projection and lead forms."),
 ("ReportEmails", "", "Comma-separated recipients of the weekly and monthly email report."),
 ("ReportWeekday", "Monday", "Day the weekly email is sent (Monday recommended, after projections are due)."),
 ("RM_Revenue_Target_KES", 1000000, "Weekly money target per RM (KES). Measured as set in Target_Basis. Source: management brief."),
 ("RM_Plots_Target", 3, "Weekly plots target per RM. Source: management brief."),
 ("RM_Leads_Per_Close", 15, "Leads needed to close one plot (1 in 15). Source: management brief."),
 ("Alert_Weeks_In_Row", 2, "Flag an RM or marketer who is red for this many consecutive weeks."),
 ("Green_Min_Pct", 100, "Attainment at or above this % is green."),
 ("Amber_Min_Pct", 70, "Attainment at or above this % (and below green) is amber. Below it is red."),
 ("Currency", "KES", "Reporting currency."),
 ("Target_Basis", "Best of both", "Which money figure is measured against the RM weekly money target. 'Booked value' = value of plots booked. 'Collected' = cash received. 'Best of both' = the higher of the two (default). Plots are always measured separately against the plots target."),
]
for r, row in enumerate(cfg, 2):
    for c, v in enumerate(row, 1):
        cell = ws.cell(row=r, column=c, value=v); cell.font = BODY; cell.border = BORDER
        if c == 2: cell.fill = INPUT_FILL
    ws.cell(row=r, column=3).alignment = Alignment(wrap_text=True)

# ---------------- LISTS ----------------
ws, L = list_tab("LISTS", [
    ("Projects", PROJECTS), ("Lead Status", STATUSES), ("Tribe", TRIBES), ("Gender", GENDERS),
    ("Visit Outcome", OUTCOMES), ("Platform", PLATFORMS), ("Visit Location", LOCATIONS),
    ("Logistics Person", LOGISTICS), ("Marketer", MKT_PEOPLE), ("RM", RMS), ("Entry Type", ENTRY_TYPES),
])

# ---------------- SOURCE_MAP ----------------
ws = sheet("SOURCE_MAP", ["Lead Source", "Owning Scorecard"], [28, 30], note="Leads are credited to the owning scorecard.")
for r, (s, o) in enumerate(SOURCES, 2):
    ws.cell(row=r, column=1, value=s).font = BODY; ws.cell(row=r, column=2, value=o).font = BODY

# ---------------- ROSTER ----------------
ws = sheet("ROSTER", ["Name", "Alias (also accepted in forms)", "Group", "Scorecard", "Role", "Email", "Active"],
           [16, 26, 14, 26, 46, 30, 10], note="Email is optional; used for personal report copies.")
roster = [
 ("Dan", "", "Marketing", "Dan - Ads + Dan - Website", "Marketing Lead (Ads 70%, Website 30%)"),
 ("Faith", "", "Marketing", "Faith (TikTok) + Marketing Coordinator", "Digital (TikTok) and Marketing Coordinator. Two forms."),
 ("Derrick", "", "Marketing", "Derrick (Facebook)", "Facebook owner"),
 ("Chege", "Nahasion", "Marketing", "Chege (Instagram)", "Instagram owner. Same person as Nahasion."),
]
for r, p in enumerate(roster, 2):
    vals = list(p) + ["", "Yes"]
    for c, v in enumerate(vals, 1): ws.cell(row=r, column=c, value=v).font = BODY
for i, name in enumerate(RMS, len(roster) + 2):
    vals = [name, "", "Sales", "RM (weekly)", "Relationship Manager", "", "Yes"]
    for c, v in enumerate(vals, 1): ws.cell(row=i, column=c, value=v).font = BODY

# ---------------- KPI_LIBRARY ----------------
ws = sheet("KPI_LIBRARY", ["Scorecard", "Employee", "KPI", "Category", "Frequency",
                           "Month 1 Target", "Month 2 Target", "Month 3 Target", "Unit", "Direction", "Source"],
           [24, 18, 40, 28, 12, 14, 14, 14, 12, 18, 30],
           note="Approved targets from the Digital KPI Scorecard and Marketing Coordinator role document, plus the three v1 gaps and the RM weekly KPIs.")
K = [
 # Faith - Digital (TikTok)
 ("Faith", "Faith", "Leads", "Leads and site visits", "Monthly", 4, 8, 12, "count", "Higher", "Auto from LEADS (TikTok)"),
 ("Faith", "Faith", "Site visits", "Leads and site visits", "Monthly", 1, 2, 3, "count", "Higher", "Auto from SITE_VISITS"),
 ("Faith", "Faith", "New followers", "Reach and brand growth", "Monthly", 600, 600, 600, "count", "Higher", "Admin"),
 ("Faith", "Faith", "Videos above 10k views", "Engagement", "Monthly", 1, 2, 2, "count", "Higher", "Admin"),
 ("Faith", "Faith", "Engagement rate", "Engagement", "Monthly", 4, 4.5, 5, "%", "Higher", "Admin"),
 ("Faith", "Faith", "Videos posted", "Process discipline", "Monthly", 16, 16, 20, "count", "Higher", "Admin"),
 ("Faith", "Faith", "TikTok live sessions", "Process discipline", "Monthly", 4, 8, 16, "count", "Higher", "Admin"),
 ("Faith", "Faith", "Comment reply time", "Process discipline", "Monthly", 2, 2, 1, "hours", "Lower", "Admin"),
 # Chege - Instagram (Nahasion alias)
 ("Chege", "Chege", "Leads", "Leads and site visits", "Monthly", 4, 8, 12, "count", "Higher", "Auto from LEADS (Instagram)"),
 ("Chege", "Chege", "Site visits", "Leads and site visits", "Monthly", 1, 2, 3, "count", "Higher", "Auto from SITE_VISITS"),
 ("Chege", "Chege", "New followers", "Reach and brand growth", "Monthly", 250, 250, 300, "count", "Higher", "Admin"),
 ("Chege", "Chege", "Reach growth (month on month)", "Reach and brand growth", "Monthly", 2500, 5000, 10000, "count", "Higher", "Admin"),
 ("Chege", "Chege", "Engagement rate", "Engagement", "Monthly", 2.5, 3, 3.5, "%", "Higher", "Admin"),
 ("Chege", "Chege", "DM reply time", "Process discipline", "Monthly", 2, 1, 1, "hours", "Lower", "Admin"),
 ("Chege", "Chege", "Feed posts per week", "Process discipline", "Weekly", 4, 4, 4, "per week", "Higher", "Admin (v1 gap, now scored)"),
 ("Chege", "Chege", "Reels per week", "Process discipline", "Weekly", 2, 2, 2, "per week", "Higher", "Admin (v1 gap, now scored)"),
 ("Chege", "Chege", "Stories per week", "Process discipline", "Weekly", 10, 10, 10, "per week", "Higher", "Admin (v1 gap, now scored)"),
 # Derrick - Facebook
 ("Derrick", "Derrick", "Organic leads", "Leads and site visits", "Monthly", 10, 15, 20, "count", "Higher", "Auto from LEADS (Facebook)"),
 ("Derrick", "Derrick", "Site visits", "Leads and site visits", "Monthly", 2, 4, 6, "count", "Higher", "Auto from SITE_VISITS"),
 ("Derrick", "Derrick", "New followers", "Reach and brand growth", "Monthly", 200, 200, 200, "count", "Higher", "Admin"),
 ("Derrick", "Derrick", "Engagement rate", "Engagement", "Monthly", 1.5, 2, 2, "%", "Higher", "Admin"),
 ("Derrick", "Derrick", "Posts per week", "Process discipline", "Weekly", 5, 5, 5, "per week", "Higher", "Admin"),
 ("Derrick", "Derrick", "Local groups posted daily", "Process discipline", "Weekly", 5, 10, 10, "per day", "Higher", "Admin"),
 ("Derrick", "Derrick", "Collaboration posts", "Engagement", "Monthly", 12, 12, 12, "per month", "Higher", "Admin"),
 ("Derrick", "Derrick", "Facebook live sessions", "Process discipline", "Monthly", 4, 8, 10, "count", "Higher", "Admin"),
 ("Derrick", "Derrick", "Inbox reply time", "Process discipline", "Monthly", 2, 1, 1, "hours", "Lower", "Admin (v1 gap, now scored)"),
 # Dan - Ads (70%)
 ("Dan - Ads", "Dan", "Leads (Meta Ads)", "Leads and site visits", "Monthly", 600, 1200, 2000, "count", "Higher", "Auto from LEADS (Meta Ads)"),
 ("Dan - Ads", "Dan", "Leads qualified", "Leads and site visits", "Monthly", 40, 50, 60, "%", "Higher", "Auto from LEADS"),
 ("Dan - Ads", "Dan", "Contacted within 15 min", "Process discipline", "Monthly", 90, 95, 100, "%", "Higher", "Admin (CRM timestamps)"),
 ("Dan - Ads", "Dan", "Site visits (Meta Ads leads)", "Leads and site visits", "Monthly", 100, 150, 300, "count", "Higher", "Auto from SITE_VISITS"),
 ("Dan - Ads", "Dan", "Cost per qualified lead (KES)", "Process discipline", "Monthly", 350, 300, 250, "KES", "Lower", "Admin: ad spend / qualified leads"),
 # Dan - Website (30%)
 ("Dan - Website", "Dan", "Leads (Website)", "Leads and site visits", "Monthly", 5, 10, 20, "count", "Higher", "Auto from LEADS (Website)"),
 ("Dan - Website", "Dan", "Website visitors", "Reach and brand growth", "Monthly", 1000, 1500, 2000, "count", "Higher", "Admin (GA4)"),
 ("Dan - Website", "Dan", "Visitor-to-enquiry rate", "Engagement", "Monthly", 1, 1.5, 2, "%", "Higher", "Auto (leads / visitors)"),
 ("Dan - Website", "Dan", "Blog posts", "Process discipline", "Monthly", 4, 4, 4, "count", "Higher", "Admin"),
 # Marketing Coordinator (Faith)
 ("Marketing Coordinator", "Faith", "Leads logged with source", "Lead handoff", "Monthly", 100, 100, 100, "%", "Higher", "Auto from LEADS"),
 ("Marketing Coordinator", "Faith", "Leads handed to agent within 15 min", "Lead handoff", "Monthly", 90, 95, 100, "%", "Higher", "Admin (workflow timestamps)"),
 ("Marketing Coordinator", "Faith", "Campaigns launched on schedule", "Campaign and content execution", "Monthly", 90, 95, 100, "%", "Higher", "Admin"),
 ("Marketing Coordinator", "Faith", "Content calendar followed", "Campaign and content execution", "Monthly", 90, 95, 100, "%", "Higher", "Admin"),
 ("Marketing Coordinator", "Faith", "Influencer posts on schedule", "Influencer and collaboration", "Monthly", 100, 100, 100, "%", "Higher", "Admin"),
 ("Marketing Coordinator", "Faith", "Influencers with tracked contact", "Influencer and collaboration", "Monthly", 100, 100, 100, "%", "Higher", "Admin"),
 ("Marketing Coordinator", "Faith", "Influencer shoots coordinated", "Influencer and collaboration", "Monthly", 4, 6, 8, "count", "Higher", "Admin"),
 ("Marketing Coordinator", "Faith", "Influencer leads", "Influencer and collaboration", "Monthly", 5, 7, 10, "count", "Higher", "Auto from LEADS (Influencer)"),
 ("Marketing Coordinator", "Faith", "Brand-guideline compliance", "Branding assets and sales materials", "Monthly", 90, 95, 95, "%", "Higher", "Admin (audit of 20 posts)"),
 ("Marketing Coordinator", "Faith", "Asset library updated within 48 hrs", "Branding assets and sales materials", "Monthly", 90, 100, 100, "%", "Higher", "Admin"),
 ("Marketing Coordinator", "Faith", "Outdated materials in circulation", "Branding assets and sales materials", "Monthly", 0, 0, 0, "count", "Lower", "Admin"),
 ("Marketing Coordinator", "Faith", "Weekly reports delivered on time", "Reporting and events", "Weekly", 1, 1, 1, "report", "Higher", "Admin (1 = on time)"),
 ("Marketing Coordinator", "Faith", "Monthly report delivered by the 5th", "Reporting and events", "Monthly", 1, 1, 1, "yes/no", "Higher", "Admin (v1 gap, now scored)"),
 # Sales RMs (weekly, each RM)
 ("Sales RM", "All RMs", "Plots booked", "Revenue", "Weekly", 3, 3, 3, "count", "Higher", "Auto from SALES_ENTRIES (New booking rows)"),
 ("Sales RM", "All RMs", "Booked value (KES)", "Revenue", "Weekly", 1000000, 1000000, 1000000, "KES", "Higher", "Auto from SALES_ENTRIES (New booking rows)"),
 ("Sales RM", "All RMs", "Money collected (KES)", "Revenue", "Weekly", None, None, None, "KES", "Higher", "Auto from SALES_ENTRIES (SET TARGET)"),
 ("Sales RM", "All RMs", "Personal leads handled", "Pipeline", "Weekly", 45, 45, 45, "count", "Higher", "Auto from LEADS (3 plots x 15 leads)"),
 ("Sales RM", "All RMs", "Calls made", "Pipeline", "Weekly", None, None, None, "count", "Higher", "Admin (SET TARGET)"),
 ("Sales RM", "All RMs", "Site visits conducted", "Pipeline", "Weekly", None, None, None, "count", "Higher", "Auto from SITE_VISITS (SET TARGET)"),
 ("Sales RM", "All RMs", "Lead-to-plot conversion", "Pipeline", "Weekly", 6.67, 6.67, 6.67, "%", "Higher", "Auto (plots / leads handled)"),
]
for r, row in enumerate(K, 2):
    for c, v in enumerate(row, 1):
        cell = ws.cell(row=r, column=c, value=v); cell.font = BODY; cell.border = BORDER
        if c in (6, 7, 8): cell.fill = INPUT_FILL
ws.cell(row=len(K)+3, column=1, value="Yellow cells are approved targets: change here, never in code. Blank = target not set (the KPI is shown but not scored).").font = NOTE

# ---------------- Data tabs ----------------
def dropdowns(ws, cols_refs, rows=1000):
    for col, ref in cols_refs:
        dv_list(ws, col, ref, rows)

ET = L["Entry Type"]; PROJ = L["Projects"]; STAT = L["Lead Status"]; TRIB = L["Tribe"]; GEN = L["Gender"]; OUT = L["Visit Outcome"]
LOC = L["Visit Location"]; LOG = L["Logistics Person"]; MKT = L["Marketer"]; RM = L["RM"]; PLAT = L["Platform"]
SRC = "'SOURCE_MAP'!$A$2:$A$30"

ws = sheet("PROJECTIONS", ["Submitted At", "Week Starting", "Group", "Employee", "Scorecard", "KPI",
                           "Projected Value", "Unit", "Plan / Notes", "Support Needed"],
           [18, 14, 12, 16, 26, 36, 14, 10, 40, 30], note="Written by the projection form only.")
dv_date(ws, "B")
ws = sheet("ACTUALS_MARKETING", ["Submitted At", "Week Starting", "Employee", "Scorecard", "KPI",
                                 "Actual Value", "Unit", "Evidence Link", "Admin Notes"],
           [18, 14, 16, 26, 36, 14, 10, 40, 36], note="Written by the admin actuals form only.")
ws = sheet("ACTUALS_SALES", ["Submitted At", "Week Starting", "RM", "Calls Made", "Notes"],
           [18, 14, 18, 14, 40], note="Written by the admin actuals form only.")
dv_whole(ws, "D")
ws = sheet("MARKETING_OUTPUT", ["Submitted At", "Week Starting", "Employee", "Platform", "Videos Posted",
                                "Pictures Posted", "Reach", "Engagement Rate (%)", "New Followers", "Evidence Link", "Notes"],
           [18, 14, 16, 16, 14, 14, 14, 16, 14, 36, 30], note="Admin enters per platform per marketer per week.")
dropdowns(ws, [("C", MKT), ("D", PLAT)])
ws = sheet("LEADS", ["Submitted At", "Lead Date", "Week Starting", "Lead Name", "Lead Social Page",
                     "Lead Source / Advert", "Project", "Lead Status", "Lead Feedback", "Tribe", "Gender",
                     "Assigned RM", "Contact (Restricted)"],
           [18, 13, 14, 22, 26, 22, 24, 20, 40, 14, 18, 16, 20],
           note="Contact is stored for the sales team only. The dashboard never shows it.")
dv_date(ws, "B")
dropdowns(ws, [("F", SRC), ("G", PROJ), ("H", STAT), ("J", TRIB), ("K", GEN), ("L", RM)])
ws = sheet("SITE_VISITS", ["Submitted At", "Visit Date", "Week Starting", "Client Name", "Project",
                           "Lead Source", "Location", "RM", "Logistics Person", "Outcome", "Notes"],
           [18, 13, 14, 22, 24, 18, 22, 16, 26, 22, 36], note="Every site visit, logged by date, client, project, RM and logistics person.")
dv_date(ws, "B")
dropdowns(ws, [("E", PROJ), ("F", SRC), ("G", LOC), ("H", RM), ("I", LOG), ("J", OUT)])
ws = sheet("SALES_ENTRIES", ["Submitted At", "Entry Date", "Week Starting", "Entry Type", "RM", "Client Name",
                             "Project", "Lead Source", "Tribe", "Gender", "New Plots Booked", "Booked Value (KES)",
                             "Amount Received (KES)", "Payment Reference", "Notes"],
           [18, 13, 14, 26, 16, 22, 24, 18, 14, 18, 14, 18, 18, 20, 30],
           note="One row per event. New booking = plots sold. Collection = money received with no new plot. Both can carry money.")
dv_date(ws, "B"); dv_whole(ws, "K"); dv_whole(ws, "L"); dv_whole(ws, "M")
dropdowns(ws, [("D", ET), ("E", RM), ("G", PROJ), ("H", SRC), ("I", TRIB), ("J", GEN)])

ws = sheet("ACTION_LOG", ["Date", "Person", "Issue", "Action Agreed", "Owner", "Due Date", "Status", "Outcome"],
           [13, 18, 40, 44, 16, 13, 14, 36], note="Management log: add a row when an underperformer is discussed. Not a data-entry form.")
dv_list(ws, "G", "'LISTS'!$K$2:$K$6", 500) if False else None
# Order: START_HERE first, then CONFIG, data tabs
order = ["START_HERE", "CONFIG", "ROSTER", "KPI_LIBRARY", "SOURCE_MAP", "LISTS", "PROJECTIONS",
         "ACTUALS_MARKETING", "ACTUALS_SALES", "MARKETING_OUTPUT", "LEADS", "SITE_VISITS", "SALES_ENTRIES", "ACTION_LOG"]
wb._sheets = [wb[n] for n in order]
for s in wb.worksheets:
    s.sheet_properties.tabColor = "1F3A5F" if s.title in ("START_HERE", "CONFIG") else ("C9A227" if s.title in ("KPI_LIBRARY","ROSTER","SOURCE_MAP","LISTS") else "2E8B57")
    for row in s.iter_rows():
        for c in row:
            if c.font is None or c.font.name != F:
                c.font = Font(name=F, size=c.font.size if c.font and c.font.size else 10, bold=c.font.bold if c.font else False, color=c.font.color if c.font else None, italic=c.font.italic if c.font else False)
wb.save("/home/claude/hyssop/HYSSOP_PERFORMANCE_TEMPLATE.xlsx")
print("saved")
