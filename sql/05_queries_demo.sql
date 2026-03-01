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

/* ---------------------------------------------------------------------------
   Quick sanity checks (optional)
--------------------------------------------------------------------------- */
SELECT TOP (5) * FROM marketing.campaigns ORDER BY campaign_id;
SELECT TOP (5) * FROM marketing.clicks ORDER BY click_datetime;
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
   Q3) Campaign KPI snapshot (clicks + sessions + conversions)
   - CPS = total conversions / total sessions
   - CVR = sessions with >=1 conversion / total sessions
   - ROAS = revenue / cost (cost from clicks)
============================================================================ */
;WITH conv_per_session AS
(
    SELECT
        s.campaign_id,
        s.session_id,
        COUNT(cv.conversion_id)      AS conversions,
        MIN(cv.conversion_id)        AS first_conversion,   -- NULL when no conversions in session
        SUM(cv.revenue)              AS revenue
    FROM marketing.sessions s
    LEFT JOIN marketing.conversions cv
        ON cv.session_id = s.session_id
    GROUP BY
        s.campaign_id,
        s.session_id
),
agg_sessions AS
(
    SELECT
        campaign_id,
        COUNT(*) AS sessions
    FROM marketing.sessions
    GROUP BY campaign_id
),
agg_conversions AS
(
    SELECT
        campaign_id,
        SUM(conversions)            AS conversions,
        COUNT(first_conversion)     AS first_conversions,   -- sessions with >= 1 conversion
        SUM(revenue)                AS revenue
    FROM conv_per_session
    GROUP BY campaign_id
),
agg_clicks AS
(
    SELECT
        campaign_id,
        COUNT(*)     AS clicks,
        SUM(cost)    AS cost
    FROM marketing.clicks
    GROUP BY campaign_id
)
SELECT
    c.campaign_name,
    ISNULL(cl.clicks, 0)              AS clicks,
    ISNULL(s.sessions, 0)             AS sessions,
    ISNULL(cv.conversions, 0)         AS conversions,
    ISNULL(cv.first_conversions, 0)   AS first_conversions,
    ISNULL(cv.revenue, 0)             AS revenue,
    ISNULL(cl.cost, 0)                AS cost,

    /* CPS: conversions / sessions (0 when sessions=0) */
    CAST(
        ISNULL(
            CAST(ISNULL(cv.conversions, 0) AS DECIMAL(10,2))
            / NULLIF(CAST(ISNULL(s.sessions, 0) AS DECIMAL(10,2)), 0),
        0)
    AS DECIMAL(10,2)) AS CPS,

    /* CVR: sessions_with_conversion / sessions (0 when sessions=0) */
    CAST(
        ISNULL(
            CAST(ISNULL(cv.first_conversions, 0) AS DECIMAL(10,2))
            / NULLIF(CAST(ISNULL(s.sessions, 0) AS DECIMAL(10,2)), 0),
        0)
    AS DECIMAL(10,2)) AS CVR,

    /* ROAS: revenue / cost (0 when cost=0) */
    CAST(
        ISNULL(
            CAST(ISNULL(cv.revenue, 0) AS DECIMAL(10,2))
            / NULLIF(CAST(ISNULL(cl.cost, 0) AS DECIMAL(10,2)), 0),
        0)
    AS DECIMAL(10,2)) AS ROAS
FROM marketing.campaigns c
LEFT JOIN agg_clicks cl
    ON cl.campaign_id = c.campaign_id
LEFT JOIN agg_sessions s
    ON s.campaign_id = c.campaign_id
LEFT JOIN agg_conversions cv
    ON cv.campaign_id = c.campaign_id
ORDER BY ROAS DESC, revenue DESC, sessions DESC;
GO


/* ============================================================================
   Q4) Campaign-day KPIs (click-based cost)
   - Click-driven (includes click-only days)
   - Daily rollup by click date (sessions joined via click_id)
============================================================================ */
;WITH clicks_day AS
(
    SELECT
        cl.campaign_id,
        CAST(cl.click_datetime AS DATE) AS activity_date,
        COUNT(*)                        AS clicks,
        SUM(cl.cost)                    AS cost
    FROM marketing.clicks cl
    GROUP BY
        cl.campaign_id,
        CAST(cl.click_datetime AS DATE)
),
conv_per_session_clickday AS
(
    SELECT
        cl.campaign_id,
        CAST(cl.click_datetime AS DATE) AS activity_date,
        s.session_id,
        COUNT(cv.conversion_id)         AS conversions,
        MIN(cv.conversion_id)           AS first_conversion,
        SUM(cv.revenue)                 AS revenue
    FROM marketing.sessions s
    JOIN marketing.clicks cl
        ON cl.click_id = s.click_id
    LEFT JOIN marketing.conversions cv
        ON cv.session_id = s.session_id
    GROUP BY
        cl.campaign_id,
        CAST(cl.click_datetime AS DATE),
        s.session_id
),
sessions_conv_day AS
(
    SELECT
        campaign_id,
        activity_date,
        COUNT(*)                    AS sessions,
        SUM(conversions)            AS conversions,
        COUNT(first_conversion)     AS first_conversions,
        SUM(revenue)                AS revenue
    FROM conv_per_session_clickday
    GROUP BY
        campaign_id,
        activity_date
)
SELECT
    cd.activity_date,
    c.campaign_name,
    c.channel,
    cd.clicks,
    ISNULL(sc.sessions, 0)           AS sessions,
    ISNULL(sc.conversions, 0)        AS conversions,
    ISNULL(sc.first_conversions, 0)  AS first_conversions,
    ISNULL(sc.revenue, 0)            AS revenue,
    ISNULL(cd.cost, 0)               AS cost,

    CAST(
        ISNULL(
            CAST(ISNULL(sc.conversions, 0) AS DECIMAL(10,2))
            / NULLIF(CAST(ISNULL(sc.sessions, 0) AS DECIMAL(10,2)), 0),
        0)
    AS DECIMAL(10,2)) AS CPS,

    CAST(
        ISNULL(
            CAST(ISNULL(sc.first_conversions, 0) AS DECIMAL(10,2))
            / NULLIF(CAST(ISNULL(sc.sessions, 0) AS DECIMAL(10,2)), 0),
        0)
    AS DECIMAL(10,2)) AS CVR,

    CAST(
        ISNULL(
            CAST(ISNULL(sc.revenue, 0) AS DECIMAL(10,2))
            / NULLIF(CAST(ISNULL(cd.cost, 0) AS DECIMAL(10,2)), 0),
        0)
    AS DECIMAL(10,2)) AS ROAS
FROM clicks_day cd
JOIN marketing.campaigns c
    ON c.campaign_id = cd.campaign_id
LEFT JOIN sessions_conv_day sc
    ON sc.campaign_id = cd.campaign_id
   AND sc.activity_date = cd.activity_date
ORDER BY
    cd.activity_date,
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
    clicks,
    sessions,
    conversions,
    first_conversions,
    revenue,
    cost,
    CPS,
    CVR,
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
    SUM(clicks)              AS total_clicks,
    SUM(sessions)            AS total_sessions,
    SUM(conversions)         AS total_conversions,
    SUM(first_conversions)   AS total_first_conversions,
    SUM(revenue)             AS total_revenue,
    SUM(cost)                AS total_cost,

    CAST(
        CAST(SUM(conversions) AS DECIMAL(10,2))
        / NULLIF(CAST(SUM(sessions) AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CPS_total,

    CAST(
        CAST(SUM(first_conversions) AS DECIMAL(10,2))
        / NULLIF(CAST(SUM(sessions) AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CVR_total,

    CAST(
        CAST(SUM(revenue) AS DECIMAL(10,2))
        / NULLIF(CAST(SUM(cost) AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS ROAS_total
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


/* ============================================================================
   Insight Story Queries (Stage 2) — clicks-based cost + CPS/CVR
   Schema: clicks -> sessions (optional) -> conversions (optional)
============================================================================ */

/* ----------------------------------------------------------------------------
10) Conversion KPIs per Campaign + Landing Page
   - CPS = total conversions / total sessions
   - CVR = sessions with >=1 conversion / total sessions
   Notes:
   - Landing page is taken from session when exists, otherwise from click (orphan clicks)
---------------------------------------------------------------------------- */
;WITH base AS
(
    SELECT
        cl.click_id,
        cl.campaign_id,
        COALESCE(s.landing_page, 'Orphan clicks (no session)') AS landing_page,
        s.session_id,
        cl.cost
    FROM marketing.clicks cl
    LEFT JOIN marketing.sessions s
        ON s.click_id = cl.click_id
),
per_session AS
(
    SELECT
        b.campaign_id,
        b.landing_page,
        b.session_id,
        COUNT(cv.conversion_id) AS conversions_per_session,
        MIN(cv.conversion_id)   AS first_conversion,
        SUM(cv.revenue)         AS revenue_per_session
    FROM base b
    LEFT JOIN marketing.conversions cv
        ON cv.session_id = b.session_id
    WHERE b.session_id IS NOT NULL
    GROUP BY
        b.campaign_id,
        b.landing_page,
        b.session_id
),
agg AS
(
    SELECT
        b.campaign_id,
        b.landing_page,
        COUNT(b.click_id) AS clicks,
        SUM(ISNULL(b.cost, 0)) AS cost,

        /* sessions-based metrics (only rows that actually have sessions) */
        COUNT(ps.session_id) AS sessions,
        SUM(ISNULL(ps.conversions_per_session, 0)) AS conversions,
        COUNT(ps.first_conversion) AS first_conversions,
        SUM(ISNULL(ps.revenue_per_session, 0)) AS revenue
    FROM base b
    LEFT JOIN per_session ps
        ON ps.campaign_id = b.campaign_id
       AND ps.landing_page = b.landing_page
       AND ps.session_id = b.session_id
    GROUP BY
        b.campaign_id,
        b.landing_page
)
SELECT
    c.campaign_id,
    c.campaign_name,
    a.landing_page,
    a.clicks,
    a.sessions,
    (a.clicks - a.sessions) AS orphan_clicks,
    a.conversions,
    a.first_conversions,
    a.revenue,
    a.cost,

    CAST(
        CAST(a.conversions AS DECIMAL(10,2))
        / NULLIF(CAST(a.sessions AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CPS,

    CAST(
        CAST(a.first_conversions AS DECIMAL(10,2))
        / NULLIF(CAST(a.sessions AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CVR,

    CAST(
        CAST(a.revenue AS DECIMAL(10,2))
        / NULLIF(CAST(a.cost AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS ROAS
FROM agg a
JOIN marketing.campaigns c
    ON c.campaign_id = a.campaign_id
ORDER BY
    c.campaign_id,
    a.landing_page;


/* ----------------------------------------------------------------------------
11) KPI per Campaign per Device (includes orphan clicks as a separate device bucket)
---------------------------------------------------------------------------- */
;WITH base AS
(
    SELECT
        cl.campaign_id,
        COALESCE(s.device, N'Orphan clicks (no session)') AS device,
        s.session_id,
        cl.click_id,
        cl.cost
    FROM marketing.clicks cl
    LEFT JOIN marketing.sessions s
        ON s.click_id = cl.click_id
),
per_session AS
(
    SELECT
        b.campaign_id,
        b.device,
        b.session_id,
        COUNT(cv.conversion_id) AS conversions_per_session,
        MIN(cv.conversion_id)   AS first_conversion,
        SUM(cv.revenue)         AS revenue_per_session
    FROM base b
    LEFT JOIN marketing.conversions cv
        ON cv.session_id = b.session_id
    WHERE b.session_id IS NOT NULL
    GROUP BY
        b.campaign_id,
        b.device,
        b.session_id
),
agg AS
(
    SELECT
        b.campaign_id,
        b.device,
        COUNT(b.click_id) AS clicks,
        SUM(ISNULL(b.cost, 0)) AS cost,

        COUNT(ps.session_id) AS sessions,
        SUM(ISNULL(ps.conversions_per_session, 0)) AS conversions,
        COUNT(ps.first_conversion) AS first_conversions,
        SUM(ISNULL(ps.revenue_per_session, 0)) AS revenue
    FROM base b
    LEFT JOIN per_session ps
        ON ps.campaign_id = b.campaign_id
       AND ps.device = b.device
       AND ps.session_id = b.session_id
    GROUP BY
        b.campaign_id,
        b.device
)
SELECT
    c.campaign_id,
    c.campaign_name,
    a.device,
    a.clicks,
    a.sessions,
    (a.clicks - a.sessions) AS orphan_clicks,
    a.conversions,
    a.first_conversions,
    a.revenue,
    a.cost,

    CAST(
        CAST(a.conversions AS DECIMAL(10,2))
        / NULLIF(CAST(a.sessions AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CPS,

    CAST(
        CAST(a.first_conversions AS DECIMAL(10,2))
        / NULLIF(CAST(a.sessions AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS CVR,

    CAST(
        CAST(a.revenue AS DECIMAL(10,2))
        / NULLIF(CAST(a.cost AS DECIMAL(10,2)), 0)
    AS DECIMAL(10,2)) AS ROAS
FROM agg a
JOIN marketing.campaigns c
    ON c.campaign_id = a.campaign_id
ORDER BY
    c.campaign_id,
    a.device;


/* ============================================================================
   Cohort Analysis (Stage 2)
   Based on:
   - marketing.vw_click_cohort_cvr_d0_d7_d30
   - marketing.vw_click_cohort_device_cvr_d0_d7_d30
============================================================================ */

DECLARE @cohort_start DATE = '2024-02-01';
DECLARE @cohort_end   DATE = '2024-02-28';
GO

/* ---------------------------------------------------------------------------
   C1) Cohort day lift (per campaign + cohort_date)
--------------------------------------------------------------------------- */
SELECT
    v.cohort_date,
    v.campaign_id,
    c.campaign_name,
    v.sessions_converted_D0,
    v.sessions_converted_D7,
    v.sessions_converted_D30,
    v.CVR_D0,
    v.CVR_D7,
    v.CVR_D30,
    (v.CVR_D7 - v.CVR_D0)  AS lift_0_to_7,
    (v.CVR_D30 - v.CVR_D7) AS lift_7_to_30
FROM marketing.vw_click_cohort_cvr_d0_d7_d30 v
JOIN marketing.campaigns c
    ON c.campaign_id = v.campaign_id
WHERE v.cohort_date BETWEEN @cohort_start AND @cohort_end
ORDER BY v.campaign_id, v.cohort_date;
GO

/* ---------------------------------------------------------------------------
   C2) Weighted CVR + lift per campaign (rollup over cohort dates)
--------------------------------------------------------------------------- */
;WITH rollup AS
(
    SELECT
        v.campaign_id,
        SUM(v.sessions) AS total_sessions,
        SUM(v.sessions_converted_D0)  AS conv_sessions_D0,
        SUM(v.sessions_converted_D7)  AS conv_sessions_D7,
        SUM(v.sessions_converted_D30) AS conv_sessions_D30
    FROM marketing.vw_click_cohort_cvr_d0_d7_d30 v
    WHERE v.cohort_date BETWEEN @cohort_start AND @cohort_end
    GROUP BY v.campaign_id
)
SELECT
    r.campaign_id,
    c.campaign_name,
    r.total_sessions,
    r.conv_sessions_D0,
    r.conv_sessions_D7,
    r.conv_sessions_D30,

    CAST(CAST(r.conv_sessions_D0  AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0) AS DECIMAL(10,2)) AS CVR_D0,
    CAST(CAST(r.conv_sessions_D7  AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0) AS DECIMAL(10,2)) AS CVR_D7,
    CAST(CAST(r.conv_sessions_D30 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0) AS DECIMAL(10,2)) AS CVR_D30,

    CAST(
        CAST(r.conv_sessions_D7 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
        - CAST(r.conv_sessions_D0 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
    AS DECIMAL(10,2)) AS lift_0_to_7,

    CAST(
        CAST(r.conv_sessions_D30 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
        - CAST(r.conv_sessions_D7 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
    AS DECIMAL(10,2)) AS lift_7_to_30
FROM rollup r
JOIN marketing.campaigns c
    ON c.campaign_id = r.campaign_id
ORDER BY CVR_D7 DESC, total_sessions DESC;
GO

/* ---------------------------------------------------------------------------
   C3) Weighted CVR + lift per campaign + device (sessions-only cohort view)
--------------------------------------------------------------------------- */
;WITH rollup AS
(
    SELECT
        v.campaign_id,
        v.device,
        SUM(v.sessions) AS total_sessions,
        SUM(v.sessions_converted_D0)  AS conv_sessions_D0,
        SUM(v.sessions_converted_D7)  AS conv_sessions_D7,
        SUM(v.sessions_converted_D30) AS conv_sessions_D30
    FROM marketing.vw_click_cohort_device_cvr_d0_d7_d30 v
    WHERE v.cohort_date BETWEEN @cohort_start AND @cohort_end
    GROUP BY
        v.campaign_id,
        v.device
)
SELECT
    r.campaign_id,
    c.campaign_name,
    r.device,
    r.total_sessions,
    r.conv_sessions_D7,

    CAST(CAST(r.conv_sessions_D0  AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0) AS DECIMAL(10,2)) AS CVR_D0,
    CAST(CAST(r.conv_sessions_D7  AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0) AS DECIMAL(10,2)) AS CVR_D7,
    CAST(CAST(r.conv_sessions_D30 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0) AS DECIMAL(10,2)) AS CVR_D30,

    CAST(
        CAST(r.conv_sessions_D7 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
        - CAST(r.conv_sessions_D0 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
    AS DECIMAL(10,2)) AS lift_0_to_7,

    CAST(
        CAST(r.conv_sessions_D30 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
        - CAST(r.conv_sessions_D7 AS DECIMAL(10,5)) / NULLIF(r.total_sessions, 0)
    AS DECIMAL(10,2)) AS lift_7_to_30
FROM rollup r
JOIN marketing.campaigns c
    ON c.campaign_id = r.campaign_id
ORDER BY r.campaign_id, lift_0_to_7 DESC, r.total_sessions DESC;
GO
