/* ============================================================================
  08_views_cohorts.sql
  Marketing Performance Analytics (SQL Server) — Stage 2+

  Purpose:
  - Create cohort-analysis views based on click cohorts (cohort_date = click day).
  - Provide D0 / D7 / D30 converted-session counts and CVR metrics per:
      (campaign_id, cohort_date)

  Definitions:
  - Cohort: click cohort by calendar date
      cohort_date = CAST(click_datetime AS DATE)
  - Window:
      D0  = same calendar day as cohort_date
      D7  = conversions with first_conversion_datetime < cohort_date + 8 days
      D30 = conversions with first_conversion_datetime < cohort_date + 31 days
    (These are calendar-day windows, not timestamp-accurate windows.)

  Conversion logic:
  - We measure "converted sessions" in GA4-style:
      A session is counted as converted if it has >= 1 conversion event.
  - We use the FIRST conversion datetime per session (MIN(conversion_datetime))
    and count the session once if that first conversion falls within the window.

  Notes / Design choice:
  - This view uses calendar-day cohort windows (cohort_date based).
    It does NOT measure windows from the exact click timestamp.
    (Can be upgraded later to timestamp-accurate windows if needed.)

  Dependencies:
  - marketing.clicks (click_id, campaign_id, click_datetime)
  - marketing.sessions (session_id, click_id)
  - marketing.conversions (conversion_id, session_id, conversion_datetime)
============================================================================ */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW marketing.vw_click_cohort_cvr_d0_d7_d30
AS
WITH base AS
(
    /* One row per click with cohort_date by calendar day */
    SELECT
        CAST(cl.click_datetime AS DATE) AS cohort_date,
        cl.click_id,
        cl.campaign_id
    FROM marketing.clicks cl
),
clicks_sessions AS
(
    /* Link clicks -> sessions (orphan clicks will have NULL session_id) */
    SELECT
        b.cohort_date,
        b.click_id,
        b.campaign_id,
        s.session_id
    FROM base b
    LEFT JOIN marketing.sessions s
        ON s.click_id = b.click_id
),
first_conversion_per_session AS
(
    /* For each (click, session), find first conversion datetime (if any) */
    SELECT
        cs.cohort_date,
        cs.campaign_id,
        cs.click_id,
        cs.session_id,
        MIN(c.conversion_datetime) AS first_conversion_datetime
    FROM clicks_sessions cs
    LEFT JOIN marketing.conversions c
        ON c.session_id = cs.session_id
    GROUP BY
        cs.cohort_date,
        cs.campaign_id,
        cs.click_id,
        cs.session_id
)
SELECT
    cohort_date,
    campaign_id,

    /* Cohort sizes */
    COUNT(click_id)   AS clicks,
    COUNT(session_id) AS sessions,

    /* Converted sessions (D0 / D7 / D30)
       - These are counts of sessions where the FIRST conversion falls in window.
       - Using COUNT(<datetime>) counts only non-NULL values (converted sessions).
    */
    COUNT(CASE
            WHEN CAST(first_conversion_datetime AS DATE) = cohort_date
            THEN first_conversion_datetime
          END) AS sessions_converted_D0,

    COUNT(CASE
            WHEN first_conversion_datetime < DATEADD(DAY, 8, CAST(cohort_date AS DATETIME2(0)))
            THEN first_conversion_datetime
          END) AS sessions_converted_D7,

    COUNT(CASE
            WHEN first_conversion_datetime < DATEADD(DAY, 31, CAST(cohort_date AS DATETIME2(0)))
            THEN first_conversion_datetime
          END) AS sessions_converted_D30,

    /* CVR metrics (GA4-style)
       CVR_Dx = converted_sessions_Dx / total_sessions
       - When sessions=0 => NULL (safe division)
    */
    CAST(
        CAST(
            COUNT(CASE
                    WHEN CAST(first_conversion_datetime AS DATE) = cohort_date
                    THEN first_conversion_datetime
                 END) AS DECIMAL(10,5)
        )
        / NULLIF(CAST(COUNT(session_id) AS DECIMAL(10,5)), 0)
    AS DECIMAL(10,2)) AS CVR_D0,

    CAST(
        CAST(
            COUNT(CASE
                    WHEN first_conversion_datetime < DATEADD(DAY, 8, CAST(cohort_date AS DATETIME2(0)))
                    THEN first_conversion_datetime
                 END) AS DECIMAL(10,5)
        )
        / NULLIF(CAST(COUNT(session_id) AS DECIMAL(10,5)), 0)
    AS DECIMAL(10,2)) AS CVR_D7,

    CAST(
        CAST(
            COUNT(CASE
                    WHEN first_conversion_datetime < DATEADD(DAY, 31, CAST(cohort_date AS DATETIME2(0)))
                    THEN first_conversion_datetime
                 END) AS DECIMAL(10,5)
        )
        / NULLIF(CAST(COUNT(session_id) AS DECIMAL(10,5)), 0)
    AS DECIMAL(10,2)) AS CVR_D30

FROM first_conversion_per_session
GROUP BY
    cohort_date,
    campaign_id;
GO

/* ---------------------------------------------------------------------------
  Suggested quick checks (keep these in your demo queries file, not in this file)
  Example:
    SELECT TOP (20) *
    FROM marketing.vw_click_cohort_cvr_d0_d7_d30
    ORDER BY campaign_id, cohort_date;
--------------------------------------------------------------------------- */

/* ============================================================================
  View: marketing.vw_click_cohort_device_cvr_d0_d7_d30
  File: 08_views_cohorts.sql  (Stage 2+)

  Purpose:
  - Cohort analysis segmented by device.
  - Provides D0 / D7 / D30 converted-session counts and CVR metrics per:
      (campaign_id, cohort_date, device)

  Definitions:
  - Cohort: click cohort by calendar date
      cohort_date = CAST(click_datetime AS DATE)
  - Window (calendar-day windows):
      D0  = same calendar day as cohort_date
      D7  = first conversion datetime < cohort_date + 8 days
      D30 = first conversion datetime < cohort_date + 31 days

  Conversion logic (GA4-style):
  - A session is counted as converted if it has >= 1 conversion event.
  - We compute FIRST conversion datetime per session (MIN(conversion_datetime))
    and count the session once if that first conversion falls within the window.

  Important note (sessions-only):
  - This view is sessions-only by design:
      orphan clicks (clicks without sessions) are excluded.
  - Device comes from marketing.sessions.device, so it is not meaningful for orphan clicks.

  Dependencies:
  - marketing.clicks (click_id, campaign_id, click_datetime)
  - marketing.sessions (session_id, click_id, device, session_datetime)
  - marketing.conversions (conversion_id, session_id, conversion_datetime)
============================================================================ */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW marketing.vw_click_cohort_device_cvr_d0_d7_d30
AS
WITH base AS
(
    /* One row per click with cohort_date by calendar day */
    SELECT
        CAST(cl.click_datetime AS DATE) AS cohort_date,
        cl.click_id,
        cl.campaign_id
    FROM marketing.clicks cl
),
clicks_sessions AS
(
    /* Sessions-only: keep only clicks that produced a session (excludes orphan clicks) */
    SELECT
        b.cohort_date,
        b.campaign_id,
        s.session_id,
        s.device
    FROM base b
    INNER JOIN marketing.sessions s
        ON s.click_id = b.click_id
),
first_conversion_per_session AS
(
    /* For each (cohort_date, campaign_id, device, session), find first conversion datetime (if any) */
    SELECT
        cs.cohort_date,
        cs.campaign_id,
        cs.device,
        cs.session_id,
        MIN(c.conversion_datetime) AS first_conversion_datetime
    FROM clicks_sessions cs
    LEFT JOIN marketing.conversions c
        ON c.session_id = cs.session_id
    GROUP BY
        cs.cohort_date,
        cs.campaign_id,
        cs.device,
        cs.session_id
)
SELECT
    cohort_date,
    campaign_id,
    device,

    /* cohort size (sessions-only) */
    COUNT(session_id) AS sessions,

    /* converted sessions: first conversion within window */
    COUNT(CASE
            WHEN CAST(first_conversion_datetime AS DATE) = cohort_date
            THEN first_conversion_datetime
          END) AS sessions_converted_D0,

    COUNT(CASE
            WHEN first_conversion_datetime < DATEADD(DAY, 8, CAST(cohort_date AS DATETIME2(0)))
            THEN first_conversion_datetime
          END) AS sessions_converted_D7,

    COUNT(CASE
            WHEN first_conversion_datetime < DATEADD(DAY, 31, CAST(cohort_date AS DATETIME2(0)))
            THEN first_conversion_datetime
          END) AS sessions_converted_D30,

    /* CVR metrics (GA4-style): converted sessions / total sessions */
    CAST(
        CAST(
            COUNT(CASE
                    WHEN CAST(first_conversion_datetime AS DATE) = cohort_date
                    THEN first_conversion_datetime
                 END) AS DECIMAL(10,5)
        )
        / NULLIF(CAST(COUNT(session_id) AS DECIMAL(10,5)), 0)
    AS DECIMAL(10,2)) AS CVR_D0,

    CAST(
        CAST(
            COUNT(CASE
                    WHEN first_conversion_datetime < DATEADD(DAY, 8, CAST(cohort_date AS DATETIME2(0)))
                    THEN first_conversion_datetime
                 END) AS DECIMAL(10,5)
        )
        / NULLIF(CAST(COUNT(session_id) AS DECIMAL(10,5)), 0)
    AS DECIMAL(10,2)) AS CVR_D7,

    CAST(
        CAST(
            COUNT(CASE
                    WHEN first_conversion_datetime < DATEADD(DAY, 31, CAST(cohort_date AS DATETIME2(0)))
                    THEN first_conversion_datetime
                 END) AS DECIMAL(10,5)
        )
        / NULLIF(CAST(COUNT(session_id) AS DECIMAL(10,5)), 0)
    AS DECIMAL(10,2)) AS CVR_D30

FROM first_conversion_per_session
GROUP BY
    cohort_date,
    campaign_id,
    device;
GO