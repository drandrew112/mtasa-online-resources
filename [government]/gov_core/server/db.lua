-- gov_core / server/db.lua
-- The tables of gov_core (the same tables v_gov had, the data stays). The other gov_* resources
-- create their own tables.

GOV.SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS gov_settings (
        skey VARCHAR(64) NOT NULL,
        value TEXT NOT NULL,
        updated_by VARCHAR(64) NOT NULL DEFAULT '',
        updated_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (skey)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_members (
        account_name VARCHAR(64) NOT NULL,
        role VARCHAR(16) NOT NULL,
        granted_by VARCHAR(64) NOT NULL DEFAULT '',
        granted_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (account_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_log (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        ts INT UNSIGNED NOT NULL,
        actor VARCHAR(64) NOT NULL,
        action VARCHAR(48) NOT NULL,
        detail VARCHAR(255) NOT NULL DEFAULT '',
        PRIMARY KEY (id),
        KEY idx_ts (ts)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- state companies (their money: the v_bank state account `account_id`, owner_ref = code)
    [[CREATE TABLE IF NOT EXISTS gov_companies (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        code VARCHAR(24) NOT NULL,
        name VARCHAR(64) NOT NULL,
        description VARCHAR(255) NOT NULL DEFAULT '',
        account_id INT UNSIGNED NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'active',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        closed_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        UNIQUE KEY uq_code (code),
        KEY idx_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

--- one panel change in gov_log (export log: the other gov_* resources)
function GOV.log(actor, action, detail)
    local json = type(detail) == "table" and (toJSON(detail, true) or "") or tostring(detail or "")
    DB.exec("INSERT INTO gov_log (ts, actor, action, detail) VALUES (?, ?, ?, ?)",
        GOV.now(), DB.clip(actor, 64), DB.clip(action, 48), DB.clip(json, 255))
end

function log(actor, action, detail)
    GOV.log(actor, action, detail)
    return true
end
