/* ============================================================================
  05_queries_demo.sql
  Marketing Performance Analytics – SQL Server Project

  Purpose:
  - Demo analytics queries answering common marketing questions
  - Organized as a runnable "question pack" for reviewers/recruiters

  Notes:
  - Early queries (Q1–Q6) run directly on base tables.
  - Later queries use marketing.vw_campaign_day_kpis (aggregated daily KPIs).
============================================================================ */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------------
   Quick sanity checks (optional)
--------------------------------------------------------------------------- */
SELECT TOP (5) * FROM marketing.campaigns ORDER BY campaign_id;
SELECT TOP (5) * FROM marketing.sessions ORDER BY session_datetime;
SELECT TOP (5) * FROM marketing.conversions ORDER BY conversion_datetime;
SELECT TOP (5) * FROM marketing.costs_daily ORDER BY cost_date, campaign_id;
GO


/* ============================================================================
   Q1) Traffic per campaign (sessions count)
============================================================================ */
SELECT
    c.campaign_name,
    c.channel,
    COUNT(s.session_id) AS sessions
FROM marketing.campaigns c
LEFT JOIN marketing.sessions s
    ON s.campaign_id = c.campaign_id
GROUP BY
    c.campaign_name,
    c.channel
ORDER BY sessions DESC;
GO


/* ============================================================================
   Q2) Conversions and revenue per campaign
   - Uses sessions as the bridge to conversions
============================================================================ */
SELECT
    c.campaign_name,
    COUNT(DISTINCT s.session_id)      AS sessions,
    COUNT(DISTINCT cv.conversion_id)  AS conversions,
    ISNULL(SUM(cv.revenue), 0)        AS revenue
FROM marketing.campaigns c
LEFT JOIN marketing.sessions s
    ON s.campaign_id = c.campaign_id
LEFT JOIN marketing.conversions cv
    ON cv.session_id = s.session_id
GROUP BY
    c.campaign_name
ORDER BY revenue DESC, conversions DESC, sessions DESC;
GO


/* ============================================================================
   Q3) Conversion rate per campaign
   - conversion_rate = conversions / sessions
============================================================================ */
SELECT
    c.campaign_name,
    COUNT(DISTINCT s.session_id)     AS sessions,
    COUNT(DISTINCT cv.conversion_id) AS conversions,
    CAST(
        CAST(COUNT(DISTINCT cv.conversion_id) AS DECIMAL(10,2))
        / NULLIF(CAST(COUNT(DISTINCT s.session_id) AS DECIMAL(10,2)), 0)
        AS DECIMAL(10,2)
    ) AS conversion_rate
FROM marketing.campaigns c
LEFT JOIN marketing.sessions s
    ON s.campaign_id = c.campaign_id
LEFT JOIN marketing.conversions cv
    ON cv.session_id = s.session_id
GROUP BY
    c.campaign_name
ORDER BY conversion_rate DESC, conversions DESC, sessions DESC;
GO


/* ============================================================================
   Q4) ROAS by campaign-day (from base tables)
   - ROAS = revenue / cost
   - Matches cost (campaign_id + cost_date) to session day
============================================================================ */
SELECT
    cd.cost_date,
    c.campaign_name,
    cd.cost,
    ISNULL(SUM(cv.revenue), 0) AS revenue,
    CAST(
        ISNULL(
            CAST(ISNULL(SUM(cv.revenue), 0) AS DECIMAL(10,2))
            / NULLIF(CAST(cd.cost AS DECIMAL(10,2)), 0),
        0)
        AS DECIMAL(10,2)
    ) AS ROAS
FROM marketing.costs_daily cd
JOIN marketing.campaigns c
    ON c.campaign_id = cd.campaign_id
LEFT JOIN marketing.sessions s
    ON s.campaign_id = cd.campaign_id
   AND CAST(s.session_datetime AS DATE) = cd.cost_date
LEFT JOIN marketing.conversions cv
    ON cv.session_id = s.session_id
GROUP BY
    cd.cost_date,
    c.campaign_name,
    cd.cost
ORDER BY
    cd.cost_date,
    c.campaign_name;
GO


/* ============================================================================
   Q5) Conversion mix (count + revenue by conversion_type)
============================================================================ */
SELECT
    conversion_type,
    COUNT(*) AS conversions,
    ISNULL(SUM(revenue), 0) AS revenue
FROM marketing.conversions
GROUP BY conversion_type
ORDER BY conversions DESC, revenue DESC;
GO


/* ============================================================================
   Q6) New vs Returning sessions (daily trend) using window function
   Definition:
   - A "new user session" is the first recorded session of the user (overall),
     not first within the selected date range.
============================================================================ */
DECLARE @start_date DATE = '2024-02-15';
DECLARE @end_date   DATE = '2024-02-28';

WITH s_rn AS
(
    SELECT
        s.user_id,
        s.session_id,
        s.session_datetime,
        CAST(s.session_datetime AS DATE) AS session_date,
        ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY s.session_datetime) AS rn
    FROM marketing.sessions s
),
s_flagged AS
(
    SELECT
        session_date,
        CASE WHEN rn = 1 THEN 1 ELSE 0 END AS is_new_user_session,
        CASE WHEN rn > 1 THEN 1 ELSE 0 END AS is_returning_session
    FROM s_rn
)
SELECT
    session_date,
    SUM(is_new_user_session)  AS new_user_sessions,
    SUM(is_returning_session) AS returning_sessions,
    COUNT(*)                  AS total_sessions,
    CAST(
        CAST(SUM(is_new_user_session) AS DECIMAL(10,2))
        / NULLIF(CAST(COUNT(*) AS DECIMAL(10,2)), 0)
        AS DECIMAL(10,2)
    ) AS pct_new_sessions
FROM s_flagged
WHERE session_date BETWEEN @start_date AND @end_date
GROUP BY session_date
ORDER BY session_date;
GO


/* ============================================================================
   Views-based section (uses marketing.vw_campaign_day_kpis)
============================================================================ */

/* ============================================================================
   Q7) Top revenue day per campaign (from vw_campaign_day_kpis)
============================================================================ */
SELECT
    campaign_id,
    campaign_name,
    channel,
    activity_date,
    sessions,
    conversions,
    revenue,
    cost,
    ROAS
FROM
(
    SELECT
        k.*,
        ROW_NUMBER() OVER (
            PARTITION BY campaign_id
            ORDER BY revenue DESC, conversions DESC, sessions DESC
        ) AS rn
    FROM marketing.vw_campaign_day_kpis k
) AS ranked
WHERE rn = 1
ORDER BY revenue DESC, campaign_id;
GO


/* ============================================================================
   Q8) Campaign totals (aggregated) from vw_campaign_day_kpis
============================================================================ */
SELECT
    campaign_id,
    campaign_name,
    channel,
    SUM(sessions)    AS total_sessions,
    SUM(conversions) AS total_conversions,
    SUM(revenue)     AS total_revenue,
    SUM(cost)        AS total_cost,
    CAST(
        CAST(SUM(conversions) AS DECIMAL(10,2))
        / NULLIF(CAST(SUM(sessions) AS DECIMAL(10,2)), 0)
        AS DECIMAL(10,2)
    ) AS conversion_rate_total,
    CAST(
        CAST(SUM(revenue) AS DECIMAL(10,2))
        / NULLIF(CAST(SUM(cost) AS DECIMAL(10,2)), 0)
        AS DECIMAL(10,2)
    ) AS ROAS_total
FROM marketing.vw_campaign_day_kpis
GROUP BY
    campaign_id,
    campaign_name,
    channel
ORDER BY total_revenue DESC, total_sessions DESC;
GO


/* ============================================================================
   Q9) New vs Returning trend (all campaigns) from vw_campaign_day_kpis
============================================================================ */
SELECT
    activity_date,
    SUM(new_user_sessions)    AS new_user_sessions,
    SUM(returning_sessions)   AS returning_sessions,
    SUM(sessions)             AS total_sessions,
    CAST(
        CAST(SUM(new_user_sessions) AS DECIMAL(10,2))
        / NULLIF(CAST(SUM(sessions) AS DECIMAL(10,2)), 0)
        AS DECIMAL(10,2)
    ) AS pct_new_sessions
FROM marketing.vw_campaign_day_kpis
GROUP BY activity_date
ORDER BY activity_date;
GO
