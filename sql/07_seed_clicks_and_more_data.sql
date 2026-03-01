/* ============================================================================
  02_seed_data.sql  (Stage 2)
  Marketing Performance Analytics (SQL Server)

  Purpose:
  - Load a richer dataset with clicks + sessions + conversions
  - Keep costs_daily as source of truth, while enabling per-click cost
  - Include some orphan clicks (no session)

  Run after:
  - 01_tables.sql
============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN;

    /* ------------------------------------------------------------------------
       Clean existing data (child -> parent)
    ------------------------------------------------------------------------ */
    DELETE FROM marketing.conversions;
    DELETE FROM marketing.sessions;
    DELETE FROM marketing.clicks;
    DELETE FROM marketing.costs_daily;
    DELETE FROM marketing.users;
    DELETE FROM marketing.campaigns;

    /* ------------------------------------------------------------------------
       Parameters for seed volume
    ------------------------------------------------------------------------ */
    DECLARE @start_date  DATE = '2024-01-15';
    DECLARE @end_date    DATE = '2024-03-31';   -- inclusive
    DECLARE @users_count INT  = 50;

    /* ------------------------------------------------------------------------
       campaigns (3)
    ------------------------------------------------------------------------ */
    INSERT INTO marketing.campaigns (campaign_name, channel, start_date)
    VALUES
        (N'Google Search – Brand', N'Paid Search', '2024-02-01'),
        (N'Facebook Leads',        N'Paid Social', '2024-02-05'),
        (N'Organic Search',        N'Organic',     NULL);

    /* ------------------------------------------------------------------------
       users (generated)
    ------------------------------------------------------------------------ */
    ;WITH n AS
    (
        SELECT TOP (@users_count)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    )
    INSERT INTO marketing.users (first_seen_date, registration_date, country, gender)
    SELECT
        DATEADD(DAY, (n.n % 20), @start_date) AS first_seen_date,
        CASE WHEN n.n % 3 = 0 THEN DATEADD(DAY, (n.n % 20) + 1, @start_date) ELSE NULL END AS registration_date,
        CASE (n.n % 6)
            WHEN 0 THEN N'Israel'
            WHEN 1 THEN N'USA'
            WHEN 2 THEN N'UK'
            WHEN 3 THEN N'Germany'
            WHEN 4 THEN N'France'
            ELSE N'Canada'
        END AS country,
        CASE (n.n % 4)
            WHEN 0 THEN N'Female'
            WHEN 1 THEN N'Male'
            WHEN 2 THEN N'Other'
            ELSE N'Female'
        END AS gender
    FROM n;

    /* ------------------------------------------------------------------------
       Build date range (as a CTE)
    ------------------------------------------------------------------------ */
    ;WITH dates AS
    (
        SELECT @start_date AS d
        UNION ALL
        SELECT DATEADD(DAY, 1, d)
        FROM dates
        WHERE d < @end_date
    )
    /* ------------------------------------------------------------------------
       costs_daily
       - Paid Search + Paid Social have spend most days
       - Organic = 0
    ------------------------------------------------------------------------ */
    INSERT INTO marketing.costs_daily (cost_date, campaign_id, cost)
    SELECT
        dt.d AS cost_date,
        c.campaign_id,
        CASE
            WHEN c.channel = N'Organic' THEN 0.00
            WHEN c.channel = N'Paid Search' THEN
                CAST(80 + (ABS(CHECKSUM(CONCAT(c.campaign_id, dt.d))) % 141) AS DECIMAL(10,2))  -- 80..220
            WHEN c.channel = N'Paid Social' THEN
                CAST(60 + (ABS(CHECKSUM(CONCAT(c.campaign_id, dt.d))) % 121) AS DECIMAL(10,2))  -- 60..180
            ELSE 0.00
        END AS cost
    FROM dates dt
    CROSS JOIN marketing.campaigns c
    OPTION (MAXRECURSION 0);

    /* ------------------------------------------------------------------------
       clicks
       - generate many clicks per campaign-day
       - include click_datetime, device, landing_page, cost
       - later we'll create sessions for ~90% of clicks (orphan clicks remain)
    ------------------------------------------------------------------------ */
    ;WITH dates AS
    (
        SELECT @start_date AS d
        UNION ALL
        SELECT DATEADD(DAY, 1, d)
        FROM dates
        WHERE d < @end_date
    ),
    base AS
    (
        SELECT
            dt.d AS click_date,
            c.campaign_id,
            c.channel,
            cd.cost AS daily_cost,
            CASE
                WHEN c.channel = N'Organic' THEN 12
                WHEN c.channel = N'Paid Search' THEN 35
                WHEN c.channel = N'Paid Social' THEN 28
                ELSE 10
            END AS clicks_per_day
        FROM dates dt
        CROSS JOIN marketing.campaigns c
        LEFT JOIN marketing.costs_daily cd
            ON cd.cost_date = dt.d
           AND cd.campaign_id = c.campaign_id
    ),
    nums AS
    (
        SELECT TOP (200)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    ),
    clicks_expanded AS
    (
        SELECT
            b.click_date,
            b.campaign_id,
            b.channel,
            b.daily_cost,
            b.clicks_per_day,
            nums.n AS click_n
        FROM base b
        JOIN nums
          ON nums.n <= b.clicks_per_day
    ),
    clicks_with_cost AS
    (
        SELECT
            click_date,
            campaign_id,
            channel,

            /* spread daily cost across clicks (paid channels), add tiny noise */
            CAST(
                CASE
                    WHEN channel = N'Organic' THEN 0.00
                    ELSE
                        (
                            ISNULL(daily_cost, 0.00) / NULLIF(CAST(clicks_per_day AS DECIMAL(10,2)), 0)
                        )
                        *
                        (
                            1.0 + (
                                ( (ABS(CHECKSUM(CONCAT(campaign_id, click_date, click_n))) % 21) - 10 )
                                / 1000.0
                            )
                        )
                END
            AS DECIMAL(10,2)) AS click_cost,

            /* build click_datetime across the day */
            DATEADD(MINUTE,
                (ABS(CHECKSUM(CONCAT(campaign_id, click_date, click_n, 'm'))) % 1440),
                CAST(click_date AS DATETIME2(0))
            ) AS click_datetime,

            CASE (ABS(CHECKSUM(CONCAT(campaign_id, click_date, click_n, 'd'))) % 3)
                WHEN 0 THEN N'Mobile'
                WHEN 1 THEN N'Desktop'
                ELSE N'Tablet'
            END AS device,

            CASE (ABS(CHECKSUM(CONCAT(campaign_id, click_date, click_n, 'lp'))) % 5)
                WHEN 0 THEN N'/home'
                WHEN 1 THEN N'/landing'
                WHEN 2 THEN N'/services'
                WHEN 3 THEN N'/pricing'
                ELSE N'/contact'
            END AS landing_page
        FROM clicks_expanded
    )
    INSERT INTO marketing.clicks (campaign_id, click_datetime, cost)
    SELECT
        campaign_id,
        click_datetime,
        click_cost
    FROM clicks_with_cost
    OPTION (MAXRECURSION 0);

    /* ------------------------------------------------------------------------
       sessions
       - create sessions for ~90% of clicks (leave ~10% as orphan clicks)
       - link sessions.click_id to clicks.click_id
       - assign user_id deterministically (so reruns are stable)
    ------------------------------------------------------------------------ */
;WITH users_rn AS
(
    SELECT
        user_id,
        ROW_NUMBER() OVER (ORDER BY user_id) AS rn
    FROM marketing.users
),
users_cnt AS
(
    SELECT COUNT(*) AS cnt
    FROM marketing.users
)
INSERT INTO marketing.sessions (user_id, campaign_id, click_id, device, landing_page, session_datetime)
SELECT
    u.user_id,
    cl.campaign_id,
    cl.click_id,

    CASE (ABS(CHECKSUM(CONCAT(cl.campaign_id, CAST(cl.click_datetime AS DATE), cl.click_id, 'd'))) % 3)
        WHEN 0 THEN N'Mobile'
        WHEN 1 THEN N'Desktop'
        ELSE N'Tablet'
    END AS device,

    CASE (ABS(CHECKSUM(CONCAT(cl.campaign_id, CAST(cl.click_datetime AS DATE), cl.click_id, 'lp'))) % 5)
        WHEN 0 THEN N'/home'
        WHEN 1 THEN N'/landing'
        WHEN 2 THEN N'/services'
        WHEN 3 THEN N'/pricing'
        ELSE N'/contact'
    END AS landing_page,

    DATEADD(SECOND, (cl.click_id % 300), cl.click_datetime) AS session_datetime
FROM marketing.clicks cl
CROSS JOIN users_cnt uc
JOIN users_rn u
  ON u.rn = ((cl.click_id - 1) % uc.cnt) + 1
WHERE (cl.click_id % 10) <> 0;  -- ~10% orphan clicks



   /* ------------------------------------------------------------------------
   conversions (Stage 2 with realistic lag)
   - create conversions for some sessions
   - allow multiple conversions per session in some cases
   - conversion lag:
       * Purchase: D0..D30
       * Registration/Lead: D0..D7
------------------------------------------------------------------------ */
;WITH s AS
(
    SELECT session_id, session_datetime
    FROM marketing.sessions
),
conv_base AS
(
    SELECT
        s.session_id,
        s.session_datetime,
        CASE
            WHEN s.session_id % 13 = 0 THEN 2
            WHEN s.session_id % 5  = 0 THEN 1
            ELSE 0
        END AS conv_count
    FROM s
),
nums AS
(
    SELECT 1 AS n
    UNION ALL
    SELECT 2
),
conv_expanded AS
(
    SELECT
        cb.session_id,
        cb.session_datetime,
        nums.n AS conv_n,

        /* Lag logic (deterministic):
           - Purchase: lag can be up to 30 days (D0..D30)
           - Registration/Lead: lag up to 7 days (D0..D7)
        */
        CASE
            WHEN cb.session_id % 11 = 0 THEN (ABS(CHECKSUM(CONCAT(cb.session_id, nums.n, 'lag30'))) % 31)
            ELSE (ABS(CHECKSUM(CONCAT(cb.session_id, nums.n, 'lag7'))) % 8)
        END AS lag_days,

        /* Minute offset within the conversion day (deterministic) */
        (ABS(CHECKSUM(CONCAT(cb.session_id, nums.n, 'min'))) % 720) AS lag_minutes
    FROM conv_base cb
    JOIN nums
      ON nums.n <= cb.conv_count
)
INSERT INTO marketing.conversions (session_id, conversion_datetime, conversion_type, revenue)
SELECT
    ce.session_id,
    DATEADD(MINUTE, ce.lag_minutes,
        DATEADD(DAY, ce.lag_days, ce.session_datetime)
    ) AS conversion_datetime,
    CASE
        WHEN ce.session_id % 11 = 0 THEN N'Purchase'
        WHEN ce.session_id % 7  = 0 THEN N'Registration'
        ELSE N'Lead'
    END AS conversion_type,
    CAST(
        CASE
            WHEN ce.session_id % 11 = 0 THEN 120 + ((ce.session_id % 6) * 50)
            ELSE 0
        END
    AS DECIMAL(10,2)) AS revenue
FROM conv_expanded ce;

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @num INT = ERROR_NUMBER();
    DECLARE @line INT = ERROR_LINE();
    DECLARE @throw_msg NVARCHAR(2048) =
        CONCAT(N'02_seed_data.sql. Error ', @num, N' at line ', @line, N': ', @err);
    THROW 51000, @throw_msg, 1;
END CATCH;

