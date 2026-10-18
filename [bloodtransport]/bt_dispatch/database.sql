-- ============================================================================
-- bt_tasks / bt_shifts  (owner: [bloodtransport]/bt_dispatch, via v_mysql)
-- ----------------------------------------------------------------------------
-- bt_dispatch also creates both tables on start (CREATE TABLE IF NOT EXISTS).
-- Date-times are DATETIME (server local time). The `log` / `shifts` / `tasks`
-- columns are append-only JSON lines, one MTA toJSON entry per line:
--
--   bt_tasks.log     {"at","event","info"}           status history of the task
--   bt_tasks.shifts  {"shift","at"}                  given to a shift
--                    {"shift","released","outcome"}  left it (delivered,
--                                                     cancelled, handed_over)
--   bt_shifts.tasks  {"task","at"} / {"task","released","outcome"}  the same
--                    from the shift's side; task_count = number of assignments
--   bt_shifts.pay_items  JSON list of the pay receipt lines
--   server           instance id of the server that wrote the row (v_main
--                    getServerInstanceId), right after id in both tables.
--   isPool           1 = placeholder row inserted ahead of time so a new task /
--                    shift gets its id without a blocking INSERT (PERF-01),
--                    0 = real row. Readers skip isPool = 1.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `bt_tasks` (
    `id`            INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `server`        INT          NOT NULL DEFAULT 0,
    `isPool`        TINYINT      NOT NULL DEFAULT 0,
    `type`          VARCHAR(32)  NOT NULL,
    `urgency`       VARCHAR(32)  DEFAULT NULL,
    `source`        VARCHAR(64)  DEFAULT NULL,
    `product`       VARCHAR(32)  DEFAULT NULL,
    `grp`           VARCHAR(8)   DEFAULT NULL,
    `units`         INT          DEFAULT NULL,
    `from_inst`     VARCHAR(64)  DEFAULT NULL,
    `to_inst`       VARCHAR(64)  DEFAULT NULL,
    `status`        VARCHAR(16)  NOT NULL,
    `shift_id`      INT          DEFAULT NULL,
    `reserved`      TINYINT      NOT NULL DEFAULT 0,
    `created_at`    DATETIME     DEFAULT NULL,
    `assigned_at`   DATETIME     DEFAULT NULL,
    `picked_at`     DATETIME     DEFAULT NULL,
    `delivered_at`  DATETIME     DEFAULT NULL,
    `cancelled_at`  DATETIME     DEFAULT NULL,
    `cancel_reason` VARCHAR(64)  DEFAULT NULL,
    `log`           MEDIUMTEXT,
    `shifts`        TEXT,
    KEY `idx_status` (`status`),
    KEY `idx_shift` (`shift_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bt_shifts` (
    `id`          INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `server`      INT          NOT NULL DEFAULT 0,
    `isPool`      TINYINT      NOT NULL DEFAULT 0,
    `account`     VARCHAR(64)  DEFAULT NULL,
    `player`      VARCHAR(64)  DEFAULT NULL,
    `unit`        VARCHAR(32)  DEFAULT NULL,
    `started_at`  DATETIME     DEFAULT NULL,
    `ended_at`    DATETIME     DEFAULT NULL,
    `end_reason`  VARCHAR(64)  DEFAULT NULL,
    `delivered`   INT          NOT NULL DEFAULT 0,
    `in_transit`  INT          NOT NULL DEFAULT 0,
    `cancelled`   INT          NOT NULL DEFAULT 0,
    `pay`         INT          NOT NULL DEFAULT 0,
    `pay_items`   TEXT,
    `task_count`  INT          NOT NULL DEFAULT 0,
    `tasks`       MEDIUMTEXT,
    KEY `idx_ended` (`ended_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
