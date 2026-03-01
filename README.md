# Marketing Performance Analytics (SQL Server)

## Project Overview
This project simulates a marketing analytics database in SQL Server, enabling analysis of campaign performance across clicks, sessions, conversions, revenue, and spend.  
It is built as an interview-ready portfolio project: clean schema, reproducible seed data, analytical views, stored procedures, and a runnable demo query pack.

## What This Demonstrates
- Relational modeling + constraints (schemas, PK/FK, identity)
- Analytics logic (joins, aggregation, window functions)
- KPI design with safe division patterns (NULLIF)
- Reusable analytical layer (views + stored procedures)
- Cohort thinking (D0 / D7 / D30 windows) for insight stories

---

## Repo Structure (SQL)
**Core (Stage 2 – current)**
- `01_tables.sql` – creates schema + core tables (marketing.*)
- `06_schema_clicks.sql` – adds/updates schema objects required for the clicks model (Stage 2)
- `07_seed_clicks_and_more_data.sql` – Stage 2 seed data (clicks + sessions + conversions + realistic conversion lag)
- `03_views.sql` – analytical views:
  - `vw_sessions_enriched`
  - `vw_campaign_day_kpis` (Stage 2: click-driven daily KPIs)
- `04_procedures.sql` – stored procedures:
  - `sp_campaign_performance`
  - `sp_campaign_day_performance`
  - `sp_upsert_costs_daily` (kept as daily spend upsert example)
- `08_views_cohorts.sql` – cohort views:
  - `vw_click_cohort_cvr_d0_d7_d30`
  - `vw_click_cohort_device_cvr_d0_d7_d30`
- `05_queries_demo.sql` – demo query pack (includes “Insight Story” + “Cohort Analysis” sections)

**Legacy / Scratch**
- `02_seed_data.sql` – legacy Stage 1 seed (not part of the Stage 2 run order)
- `SQLQuery1.sql`, `SQLQuery2.sql` – drafts; best kept under `sql/scratch/` (optional)

---

## Data Model (schema: `marketing`)
### Tables
- `marketing.campaigns` – campaigns (campaign_name, channel, start_date)
- `marketing.users` – users (first_seen_date, optional registration_date, country, gender)
- `marketing.clicks` – click events (campaign_id, click_datetime, cost)
- `marketing.sessions` – sessions (user_id, campaign_id, click_id, device, landing_page, session_datetime)
- `marketing.conversions` – conversions (session_id, conversion_datetime, conversion_type, revenue)
- `marketing.costs_daily` – daily spend per campaign (cost_date + campaign_id composite PK)

### Key Relationships
- campaign → many clicks / sessions  
- click → zero-or-one session (some orphan clicks exist by design in seed data)  
- user → many sessions  
- session → zero-or-many conversions  
- costs_daily is maintained as a campaign-day “source of truth” example (via MERGE upsert)

---

## KPI Definitions (Stage 2)
- **CPS** = total conversions / total sessions  
- **CVR (GA4-style)** = sessions with ≥ 1 conversion / total sessions  
  - Implemented by counting each session once if it has at least one conversion.
- **ROAS** = revenue / cost  
  - Stage 2 daily views/procedures use **click-based cost** (`SUM(clicks.cost)`).

### Attribution Choice (Daily Reporting)
Daily outcomes (conversions/revenue) are aligned to the **session day** (`session_date`), not to `conversion_datetime`.

---

## Analytical Layer
### Views
- `marketing.vw_sessions_enriched`
  - Adds `session_date`
  - Adds `rn_user_session` and `is_new_user_session` based on `ROW_NUMBER()` over user history

- `marketing.vw_campaign_day_kpis` (Stage 2)
  - Daily campaign KPIs: clicks, sessions, new vs returning sessions, conversions, first_conversions, revenue, cost, CPS, CVR, ROAS
  - **Click-driven**: built from click-days; sessions/conversions joined by matching activity date

### Stored Procedures
- `marketing.sp_campaign_performance(@start_date, @end_date)`
  - Campaign-level KPIs for a date range (returns campaigns even with 0 activity)
  - Includes clicks, sessions, conversions, first_conversions, revenue, cost, CPS, CVR, ROAS

- `marketing.sp_campaign_day_performance(@start_date, @end_date)`
  - Campaign × date grid for the requested range
  - Joins sessions/conversions by session_date; joins clicks by click_date
  - Includes clicks, sessions, conversions, first_conversions, revenue, cost, CPS, CVR, ROAS

- `marketing.sp_upsert_costs_daily(@cost_date, @campaign_id, @cost)`
  - Upserts daily cost into `marketing.costs_daily` and returns an audit log
  - Included as an example of controlled ingestion via MERGE

---

## Cohort Analysis (Stage 2)
### Cohort Views
- `marketing.vw_click_cohort_cvr_d0_d7_d30`
  - Cohort granularity: `campaign_id + cohort_date`
  - Cohort = click cohort by calendar date: `cohort_date = CAST(click_datetime AS DATE)`
  - Windows: D0 / D7 / D30 (calendar-day windows)
  - Measures “converted sessions” in GA4-style (session counted once if it has ≥ 1 conversion)

- `marketing.vw_click_cohort_device_cvr_d0_d7_d30`
  - Same cohort logic, segmented by `device`
  - **Sessions-only** by design (excludes orphan clicks), because device is a session dimension

### Note on Cohort Windows
Cohort windows are currently **calendar-day based** (cohort_date), not timestamp-accurate windows based on `click_datetime`.  
This can be upgraded later if needed.

---

## Notes / Known Limitations (Stage 2)
- `vw_campaign_day_kpis` is click-driven: it includes days with clicks, and joins session-based metrics by `session_date`.  
  As a result, sessions that have no associated click (e.g., direct traffic) may be excluded from the daily view.  
  (Acceptable for this demo dataset; can be addressed later with a date grid / activity calendar.)

---

## How to Run (Stage 2)
Run scripts in this order:

1. `01_tables.sql`
2. `06_schema_clicks.sql`
3. `07_seed_clicks_and_more_data.sql`
4. `03_views.sql`
5. `04_procedures.sql`
6. `08_views_cohorts.sql`
7. `05_queries_demo.sql`

---

## Quick Demo
- Daily KPIs:
  - `SELECT TOP (50) * FROM marketing.vw_campaign_day_kpis ORDER BY activity_date DESC, campaign_id;`
- Campaign KPIs (range):
  - `EXEC marketing.sp_campaign_performance '2024-02-01','2024-03-31';`
- Campaign-day KPIs (range):
  - `EXEC marketing.sp_campaign_day_performance '2024-02-01','2024-03-31';`
- Cohorts:
  - `SELECT TOP (50) * FROM marketing.vw_click_cohort_cvr_d0_d7_d30 ORDER BY campaign_id, cohort_date;`
  - `SELECT TOP (50) * FROM marketing.vw_click_cohort_device_cvr_d0_d7_d30 ORDER BY campaign_id, cohort_date, device;`

---

## Tech Stack
- SQL Server
- T-SQL (tables, constraints, views, stored procedures, window functions)
