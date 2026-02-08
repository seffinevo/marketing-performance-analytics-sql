# Marketing Performance Analytics – SQL Server Project

## Project Overview
This project simulates a digital marketing analytics system built in SQL Server.
It enables analysis of marketing performance across campaigns, including traffic, conversions, revenue attribution, marketing spend, and user behavior (new vs returning users).

The project is designed end-to-end: from data modeling and constraints, through reproducible seed data, to business-focused analytical views, stored procedures, and demo queries.

## Goals
- Build an interview-ready SQL portfolio project beyond “course level”
- Demonstrate data modeling, KPI aggregation, and robust SQL patterns (joins, window functions, safe division, upsert)
- Provide an easy-to-run repo with reproducible outputs

## Repo Structure
- 01_tables.sql – create schema + tables + constraints
- 02_seed_data.sql – insert seed data (safe to re-run)
- 03_views.sql – create analytical views
- 04_procedures.sql – create stored procedures
- 05_queries_demo.sql – demo queries (validation + examples)

## Data Model (schema: marketing)
### Tables
- marketing.campaigns – marketing campaigns (name, channel, start_date)
- marketing.users – users (first_seen_date, optional registration_date, country, gender)
- marketing.sessions – sessions (FKs to users + campaigns, device, landing_page, session_datetime)
- marketing.conversions – conversions (FK to sessions, conversion_datetime, conversion_type, revenue)
- marketing.costs_daily – daily spend per campaign (composite PK: cost_date + campaign_id)

Key relationships:
- One campaign → many sessions
- One user → many sessions
- One session → zero or more conversions
- One campaign + date → one cost record

## Analytical Layer
### Views
- marketing.vw_sessions_enriched
  - Adds session sequencing per user (rn_user_session) and an is_new_user_session flag using ROW_NUMBER()

- marketing.vw_campaign_day_kpis
  - Daily KPI aggregation per campaign:
    - sessions, new vs returning sessions
    - conversions, revenue
    - cost, conversion_rate, ROAS
  - Important note: this view intentionally includes only days with traffic (sessions).
    Days with cost but no sessions are not included (by design). For a full campaign×date grid, use marketing.sp_campaign_day_performance.

### Stored Procedures
- marketing.sp_campaign_performance(@start_date, @end_date)
  - Campaign-level KPIs for a date range (returns campaigns even with 0 activity)

- marketing.sp_campaign_day_performance(@start_date, @end_date)
  - Campaign-day KPIs using a campaign × date grid for the requested range (includes zero-activity days)

- marketing.sp_upsert_costs_daily(@cost_date, @campaign_id, @cost)
  - Upsert daily cost into marketing.costs_daily (insert/update)

## Business Questions Answered
- How much traffic does each campaign generate?
- How many conversions and how much revenue does each campaign produce?
- What is the conversion rate per campaign?
- What is the ROAS (Return on Ad Spend) by campaign and by day?
- How many sessions come from new users vs returning users over time?
- What are the top revenue days per campaign and how do conversion types differ?

## How to Run
Run scripts in this order:
1) 01_tables.sql
2) 02_seed_data.sql
3) 03_views.sql
4) 04_procedures.sql
5) 05_queries_demo.sql

## Design Decisions
- Costs at campaign-day level (marketing.costs_daily)
  - Matches common ad platform reporting granularity.

- Daily attribution aligns revenue to session_date (not conversion_datetime)
  - In daily reporting, outcomes are aligned to the day the session happened, so traffic+cost vs outcome are comparable on the same day.

- New vs Returning definition is global
  - “New user session” is the user’s first-ever session in the dataset, not “new within the selected date range”.

- marketing.vw_campaign_day_kpis includes only traffic days
  - The view returns only dates where sessions exist (by design). For “full grid” reporting use marketing.sp_campaign_day_performance.

- Safe division patterns
  - Calculations use safe division patterns (NULLIF) to avoid divide-by-zero issues.

## Notes / Known Limitations (Stage 1)
- The seed script (02_seed_data.sql) is safe to re-run because it deletes existing rows (child → parent) and inserts data again.
- Date grid logic is implemented inside a stored procedure. Stage 2 improvement: replace this with a dedicated Calendar/Date dimension table.

## Quick Demo
After running all scripts, you can:
- Query marketing.vw_campaign_day_kpis for daily KPIs
- Run:
  - EXEC marketing.sp_campaign_performance '2024-02-10', '2024-02-22';
  - EXEC marketing.sp_campaign_day_performance '2024-02-10', '2024-02-22';
- Use 05_queries_demo.sql to see example analysis queries (window functions, top days, breakdown by conversion type, etc.)

## Technologies
- SQL Server
- T-SQL (tables, constraints, views, stored procedures, analytical queries)
