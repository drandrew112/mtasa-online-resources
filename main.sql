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
-- [player_interaction]/v_socialpanel/database.sql,
-- [bloodtransport]/bt_dispatch/database.sql,
-- [minigames]/v_gangwar/database.sql); this file is the union of
-- those, kept in sync by hand.


-- ============================================================================
-- accounts  (owner: acc_auth, via v_mysql)
-- ----------------------------------------------------------------------------
-- Replaces the old `global_account_data` table. One row per registered
-- account.
--
--   account_data  JSON object of arbitrary key -> { "v": <string>, "t": <type> }
--                 pairs (type = string | int | float | boolean). This is what
--                 exports.v_mysql:getAccData / setAccData read and write - the
--                 replacement for MTA's own getAccountData / setAccountData.
--   password      account password hash (managed by acc_auth).
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
-- bans  (owner: acc_bans, via v_mysql)
-- ----------------------------------------------------------------------------
-- Account bans, shared by every server on this database. acc_bans also
-- creates the table on start (CREATE TABLE IF NOT EXISTS).
--
--   account_name  banned account.
--   serial / ip   the player's serial / IP if they were online at ban time;
--                 the serial is checked on join too.
--   reason/admin  why and by whom.
--   created_at    unix timestamp of the ban.
--   lifted_at     0 while active; unix timestamp once unbanned.
--   lifted_by     who lifted it.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `bans` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `account_name` VARCHAR(50)  DEFAULT NULL,
    `serial`       VARCHAR(32)  DEFAULT NULL,
    `ip`           VARCHAR(45)  DEFAULT NULL,
    `reason`       TEXT         NOT NULL,
    `admin`        VARCHAR(64)  NOT NULL DEFAULT '',
    `created_at`   INT          NOT NULL DEFAULT 0,
    `lifted_at`    INT          NOT NULL DEFAULT 0,
    `lifted_by`    VARCHAR(64)  DEFAULT NULL,
    KEY `idx_account` (`account_name`),
    KEY `idx_serial`  (`serial`)
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


-- ============================================================================
-- weekly_schedule  (owner: [core]/v_weekly)
-- ----------------------------------------------------------------------------
-- One row per configured week.
--   week_start  unix timestamp (UTC) of Tuesday 10:00 UTC
--   data        JSON: { jobs = { [jobId] = { money, xp, label } },
--                       timetrial = <index>, custom = { ... },
--                       news = { title, body } }
-- A week without a row inherits the latest earlier row (news excluded).
-- ============================================================================

CREATE TABLE IF NOT EXISTS `weekly_schedule` (
    `week_start` INT          NOT NULL PRIMARY KEY,
    `data`       MEDIUMTEXT   NOT NULL,
    `updated_by` VARCHAR(50)  DEFAULT NULL,
    `updated_at` INT          NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


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
--   Pool rows: placeholders inserted ahead of time so a new task / shift gets
--                    its id without a blocking INSERT (PERF-01). bt_tasks:
--                    status = 'pool', source = 'pool:<server md5>'; bt_shifts:
--                    end_reason = 'pool', account = 'pool:<server md5>'.
--                    Readers skip them.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `bt_tasks` (
    `id`            INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
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

-- ============================================================================
-- gangwars  (owner: [minigames]/v_gangwar, via v_mysql)
-- ----------------------------------------------------------------------------
-- v_gangwar also creates the table on start (CREATE TABLE IF NOT EXISTS).
-- One row per gang war, made with /gangwareditor (admin_level >= 5).
--
--   x, y, z, interior, dimension   centre of the territory
--   trigger_radius   an armed player this close reserves it (red circle on his radar)
--   zone_radius      the red circle; entering it spawns the attackers
--   release_radius   the starter beyond this ends the reservation / the run
--   gang             ai_peds group of the attackers is "gw_<gang>"
--   attackers        JSON (MTA toJSON) list of
--                    {skin, x, y, z, rot, weapon, ammo, health, armor, accuracy (0..1), aggro,
--                     task ("guard" | "patrol"), patrol [[x,y,z], ...], wait [min_ms, max_ms],
--                     speed ("walk" | "run" | "sprint")}
--   reward_money / reward_xp   base reward of the starter (each kill: +1500 / +500 to the killer)
--   days             "1234567" (1 = Monday ... 7 = Sunday)
--   hour_from / hour_to        [from, to) server time; 0-24 = all day, from > to wraps past midnight
--   last_run         unix time of the last completed run; 3-day global cooldown from it (NULL = never ran)
--   isRunning        1 = a run is in progress on a server sharing this database, nobody else may start it;
--                    0 = startable. Set atomically on reservation, back to 0 when the run ends
-- ============================================================================

CREATE TABLE IF NOT EXISTS `gangwars` (
    `id`             INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `name`           VARCHAR(64)  NOT NULL,
    `enabled`        TINYINT(1)   NOT NULL DEFAULT 1,
    `x`              FLOAT        NOT NULL,
    `y`              FLOAT        NOT NULL,
    `z`              FLOAT        NOT NULL,
    `interior`       INT          NOT NULL DEFAULT 0,
    `dimension`      INT          NOT NULL DEFAULT 0,
    `trigger_radius` FLOAT        NOT NULL DEFAULT 150,
    `zone_radius`    FLOAT        NOT NULL DEFAULT 60,
    `release_radius` FLOAT        NOT NULL DEFAULT 250,
    `gang`           VARCHAR(32)  NOT NULL DEFAULT 'gang',
    `attackers`      MEDIUMTEXT,
    `reward_money`   INT          NOT NULL DEFAULT 0,
    `reward_xp`      INT          NOT NULL DEFAULT 0,
    `days`           VARCHAR(7)   NOT NULL DEFAULT '1234567',
    `hour_from`      TINYINT      NOT NULL DEFAULT 0,
    `hour_to`        TINYINT      NOT NULL DEFAULT 24,
    `last_run`       INT          DEFAULT NULL,
    `isRunning`      TINYINT(1)   NOT NULL DEFAULT 0,
    `created_by`     VARCHAR(50)  DEFAULT NULL,
    `created_at`     INT          DEFAULT NULL,
    `updated_by`     VARCHAR(50)  DEFAULT NULL,
    `updated_at`     INT          DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- password_resets  (acc_auth: forgotten password codes)
-- ---------------------------------------------------------------------------
-- One row per emailed code; only the sha256 of the code is stored. used_at = 0
-- while the code is alive. acc_auth also creates the table on start.
CREATE TABLE IF NOT EXISTS `password_resets` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `account_name` VARCHAR(50)  NOT NULL,
    `code_hash`    CHAR(64)     NOT NULL,
    `expires_at`   INT          NOT NULL DEFAULT 0,
    `attempts`     INT          NOT NULL DEFAULT 0,
    `serial`       VARCHAR(32)  DEFAULT NULL,
    `ip`           VARCHAR(45)  DEFAULT NULL,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `used_at`      INT          NOT NULL DEFAULT 0,
    KEY `idx_account` (`account_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- accounts.email: one account per email (several NULLs are allowed).
-- acc_auth adds it on start when it is missing:
-- ALTER TABLE `accounts` ADD UNIQUE KEY `uniq_email` (`email`);

-- ---------------------------------------------------------------------------
-- news  (v_news: /news editor, login screen and account menu)
-- ---------------------------------------------------------------------------
-- published_at may be in the future (scheduled). deleted_at > 0 = deleted.
-- v_news also creates the table on start.
CREATE TABLE IF NOT EXISTS `news` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `published_at` INT          NOT NULL DEFAULT 0,
    `title`        VARCHAR(255) NOT NULL DEFAULT '',
    `body`         TEXT         NOT NULL,
    `author`       VARCHAR(64)  NOT NULL DEFAULT '',
    `created_at`   INT          NOT NULL DEFAULT 0,
    `updated_at`   INT          NOT NULL DEFAULT 0,
    `deleted_at`   INT          NOT NULL DEFAULT 0,
    KEY `idx_published` (`published_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- mails  (v_mail: every mail the server sent; v_admin Mail page history; weekly updates)
-- ---------------------------------------------------------------------------
-- One row per mail. group_key joins the mails of one circular / one weekly
-- update ("circular:<ts>:<admin>", "updates:<ts>"); NULL = a single mail.
-- status: pending | sending | sent | failed | skipped. No email address is stored.
-- v_mail also creates the table on start (after mysql:connected).
CREATE TABLE IF NOT EXISTS `mails` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `group_key`    VARCHAR(64)  NULL DEFAULT NULL,
    `kind`         VARCHAR(32)  NOT NULL DEFAULT '',
    `sender`       VARCHAR(64)  NOT NULL DEFAULT '',
    `server_id`    INT          NOT NULL DEFAULT 0,
    `account_name` VARCHAR(64)  NULL DEFAULT NULL,
    `language`     VARCHAR(8)   NOT NULL DEFAULT '',
    `subject`      VARCHAR(255) NOT NULL DEFAULT '',
    `body`         MEDIUMTEXT   NULL,
    `template`     MEDIUMTEXT   NULL,
    `status`       VARCHAR(16)  NOT NULL DEFAULT 'sent',
    `message_id`   VARCHAR(128) NULL DEFAULT NULL,
    `error`        VARCHAR(255) NULL DEFAULT NULL,
    `created_at`   INT          NOT NULL DEFAULT 0,
    `sent_at`      INT          NOT NULL DEFAULT 0,
    KEY `idx_group` (`group_key`),
    KEY `idx_kind_status` (`kind`, `status`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- admin_log  (v_admin 3.0: every admin action from the game and the web panel)
-- ---------------------------------------------------------------------------
-- admin = the admin's account, admin_name = the nick at the time, source = game | web,
-- target = the account the action was about (NULL = none). Admin log page + the
-- Punishments tab of the Accounts page. v_admin also creates the table on start.
CREATE TABLE IF NOT EXISTS `admin_log` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `ts`         INT          NOT NULL DEFAULT 0,
    `admin`      VARCHAR(64)  NOT NULL DEFAULT '',
    `admin_name` VARCHAR(64)  NOT NULL DEFAULT '',
    `source`     VARCHAR(8)   NOT NULL DEFAULT 'game',
    `level`      INT          NOT NULL DEFAULT 0,
    `action`     VARCHAR(255) NOT NULL DEFAULT '',
    `target`     VARCHAR(64)  NULL DEFAULT NULL,
    KEY `idx_ts` (`ts`),
    KEY `idx_admin` (`admin`),
    KEY `idx_target` (`target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
