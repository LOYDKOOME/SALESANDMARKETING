# Deployment guide: from zero to a live dashboard on Posit Connect

Work through the parts in order. Parts 1 to 3 set up the data and forms. Parts 4 to 6 publish the dashboard from GitHub. Allow about one afternoon the first time.

You need: a Google Workspace account (for "Anyone within your organisation" access), a GitHub account, and Posit Connect access with permission to publish content and set environment variables.

---

## Part 1: The Google Sheet

1. Download `HYSSOP_PERFORMANCE_TEMPLATE.xlsx` from this package.
2. Open Google Drive, click **New > File upload**, choose the file, then right-click it and choose **Open with > Google Sheets**. (Use Google Sheets, not Excel, so the dropdowns and Apps Script work.)
3. Rename it, for example `HYSSOP PERFORMANCE DATA`.
4. Copy the **Sheet ID** from the URL. It is the long string between `/d/` and `/edit`. You will use it in Parts 4 and 5.
5. Open **CONFIG** and fill in:
   - `ProgramStart`: the first Monday of Month 1, as `YYYY-MM-DD`.
   - `AdminEmails`: the Google accounts allowed to enter actuals (comma separated).
   - `ReportEmails`: who receives the weekly and monthly email.
   - Leave `StaffEmails` blank unless you want to restrict the forms to a list.
6. Open **LISTS** and replace the placeholder projects, sites and logistics persons with your real names. The forms and dropdowns read from here.
7. Open **ROSTER** and check the names. Chege is listed with alias Nahasion. Set `Active` to `No` for anyone who has left.
8. Share the sheet with your staff only as needed. **Give employees no edit access.** Staff use the forms, which write on their behalf.

## Part 2: Apps Script and the web forms

1. In the sheet, click **Extensions > Apps Script**.
2. Delete the default `Code.gs` content and paste in the package's `Code.gs`.
3. Click the **+** next to Files, choose **HTML**, and name it exactly `Index` (no extension). Paste the contents of `Index.html`.
4. Click **Project Settings** (gear icon), tick **Show "appsscript.json" manifest file in editor**, go back to the editor and paste the package's `appsscript.json`.
5. Click **Save project** (disk icon).
6. In the function dropdown choose `setupHyssopSystem` and click **Run**. Authorise the requested permissions (the account must be an admin email). It checks that all tabs exist and installs the email triggers. It never deletes data.
7. Click **Deploy > New deployment**. Choose the type **Web app**:
   - Execute as: **Me** (the deployer). This lets staff submit forms without edit access to the sheet.
   - Who has access: **Anyone within [your organisation]**.
8. Click **Deploy**, authorise, and copy the **Web app URL**. Your pages are:
   - Projections (marketers and RMs): `URL?page=projection`
   - Lead capture: `URL?page=leads`
   - Admin entry (4 options): `URL?page=admin`
9. Bookmark those three links, or put them on the team's WhatsApp group.

**Test the forms now.** Submit one projection, one lead, one site visit and one booking with test values, then check that each appears in its tab. Delete the test rows afterwards (Edit > Delete rows). Check that a non-admin account opening `?page=admin` is refused.

## Part 3: Weekly and monthly email

The triggers were installed in Part 2 step 6. To confirm:

1. In the sheet, open the **Hyssop** menu and choose **Send weekly report now**. The weekly email goes to `ReportEmails`. Check it arrives and looks right.
2. Triggers run automatically: weekly on Monday at 07:00 for the previous week, and monthly on the 1st at 08:00 for the previous month (Africa/Nairobi time).
3. To change the schedule, edit `installReportTriggers` in `Code.gs`, run it again, and check **Triggers** (clock icon) in Apps Script.

## Part 4: Google service account (dashboard access)

The dashboard needs its own read-only identity. Do not use a personal account on the server.

1. Go to <https://console.cloud.google.com>. Create a project, for example `hyssop-dashboard`.
2. **APIs & Services > Library**: search for **Google Sheets API** and **Google Drive API**, and enable both.
3. **IAM & Admin > Service Accounts > Create service account**. Name it `hyssop-dashboard-reader`. Skip the optional role steps. Click **Done**.
4. Open the new account, go to **Keys > Add key > Create new key > JSON**. A `.json` file downloads. **Keep it private.** Never commit it to GitHub.
5. Copy the service account's email address (it looks like `hyssop-dashboard-reader@your-project.iam.gserviceaccount.com`).
6. Back in the Google Sheet, click **Share**, paste that email, set the role to **Viewer**, untick "Notify people", and click **Share**.

## Part 5: Test the dashboard on your computer

1. Install R (4.3 or newer) and RStudio.
2. Open a terminal in the project folder and install the packages once:
   ```r
   install.packages(c("shiny", "shinydashboard", "googlesheets4", "dplyr", "tidyr",
                      "plotly", "DT", "scales", "lubridate", "stringr", "rsconnect"))
   ```
3. Create a file named `.Renviron` in the project folder (it is ignored by Git):
   ```
   HYSSOP_SHEET_ID=paste-your-sheet-id-here
   HYSSOP_SA_JSON=C:/path/to/your-service-account-key.json
   ```
   Restart R after saving so the file is read.
4. Run the app from the project folder:
   ```r
   shiny::runApp()
   ```
   The first time, R asks you to sign in to Google in the browser. Use an account that can see the sheet. (This sign-in is only for your computer. Connect uses the service account.)
5. Check each page. Enter a few test forms and refresh. An empty page usually means the sheet has no data yet. Check the **Data health** page for the reason.

## Part 6: Publish the dashboard from GitHub to Posit Connect

### 6a. Put the project on GitHub

1. Create a **private** repository on GitHub, for example `hyssop-performance`. Keep it private because it describes staff and performance.
2. On your computer, in the project folder:
   ```bash
   git init
   git add .
   git commit -m "Hyssop performance system v3"
   git branch -M main
   git remote add origin https://github.com/YOUR-USER/hyssop-performance.git
   git push -u origin main
   ```
3. Check on GitHub that **no** `.json` key, `.Renviron` or `.secrets/` file was uploaded. `appsscript.json` should be there. The `.gitignore` in the package protects you, but check once.

### 6b. Create the manifest (required by Connect)

Connect needs a `manifest.json` that lists the R packages the app uses. Create it once, and again whenever you add a package.

```r
setwd("path/to/hyssop-performance")
rsconnect::writeManifest(appDir = ".", appPrimaryDoc = "app.R")
```

Then commit and push it:

```bash
git add manifest.json
git commit -m "Add manifest for Posit Connect"
git push
```

### 6c. Publish on Posit Connect

Connect offers two ways to publish. Use whichever your Connect admin has enabled.

**Option 1: Git-backed deployment (publish straight from GitHub)**

1. In Posit Connect, click **+ New Content**, then **Git-backed** (or **Deploy from Git**, depending on your version).
2. Enter the repository URL, `https://github.com/YOUR-USER/hyssop-performance`, and branch `main`. Choose the app directory `/` (the root) and the primary file `app.R`.
3. For a private repository, connect your GitHub account when Connect asks (or add a deploy key or token as your admin instructs).
4. Click **Create** and let Connect build. The first build takes a few minutes while it installs packages.

**Option 2: Deploy from your computer with rsconnect**

Use this if Git-backed content is not enabled. Once only, register your Connect server:

```r
rsconnect::addConnectServer("https://connect.yourcompany.com", "hyssop-connect")
rsconnect::connectUser(account = "your-connect-username", server = "hyssop-connect")
```

Then deploy:

```r
rsconnect::deployApp(appDir = ".", appPrimaryDoc = "app.R", appName = "hyssop-performance",
                     server = "hyssop-connect")
```

### 6d. Set the secrets on Connect (do this before the first visit)

The app will not start without these. Never type them into the code.

1. Open the app in Connect, go to **Settings > Vars** (called **Environment variables** in some versions).
2. Add `HYSSOP_SHEET_ID` with the Sheet ID from Part 1.
3. Add `HYSSOP_SA_JSON` and paste the **entire contents** of the service account JSON file (open the file in a text editor, select all, copy, paste). Start with `{` and end with `}`.
4. Save, then **restart** the content (or **Redeploy**).

### 6e. Who can see the dashboard

1. Open the app's **Settings > Access**.
2. Choose **Specific users or groups** and add the management team only. Do not choose "Anyone".
3. Copy the app's URL and send it to management.

### 6f. Updating later

- **Git-backed:** push to GitHub, then click **Redeploy** in Connect (or enable automatic deployment on push if your admin allows it).
- **rsconnect:** run `rsconnect::deployApp(...)` again.
- After adding any package, run `rsconnect::writeManifest()` again and push the new `manifest.json`.

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Dashboard says "Set HYSSOP_SHEET_ID" | The variable is missing on Connect (Part 6d). Add it and restart. |
| Dashboard says "Load failed" or a tab is missing | The service account is not shared on the sheet as Viewer (Part 4 step 6), or the tab was renamed. Restore the name in the template. |
| Admin page says "Admin only" | Your Google account is not in `AdminEmails` in CONFIG. Add it, or sign in with an admin account. |
| A form says "Unknown KPI for this role" | The KPI name in the form no longer matches KPI_LIBRARY. Re-copy the library from the template. |
| Weekly email did not arrive | Check **ReportEmails** in CONFIG, and that the trigger ran (Apps Script > Triggers > Executions). Send one manually from the Hyssop menu. |
| An RM shows red for weeks before they joined | Expected until you set the period start on the dashboard sidebar. Their earlier weeks show zero. |
| Chege appears as "Nahasion" anywhere | Should not happen: Nahasion is converted to Chege in the forms and in the dashboard. Check the ROSTER alias. |
| Connect build fails on a package | Install the package locally, run `rsconnect::writeManifest()`, push, and redeploy. |
| Dashboard numbers look wrong | Open **Data health** first. Then check the SALES_ENTRIES tab for missing projects, zero-plot bookings, or plots on collections. |

## Security checklist before go-live

- [ ] The sheet is private. Only the admin team and the service account can open it.
- [ ] The service account key is not in GitHub, and only lives in Connect Vars and in your secure local folder.
- [ ] The Connect app is shared with the management group only.
- [ ] The admin page refuses a non-admin test account.
- [ ] Client contact numbers are only in the LEADS "Contact (Restricted)" column. The dashboard never reads that column.
- [ ] You have deleted all test rows from every data tab.
