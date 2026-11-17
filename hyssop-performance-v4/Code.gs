/*************************************************************
 * HYSSOP PERFORMANCE SYSTEM v3 - Code.gs
 * Marketing + Sales (RM) performance. Data enters ONLY through the web forms.
 *
 *   page=projection  -> weekly projections (marketers by role, RMs)
 *   page=leads       -> lead capture (everyone in the sales/marketing team)
 *   page=admin       -> admin entry: 1 Marketing KPI actuals, 2 Marketing output,
 *                       3 Site visits, 4 Bookings, revenue and RM calls
 *
 * Also: weekly and monthly email report, alias handling (Nahasion = Chege).
 * The dashboard (app.R) reads the same tabs; it never writes.
 *************************************************************/

const TZ_FALLBACK = "Africa/Nairobi";
const ALIAS = { "nahasion": "Chege" };                     // Chege and Nahasion are one person

const MKT_MARKETERS = ["Dan", "Faith", "Derrick", "Chege"];
const SCORECARDS_BY_CHOICE = {
  "Dan": ["Dan - Ads", "Dan - Website"],
  "Faith|Digital": ["Faith"],
  "Faith|Coordinator": ["Marketing Coordinator"],
  "Derrick": ["Derrick"],
  "Chege": ["Chege"]
};

/* ============================ WEB APP ============================ */

function doGet(e) {
  const req = e && e.parameter && e.parameter.page;
  const page = ["projection", "leads", "admin"].includes(req) ? req : "projection";
  if (page === "admin" && !isAdmin_()) return denied_("Admin access only",
    "Your Google account is not on the AdminEmails list in CONFIG.");
  const t = HtmlService.createTemplateFromFile("Index");
  t.page = page;
  return t.evaluate().setTitle("Hyssop Performance").setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function denied_(title, msg) {
  return HtmlService.createHtmlOutput("<h3 style='font-family:Arial'>" + title + "</h3><p style='font-family:Arial'>" + msg + "</p>");
}

// Called by the page on load: lists, roster, and who is signed in.
function getBootstrap() {
  const cfg = readConfig_();
  const lists = readLists_();
  lists["Lead Source"] = readObjects_("SOURCE_MAP").map(r => r["Lead Source"]).filter(Boolean);
  const roster = readObjects_("ROSTER").filter(r => String(r["Active"]).toLowerCase() !== "no");
  return {
    user: userEmail_(), isAdmin: isAdmin_(), lists: lists, roster: roster,
    marketers: MKT_MARKETERS, rms: roster.filter(r => r["Group"] === "Sales").map(r => r["Name"]),
    programName: cfg.ProgramName || "Hyssop Performance", tz: tz_()
  };
}

// The KPIs a marketer must fill in, for the role they chose. Faith sees her role-specific form.
function getProjectionSpec(choice) {
  const cards = SCORECARDS_BY_CHOICE[choice] || [];
  return readObjects_("KPI_LIBRARY")
    .filter(r => cards.includes(r["Scorecard"]))
    .map(r => ({ kpi: r["KPI"], unit: r["Unit"], direction: r["Direction"], scorecard: r["Scorecard"],
                 category: r["Category"], frequency: r["Frequency"], source: r["Source"] || "",
                 m1: r["Month 1 Target"], m2: r["Month 2 Target"], m3: r["Month 3 Target"] }));
}

/* ============================ FORMS ============================ */

// 1. Projection: marketer commitments (one row per KPI) or RM weekly projection.
function submitProjection(p) {
  const who = canonical_(p.employee);
  const week = weekStart_(p.weekDate || today_());
  const group = p.group;
  const rows = [];
  if (group === "Sales") {
    required_(p, ["employee"]);
    const items = [
      ["Money collected (KES)", p.money, "KES"], ["Booked value (KES)", p.booked, "KES"],
      ["Plots booked", p.plots, "count"], ["Calls made", p.calls, "count"],
      ["Site visits conducted", p.visits, "count"], ["Personal leads handled", p.leads, "count"]
    ];
    items.forEach(it => {
      if (it[1] !== "" && it[1] !== undefined && it[1] !== null)
        rows.push(projRow_(week, "Sales", who, "Sales RM", it[0], nonNeg_(it[1], it[0]), it[2], p.notes, p.support));
    });
  } else {
    required_(p, ["employee", "choice"]);
    const spec = getProjectionSpec(p.choice);
    if (!spec.length) throw new Error("Please choose a valid marketing role.");
    // Scorecard and unit come from the server's KPI_LIBRARY, never from the browser.
    (p.items || []).forEach(it => {
      const v = it.value;
      if (v === "" || v === undefined || v === null) return;
      const spec = getProjectionSpec(p.choice).find(s => s.kpi === it.kpi);
      if (!spec) throw new Error("Unknown KPI for this role: " + it.kpi);
      checkPct_(spec.unit, Number(v), it.kpi);
      rows.push(projRow_(week, "Marketing", who, spec.scorecard, spec.kpi, nonNeg_(v, it.kpi), spec.unit, it.notes || p.notes, p.support));
    });
    if (!rows.length) throw new Error("Enter at least one commitment.");
  }
  appendRows_("PROJECTIONS", rows);
  return "Saved " + rows.length + " projection line(s) for week of " + week + ".";
}

// 2. Lead capture (all staff).
function submitLead(p) {
  required_(p, ["leadDate", "leadName", "source", "project", "status", "tribe", "gender"]);
  const date = dateKey_(p.leadDate);
  const row = {
    "Submitted At": now_(), "Lead Date": date, "Week Starting": weekStart_(date),
    "Lead Name": p.leadName, "Lead Social Page": p.socialPage || "", "Lead Source / Advert": p.source,
    "Project": p.project, "Lead Status": p.status, "Lead Feedback": p.feedback || "",
    "Tribe": p.tribe, "Gender": p.gender, "Assigned RM": canonical_(p.assignedRm || ""),
    "Contact (Restricted)": p.contact || ""
  };
  appendObj_("LEADS", row);
  return "Lead saved.";
}

// 3. Admin: marketing KPI actuals. The role decides the scorecard; automatic KPIs are refused.
function submitActualsMarketing(p) {
  assertAdmin_();
  required_(p, ["weekDate", "employee", "choice"]);
  const week = weekStart_(p.weekDate);
  const who = canonical_(p.employee);
  const spec = getProjectionSpec(p.choice);
  if (!spec.length) throw new Error("Choose a valid marketer or role.");
  const rows = (p.items || []).filter(it => it.value !== "" && it.value !== null && it.value !== undefined)
    .map(it => {
      const s = spec.find(x => x.kpi === it.kpi);
      if (!s) throw new Error("Unknown KPI for this role: " + it.kpi);
      if (/^auto/i.test(s.source)) throw new Error(it.kpi + " is calculated automatically and cannot be typed in.");
      checkPct_(s.unit, Number(it.value), it.kpi);
      return { "Submitted At": now_(), "Week Starting": week, "Employee": who, "Scorecard": s.scorecard,
               "KPI": s.kpi, "Actual Value": nonNeg_(it.value, it.kpi), "Unit": s.unit,
               "Evidence Link": p.evidence || "", "Admin Notes": p.notes || "" };
    });
  if (!rows.length) throw new Error("Enter at least one actual.");
  appendRows_("ACTUALS_MARKETING", rows);
  return "Saved " + rows.length + " actual(s) for " + who + " (week of " + week + ").";
}

// 4a. Admin: marketing output per platform (videos, pictures, reach).
function submitMarketingOutput(p) {
  assertAdmin_();
  required_(p, ["weekDate", "employee", "platform"]);
  appendObj_("MARKETING_OUTPUT", {
    "Submitted At": now_(), "Week Starting": weekStart_(p.weekDate), "Employee": canonical_(p.employee),
    "Platform": p.platform, "Videos Posted": int_(p.videos || 0, "Videos"), "Pictures Posted": int_(p.pictures || 0, "Pictures"),
    "Reach": nonNeg_(p.reach || 0, "Reach"), "Engagement Rate (%)": p.engagement === "" || p.engagement == null ? "" : pctOk_(p.engagement, "Engagement"),
    "New Followers": nonNeg_(p.followers || 0, "New followers"), "Evidence Link": p.evidence || "", "Notes": p.notes || ""
  });
  return "Marketing output saved.";
}

// 4b. Admin: site visits (every visit, every project).
function submitSiteVisit(p) {
  assertAdmin_();
  required_(p, ["visitDate", "client", "project", "source", "location", "rm", "logistics", "outcome"]);
  appendObj_("SITE_VISITS", {
    "Submitted At": now_(), "Visit Date": dateKey_(p.visitDate), "Week Starting": weekStart_(p.visitDate),
    "Client Name": p.client, "Project": p.project, "Lead Source": p.source, "Location": p.location,
    "RM": canonical_(p.rm), "Logistics Person": p.logistics, "Outcome": p.outcome, "Notes": p.notes || ""
  });
  return "Site visit saved.";
}

// 4c. Admin: sales entries. Two types: "New booking" (plots sold) and
// "Collection (no new plot)" (money received with no plot). Either can carry money received.
const ENTRY_NEW = "New booking";
const ENTRY_COLLECT = "Collection (no new plot)";
function submitSalesEntry(p) {
  assertAdmin_();
  required_(p, ["entryDate", "entryType", "rm", "client", "project", "source"]);
  const type = p.entryType;
  const plots = p.plots === "" || p.plots == null ? 0 : int_(p.plots, "New plots booked");
  const booked = p.bookedValue === "" || p.bookedValue == null ? 0 : nonNeg_(p.bookedValue, "Booked value");
  const received = p.amountReceived === "" || p.amountReceived == null ? 0 : nonNeg_(p.amountReceived, "Amount received");
  if (type === ENTRY_NEW) {
    if (plots < 1) throw new Error("A new booking needs at least 1 plot.");
    if (booked <= 0) throw new Error("A new booking needs the booked value (KES).");
  } else if (type === ENTRY_COLLECT) {
    if (plots !== 0) throw new Error("A collection cannot include new plots. Use 'New booking' for plots.");
    if (received <= 0) throw new Error("A collection needs the amount received (KES).");
  } else {
    throw new Error("Choose an entry type.");
  }
  const date = dateKey_(p.entryDate);
  appendObj_("SALES_ENTRIES", {
    "Submitted At": now_(), "Entry Date": date, "Week Starting": weekStart_(date), "Entry Type": type,
    "RM": canonical_(p.rm), "Client Name": p.client, "Project": p.project, "Lead Source": p.source,
    "Tribe": p.tribe || "", "Gender": p.gender || "", "New Plots Booked": plots,
    "Booked Value (KES)": booked, "Amount Received (KES)": received,
    "Payment Reference": p.reference || "", "Notes": p.notes || ""
  });
  return type === ENTRY_NEW ? "Booking saved: " + plots + " plot(s)." : "Collection saved: KES " + received + " (no plot).";
}

// 4d. Admin: RM calls made for the week.
function submitSalesActuals(p) {
  assertAdmin_();
  required_(p, ["weekDate", "rm", "calls"]);
  appendObj_("ACTUALS_SALES", {
    "Submitted At": now_(), "Week Starting": weekStart_(p.weekDate), "RM": canonical_(p.rm),
    "Calls Made": int_(p.calls, "Calls made"), "Notes": p.notes || ""
  });
  return "RM calls saved.";
}

/* ============================ EMAIL REPORTS ============================ */

// Runs weekly (trigger). Summarises the last full Monday-to-Sunday week.
function sendWeeklyReport() { sendReport_("weekly"); }

// Runs on the 1st of each month. Summarises the previous calendar month.
function sendMonthlyReport() { sendReport_("monthly"); }

function sendReport_(kind) {
  const cfg = readConfig_();
  const recipients = String(cfg.ReportEmails || "").trim();
  if (!recipients) return;
  const range = kind === "weekly" ? lastWeekRange_() : lastMonthRange_();
  const s = summarise_(range.from, range.to);
  const html = buildEmail_(s, kind, range, cfg);
  MailApp.sendEmail({ to: recipients, subject: "Hyssop " + (kind === "weekly" ? "weekly" : "monthly") +
    " performance report: " + range.label, htmlBody: html, name: "Hyssop Performance" });
}

function summarise_(from, to) {
  const rows = readObjects_("SALES_ENTRIES").filter(r => inRange_(r["Entry Date"], from, to));
  const basis = String(cfgVal_("Target_Basis") || "Booked value");
  const rmTargets = { rev: num_(cfgVal_("RM_Revenue_Target_KES")), plots: num_(cfgVal_("RM_Plots_Target")) };
  const leads = readObjects_("LEADS").filter(r => inRange_(r["Lead Date"], from, to));
  const visits = readObjects_("SITE_VISITS").filter(r => inRange_(r["Visit Date"], from, to));
  const sumBy = (arr, key, fn) => arr.reduce((m, r) => { const k = r[key] || "Unassigned"; m[k] = (m[k] || 0) + fn(r); return m; }, {});
  const plotsOf = r => num_(r["New Plots Booked"]);
  const bookedOf = r => num_(r["Booked Value (KES)"]);
  const collectedOf = r => num_(r["Amount Received (KES)"]);
  const plots = rows.reduce((a, r) => a + plotsOf(r), 0);
  const booked = rows.reduce((a, r) => a + bookedOf(r), 0);
  const collected = rows.reduce((a, r) => a + collectedOf(r), 0);
  const collectedNoPlot = rows.filter(r => plotsOf(r) === 0).reduce((a, r) => a + collectedOf(r), 0);
  const rms = [...new Set(rows.map(r => canonical_(r["RM"])).concat(readRMs_()))].filter(Boolean).map(name => {
    const b = rows.filter(r => canonical_(r["RM"]) === name);
    const bk = b.reduce((a, r) => a + bookedOf(r), 0);
    const cl = b.reduce((a, r) => a + collectedOf(r), 0);
    const rev = basis === "Collected" ? cl : basis === "Booked value" ? bk : Math.max(bk, cl);
    const pl = b.reduce((a, r) => a + plotsOf(r), 0);
    const att = Math.min(120, Math.round(100 * Math.max(rev / (rmTargets.rev || 1), pl / (rmTargets.plots || 1))));
    return { name, rev, plots: pl, collected: b.reduce((a, r) => a + collectedOf(r), 0),
             status: att >= 100 ? "green" : att >= 70 ? "amber" : "red" };
  }).sort((a, b) => b.rev - a.rev);
  return {
    basis, plots, booked, collected, collectedNoPlot, rms,
    leads: leads.length, visits: visits.length,
    leadsByProject: sumBy(leads, "Project", () => 1),
    plotsByProject: sumBy(rows, "Project", plotsOf),
    collectedByProject: sumBy(rows, "Project", collectedOf),
    bookedByProject: sumBy(rows, "Project", bookedOf)
  };
}

function buildEmail_(s, kind, range, cfg) {
  const money = v => "KES " + Math.round(v).toLocaleString("en-US");
  const row = (a, b) => "<tr><td style='padding:6px 10px;border-bottom:1px solid #e5e9f0'>" + a + "</td><td style='padding:6px 10px;border-bottom:1px solid #e5e9f0;text-align:right'>" + b + "</td></tr>";
  const colour = { green: "#2e8b57", amber: "#d4a017", red: "#c0392b" };
  const cell = "padding:6px 10px;border-bottom:1px solid #e5e9f0;text-align:right";
  const rmRows = s.rms.map(r => "<tr><td style='padding:6px 10px;border-bottom:1px solid #e5e9f0'>" + r.name + "</td><td style='" + cell + "'>" +
    money(r.collected) + "</td><td style='" + cell + "'>" + r.plots + "</td><td style='" + cell + "'>" + money(r.rev) +
    "</td><td style='padding:6px 10px;border-bottom:1px solid #e5e9f0;text-align:center;color:" + colour[r.status] + ";font-weight:bold'>" +
    r.status.toUpperCase() + "</td></tr>").join("");
  const projRows = Object.keys(s.collectedByProject).map(p => row(p, money(s.collectedByProject[p]) + " collected | " +
    (s.plotsByProject[p] || 0) + " plots | " + money(s.bookedByProject[p] || 0) + " booked")).join("");
  const reds = s.rms.filter(r => r.status === "red").map(r => r.name);
  const scenario = s.plots > 0 && s.collected > 0 ? "Plots were booked and money came in." :
                   s.plots > 0 ? "Plots were booked; money not yet collected." :
                   s.collected > 0 ? "No new plots this period, but money came in from existing or earlier clients." :
                   "No sales activity this period.";
  return "<div style='font-family:Arial,sans-serif;color:#1f2d3d;max-width:680px'>" +
    "<h2 style='color:#1F3A5F;margin-bottom:4px'>" + (cfg.ProgramName || "Hyssop Performance") + "</h2>" +
    "<p style='color:#555;margin-top:0'>" + (kind === "weekly" ? "Weekly" : "Monthly") + " report: " + range.label + "</p>" +
    "<p style='font-size:14px'><b>What happened:</b> " + scenario + "</p>" +
    "<table style='width:100%;border-collapse:collapse;font-size:14px'>" +
    row("Money collected (all sources)", money(s.collected)) +
    row("&nbsp;&nbsp;of which collections with no new plot", money(s.collectedNoPlot)) +
    row("New plots booked", s.plots) + row("Booked value of new plots", money(s.booked)) +
    row("Leads", s.leads) + row("Site visits", s.visits) + "</table>" +
    "<h3 style='color:#1F3A5F'>Sales RMs</h3><table style='width:100%;border-collapse:collapse;font-size:13px'>" +
    "<tr style='background:#1F3A5F;color:#fff'><th style='padding:6px 10px;text-align:left'>RM</th><th>Collected</th><th>Plots</th><th>Target measure (" + s.basis + ")</th><th>Status</th></tr>" + rmRows + "</table>" +
    "<h3 style='color:#1F3A5F'>By project</h3><table style='width:100%;border-collapse:collapse;font-size:13px'>" + projRows + "</table>" +
    (reds.length ? "<p style='color:#c0392b'><b>Below target this period:</b> " + reds.join(", ") + ". The dashboard alert panel flags anyone red 2 or more weeks in a row.</p>" : "") +
    "<p style='color:#777;font-size:12px'>Status: green at or above 100% of target, amber 70 to 99%, red below 70%. Open the dashboard for trends, marketing scorecards and profiles.</p></div>";
}

function lastWeekRange_() {
  const tz = tz_(); const now = new Date();
  const mon = new Date(weekStart_(Utilities.formatDate(now, tz, "yyyy-MM-dd")) + "T12:00:00");
  const from = new Date(mon.getTime() - 7 * 86400000);
  const to = new Date(mon.getTime() - 86400000);
  const f = d => Utilities.formatDate(d, tz, "yyyy-MM-dd");
  return { from: f(from), to: f(to), label: "week " + f(from) + " to " + f(to) };
}

function lastMonthRange_() {
  const tz = tz_(); const d = new Date();
  const first = new Date(d.getFullYear(), d.getMonth() - 1, 1, 12);
  const last = new Date(d.getFullYear(), d.getMonth(), 0, 12);
  const f = x => Utilities.formatDate(x, tz, "yyyy-MM-dd");
  return { from: f(first), to: f(last), label: Utilities.formatDate(first, tz, "MMMM yyyy") };
}

/* ============================ SETUP & MENU ============================ */

function onOpen() {
  SpreadsheetApp.getUi().createMenu("Hyssop")
    .addItem("Check setup", "checkSetup")
    .addItem("Send weekly report now", "sendWeeklyReport")
    .addItem("Send monthly report now", "sendMonthlyReport")
    .addSeparator()
    .addItem("Install weekly and monthly email triggers", "installReportTriggers")
    .addToUi();
}

// Run once after pasting the code. Never deletes data.
function setupHyssopSystem() {
  checkSetup();
  installReportTriggers();
}

function checkSetup() {
  const required = ["CONFIG", "ROSTER", "KPI_LIBRARY", "SOURCE_MAP", "LISTS", "PROJECTIONS", "ACTUALS_MARKETING",
    "ACTUALS_SALES", "MARKETING_OUTPUT", "LEADS", "SITE_VISITS", "SALES_ENTRIES"];
  const ss = SpreadsheetApp.getActive();
  const missing = required.filter(n => !ss.getSheetByName(n));
  const msg = missing.length ? "Missing tabs: " + missing.join(", ") + ". Re-copy the template." : "All tabs present.";
  SpreadsheetApp.getActive().toast(msg, "Hyssop setup", 8);
  Logger.log(msg);
  return msg;
}

function installReportTriggers() {
  ScriptApp.getProjectTriggers().forEach(t => {
    const fn = t.getHandlerFunction();
    if (fn === "sendWeeklyReport" || fn === "sendMonthlyReport") ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger("sendWeeklyReport").timeBased().onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(7).create();
  ScriptApp.newTrigger("sendMonthlyReport").timeBased().onMonthDay(1).atHour(8).create();
  return "Triggers installed: weekly Monday 07:00, monthly 1st 08:00 (Africa/Nairobi).";
}

/* ============================ ACCESS ============================ */

function userEmail_() { try { return (Session.getActiveUser().getEmail() || "").toLowerCase(); } catch (e) { return ""; } }
function listCfg_(v) { return String(v || "").split(/[,;\s]+/).map(s => s.trim().toLowerCase()).filter(Boolean); }
function isAdmin_() {
  const u = userEmail_();
  return !!u && listCfg_(cfgVal_("AdminEmails")).includes(u);
}
function assertAdmin_() { if (!isAdmin_()) throw new Error("Admin only. Your account is not in AdminEmails."); }

/* ============================ SHEET HELPERS ============================ */

function ss_() { return SpreadsheetApp.getActive(); }
function tz_() { return Session.getScriptTimeZone() || TZ_FALLBACK; }
function now_() { return Utilities.formatDate(new Date(), tz_(), "yyyy-MM-dd HH:mm"); }
function today_() { return Utilities.formatDate(new Date(), tz_(), "yyyy-MM-dd"); }

function readObjects_(tab) {
  const sh = ss_().getSheetByName(tab);
  if (!sh || sh.getLastRow() < 2) return [];
  const values = sh.getRange(1, 1, sh.getLastRow(), sh.getLastColumn()).getDisplayValues();
  const head = values[0];
  return values.slice(1).filter(r => r.some(c => c !== "")).map(r => {
    const o = {}; head.forEach((h, i) => { if (h) o[h] = r[i]; }); return o;
  });
}

function readConfig_() {
  const o = {};
  readObjects_("CONFIG").forEach(r => { if (r["Key"]) o[r["Key"]] = r["Value"]; });
  return o;
}
function cfgVal_(k) { return readConfig_()[k] || ""; }

function readLists_() {
  const sh = ss_().getSheetByName("LISTS");
  if (!sh) return {};
  const v = sh.getDataRange().getDisplayValues();
  const out = {};
  v[0].forEach((h, i) => { out[h] = v.slice(1).map(r => r[i]).filter(Boolean); });
  return out;
}

function readRMs_() { return readObjects_("ROSTER").filter(r => r["Group"] === "Sales").map(r => r["Name"]); }

function appendObj_(tab, obj) { appendRows_(tab, [obj]); }

// Appends rows matched by header name; extends the tab if it is full.
function appendRows_(tab, objs) {
  const sh = ss_().getSheetByName(tab);
  if (!sh) throw new Error("Tab not found: " + tab + ". Run Hyssop > Check setup.");
  const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getDisplayValues()[0];
  const data = objs.map(o => head.map(h => (o[h] !== undefined ? o[h] : "")));
  const start = Math.max(sh.getLastRow() + 1, 2);
  if (start + data.length - 1 > sh.getMaxRows()) sh.insertRowsAfter(sh.getMaxRows(), start + data.length - sh.getMaxRows());
  sh.getRange(start, 1, data.length, head.length).setValues(data);
}

/* ============================ VALIDATION ============================ */

function required_(p, keys) {
  keys.forEach(k => { if (p[k] === undefined || p[k] === null || String(p[k]).trim() === "") throw new Error("Please fill in: " + k); });
}
function nonNeg_(v, label) {
  const n = Number(v);
  if (!isFinite(n) || n < 0) throw new Error(label + " must be a number of 0 or more.");
  return n;
}
function int_(v, label) {
  const n = nonNeg_(v, label);
  if (!Number.isInteger(n)) throw new Error(label + " must be a whole number.");
  return n;
}
function checkPct_(unit, n, label) { if (unit === "%" && n > 100) throw new Error(label + " is a percentage and cannot exceed 100."); }
function pctOk_(v, label) { const n = nonNeg_(v, label); if (n > 100) throw new Error(label + " cannot exceed 100."); return n; }
function num_(v) { const n = Number(String(v).replace(/[,\sKES]/g, "")); return isFinite(n) ? n : 0; }

// Aliases (Nahasion) map to the canonical employee name.
function canonical_(name) {
  const k = String(name || "").trim();
  return ALIAS[k.toLowerCase()] || k;
}

function dateKey_(v) {
  const d = (v instanceof Date) ? v : new Date(String(v) + "T12:00:00");
  if (isNaN(d.getTime())) throw new Error("Invalid date: " + v);
  return Utilities.formatDate(d, tz_(), "yyyy-MM-dd");
}

// Monday on or before a date.
function weekStart_(v) {
  const k = dateKey_(v);
  const d = new Date(k + "T12:00:00");
  const diff = (d.getDay() + 6) % 7;
  return Utilities.formatDate(new Date(d.getTime() - diff * 86400000), tz_(), "yyyy-MM-dd");
}

function inRange_(v, from, to) { const k = String(v || "").slice(0, 10); return k >= from && k <= to; }

function projRow_(week, group, who, scorecard, kpi, value, unit, notes, support) {
  return { "Submitted At": now_(), "Week Starting": week, "Group": group, "Employee": who,
           "Scorecard": scorecard, "KPI": kpi, "Projected Value": value, "Unit": unit,
           "Plan / Notes": notes || "", "Support Needed": support || "" };
}
