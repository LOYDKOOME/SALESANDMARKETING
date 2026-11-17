# Hyssop Performance System v3

Marketing and sales performance in one system: data is entered through web forms into one Google Sheet, and a read-only R Shiny dashboard (hosted on Posit Connect from GitHub) shows management the results. A weekly and monthly email report goes to management automatically.

```
Web forms (Apps Script)                 Google Sheet (system of record)             Dashboard (R Shiny)
 projection: marketers by role  ─┐       PROJECTIONS, ACTUALS_*, MARKETING_OUTPUT   ┌─ Executive
 projection: RMs                ─┤       LEADS, SITE_VISITS, SALES_ENTRIES, ACTION_LOG ──┼─ Sales RM performance
 lead capture                   ─┼──►    ROSTER, KPI_LIBRARY, CONFIG, LISTS       ├─ RM profiles
 admin: 4 entry options         ─┘                    │                            ├─ Projects and analysis
                                                      │                            ├─ Marketing
 Weekly and monthly email  ◄── Apps Script triggers ◄─┘                            ├─ Alerts and actions
                                                                                   └─ Data health
```

## What is in this package

| File | Purpose |
|---|---|
| `app.R` | The dashboard (one file, deployable as is) |
| `Code.gs` | Apps Script: web forms backend, validation, weekly and monthly email |
| `Index.html` | The three form pages (projection, lead capture, admin entry) |
| `appsscript.json` | Time zone (Africa/Nairobi), web app settings, required permissions |
| `HYSSOP_PERFORMANCE_TEMPLATE.xlsx` | The Google Sheet template: upload to Drive and open with Google Sheets |
| `docs/DEPLOYMENT.md` | Step by step: Google Sheet, Apps Script, forms, GitHub, Posit Connect |
| `docs/KPI_COVERAGE.md` | Every approved KPI and where its number comes from |
| `tools/build_template.py` | Rebuilds the Google Sheet template (for developers) |
| `.gitignore` | Keeps keys and secrets out of GitHub |

## Dashboard pages

1. **Executive dashboard**: money collected, booked value of new plots, new plots, money in with no new plot, leads, visits and conversion; a weekly trend of booked value, money collected, plots and projection; a **week-by-week story** that says exactly what happened (plots and money in, plots only, money only); how many RMs had money in without a new plot; leads, plots and money by project; RM contribution; funnel; and the **alert panel** for RMs red 2 or more weeks in a row.
2. **Sales and collections**: league table with colour status and each RM's latest scenario, attainment heatmap by RM and week, projection against actual (money, booked value, plots).
3. **RM profiles**: pick an RM for money collected, booked value, plots, latest status and scenario, weekly record (what happened, actual, projected), funnel and follow-up history.
4. **Projects and analysis**: money collected by project each week, project summary (plots, booked value, money in, money with no plot), plots and money by tribe, gender and lead source, and visits by location.
5. **Marketing dashboard**: monthly scorecards for Dan, Faith, Derrick and Chege (Nahasion), KPI detail with colour status, weekly commitment against actual, sales (plots and money) from each digital source owner, marketing output by platform, and leads by source.
6. **Alerts and actions**: every red week for each RM, the underperformer flag, and the action log.
7. **Data health and library**: data checks and the approved KPI library.

Colour rules used everywhere: **green** = 100% of target or more (marketing: 85 and above, bonus-eligible); **amber** = 70 to 99% (marketing: 70 to 84, on track); **red** = below 70% (marketing: below 70, coaching plan). An RM or marketer red for **2 consecutive completed weeks** is flagged as underperforming in the alert panel.

## How the numbers are defined

Sales are recorded as events in **SALES_ENTRIES**, in one of two types:

- **New booking**: plots sold. It records the number of plots, the booked value of those plots, and any money received at the same time (a deposit).
- **Collection (no new plot)**: money received from an existing or earlier client, with no new plot. Plots must be 0.

The dashboard keeps the two measures separate, so nothing is blended:

- **New plots** count only on New booking rows.
- **Booked value** is the value of the plots sold.
- **Money collected** is all cash received, from any entry type.
- **Money with no new plot** is cash received on collection rows. It is shown separately, so a week with money in and no plot is visible.
- **What happened** for each week (company and RM) is one of four scenarios: *Plots and money in*, *Plots booked, money not yet in*, *Money in, no new plot*, or *No sales activity*.

**RM target.** Each RM's weekly money target (KES 1,000,000) is measured by the setting `Target_Basis` in CONFIG: *Best of both* (default, the higher of booked value and money collected), *Booked value*, or *Collected*. Plots are measured separately against the plots target (3). Attainment is the higher of the money and plots ratios, capped at 120%.

**Sources.** Every sale, lead and visit carries a source. Digital sources credit the marketer who owns them (TikTok to Faith, Instagram to Chege, Facebook to Derrick, Meta Ads and Website to Dan, Influencer to the Marketing Coordinator). Inooro TV, Citizen TV, Existing client, Referral and Walk-in belong to Sales. The Marketing dashboard shows the sales each digital owner brought in.

**Leads, visits and weeks.** Leads are credited to the owner of their source. Duplicate leads (same name and project) are excluded. Site visits count when completed or converted. Weeks start on Monday, and the current week is never flagged until it has ended.

**Marketing scores** use each scorecard's category weights from the company documents. Dan's score is 70% Ads and 30% Website. A missing value counts as zero and is shown as "No data".

## Quick start

1. Read `docs/DEPLOYMENT.md` from start to finish once. It takes about one afternoon, including the Google service account and Posit Connect.
2. Upload `HYSSOP_PERFORMANCE_TEMPLATE.xlsx` to Google Drive and open it with Google Sheets. Note the Sheet ID from its URL.
3. Fill in **CONFIG** (program start, admin emails, report recipients) and the placeholder names in **LISTS** (projects, sites, logistics people).
4. Paste `Code.gs`, `Index.html` and `appsscript.json` into the sheet's Apps Script project, run `setupHyssopSystem`, and deploy the web app.
5. Push this repository to GitHub, publish `app.R` on Posit Connect, and set the environment variables.

## Decisions to confirm (your call, each is one setting)

- **Project names.** The template uses placeholders ("Project A (rename me)"). Replace them in LISTS before go-live.
- **RM calls and site-visit targets.** The brief gives no numbers. They are blank in KPI_LIBRARY, so they show on the dashboard but are not scored until you set them.
- **Personal leads target.** Set at 45 a week (3 plots times 15 leads per close). Change it in KPI_LIBRARY.
- **Collections without a plot** are counted as money for the RM and the company, and are never counted as plots. Confirm that is the rule you want.
- **RM money target basis.** Default is "Best of both" (booked value or money collected, whichever is higher), because the brief says "3 plots or 1M in a week". Change `Target_Basis` in CONFIG to "Booked value" or "Collected" to use one measure only.
- **Chege and Nahasion.** These are one person. Every record is stored as Chege, and Nahasion is an alias that is converted automatically in the forms and the dashboard.
- **Faith holds two roles.** Her form asks which role she is filling in (Digital or Marketing Coordinator). Her two scorecards are kept separate.
- **"Qualified" leads.** A lead counts as qualified when its status is Site visited, Sales assigned (RM), or Sale closed. Change this rule in `app.R` if you define it differently.
- **Contact within 15 minutes** for Dan's ads is typed in by the admin from CRM timestamps, because the lead form does not capture those times.

## Not included, and why

- **Live platform APIs** (TikTok, Meta, GA4). The numbers are entered from exports at week end. Connecting the APIs is a separate phase.
- **Marketing scores inside the email.** The email covers sales, leads, visits and the RM status. Marketing scorecards are on the dashboard. A combined email can be added as a scheduled R report later.

## Testing status

- The scoring and calculation code was run against realistic sample data (19 RMs, four marketers, nine weeks, one duplicate lead, one RM with a deliberate three-week slump). The alert fired correctly, the duplicate was excluded, and the in-progress week was not flagged.
- Every dashboard output was rendered in a test session without errors.
- `Code.gs` and the form JavaScript pass syntax checks.
- **Still to test in your environment:** the three web forms in a browser with real Google accounts, the admin access check, the email trigger, and the dashboard on Posit Connect with your real service account. Test in a copy of the sheet first.
