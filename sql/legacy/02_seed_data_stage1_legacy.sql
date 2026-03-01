/* ============================================================================
  02_seed_data.sql
  Marketing Performance Analytics (SQL Server)

  Purpose:
  - Load a small-but-rich manual dataset (safe to re-run)
  - Explicit column lists, clean output, and realistic relationships

  Run after:
  - 01_tables.sql
============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN;

    /* ------------------------------------------------------------------------
       Clean existing data (child -> parent) to avoid duplicates on re-run
    ------------------------------------------------------------------------ */
    DELETE FROM marketing.conversions;
    DELETE FROM marketing.sessions;
    DELETE FROM marketing.costs_daily;
    DELETE FROM marketing.users;
    DELETE FROM marketing.campaigns;

    /* ------------------------------------------------------------------------
       campaigns (3)
    ------------------------------------------------------------------------ */
    INSERT INTO marketing.campaigns (campaign_name, channel, start_date)
    VALUES
        (N'Google Search – Brand', N'Paid Search', '2024-02-01'),
        (N'Facebook Leads',        N'Paid Social', '2024-02-05'),
        (N'Organic Search',        N'Organic',     NULL);

    /* ------------------------------------------------------------------------
       users (12)
       - some registered, some not
    ------------------------------------------------------------------------ */
    INSERT INTO marketing.users (first_seen_date, registration_date, country, gender)
    VALUES
        ('2024-02-10', NULL,         N'Israel',  N'Female'), -- 1
        ('2024-02-11', '2024-02-11', N'Israel',  N'Male'),   -- 2
        ('2024-02-12', '2024-02-13', N'Israel',  N'Female'), -- 3
        ('2024-02-13', NULL,         N'USA',     N'Female'), -- 4
        ('2024-02-14', NULL,         N'UK',      N'Male'),   -- 5
        ('2024-02-15', '2024-02-16', N'Germany', N'Female'), -- 6
        ('2024-02-16', NULL,         N'France',  N'Female'), -- 7
        ('2024-02-17', NULL,         N'Israel',  N'Other'),  -- 8
        ('2024-02-18', '2024-02-20', N'Canada',  N'Male'),   -- 9
        ('2024-02-19', NULL,         N'Israel',  N'Female'), -- 10
        ('2024-02-20', '2024-02-20', N'USA',     N'Male'),   -- 11
        ('2024-02-21', NULL,         N'Israel',  N'Female'); -- 12

    /* ------------------------------------------------------------------------
       sessions (36)
       campaign_id: 1=Paid Search, 2=Paid Social, 3=Organic
    ------------------------------------------------------------------------ */
    INSERT INTO marketing.sessions (user_id, campaign_id, device, landing_page, session_datetime)
    VALUES
        -- 2024-02-10
        (1, 1, N'Mobile',  N'/home',     '2024-02-10T10:15:00'),
        (1, 3, N'Desktop', N'/blog',     '2024-02-10T18:40:00'),
        (2, 2, N'Mobile',  N'/contact',  '2024-02-10T20:45:00'),

        -- 2024-02-11
        (2, 2, N'Mobile',  N'/contact',  '2024-02-11T09:05:00'),
        (3, 1, N'Desktop', N'/services', '2024-02-11T13:10:00'),
        (4, 1, N'Mobile',  N'/landing',  '2024-02-11T21:25:00'),

        -- 2024-02-12
        (3, 1, N'Desktop', N'/pricing',  '2024-02-12T08:20:00'),
        (5, 3, N'Desktop', N'/blog',     '2024-02-12T11:30:00'),
        (1, 1, N'Mobile',  N'/home',     '2024-02-12T14:10:00'),

        -- 2024-02-13
        (6, 2, N'Mobile',  N'/landing',  '2024-02-13T10:00:00'),
        (7, 3, N'Desktop', N'/about',    '2024-02-13T12:40:00'),
        (4, 1, N'Desktop', N'/services', '2024-02-13T19:15:00'),

        -- 2024-02-14
        (1, 1, N'Mobile',  N'/contact',  '2024-02-14T09:10:00'),
        (8, 2, N'Mobile',  N'/home',     '2024-02-14T11:55:00'),
        (9, 3, N'Desktop', N'/blog',     '2024-02-14T21:20:00'),

        -- 2024-02-15
        (10, 1, N'Desktop', N'/landing', '2024-02-15T08:40:00'),
        (2, 2, N'Mobile',   N'/contact', '2024-02-15T12:10:00'),
        (6, 2, N'Mobile',   N'/pricing', '2024-02-15T18:30:00'),

        -- 2024-02-16
        (3, 3, N'Desktop', N'/blog',     '2024-02-16T09:25:00'),
        (7, 1, N'Mobile',  N'/services', '2024-02-16T13:05:00'),
        (11,2, N'Mobile',  N'/home',     '2024-02-16T20:50:00'),

        -- 2024-02-17
        (12,1, N'Desktop', N'/services', '2024-02-17T10:10:00'),
        (1, 1, N'Mobile',  N'/home',     '2024-02-17T14:45:00'),
        (9, 3, N'Desktop', N'/about',    '2024-02-17T22:05:00'),

        -- 2024-02-18
        (2, 2, N'Mobile',  N'/contact',  '2024-02-18T09:15:00'),
        (6, 2, N'Desktop', N'/landing',  '2024-02-18T12:00:00'),
        (10,3, N'Desktop', N'/blog',     '2024-02-18T19:40:00'),

        -- 2024-02-19
        (3, 1, N'Mobile',  N'/pricing',  '2024-02-19T08:05:00'),
        (8, 2, N'Mobile',  N'/home',     '2024-02-19T11:30:00'),
        (11,1, N'Desktop', N'/services', '2024-02-19T21:10:00'),

        -- 2024-02-20
        (1, 1, N'Mobile',  N'/home',     '2024-02-20T09:00:00'),
        (5, 3, N'Desktop', N'/blog',     '2024-02-20T12:45:00'),
        (9, 2, N'Mobile',  N'/contact',  '2024-02-20T20:15:00'),

        -- 2024-02-21
        (6, 2, N'Mobile',  N'/landing',  '2024-02-21T10:05:00'),
        (12,1, N'Desktop', N'/services', '2024-02-21T16:30:00'),
        (7, 3, N'Desktop', N'/about',    '2024-02-21T21:55:00'),

        -- 2024-02-22
        (2, 2, N'Mobile',  N'/contact',  '2024-02-22T09:45:00'),
        (3, 1, N'Desktop', N'/pricing',  '2024-02-22T13:20:00'),
        (10,3, N'Desktop', N'/blog',     '2024-02-22T18:10:00');

    /* ------------------------------------------------------------------------
       conversions (14)
       - session_id refers to inserted sessions (1..36)
       - types must match: Lead / Registration / Purchase
    ------------------------------------------------------------------------ */
    INSERT INTO marketing.conversions (session_id, conversion_datetime, conversion_type, revenue)
    VALUES
        (1,  '2024-02-10T10:18:00', N'Lead',         0.00),
        (3,  '2024-02-10T20:47:00', N'Registration', 0.00),
        (5,  '2024-02-11T13:25:00', N'Purchase',   150.00),
        (7,  '2024-02-12T08:35:00', N'Lead',         0.00),
        (9,  '2024-02-12T14:25:00', N'Purchase',   250.00),
        (10, '2024-02-13T10:12:00', N'Registration', 0.00),
        (12, '2024-02-13T19:28:00', N'Lead',         0.00),
        (13, '2024-02-14T09:18:00', N'Purchase',   300.00),
        (16, '2024-02-15T08:55:00', N'Lead',         0.00),
        (17, '2024-02-15T12:20:00', N'Registration', 0.00),
        (20, '2024-02-16T13:15:00', N'Purchase',   200.00),
        (23, '2024-02-17T14:52:00', N'Lead',         0.00),
        (28, '2024-02-18T12:10:00', N'Purchase',   120.00),
        (33, '2024-02-20T20:22:00', N'Registration', 0.00);

    /* ------------------------------------------------------------------------
       costs_daily (25 rows)
       - spend for Paid Search and Paid Social on selected days
       - Organic = 0 by design
    ------------------------------------------------------------------------ */
    INSERT INTO marketing.costs_daily (cost_date, campaign_id, cost)
    VALUES
        ('2024-02-10', 1, 120.00),
        ('2024-02-10', 2,  90.00),
        ('2024-02-11', 1, 130.00),
        ('2024-02-11', 2,  80.00),
        ('2024-02-12', 1, 150.00),
        ('2024-02-12', 2,  95.00),
        ('2024-02-13', 1, 110.00),
        ('2024-02-13', 2,  70.00),
        ('2024-02-14', 1, 200.00),
        ('2024-02-14', 2, 100.00),
        ('2024-02-15', 1, 100.00),
        ('2024-02-15', 2, 120.00),
        ('2024-02-16', 1, 140.00),
        ('2024-02-16', 2,  60.00),
        ('2024-02-17', 1, 150.00),
        ('2024-02-17', 2, 110.00),
        ('2024-02-18', 1, 175.00),
        ('2024-02-18', 2, 100.00),
        ('2024-02-19', 1, 125.00),
        ('2024-02-19', 2,  85.00),
        ('2024-02-20', 1, 100.00),
        ('2024-02-20', 2,  90.00),
        ('2024-02-21', 1,  95.00),
        ('2024-02-21', 2,  75.00),
        ('2024-02-22', 1, 105.00);

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


