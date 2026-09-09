-- MTA Online :: master database schema
--
-- Every persistent system now stores its data in the shared MySQL database
-- configured in [core]/v_mysql/config.lua (MYSQL_CONFIG.database), reached
-- through v_mysql's exports. This file creates every table the mod needs.
--
-- Run it once against that database:
--
--   mysql -h <host> -P <port> -u <user> -p <database> < main.sql
--
-- or paste it into phpMyAdmin / Adminer. It is safe to re-run (CREATE TABLE
-- IF NOT EXISTS). Individual resources also ship the slice they own
-- ([core]/v_mysql/database.sql, [vehicles]/v_ownveh/database.sql,
-- [player_interaction]/v_socialpanel/database.sql); this file is the union of
-- those, kept in sync by hand.


-- ============================================================================
-- accounts  (owner: v_accounts, via v_mysql)
-- ----------------------------------------------------------------------------
-- Replaces the old `global_account_data` table. One row per registered
-- account.
--
--   account_data  JSON object of arbitrary key -> { "v": <string>, "t": <type> }
--                 pairs (type = string | int | float | boolean). This is what
--                 exports.v_mysql:getAccData / setAccData read and write - the
--                 replacement for MTA's own getAccountData / setAccountData.
--   password      account password hash (managed by v_accounts).
--   email         optional contact e-mail.
--   display_name  shown name, independent of the login/account name.
--   admin_level   staff level, 0 = player (read by v_admin, v_levelsys, ...).
--   created_at    unix timestamp the account was registered.
--   updated_at    unix timestamp of the last write.
-- ============================================================================

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


-- ============================================================================
-- vehicles  (owner: [vehicles]/v_ownveh)
-- ----------------------------------------------------------------------------
-- One row per player-owned personal vehicle. `id` is the vehicle's permanent
-- identifier, used by every v_ownveh export and stored on the owner's account
-- as "owned_vehicle_ids" ("1,2,3"). Health is intentionally NOT stored: a
-- wreck gets isDestroyed = 1 and must be unlocked with
-- setVehicleDestroyed(id, false).
--
--   colors    "r,g,b,r,g,b,..."  (everything getVehicleColor(veh, true) returns)
--   upgrades  "id,id,id"         (getVehicleUpgrades)
--   handling  JSON object        (only properties that differ from stock)
--   customs   JSON object        (v_customs extras kept on element data:
--                                 nitro level, neon colour, air-ride,
--                                 bulletproof tyres, LSD doors). "{}" when
--                                 nothing applies.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `vehicles` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `account_name` VARCHAR(50)  NOT NULL,
    `model`        INT          NOT NULL,
    `colors`       TEXT         NOT NULL,
    `paintjob`     INT          NOT NULL DEFAULT 3,
    `upgrades`     TEXT         NOT NULL,
    `handling`     TEXT         NOT NULL,
    `customs`      TEXT         NOT NULL,
    `plate`        VARCHAR(32)  DEFAULT NULL,
    `isDestroyed`  TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `updated_at`   INT          NOT NULL DEFAULT 0,
    KEY `idx_vehicles_account` (`account_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================================
-- crews  (owner: [player_interaction]/v_socialpanel)
-- ----------------------------------------------------------------------------
-- One row per crew. `name` is the case-insensitive unique identifier (the mod
-- keys crews by name:lower()). `members` is a newline-separated list of account
-- names, founder included - rewritten whole on every join / leave / kick.
-- `founder` passes to the oldest member when the founder leaves; the row is
-- deleted once the crew hits 0 members.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `crews` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `name`        VARCHAR(32)      NOT NULL,
    `tag`         VARCHAR(16)      NOT NULL DEFAULT 'CREW',
    `founder`     VARCHAR(50)      NOT NULL,
    `description` VARCHAR(160)     NOT NULL DEFAULT '',
    `color_r`     TINYINT UNSIGNED NOT NULL DEFAULT 255,
    `color_g`     TINYINT UNSIGNED NOT NULL DEFAULT 200,
    `color_b`     TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `members`     TEXT             NOT NULL,
    `created_at`  INT              NOT NULL DEFAULT 0,
    `updated_at`  INT              NOT NULL DEFAULT 0,
    UNIQUE KEY `unique_crew_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================================
-- messages  (owner: [player_interaction]/v_socialpanel)
-- ----------------------------------------------------------------------------
-- One row per message, both private DMs and crew chat.
--   kind        'dm'   -> sender + recipient are account names
--               'crew' -> sender is an account name, recipient is the crew name
--   is_read     DM read flag (recipient's point of view); always 0 for crew
--               messages (crew "seen" is tracked per account in account_data).
-- History is capped per conversation (SP.MSG_HISTORY); the server deletes the
-- oldest rows as new ones arrive.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `messages` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `kind`       ENUM('dm','crew') NOT NULL,
    `sender`     VARCHAR(50)       NOT NULL,
    `recipient`  VARCHAR(50)       NOT NULL,
    `body`       VARCHAR(255)      NOT NULL,
    `is_read`    TINYINT(1)        NOT NULL DEFAULT 0,
    `created_at` INT               NOT NULL DEFAULT 0,
    KEY `idx_messages_dm`   (`kind`, `sender`, `recipient`),
    KEY `idx_messages_crew` (`kind`, `recipient`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================================
-- friendRequests  (owner: [player_interaction]/v_socialpanel)
-- ----------------------------------------------------------------------------
-- One row per pending incoming friend request. Removed when accepted, declined,
-- or when the reverse request turns the pair into friends. Friend *lists*
-- themselves stay in account_data (key "socialpanel:friends").
-- ============================================================================

CREATE TABLE IF NOT EXISTS `friendRequests` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `sender`     VARCHAR(50) NOT NULL,
    `recipient`  VARCHAR(50) NOT NULL,
    `created_at` INT         NOT NULL DEFAULT 0,
    UNIQUE KEY `unique_request` (`sender`, `recipient`),
    KEY `idx_friendrequests_recipient` (`recipient`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
