-- v_collectibles: one row per collected item (also created on resource start; copy kept in the repo-root main.sql)
CREATE TABLE IF NOT EXISTS `collectibles_found` (
    `account`  VARCHAR(64)  NOT NULL,
    `list_id`  VARCHAR(32)  NOT NULL,
    `item_id`  INT UNSIGNED NOT NULL,
    `found_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`account`, `list_id`, `item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
