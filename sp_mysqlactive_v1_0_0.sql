/*
================================================================================
sp_mysqlactive
================================================================================

Author.............: Felipe Queiroz
Company............: QZ Data
Created Date.......: 2026-05-25
Version............: 1.0.0

Description........:
Lightweight MySQL activity monitoring procedure inspired by sp_WhoIsActive
for SQL Server.

Features...........:
- Active session monitoring
- Optional sleeping session visualization
- Internal Daemon session filtering
- Blocking session detection
- Transaction visibility
- Lock wait analysis
- Current wait event details
- Running query visualization with SQL text fallback
- Basic statement metrics for troubleshooting
- Filtering by minimum elapsed time
- Filtering by database name

Compatibility......:
- MySQL 8.0+
- Requires performance_schema enabled
- Requires access to:
  - performance_schema.threads
  - performance_schema.processlist
  - performance_schema.events_statements_current
  - performance_schema.events_waits_current
  - performance_schema.data_lock_waits
  - information_schema.innodb_trx

Main Usage.........:

CALL sp_mysqlactive();

Advanced Usage.....:

CALL sp_mysqlactive_full(FALSE, 0, NULL);
CALL sp_mysqlactive_full(TRUE, 10, NULL);
CALL sp_mysqlactive_full(TRUE, 0, 'your_database_name');

Version Info.......:

CALL sp_mysqlactive_version();

Notes..............:
- sp_mysqlactive() hides sleeping sessions by default.
- sp_mysqlactive_full() allows advanced filters.
- SQL SECURITY INVOKER is used to respect the caller permissions.
- This procedure only reads MySQL metadata/performance views.
- Internal daemon threads are hidden by default.
- SQL text is read from events_statements_current and falls back to performance_schema.processlist.INFO.

================================================================================
*/

DROP PROCEDURE IF EXISTS sp_mysqlactive;
DROP PROCEDURE IF EXISTS sp_mysqlactive_full;
DROP PROCEDURE IF EXISTS sp_mysqlactive_version;

DELIMITER $$

CREATE PROCEDURE sp_mysqlactive_full(
    IN p_show_sleep BOOLEAN,
    IN p_min_elapsed_seconds INT,
    IN p_database_name VARCHAR(128)
)
SQL SECURITY INVOKER
BEGIN

    IF p_show_sleep IS NULL THEN
        SET p_show_sleep = FALSE;
    END IF;

    IF p_min_elapsed_seconds IS NULL THEN
        SET p_min_elapsed_seconds = 0;
    END IF;

    SELECT
        t.PROCESSLIST_ID AS session_id,

        CASE
            WHEN b.trx_mysql_thread_id IS NOT NULL THEN 'BLOCKED'
            WHEN EXISTS (
                SELECT 1
                FROM performance_schema.data_lock_waits dlw2
                INNER JOIN information_schema.innodb_trx trx2
                        ON trx2.trx_id = dlw2.BLOCKING_ENGINE_TRANSACTION_ID
                WHERE trx2.trx_mysql_thread_id = t.PROCESSLIST_ID
            ) THEN 'BLOCKING'
            WHEN t.PROCESSLIST_COMMAND = 'Sleep' THEN 'SLEEPING'
            ELSE 'RUNNING'
        END AS activity_status,

        CONCAT(
            LPAD(FLOOR(t.PROCESSLIST_TIME / 86400), 2, '0'),
            ' ',
            SEC_TO_TIME(t.PROCESSLIST_TIME % 86400)
        ) AS elapsed_time,

        t.PROCESSLIST_TIME AS elapsed_seconds,

        t.PROCESSLIST_USER AS login_name,
        t.PROCESSLIST_HOST AS host_name,
        t.PROCESSLIST_DB AS database_name,

        b.trx_mysql_thread_id AS blocking_session_id,

        t.PROCESSLIST_COMMAND AS command,
        t.PROCESSLIST_STATE AS state,

        trx.trx_state,

        TIMESTAMPDIFF(
            SECOND,
            trx.trx_started,
            NOW()
        ) AS open_tran_seconds,

        trx.trx_rows_locked,
        trx.trx_rows_modified,

        es.ROWS_EXAMINED AS rows_examined,
        es.ROWS_SENT AS rows_sent,
        es.CREATED_TMP_TABLES AS created_tmp_tables,
        es.CREATED_TMP_DISK_TABLES AS created_tmp_disk_tables,
        es.SORT_ROWS AS sort_rows,
        es.NO_INDEX_USED AS no_index_used,
        es.NO_GOOD_INDEX_USED AS no_good_index_used,

        ew.EVENT_NAME AS wait_event,
        ew.OBJECT_SCHEMA AS wait_object_schema,
        ew.OBJECT_NAME AS wait_object_name,
        ew.INDEX_NAME AS wait_index_name,
        ROUND(ew.TIMER_WAIT / 1000000000000, 6) AS wait_seconds,

        COALESCE(
            LEFT(es.SQL_TEXT, 1000),
            LEFT(pl.INFO, 1000)
        ) AS sql_text

    FROM performance_schema.threads t

    LEFT JOIN performance_schema.processlist pl
           ON pl.ID = t.PROCESSLIST_ID

    LEFT JOIN performance_schema.events_statements_current es
           ON t.THREAD_ID = es.THREAD_ID

    LEFT JOIN performance_schema.events_waits_current ew
           ON ew.THREAD_ID = t.THREAD_ID

    LEFT JOIN information_schema.innodb_trx trx
           ON trx.trx_mysql_thread_id = t.PROCESSLIST_ID

    LEFT JOIN performance_schema.data_lock_waits dlw
           ON dlw.REQUESTING_ENGINE_TRANSACTION_ID = trx.trx_id

    LEFT JOIN information_schema.innodb_trx b
           ON b.trx_id = dlw.BLOCKING_ENGINE_TRANSACTION_ID

    WHERE t.PROCESSLIST_ID IS NOT NULL
      AND t.PROCESSLIST_ID <> CONNECTION_ID()
      AND COALESCE(t.PROCESSLIST_COMMAND, '') <> 'Daemon'
      AND COALESCE(t.PROCESSLIST_USER, '') NOT IN ('event_scheduler')
      AND (
            p_show_sleep = TRUE
            OR t.PROCESSLIST_COMMAND <> 'Sleep'
          )
      AND t.PROCESSLIST_TIME >= p_min_elapsed_seconds
      AND (
            p_database_name IS NULL
            OR t.PROCESSLIST_DB = p_database_name
          )

    ORDER BY
        CASE
            WHEN b.trx_mysql_thread_id IS NOT NULL THEN 1
            WHEN EXISTS (
                SELECT 1
                FROM performance_schema.data_lock_waits dlw2
                INNER JOIN information_schema.innodb_trx trx2
                        ON trx2.trx_id = dlw2.BLOCKING_ENGINE_TRANSACTION_ID
                WHERE trx2.trx_mysql_thread_id = t.PROCESSLIST_ID
            ) THEN 2
            ELSE 3
        END,
        t.PROCESSLIST_TIME DESC;

END $$


CREATE PROCEDURE sp_mysqlactive()
SQL SECURITY INVOKER
BEGIN

    CALL sp_mysqlactive_full(FALSE, 0, NULL);

END $$


CREATE PROCEDURE sp_mysqlactive_version()
SQL SECURITY INVOKER
BEGIN

    SELECT
        'sp_mysqlactive' AS procedure_name,
        '1.0.0' AS version,
        'Felipe Queiroz' AS created_by,
        'QZ Data' AS company,
        '2026-05-25' AS created_date,
        'MySQL 8.0+' AS mysql_compatibility,
        'performance_schema required' AS requirement,
        'Lightweight MySQL activity monitoring procedure inspired by sp_WhoIsActive for SQL Server' AS description,
        'sp_mysqlactive(), sp_mysqlactive_full(show_sleep, min_elapsed_seconds, database_name), sp_mysqlactive_version()' AS available_procedures;

END $$

DELIMITER ;

-- Basic validation:
-- CALL sp_mysqlactive_version();
-- CALL sp_mysqlactive();
-- CALL sp_mysqlactive_full(TRUE, 0, NULL);
-- CALL sp_mysqlactive_full(TRUE, 10, NULL);
-- CALL sp_mysqlactive_full(TRUE, 0, 'your_database_name');
