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
