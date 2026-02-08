/* ============================================================================
  04_procedures.sql
  Marketing Performance Analytics (SQL Server)

  Contents:
  1) sp_campaign_performance      - KPIs by campaign (range)
  2) sp_campaign_day_performance  - KPIs by campaign-day (range)
  3) sp_upsert_costs_daily        - Upsert cost for a campaign-day (MERGE)

  Notes:
  - Reporting procedures do not modify data, so no explicit transaction is required
  - Upsert procedure uses TRY/CATCH, XACT_ABORT, and returns an audit log
============================================================================ */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------------
   1) Campaign performance (range)
--------------------------------------------------------------------------- */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE marketing.sp_campaign_performance
    @start_date DATE,
    @end_date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    /* Basic parameter validation */
    IF @start_date IS NULL OR @end_date IS NULL
        THROW 50010, 'start_date and end_date are required', 1;

    IF @start_date > @end_date
        THROW 50011, 'start_date cannot be after end_date', 1;

    ;WITH sessions_conv AS
    (
        SELECT
            s.campaign_id,
            COUNT(DISTINCT s.session_id) AS sessions,
            COUNT(DISTINCT cv.conversion_id) AS conversions,
            SUM(cv.revenue) AS revenue
        FROM marketing.sessions s
        LEFT JOIN marketing.conversions cv
            ON cv.session_id = s.session_id
        WHERE CAST(s.session_datetime AS DATE) BETWEEN @start_date AND @end_date
        GROUP BY s.campaign_id
    ),
    costs AS
    (
        SELECT
            campaign_id,
            SUM(cost) AS cost
        FROM marketing.costs_daily
        WHERE cost_date BETWEEN @start_date AND @end_date
        GROUP BY campaign_id
    )
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.channel,

        ISNULL(sc.sessions, 0)     AS sessions,
        ISNULL(sc.conversions, 0)  AS conversions,
        ISNULL(sc.revenue, 0)      AS revenue,
        ISNULL(cd.cost, 0)         AS cost,

        /* conversion_rate: if sessions=0 => 0 */
        CAST(
            ISNULL(
                CAST(ISNULL(sc.conversions, 0) AS DECIMAL(10,2))
                / NULLIF(CAST(ISNULL(sc.sessions, 0) AS DECIMAL(10,2)), 0),
            0)
            AS DECIMAL(10,2)
        ) AS conversion_rate,

        /* ROAS: if cost=0 => 0 (project choice for cleaner demo output) */
        CAST(
            ISNULL(
                CAST(ISNULL(sc.revenue, 0) AS DECIMAL(10,2))
                / NULLIF(CAST(ISNULL(cd.cost, 0) AS DECIMAL(10,2)), 0),
            0)
            AS DECIMAL(10,2)
        ) AS ROAS
    FROM marketing.campaigns c
    LEFT JOIN sessions_conv sc
        ON c.campaign_id = sc.campaign_id
    LEFT JOIN costs cd
        ON c.campaign_id = cd.campaign_id
    ORDER BY
        ISNULL(sc.revenue, 0) DESC,
        ISNULL(sc.sessions, 0) DESC;
END;
GO


/* ---------------------------------------------------------------------------
   2) Campaign-day performance (range)
   - Returns campaign x date grid for the requested range, even when there is no data.
--------------------------------------------------------------------------- */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE marketing.sp_campaign_day_performance
    @start_date DATE,
    @end_date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @start_date IS NULL OR @end_date IS NULL
        THROW 50020, 'start_date and end_date are required', 1;

    IF @start_date > @end_date
        THROW 50021, 'start_date cannot be after end_date', 1;

    /* Date grid (within the chosen range) */
    DECLARE @dates TABLE ([date] DATE NOT NULL PRIMARY KEY);

    DECLARE @d DATE = @start_date;
    WHILE @d <= @end_date
    BEGIN
        INSERT INTO @dates ([date]) VALUES (@d);
        SET @d = DATEADD(DAY, 1, @d);
    END;

    /* Campaign x Date grid */
    DECLARE @campaigns_dates TABLE
    (
        campaign_id   INT          NOT NULL,
        campaign_name VARCHAR(50)  NOT NULL,
        channel       VARCHAR(25)  NOT NULL,
        [date]        DATE         NOT NULL
    );

    INSERT INTO @campaigns_dates (campaign_id, campaign_name, channel, [date])
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.channel,
        d.[date]
    FROM marketing.campaigns c
    CROSS JOIN @dates d;

    SELECT
        cdg.campaign_id,
        cdg.campaign_name,
        cdg.channel,
        cdg.[date],

        COUNT(DISTINCT s.session_id)        AS sessions,
        COUNT(DISTINCT cv.conversion_id)    AS conversions,
        ISNULL(SUM(cv.revenue), 0)          AS revenue,
        ISNULL(SUM(costs.cost), 0)          AS cost,

        CAST(
            ISNULL(
                CAST(COUNT(DISTINCT cv.conversion_id) AS DECIMAL(10,2))
                / NULLIF(CAST(COUNT(DISTINCT s.session_id) AS DECIMAL(10,2)), 0),
            0)
            AS DECIMAL(10,2)
        ) AS conversion_rate,

        CAST(
            ISNULL(
                CAST(ISNULL(SUM(cv.revenue), 0) AS DECIMAL(10,2))
                / NULLIF(CAST(ISNULL(SUM(costs.cost), 0) AS DECIMAL(10,2)), 0),
            0)
            AS DECIMAL(10,2)
        ) AS ROAS
    FROM @campaigns_dates cdg
    LEFT JOIN marketing.sessions s
        ON s.campaign_id = cdg.campaign_id
       AND CAST(s.session_datetime AS DATE) = cdg.[date]
    LEFT JOIN marketing.conversions cv
        ON cv.session_id = s.session_id
    LEFT JOIN marketing.costs_daily costs
        ON costs.campaign_id = cdg.campaign_id
       AND costs.cost_date = cdg.[date]
    GROUP BY
        cdg.campaign_id,
        cdg.campaign_name,
        cdg.channel,
        cdg.[date]
    ORDER BY
        cdg.campaign_id,
        cdg.[date];
END;
GO


/* ---------------------------------------------------------------------------
   3) Upsert costs_daily (MERGE) + audit output
--------------------------------------------------------------------------- */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE marketing.sp_upsert_costs_daily
    @cost_date   DATE,
    @campaign_id INT,
    @cost        DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY

        /* Parameter validation */
        IF @cost_date IS NULL
            THROW 50030, 'Cost date is required', 1;

        IF @campaign_id IS NULL
            THROW 50031, 'Campaign id is required', 1;

        IF @cost IS NULL
            THROW 50032, 'Cost cannot be NULL', 1;

        IF @cost < 0
            THROW 50033, 'Cost cannot be negative', 1;

        IF NOT EXISTS (SELECT 1 FROM marketing.campaigns WHERE campaign_id = @campaign_id)
            THROW 50034, 'Campaign does not exist', 1;

        DECLARE @source TABLE
        (
            cost_date   DATE NOT NULL,
            campaign_id INT  NOT NULL,
            cost        DECIMAL(10,2) NOT NULL
        );

        INSERT INTO @source (cost_date, campaign_id, cost)
        VALUES (@cost_date, @campaign_id, @cost);

        DECLARE @merge_log TABLE
        (
            action_taken   VARCHAR(10),
            new_cost_date  DATE,
            old_cost_date  DATE,
            new_campaign_id INT,
            old_campaign_id INT,
            new_cost       DECIMAL(10,2),
            old_cost       DECIMAL(10,2),
            [timestamp]    DATETIME2(0)
        );

        MERGE INTO marketing.costs_daily AS target
        USING @source AS src
            ON src.cost_date = target.cost_date
           AND src.campaign_id = target.campaign_id
        WHEN MATCHED THEN
            UPDATE SET target.cost = src.cost
        WHEN NOT MATCHED THEN
            INSERT (cost_date, campaign_id, cost)
            VALUES (src.cost_date, src.campaign_id, src.cost)
        OUTPUT
            $action,
            INSERTED.cost_date,
            DELETED.cost_date,
            INSERTED.campaign_id,
            DELETED.campaign_id,
            INSERTED.cost,
            DELETED.cost,
            SYSDATETIME()
        INTO @merge_log;

        SELECT *
        FROM @merge_log;

    END TRY
    BEGIN CATCH
        /* Re-throw with original error details */
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @num INT = ERROR_NUMBER();
        DECLARE @state INT = ERROR_STATE();
        DECLARE @sev INT = ERROR_SEVERITY();

        THROW 52001, @msg, 1;
    END CATCH
END;
GO
