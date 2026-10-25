-- gov_perms / server/db.lua
-- The tables (DESIGN.md 3). The catalogue (gov_perms) mirrors what the modules declare; groups,
-- their rights, appointments and branches are edited on the Permissions page; salary payouts
-- are kept for 30 days (the Budget plan, the Officials tab).

PERMS.SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS gov_perms (
        perm VARCHAR(64) NOT NULL,
        module VARCHAR(32) NOT NULL,
        area VARCHAR(24) NOT NULL,
        family VARCHAR(48) NOT NULL DEFAULT '',
        target VARCHAR(32) NOT NULL DEFAULT '',
        danger TINYINT UNSIGNED NOT NULL DEFAULT 1,
        sort SMALLINT UNSIGNED NOT NULL DEFAULT 100,
        active TINYINT(1) NOT NULL DEFAULT 1,
        first_seen INT UNSIGNED NOT NULL DEFAULT 0,
        last_seen INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (perm),
        KEY idx_module (module),
        KEY idx_family (family)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_perms_groups (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        code VARCHAR(32) NOT NULL,
        name VARCHAR(64) NOT NULL,
        description VARCHAR(255) NOT NULL DEFAULT '',
        kind VARCHAR(16) NOT NULL DEFAULT 'position',
        seniority SMALLINT UNSIGNED NOT NULL DEFAULT 100,   -- the rank (RANK is a reserved word in MySQL 8)
        max_holders SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        salary INT UNSIGNED NOT NULL DEFAULT 0,
        tax_key VARCHAR(24) NOT NULL DEFAULT 'standard',
        color CHAR(7) NOT NULL DEFAULT '#888888',
        status VARCHAR(16) NOT NULL DEFAULT 'active',
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        updated_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        UNIQUE KEY uq_code (code)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_perms_group_perms (
        group_id INT UNSIGNED NOT NULL,
        perm VARCHAR(64) NOT NULL,
        branch VARCHAR(24) NOT NULL DEFAULT '',
        granted_by VARCHAR(64) NOT NULL DEFAULT '',
        granted_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (group_id, perm, branch)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_perms_members (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        account_name VARCHAR(64) NOT NULL,
        group_id INT UNSIGNED NOT NULL,
        granted_by VARCHAR(64) NOT NULL DEFAULT '',
        granted_at INT UNSIGNED NOT NULL DEFAULT 0,
        expires_at INT UNSIGNED NOT NULL DEFAULT 0,
        salary_sec INT UNSIGNED NOT NULL DEFAULT 0,
        note VARCHAR(128) NOT NULL DEFAULT '',
        PRIMARY KEY (id),
        UNIQUE KEY uq_member (account_name, group_id),
        KEY idx_group (group_id),
        KEY idx_expires (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_branches (
        code VARCHAR(24) NOT NULL,
        name VARCHAR(64) NOT NULL,
        sort SMALLINT UNSIGNED NOT NULL DEFAULT 100,
        status VARCHAR(16) NOT NULL DEFAULT 'active',
        PRIMARY KEY (code)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_perms_salaries (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        ts INT UNSIGNED NOT NULL,
        account_name VARCHAR(64) NOT NULL,
        group_id INT UNSIGNED NOT NULL,
        gross INT UNSIGNED NOT NULL,
        tax INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        KEY idx_ts (ts),
        KEY idx_group_ts (group_id, ts)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}
