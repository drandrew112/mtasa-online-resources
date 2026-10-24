if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
-- biz_core / server/db.lua
-- Tables of the organization system (shared v_mysql database) and small query
-- helpers. The tables create themselves on start; database.sql has the same
-- schema for a manual install.
--
-- Writes go through v_mysql:mysqlExec (queued and retried after a reconnect),
-- reads through the async lib. Balances are only ever changed with deltas
-- (balance = balance + ?), so writes of several instances add up correctly.

DB = { ready = false }

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS biz_companies (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        owner_account VARCHAR(64) NULL,
        founder_account VARCHAR(64) NOT NULL,
        name VARCHAR(48) NOT NULL,
        name_key VARCHAR(48) NULL,
        balance_clean BIGINT NOT NULL DEFAULT 0,
        balance_dirty BIGINT NOT NULL DEFAULT 0,
        launder_queue BIGINT NOT NULL DEFAULT 0,
        hq_unit_id INT UNSIGNED NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'active',
        active_seconds INT UNSIGNED NOT NULL DEFAULT 0,
        upkeep_seconds INT UNSIGNED NOT NULL DEFAULT 0,
        value_cache BIGINT NOT NULL DEFAULT 0,
        peak_value BIGINT NOT NULL DEFAULT 0,
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        renamed_at INT UNSIGNED NOT NULL DEFAULT 0,
        sold_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        UNIQUE KEY uq_owner (owner_account),
        UNIQUE KEY uq_name (name_key),
        KEY idx_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS biz_units (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        company_id INT UNSIGNED NOT NULL,
        property_id VARCHAR(48) NOT NULL,
        price_paid BIGINT NOT NULL DEFAULT 0,
        upgrades_paid BIGINT NOT NULL DEFAULT 0,
        purchased_at INT UNSIGNED NOT NULL DEFAULT 0,
        data_json TEXT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_company_property (company_id, property_id),
        KEY idx_company (company_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS biz_ledger (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        company_id INT UNSIGNED NOT NULL,
        ts INT UNSIGNED NOT NULL,
        amount BIGINT NOT NULL,
        dirty TINYINT NOT NULL DEFAULT 0,
        balance_after BIGINT NOT NULL DEFAULT 0,
        category VARCHAR(32) NOT NULL,
        description VARCHAR(160) NOT NULL DEFAULT '',
        actor_account VARCHAR(64) NOT NULL DEFAULT '',
        ref VARCHAR(64) NOT NULL DEFAULT '',
        PRIMARY KEY (id),
        KEY idx_company_ts (company_id, ts)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

addEvent("biz_core:dbReady", false)

-- columns added after the first release: { table, column, definition }
local COLUMNS = {
    { "biz_companies", "tax_seconds", "INT UNSIGNED NOT NULL DEFAULT 0" },   -- property tax clock
}

local function addColumns(i)
    if i > #COLUMNS then
        DB.ready = true
        triggerEvent("biz_core:dbReady", resourceRoot)
        return
    end
    local t, col, def = unpack(COLUMNS[i])
    MYSQL.query(function(rows)
        if rows == false then return setTimer(addColumns, 10000, 1, i) end
        if rows and rows[1] and tonumber(rows[1].n) and tonumber(rows[1].n) > 0 then return addColumns(i + 1) end
        MYSQL.query(function(ok, err)
            if ok == false then outputDebugString("[biz_core] add column " .. col .. " failed: " .. tostring(err), 1) end
            addColumns(i + 1)
        end, "ALTER TABLE " .. t .. " ADD COLUMN " .. col .. " " .. def)
    end, "SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?", t, col)
end

local function runSchema(i)
    if i > #SCHEMA then return addColumns(1) end
    MYSQL.query(function(ok, err)
        if ok == false then
            outputDebugString("[biz_core] schema " .. i .. " failed: " .. tostring(err), 1)
            -- retry later: v_mysql may not be connected yet
            setTimer(runSchema, 10000, 1, i)
            return
        end
        runSchema(i + 1)
    end, SCHEMA[i])
end

function DB.start()
    runSchema(1)
end

function DB.exec(sql, ...)
    local res = getResourceFromName("v_mysql")
    if not res or getResourceState(res) ~= "running" then return false end
    return exports.v_mysql:mysqlExec(sql, ...)
end

function DB.query(cb, sql, ...)
    return MYSQL.query(cb, sql, ...)
end

function DB.insert(cb, sql, ...)
    return MYSQL.insert(cb, sql, ...)
end

function BIZ.now()
    return getRealTime().timestamp
end

--- integer of a DB value (MySQL BIGINT can arrive as string)
function DB.int(v)
    return math.floor(tonumber(v) or 0)
end

--- short text for VARCHAR columns
function DB.clip(s, n)
    s = tostring(s or "")
    if #s > n then s = s:sub(1, n) end
    return s
end
