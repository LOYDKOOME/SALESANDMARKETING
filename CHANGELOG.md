# Changelog

## v4: money and plots reported separately (current)

**What changed for you**
- The BOOKINGS tab is now **SALES_ENTRIES**. Each row is one event:
  - **New booking**: plots sold, booked value, and any amount received at the same time.
  - **Collection (no new plot)**: money received from an existing or earlier client. Plots must be 0.
- A week with money in and no new plot is now recorded and shown. The dashboard reports **money collected** and **new plots** separately, and each week gets a plain-language scenario: *Plots and money in*, *Plots booked, money not yet in*, *Money in, no new plot*, or *No sales activity*.
- New sources: **Inooro TV**, **Citizen TV**, **Existing client** (all owned by Sales), so those sales show on the dashboard alongside digital sales.
- CONFIG has a new setting **Target_Basis** for how the RM money target is measured: *Best of both* (default), *Booked value*, or *Collected*.
- The sales projection asks RMs for money to collect, booked value, plots, calls, site visits and personal leads, and checks them against actuals.
- The Marketing dashboard shows the plots and money brought in by each digital source owner.
- The weekly and monthly email reports money collected, booked value, plots, money with no plot, and the RM status.

**Other fixes**
- A week with no RM data no longer breaks the RM table.
- Dashboard value boxes show the money and plots measures separately.

## v3
- Marketing and sales dashboard; forms for projections, leads and admin entry; weekly and monthly email; Chege and Nahasion treated as one person.

## v2
- Marketing KPI scoring engine and first dashboard (superseded).
