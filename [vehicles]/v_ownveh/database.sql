-- v_ownveh :: database schema
--
-- Owned vehicles are now stored in the shared MySQL database used by v_mysql
-- (MYSQL_CONFIG.database), not in a local vehicles.db anymore.
--
-- Run this once against that database:
--
--   mysql -h <host> -P <port> -u <user> -p <database> < database.sql
--
-- or paste it into phpMyAdmin / Adminer. This is the `vehicles` slice only;
-- the whole mod's schema lives in ../../main.sql.
--
-- One row per owned vehicle. The `id` is the vehicle's permanent identifier
-- used by every export and stored on the owner's account as
-- "owned_vehicle_ids" ("1,2,3"). Health is intentionally NOT stored: a wreck
-- gets isDestroyed = 1 and must be unlocked with setVehicleDestroyed(id, false).
--
-- Serialisation of the wider fields (unchanged from the old SQLite layer):
--   colors    "r,g,b,r,g,b,..."  (everything getVehicleColor(veh, true) returns)
--   upgrades  "id,id,id"         (getVehicleUpgrades)
--   handling  JSON object        (only properties that differ from stock)
--   customs   JSON object        (v_customs extras kept on element data:
--                                 nitro level, neon colour, air-ride,
--                                 bulletproof tyres, LSD doors). "{}" when
--                                 nothing applies.

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
