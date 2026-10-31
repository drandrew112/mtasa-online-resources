-- police_system / modules/db/server/schema.lua
-- The pol_* tables (also in the repo main.sql). Tables with an id have is_pool + server: 2 placeholder rows per
-- server instance (pool.lua); every reader filters them out (POL.db.NOT_POOL). Times are epoch seconds.

POL_SCHEMA = {
[[CREATE TABLE IF NOT EXISTS `pol_citizens` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `kind`         VARCHAR(8)   DEFAULT NULL,
    `account_name` VARCHAR(50)  DEFAULT NULL,
    `name`         VARCHAR(64)  DEFAULT NULL,
    `gender`       CHAR(1)      DEFAULT NULL,
    `birth_date`   DATE         DEFAULT NULL,
    `skin`         INT          DEFAULT NULL,
    `flags`        TEXT,
    `generated`    TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `last_seen`    INT          NOT NULL DEFAULT 0,
    `is_pool`      TINYINT(1)   NOT NULL DEFAULT 0,
    `server`       VARCHAR(32)  DEFAULT NULL,
    KEY `idx_polc_account` (`account_name`),
    KEY `idx_polc_name` (`name`),
    KEY `idx_polc_pool` (`is_pool`, `server`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `pol_vehicles` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `kind`             VARCHAR(8)   DEFAULT NULL,
    `owner_citizen_id` INT          DEFAULT NULL,
    `ownveh_id`        INT          DEFAULT NULL,
    `plate`            VARCHAR(32)  DEFAULT NULL,
    `model`            INT          DEFAULT NULL,
    `color`            VARCHAR(64)  DEFAULT NULL,
    `flags`            TEXT,
    `created_at`       INT          NOT NULL DEFAULT 0,
    `is_pool`          TINYINT(1)   NOT NULL DEFAULT 0,
    `server`           VARCHAR(32)  DEFAULT NULL,
    KEY `idx_polv_plate` (`plate`),
    KEY `idx_polv_ownveh` (`ownveh_id`),
    KEY `idx_polv_owner` (`owner_citizen_id`),
    KEY `idx_polv_pool` (`is_pool`, `server`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `pol_records` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `type`         VARCHAR(8)   DEFAULT NULL,
    `btk_id`       VARCHAR(48)  DEFAULT NULL,
    `amount`       INT          NOT NULL DEFAULT 0,
    `paid`         TINYINT(1)   NOT NULL DEFAULT 0,
    `refunded`     TINYINT(1)   NOT NULL DEFAULT 0,
    `citizen_id`   INT          DEFAULT NULL,
    `vehicle_id`   INT          DEFAULT NULL,
    `officer`      VARCHAR(50)  DEFAULT NULL,
    `officer_name` VARCHAR(64)  DEFAULT NULL,
    `unit`         VARCHAR(8)   DEFAULT NULL,
    `shift_id`     INT          DEFAULT NULL,
    `report_id`    INT          DEFAULT NULL,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `is_pool`      TINYINT(1)   NOT NULL DEFAULT 0,
    `server`       VARCHAR(32)  DEFAULT NULL,
    KEY `idx_polr_citizen` (`citizen_id`),
    KEY `idx_polr_vehicle` (`vehicle_id`),
    KEY `idx_polr_created` (`created_at`),
    KEY `idx_polr_pool` (`is_pool`, `server`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `pol_warrants` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `citizen_id`   INT          DEFAULT NULL,
    `reasons`      TEXT,
    `description`  TEXT,
    `lang`         VARCHAR(8)   DEFAULT NULL,
    `status`       VARCHAR(10)  DEFAULT NULL,
    `issued_by`    VARCHAR(50)  DEFAULT NULL,
    `issued_name`  VARCHAR(64)  DEFAULT NULL,
    `updated_by`   VARCHAR(50)  DEFAULT NULL,
    `updated_name` VARCHAR(64)  DEFAULT NULL,
    `history`      TEXT,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `updated_at`   INT          NOT NULL DEFAULT 0,
    `is_pool`      TINYINT(1)   NOT NULL DEFAULT 0,
    `server`       VARCHAR(32)  DEFAULT NULL,
    KEY `idx_polw_citizen` (`citizen_id`),
    KEY `idx_polw_status` (`status`),
    KEY `idx_polw_pool` (`is_pool`, `server`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `pol_reports` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `shift_id`     INT          DEFAULT NULL,
    `incident_id`  VARCHAR(24)  DEFAULT NULL,
    `type`         VARCHAR(24)  DEFAULT NULL,
    `pay_type`     VARCHAR(24)  DEFAULT NULL,
    `level`        INT          NOT NULL DEFAULT 0,
    `lang`         VARCHAR(8)   DEFAULT NULL,
    `author`       VARCHAR(50)  DEFAULT NULL,
    `author_name`  VARCHAR(64)  DEFAULT NULL,
    `unit`         VARCHAR(8)   DEFAULT NULL,
    `members`      TEXT,
    `title`        VARCHAR(160) DEFAULT NULL,
    `body`         MEDIUMTEXT,
    `subjects`     TEXT,
    `status`       VARCHAR(10)  DEFAULT NULL,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `submitted_at` INT          NOT NULL DEFAULT 0,
    `is_pool`      TINYINT(1)   NOT NULL DEFAULT 0,
    `server`       VARCHAR(32)  DEFAULT NULL,
    KEY `idx_polrep_shift` (`shift_id`),
    KEY `idx_polrep_status` (`status`),
    KEY `idx_polrep_pool` (`is_pool`, `server`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `pol_shifts` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `callsign`     VARCHAR(8)   DEFAULT NULL,
    `unit_type`    VARCHAR(8)   DEFAULT NULL,
    `leader`       VARCHAR(50)  DEFAULT NULL,
    `members`      TEXT,
    `server`       VARCHAR(32)  DEFAULT NULL,
    `started_at`   INT          NOT NULL DEFAULT 0,
    `ended_at`     INT          DEFAULT NULL,
    `events`       MEDIUMTEXT,
    `pay`          TEXT,
    `pay_pending`  TINYINT(1)   NOT NULL DEFAULT 0,
    `is_pool`      TINYINT(1)   NOT NULL DEFAULT 0,
    KEY `idx_pols_open` (`ended_at`, `callsign`),
    KEY `idx_pols_pool` (`is_pool`, `server`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS `pol_stats` (
    `day`    DATE         NOT NULL,
    `stat`   VARCHAR(48)  NOT NULL,
    `amount` INT          NOT NULL DEFAULT 0,
    PRIMARY KEY (`day`, `stat`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- pool rows: the INSERT that makes a placeholder of each table
POL_POOL_TABLES = {
    pol_citizens = "INSERT INTO pol_citizens (is_pool, server) VALUES (1, ?)",
    pol_vehicles = "INSERT INTO pol_vehicles (is_pool, server) VALUES (1, ?)",
    pol_records  = "INSERT INTO pol_records (is_pool, server) VALUES (1, ?)",
    pol_warrants = "INSERT INTO pol_warrants (is_pool, server) VALUES (1, ?)",
    pol_reports  = "INSERT INTO pol_reports (is_pool, server) VALUES (1, ?)",
    pol_shifts   = "INSERT INTO pol_shifts (is_pool, server, ended_at) VALUES (1, ?, 0)",
}
