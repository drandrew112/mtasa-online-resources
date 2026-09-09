-- v_socialpanel :: database schema
--
-- Crews and every private / crew message now live in the shared MySQL database
-- used by v_mysql (MYSQL_CONFIG.database), not in local crews.xml / messages.xml
-- anymore. Friend *lists* stay in account data (accounts.account_data, key
-- "socialpanel:friends"); friend *requests* get their own table below.
--
-- Run this once against that database:
--
--   mysql -h <host> -P <port> -u <user> -p <database> < database.sql
--
-- or paste it into phpMyAdmin / Adminer. This is the social-panel slice only;
-- the whole mod's schema lives in ../../main.sql.


-- ============================================================================
-- crews
-- ----------------------------------------------------------------------------
-- One row per crew. `name` is the case-insensitive unique identifier (the mod
-- keys crews by name:lower()). `members` is a newline-separated list of account
-- names, founder included - rewritten whole on every join / leave / kick.
--   color_r/g/b   crew colour, 0-255
--   founder       account name of the current founder (passes to the oldest
--                 member when the founder leaves; row is deleted at 0 members)
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
-- messages
-- ----------------------------------------------------------------------------
-- One row per message, both private DMs and crew chat.
--   kind        'dm'   -> sender + recipient are account names
--               'crew' -> sender is an account name, recipient is the crew name
--   body        message text (<= SP.MSG_MAX_LEN chars)
--   is_read     DM read flag (from the recipient's point of view); always 0 for
--               crew messages (crew "seen" is tracked per account in accData).
-- History is capped per conversation (SP.MSG_HISTORY) - the server deletes the
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
-- friendRequests
-- ----------------------------------------------------------------------------
-- One row per pending incoming friend request. Removed when accepted, declined,
-- or when the reverse request turns the pair into friends. The (sender,
-- recipient) pair is unique.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `friendRequests` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `sender`     VARCHAR(50) NOT NULL,
    `recipient`  VARCHAR(50) NOT NULL,
    `created_at` INT         NOT NULL DEFAULT 0,
    UNIQUE KEY `unique_request` (`sender`, `recipient`),
    KEY `idx_friendrequests_recipient` (`recipient`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
