/* ============================================================================
  03_views.sql
  Marketing Performance Analytics (SQL Server)

  Purpose:
  - Create analytical views used by reporting queries and procedures
  - Keep logic reusable, readable, and consistent
============================================================================ */

/* ============================================================================
    Stage 2: vw_campaign_day_kpis updated to include clicks-based cost + CVR (sessions with >=1 conversion / sessions)
   Note: click-driven daily view; direct sessions without click may be excluded.
============================================================================*/

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
   - This view is click-driven (includes days with clicks). Sessions without 
     associated clicks (direct) may be excluded
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
        cvi.campaign_id,
        cvi.activity_date,
        SUM(cvi.conversions) AS conversions,
        COUNT(cvi.first_conversion) AS first_conversions, 
        SUM(cvi.revenue) AS revenue
    FROM
    (
        SELECT 
            s.campaign_id,
            s.session_id,
            CAST(s.session_datetime AS DATE) AS activity_date,
            COUNT(cv.conversion_id) AS conversions,
            MIN(cv.conversion_id) AS first_conversion,
            SUM(cv.revenue) AS revenue
        FROM marketing.sessions s
        LEFT JOIN marketing.conversions cv
            ON cv.session_id = s.session_id
        GROUP BY 
            s.campaign_id,
            s.session_id,
            CAST(s.session_datetime AS DATE)
    ) AS cvi
    GROUP BY
        cvi.campaign_id,
        cvi.activity_date
),
agg_clicks AS
(
    SELECT
        cl.campaign_id,
        CAST(cl.click_datetime AS DATE) AS activity_date,
        COUNT(cl.click_id) AS clicks,
        SUM(cl.cost) AS cost
    FROM marketing.clicks cl
    GROUP BY 
        cl.campaign_id,
        CAST(cl.click_datetime AS DATE)

)
SELECT
    cl.campaign_id,
    c.campaign_name,
    c.channel,
    cl.activity_date,
    ISNULL(s.sessions, 0) AS sessions,
    ISNULL(s.new_user_sessions, 0) AS new_user_sessions,
    ISNULL(s.returning_sessions, 0) AS returning_sessions,
    ISNULL(cl.clicks, 0) AS clicks,
    ISNULL(cv.conversions, 0) AS conversions,
    ISNULL(cv.first_conversions, 0) AS first_conversions,
    ISNULL(cv.revenue, 0) AS revenue,
    ISNULL(cl.cost, 0) AS cost,

    /* rates */
    CAST(
        CAST(ISNULL(cv.conversions, 0) AS DECIMAL(10,2))
        / NULLIF(CAST(ISNULL(s.sessions, 0) AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CPS,

    CAST(
        CAST(ISNULL(cv.first_conversions, 0) AS DECIMAL(10,2))
        / NULLIF(CAST(ISNULL(s.sessions, 0) AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CVR,

    CAST(
        CAST(ISNULL(cv.revenue, 0) AS DECIMAL(10,2))
        / NULLIF(CAST(ISNULL(cl.cost, 0) AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS ROAS

FROM agg_clicks cl
JOIN marketing.campaigns c
    ON c.campaign_id = cl.campaign_id
LEFT JOIN agg_sessions s
    ON s.campaign_id = cl.campaign_id
   AND s.activity_date = cl.activity_date
LEFT JOIN agg_conversions cv
    ON cv.campaign_id = cl.campaign_id
   AND cv.activity_date = cl.activity_date;
GO

