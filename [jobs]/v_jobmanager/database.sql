-- v_jobmanager :: database schema (also included in ../../main.sql)
-- Created by core/storage.lua at start too. The three tables share their columns:
--
--   data           the game JSON without id / createdBy / image
--   image          base64 JPEG thumbnail (NULL = none: clients show assets/jobs/default.jpg)
--   image_version  bumped on every new photo (client cache key)
--
--   jobs_draft.target  'official' | 'community': the table Publish writes into
--   jobs_draft.image   NULL = same as the live copy, '' = removed, else the new photo
CREATE TABLE IF NOT EXISTS `jobs_official` (
    `id`            VARCHAR(64)  NOT NULL PRIMARY KEY,
    `name`          VARCHAR(80)  NOT NULL,
    `type`          VARCHAR(16)  NOT NULL,
    `created_by`    VARCHAR(50)  NOT NULL,
    `published_by`  VARCHAR(50)  DEFAULT NULL,
    `data`          MEDIUMTEXT   NOT NULL,
    `image`         MEDIUMTEXT   NULL,
    `image_version` INT          NOT NULL DEFAULT 0,
    `created_at`    INT          NOT NULL DEFAULT 0,
    `updated_at`    INT          NOT NULL DEFAULT 0,
    KEY `idx_created_by` (`created_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `jobs_community` (
    `id`            VARCHAR(64)  NOT NULL PRIMARY KEY,
    `name`          VARCHAR(80)  NOT NULL,
    `type`          VARCHAR(16)  NOT NULL,
    `created_by`    VARCHAR(50)  NOT NULL,
    `published_by`  VARCHAR(50)  DEFAULT NULL,
    `data`          MEDIUMTEXT   NOT NULL,
    `image`         MEDIUMTEXT   NULL,
    `image_version` INT          NOT NULL DEFAULT 0,
    `created_at`    INT          NOT NULL DEFAULT 0,
    `updated_at`    INT          NOT NULL DEFAULT 0,
    KEY `idx_created_by` (`created_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `jobs_draft` (
    `id`            VARCHAR(64)  NOT NULL PRIMARY KEY,
    `name`          VARCHAR(80)  NOT NULL,
    `type`          VARCHAR(16)  NOT NULL,
    `created_by`    VARCHAR(50)  NOT NULL,
    `target`        VARCHAR(16)  NOT NULL DEFAULT 'community',
    `data`          MEDIUMTEXT   NOT NULL,
    `image`         MEDIUMTEXT   NULL,
    `image_version` INT          NOT NULL DEFAULT 0,
    `created_at`    INT          NOT NULL DEFAULT 0,
    `updated_at`    INT          NOT NULL DEFAULT 0,
    KEY `idx_created_by` (`created_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
