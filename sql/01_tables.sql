/* ============================================================================
  01_tables.sql
  Marketing Performance Analytics (SQL Server)

  Purpose:
  - Create schema + core tables for a marketing analytics mini-warehouse:
    campaigns, users, sessions, conversions, costs_daily

  Notes:
  - This script is written to be re-runnable (idempotent) for local dev.
  - Run order for the whole project:
    01_tables.sql -> 02_seed_data.sql -> 03_views.sql -> 04_procedures.sql -> 05_queries_demo.sql
============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN;

    /* ------------------------------------------------------------------------
       Optional: create and use a dedicated database
       (Uncomment if you want the script to create the DB)
    ------------------------------------------------------------------------ */
    /*
    IF DB_ID(N'MarketingAnalytics') IS NULL
        CREATE DATABASE MarketingAnalytics;
    GO
    USE MarketingAnalytics;
    GO
    */

    /* ------------------------------------------------------------------------
       Create schema
    ------------------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'marketing')
        EXEC(N'CREATE SCHEMA marketing');
    -- No GO inside transaction; keep it simple.

    /* ------------------------------------------------------------------------
       Drop tables (reverse dependency order) for re-runs
       Conversions -> Sessions -> Costs -> Users -> Campaigns
    ------------------------------------------------------------------------ */
    IF OBJECT_ID(N'marketing.conversions', N'U') IS NOT NULL DROP TABLE marketing.conversions;
    IF OBJECT_ID(N'marketing.sessions', N'U')    IS NOT NULL DROP TABLE marketing.sessions;
    IF OBJECT_ID(N'marketing.costs_daily', N'U') IS NOT NULL DROP TABLE marketing.costs_daily;
    IF OBJECT_ID(N'marketing.users', N'U')       IS NOT NULL DROP TABLE marketing.users;
    IF OBJECT_ID(N'marketing.campaigns', N'U')   IS NOT NULL DROP TABLE marketing.campaigns;

    /* ------------------------------------------------------------------------
       Table: campaigns
    ------------------------------------------------------------------------ */
    CREATE TABLE marketing.campaigns
    (
        campaign_id   INT IDENTITY(1,1) NOT NULL
            CONSTRAINT pk_campaigns PRIMARY KEY,
        campaign_name NVARCHAR(100)     NOT NULL,
        channel       NVARCHAR(50)      NOT NULL,
        start_date    DATE              NULL
    );

    /* ------------------------------------------------------------------------
       Table: users
       - first_seen_date: first time user is seen in the system (required)
       - registration_date: nullable because not all visitors register
    ------------------------------------------------------------------------ */
    CREATE TABLE marketing.users
    (
        user_id            INT IDENTITY(1,1) NOT NULL
            CONSTRAINT pk_users PRIMARY KEY,
        first_seen_date    DATE              NOT NULL,
        registration_date  DATE              NULL,
        country            NVARCHAR(50)       NULL,
        gender             NVARCHAR(25)       NULL,
        CONSTRAINT ck_users_registration_after_first_seen
            CHECK (registration_date IS NULL OR registration_date >= first_seen_date)
    );

    /* ------------------------------------------------------------------------
       Table: sessions
       - DATETIME2 is preferred for precision & consistency
       - device has a default
    ------------------------------------------------------------------------ */
    CREATE TABLE marketing.sessions
    (
        session_id       INT IDENTITY(1,1) NOT NULL
            CONSTRAINT pk_sessions PRIMARY KEY,
        user_id          INT               NOT NULL,
        campaign_id      INT               NOT NULL,
        device           NVARCHAR(25)      NOT NULL
            CONSTRAINT df_sessions_device DEFAULT (N'Unknown'),
        landing_page     NVARCHAR(200)     NULL,
        session_datetime DATETIME2(0)      NOT NULL,

        CONSTRAINT fk_sessions_user
            FOREIGN KEY (user_id) REFERENCES marketing.users(user_id),

        CONSTRAINT fk_sessions_campaign
            FOREIGN KEY (campaign_id) REFERENCES marketing.campaigns(campaign_id)
    );

    /* ------------------------------------------------------------------------
       Table: conversions
       - conversion_type is validated via CHECK
       - revenue is non-negative, default 0
    ------------------------------------------------------------------------ */
    CREATE TABLE marketing.conversions
    (
        conversion_id       INT IDENTITY(1,1) NOT NULL
            CONSTRAINT pk_conversions PRIMARY KEY,
        session_id          INT               NOT NULL,
        conversion_datetime DATETIME2(0)      NOT NULL,
        conversion_type     NVARCHAR(25)      NOT NULL,
        revenue             DECIMAL(10,2)     NOT NULL
            CONSTRAINT df_conversions_revenue DEFAULT (0),

        CONSTRAINT fk_conversions_session
            FOREIGN KEY (session_id) REFERENCES marketing.sessions(session_id),

        CONSTRAINT ck_conversions_type
            CHECK (conversion_type IN (N'Lead', N'Registration', N'Purchase')),

        CONSTRAINT ck_conversions_revenue_nonneg
            CHECK (revenue >= 0)
    );

    /* ------------------------------------------------------------------------
       Table: costs_daily
       - Composite PK: (cost_date, campaign_id)
       - cost is non-negative, default 0
    ------------------------------------------------------------------------ */
    CREATE TABLE marketing.costs_daily
    (
        cost_date   DATE           NOT NULL,
        campaign_id INT            NOT NULL,
        cost        DECIMAL(10,2)  NOT NULL
            CONSTRAINT df_costs_daily_cost DEFAULT (0),

        CONSTRAINT pk_costs_daily
            PRIMARY KEY (cost_date, campaign_id),

        CONSTRAINT fk_costs_daily_campaign
            FOREIGN KEY (campaign_id) REFERENCES marketing.campaigns(campaign_id),

        CONSTRAINT ck_costs_daily_cost_nonneg
            CHECK (cost >= 0)
    );

    /* ------------------------------------------------------------------------
       Helpful indexes (small but professional)
       - Speeds up common joins & date filtering
    ------------------------------------------------------------------------ */
    CREATE INDEX ix_sessions_campaign_datetime
        ON marketing.sessions (campaign_id, session_datetime);

    CREATE INDEX ix_sessions_user_datetime
        ON marketing.sessions (user_id, session_datetime);

    CREATE INDEX ix_conversions_session
        ON marketing.conversions (session_id);

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    -- Surface a readable error
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @num INT = ERROR_NUMBER();
    DECLARE @line INT = ERROR_LINE();
    DECLARE @throw_msg NVARCHAR(2048) =
    CONCAT(N'01_tables.sql failed. Error ', @num, N' at line ', @line, N': ', @err);
    THROW 51000, @throw_msg, 1;
END CATCH;



