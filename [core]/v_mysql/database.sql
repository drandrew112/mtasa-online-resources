-- v_mysql :: database schema
--
-- Run this once against the database named in config.lua (MYSQL_CONFIG.database).
--
--   mysql -h <host> -P <port> -u <user> -p <database> < database.sql
--
-- or paste it into phpMyAdmin / Adminer.
--
-- This is the account slice only. The whole mod's schema (this table plus
-- every resource's own) lives in ../../main.sql.
--
-- Replaces the old `global_account_data` table. `account_data` is a JSON object
-- of arbitrary key -> { "v": <string>, "t": <type> } pairs (type = string /
-- int / float / boolean) - what exports.v_mysql:getAccData / setAccData read
-- and write. The other columns are managed by v_accounts (password, email,
-- display_name, created_at) and v_admin (admin_level).

CREATE TABLE IF NOT EXISTS `accounts` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `account_name` VARCHAR(50)  NOT NULL,
    `password`     VARCHAR(255) DEFAULT NULL,
    `email`        VARCHAR(255) DEFAULT NULL,
    `display_name` VARCHAR(64)  DEFAULT NULL,
    `admin_level`  INT          NOT NULL DEFAULT 0,
    `account_data` MEDIUMTEXT   NOT NULL,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `updated_at`   INT          NOT NULL DEFAULT 0,
    UNIQUE KEY `unique_account` (`account_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
