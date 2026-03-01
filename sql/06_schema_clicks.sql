/* ============================================================================
  06_schema_clicks.sql
  Stage 2 – Click-level costs tracking (re-runnable)

  Re-runnable behavior:
  - Drops the sessions->clicks FK (if exists)
  - Drops indexes related to click linkage (if exist)
  - Drops marketing.clicks table (if exists)
  - Recreates clicks table + indexes
  - Ensures sessions.click_id column exists
  - Recreates FK + index

  Assumes Stage 1 objects already exist:
  - marketing.campaigns
  - marketing.sessions
============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN;

    /* ------------------------------------------------------------------------
       0) Drop FK from sessions -> clicks (if exists)
    ------------------------------------------------------------------------ */
    IF EXISTS (
        SELECT 1
        FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID(N'marketing.sessions')
          AND name = N'fk_sessions_click'
    )
    BEGIN
        ALTER TABLE marketing.sessions
            DROP CONSTRAINT fk_sessions_click;
    END;

    /* ------------------------------------------------------------------------
       1) Drop index on sessions.click_id (if exists)
    ------------------------------------------------------------------------ */
    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'marketing.sessions')
          AND name = N'ix_sessions_click_id'
    )
    BEGIN
        DROP INDEX ix_sessions_click_id ON marketing.sessions;
    END;

    /* ------------------------------------------------------------------------
       2) Drop clicks table indexes and table (if exists)
    ------------------------------------------------------------------------ */
    IF OBJECT_ID(N'marketing.clicks', N'U') IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'marketing.clicks')
              AND name = N'ix_clicks_campaign_datetime'
        )
        BEGIN
            DROP INDEX ix_clicks_campaign_datetime ON marketing.clicks;
        END;

        DROP TABLE marketing.clicks;
    END;

    /* ------------------------------------------------------------------------
       3) Create clicks table
    ------------------------------------------------------------------------ */
    CREATE TABLE marketing.clicks
    (
        click_id        INT IDENTITY(1,1) NOT NULL
            CONSTRAINT pk_clicks PRIMARY KEY,
        campaign_id     INT               NOT NULL,
        click_datetime  DATETIME2(0)      NOT NULL,
        cost            DECIMAL(10,2)     NOT NULL,

        CONSTRAINT fk_clicks_campaign
            FOREIGN KEY (campaign_id) REFERENCES marketing.campaigns(campaign_id)
    );

    CREATE INDEX ix_clicks_campaign_datetime
    ON marketing.clicks (campaign_id, click_datetime);

    /* ------------------------------------------------------------------------
       4) Ensure sessions.click_id exists (add if missing)
    ------------------------------------------------------------------------ */
    IF COL_LENGTH(N'marketing.sessions', N'click_id') IS NULL
    BEGIN
        ALTER TABLE marketing.sessions
            ADD click_id INT NULL;
    END;

    /* ------------------------------------------------------------------------
       5) Recreate FK sessions -> clicks
    ------------------------------------------------------------------------ */
    ALTER TABLE marketing.sessions
        ADD CONSTRAINT fk_sessions_click
            FOREIGN KEY (click_id) REFERENCES marketing.clicks(click_id);

    /* ------------------------------------------------------------------------
       6) Recreate index on sessions.click_id
    ------------------------------------------------------------------------ */
    CREATE INDEX ix_sessions_click_id
    ON marketing.sessions (click_id);

    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
    THROW 51000, @msg, 1;
END CATCH;


