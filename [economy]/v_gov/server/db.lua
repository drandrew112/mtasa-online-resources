-- v_gov / server/db.lua
-- Tables (DESIGN.md 9), the async MySQL lib and small helpers.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

DB = { ready = false }

local SCHEMA = {
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

    [[CREATE TABLE IF NOT EXISTS gov_tax_runs (
        period_start INT UNSIGNED NOT NULL,
        instance VARCHAR(16) NOT NULL,
        companies INT UNSIGNED NOT NULL DEFAULT 0,
        total BIGINT NOT NULL DEFAULT 0,
        finished_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (period_start)
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

    [[CREATE TABLE IF NOT EXISTS gov_votes (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        title VARCHAR(120) NOT NULL,
        description TEXT NOT NULL,
        options TEXT NOT NULL,
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        ends_at INT UNSIGNED NOT NULL DEFAULT 0,
        status VARCHAR(16) NOT NULL DEFAULT 'open',
        closed_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        KEY idx_status (status, ends_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS gov_vote_ballots (
        vote_id INT UNSIGNED NOT NULL,
        account_name VARCHAR(64) NOT NULL,
        option_idx TINYINT UNSIGNED NOT NULL,
        ts INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (vote_id, account_name),
        KEY idx_account (account_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- government news (server/news.lua); texts = JSON { [lang] = { title, body } }
    [[CREATE TABLE IF NOT EXISTS gov_news (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        texts MEDIUMTEXT NOT NULL,
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        mail_group VARCHAR(64) NOT NULL DEFAULT '',
        deleted_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        KEY idx_list (deleted_at, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

addEvent("v_gov:dbReady", false)

local function runSchema(i)
    if i > #SCHEMA then
        DB.ready = true
        triggerEvent("v_gov:dbReady", resourceRoot)
        return
    end
    MYSQL.query(function(ok, err)
        if ok == false then
            outputDebugString("[v_gov] schema " .. i .. " failed: " .. tostring(err), 1)
            setTimer(runSchema, 10000, 1, i)
            return
        end
        runSchema(i + 1)
    end, SCHEMA[i])
end

function DB.start() runSchema(1) end

function DB.exec(sql, ...)
    if not isResourceRunning("v_mysql") then return false end
    return exports.v_mysql:mysqlExec(sql, ...)
end

function DB.query(cb, sql, ...) return MYSQL.query(cb, sql, ...) end

function DB.int(v) return math.floor(tonumber(v) or 0) end

function DB.clip(s, n)
    s = tostring(s or "")
    if #s > n then s = s:sub(1, n) end
    return s
end

function isResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

function GOV.now() return getRealTime().timestamp end

function GOV.instance()
    if not isResourceRunning("v_main") then return "" end
    return tostring(exports.v_main:getServerInstanceId() or "")
end

--- account name of a logged-in player (lower-case), or nil
function GOV.accountOf(player)
    if not isElement(player) or getElementType(player) ~= "player" then return nil end
    if getElementData(player, "isLogged") ~= true then return nil end
    local name = getElementData(player, "accName")
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end

function GOV.bank()
    return isResourceRunning("v_bank") and exports.v_bank or nil
end

--- one panel change in gov_log
function GOV.log(actor, action, detail)
    local json = type(detail) == "table" and (toJSON(detail, true) or "") or tostring(detail or "")
    DB.exec("INSERT INTO gov_log (ts, actor, action, detail) VALUES (?, ?, ?, ?)",
        GOV.now(), DB.clip(actor, 64), DB.clip(action, 48), DB.clip(json, 255))
end
