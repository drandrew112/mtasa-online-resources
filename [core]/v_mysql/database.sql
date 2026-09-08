-- v_mysql :: database schema
--
-- Run this once against the database named in config.lua (MYSQL_CONFIG.database).
--
--   mysql -h <host> -P <port> -u <user> -p <database> < database.sql
--
-- or paste it into phpMyAdmin / Adminer.

CREATE TABLE IF NOT EXISTS `global_account_data` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `account_name` VARCHAR(50) NOT NULL,
    `account_data` TEXT        NOT NULL,
    UNIQUE KEY `unique_account` (`account_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
