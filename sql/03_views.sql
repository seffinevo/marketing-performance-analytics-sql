/* ============================================================================
  03_views.sql
  Marketing Performance Analytics (SQL Server)

  Purpose:
  - Create analytical views used by reporting queries and procedures
  - Keep logic reusable, readable, and consistent

  Notes:
  - vw_campaign_day_kpis includes ONLY days with traffic (sessions).
    It is a deliberate reporting choice for this project.
============================================================================ */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------------
   View 1: vw_sessions_enriched
   - Adds session_date
   - Flags whether a session is the user's first recorded session (new user)
--------------------------------------------------------------------------- */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW marketing.vw_sessions_enriched
AS
WITH s_rn AS
(
    SELECT
        s.user_id,
        s.session_id,
        s.campaign_id,
        s.landing_page,
        s.device,
        s.session_datetime,
        CAST(s.session_datetime AS DATE) AS session_date,
        ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY s.session_datetime) AS rn_user_session
    FROM marketing.sessions s
)
SELECT
    user_id,
    session_id,
    campaign_id,
    landing_page,
    device,
    session_datetime,
    session_date,
    rn_user_session,
    CASE WHEN rn_user_session = 1 THEN 1 ELSE 0 END AS is_new_user_session
FROM s_rn;
GO

/* ---------------------------------------------------------------------------
   View 2: vw_campaign_day_kpis
   - Campaign-day KPIs (sessions, new/returning, conversions, revenue, cost)
   - Attribution note: revenue/conversions are aligned to the SESSION day
   - IMPORTANT: This view returns only dates where sessions exist (traffic days)
--------------------------------------------------------------------------- */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW marketing.vw_campaign_day_kpis
AS
WITH agg_sessions AS
(
    SELECT
        se.campaign_id,
        se.session_date AS activity_date,
        COUNT(*) AS sessions,
        SUM(se.is_new_user_session) AS new_user_sessions,
        COUNT(*) - SUM(se.is_new_user_session) AS returning_sessions
    FROM marketing.vw_sessions_enriched se
    GROUP BY
        se.campaign_id,
        se.session_date
),
agg_conversions AS
(
    SELECT
        s.campaign_id,
        CAST(s.session_datetime AS DATE) AS activity_date,
        COUNT(DISTINCT cv.conversion_id) AS conversions,
        SUM(cv.revenue) AS revenue
    FROM marketing.sessions s
    LEFT JOIN marketing.conversions cv
        ON cv.session_id = s.session_id
    GROUP BY
        s.campaign_id,
        CAST(s.session_datetime AS DATE)
),
agg_costs AS
(
    SELECT
        cd.campaign_id,
        cd.cost_date AS activity_date,
        SUM(cd.cost) AS cost
    FROM marketing.costs_daily cd
    GROUP BY
        cd.campaign_id,
        cd.cost_date
)
SELECT
    c.campaign_id,
    c.campaign_name,
    c.channel,
    s.activity_date,
    s.sessions,
    s.new_user_sessions,
    s.returning_sessions,

    ISNULL(cv.conversions, 0) AS conversions,
    ISNULL(cv.revenue, 0) AS revenue,
    ISNULL(co.cost, 0) AS cost,

    /* rates */
    CAST(
        CAST(ISNULL(cv.conversions, 0) AS DECIMAL(10,2))
        / NULLIF(CAST(s.sessions AS DECIMAL(10,2)), 0)
        AS DECIMAL(10,2)
    ) AS conversion_rate,

    CAST(
        CAST(ISNULL(cv.revenue, 0) AS DECIMAL(10,2))
        / NULLIF(CAST(ISNULL(co.cost, 0) AS DECIMAL(10,2)), 0)
        AS DECIMAL(10,2)
    ) AS ROAS

FROM agg_sessions s
JOIN marketing.campaigns c
    ON c.campaign_id = s.campaign_id
LEFT JOIN agg_conversions cv
    ON cv.campaign_id = s.campaign_id
   AND cv.activity_date = s.activity_date
LEFT JOIN agg_costs co
    ON co.campaign_id = s.campaign_id
   AND co.activity_date = s.activity_date;
GO
