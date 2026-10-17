-- ============================================================================
-- med_tasks / med_shifts  (owner: [medical]/med_erm, via v_mysql)
-- ----------------------------------------------------------------------------
-- med_erm also creates both tables on start (CREATE TABLE IF NOT EXISTS).
-- Date-times are DATETIME (server local time). The `shifts` / `tasks` columns
-- are append-only JSON lines, one MTA toJSON entry per line:
--
--   med_tasks.shifts  {"shift","at"}                  given to a shift
--                     {"shift","released","outcome"}  left it
--   med_shifts.tasks  {"task","at"} / {"task","released","outcome"}  the same
--                     from the shift's side; task_count = number of assignments
--   med_shifts.server = "<server name>:<port>"; a restart closes only its own
--                     open shifts. Open shift (ended_at IS NULL) = callsign on
--                     duty, checked on sign-in across every server.
--   Pool rows: placeholders inserted ahead of time so a new task / shift gets
--                     its id without a blocking INSERT (PERF-01). med_tasks:
--                     status = 'pool', source = 'pool:<server md5>';
--                     med_shifts: end_reason = 'pool'. Readers skip them.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `med_tasks` (
    `id`             INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `title`          VARCHAR(255) NOT NULL,
    `description`    TEXT,
    `caller`         VARCHAR(128) DEFAULT NULL,
    `pos_x`          FLOAT        DEFAULT NULL,
    `pos_y`          FLOAT        DEFAULT NULL,
    `pos_z`          FLOAT        DEFAULT NULL,
    `zone`           VARCHAR(64)  DEFAULT NULL,
    `priority`       INT          DEFAULT NULL,
    `status`         VARCHAR(16)  NOT NULL,
    `units`          TEXT,
    `response_log`   TEXT,
    `created_ts`     INT          DEFAULT NULL,
    `created_at`     DATETIME     DEFAULT NULL,
    `prioritized_at` DATETIME     DEFAULT NULL,
    `assigned_at`    DATETIME     DEFAULT NULL,
    `closed_at`      DATETIME     DEFAULT NULL,
    `close_reason`   TEXT,
    `source`         VARCHAR(64)  DEFAULT NULL,
    `meta`           TEXT,
    `shifts`         TEXT,
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `med_shifts` (
    `id`           INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `server`       VARCHAR(96)  DEFAULT NULL,
    `callsign`     VARCHAR(16)  DEFAULT NULL,
    `unit_type`    VARCHAR(16)  DEFAULT NULL,
    `plate`        VARCHAR(16)  DEFAULT NULL,
    `members`      TEXT,
    `closed_tasks` TEXT,
    `started_at`   DATETIME     NOT NULL,
    `ended_at`     DATETIME     DEFAULT NULL,
    `end_reason`   VARCHAR(64)  DEFAULT NULL,
    `task_count`   INT          NOT NULL DEFAULT 0,
    `tasks`        MEDIUMTEXT,
    KEY `idx_open` (`ended_at`, `callsign`),
    KEY `idx_server` (`server`, `ended_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
