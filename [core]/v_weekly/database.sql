-- v_weekly :: database schema (also included in ../../main.sql)
--
--   week_start  unix timestamp (UTC) of Tuesday 10:00 UTC
--   data        JSON: { jobs = { [jobId] = { money, xp, label } },
--                       timetrial = <index>, custom = { ... },
--                       news = { title, body } }
CREATE TABLE IF NOT EXISTS `weekly_schedule` (
    `week_start` INT          NOT NULL PRIMARY KEY,
    `data`       MEDIUMTEXT   NOT NULL,
    `updated_by` VARCHAR(50)  DEFAULT NULL,
    `updated_at` INT          NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
