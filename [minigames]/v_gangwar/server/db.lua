-- gangwars table (v_mysql). Every row is cached in GangWars.list; the editor writes through here.
-- Schema: database.sql (also in the repo-root main.sql); created on start when missing.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib (PERF-01)

GangWars = { list = {}, loaded = false }

local TABLE = "gangwars"
local COLUMNS = "id, name, enabled, x, y, z, interior, dimension, trigger_radius, zone_radius, release_radius, gang, "
    .. "attackers, reward_money, reward_xp, days, hour_from, hour_to, last_run, isRunning, created_by, created_at, updated_by, updated_at"

local function sql() return exports.v_mysql end

local function now() return getRealTime().timestamp end

local function decodeList(s)
    if type(s) ~= "string" or s == "" then return {} end
    local ok, t = pcall(fromJSON, s)
    return (ok and type(t) == "table") and t or {}
end

local function fromRow(r)
    local gw = {
        id = tonumber(r.id), name = tostring(r.name or ""), enabled = tonumber(r.enabled) == 1,
        x = tonumber(r.x) or 0, y = tonumber(r.y) or 0, z = tonumber(r.z) or 0,
        interior = tonumber(r.interior) or 0, dimension = tonumber(r.dimension) or 0,
        trigger_radius = tonumber(r.trigger_radius) or GW.DEFAULTS.trigger_radius,
        zone_radius = tonumber(r.zone_radius) or GW.DEFAULTS.zone_radius,
        release_radius = tonumber(r.release_radius) or GW.DEFAULTS.release_radius,
        gang = tostring(r.gang or GW.DEFAULTS.gang),
        reward_money = tonumber(r.reward_money) or 0, reward_xp = tonumber(r.reward_xp) or 0,
        days = tostring(r.days or GW.DEFAULTS.days),
        hour_from = tonumber(r.hour_from) or 0, hour_to = tonumber(r.hour_to) or 24,
        last_run = tonumber(r.last_run),
        isRunning = tonumber(r.isRunning) == 1,
        created_by = r.created_by, created_at = tonumber(r.created_at),
        updated_by = r.updated_by, updated_at = tonumber(r.updated_at),
    }
    -- rows written by hand may be broken: the same rules as an editor save
    gw.attackers = Sanitize.attackers(decodeList(r.attackers))
    return gw
end

-- cb(): the table exists and has every column (an older table gets isRunning added)
function GangWars.ensureTable(cb)
    MYSQL.query(function()
        MYSQL.query(function(rows)
            if type(rows) == "table" and #rows == 0 then
                MYSQL.query(function() if cb then cb() end end,
                    "ALTER TABLE `" .. TABLE .. "` ADD COLUMN `isRunning` TINYINT(1) NOT NULL DEFAULT 0 AFTER `last_run`")
            elseif cb then
                cb()
            end
        end, "SHOW COLUMNS FROM `" .. TABLE .. "` LIKE 'isRunning'")
    end, [[CREATE TABLE IF NOT EXISTS `gangwars` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

-- cb(ok)
function GangWars.load(cb)
    MYSQL.query(function(rows)
        if type(rows) ~= "table" then
            if cb then cb(false) end
            return
        end
        local list = {}
        for _, r in ipairs(rows) do
            local gw = fromRow(r)
            if gw.id then list[gw.id] = gw end
        end
        GangWars.list = list
        GangWars.loaded = true
        if cb then cb(true) end
    end, "SELECT " .. COLUMNS .. " FROM `" .. TABLE .. "`")
end

-- other servers may share the database: only last_run and isRunning are refreshed (the editor writes the rest
-- through here). isRunning of a run of this server stays set locally (GangWars.claim / release own it).
function GangWars.refreshShared()
    MYSQL.query(function(rows)
        if type(rows) ~= "table" then return end
        for _, r in ipairs(rows) do
            local gw = GangWars.list[tonumber(r.id)]
            if gw then
                local lr = tonumber(r.last_run)
                if lr and (not gw.last_run or lr > gw.last_run) then gw.last_run = lr end
                if not gw.claimed then gw.isRunning = tonumber(r.isRunning) == 1 end
            end
        end
    end, "SELECT id, last_run, isRunning FROM `" .. TABLE .. "`")
end

function GangWars.get(id) return GangWars.list[tonumber(id)] end

-- column values in the INSERT / UPDATE order, then the extra ones (a call in the middle of an argument list would be
-- cut to its first value)
local function values(gw, ...)
    local v = { gw.name, gw.enabled and 1 or 0, gw.x, gw.y, gw.z, gw.interior, gw.dimension,
        gw.trigger_radius, gw.zone_radius, gw.release_radius, gw.gang, toJSON(gw.attackers, true),
        gw.reward_money, gw.reward_xp, gw.days, gw.hour_from, gw.hour_to }
    for _, extra in ipairs({ ... }) do v[#v + 1] = extra end
    return unpack(v)
end

-- gw: sanitized doc (Sanitize.doc). New when gw.id is nil. cb(id | false)
function GangWars.save(gw, by, cb)
    local t = now()
    by = tostring(by or ""):sub(1, 50)
    local old = gw.id and GangWars.list[gw.id]
    if old then
        gw.last_run, gw.created_by, gw.created_at = old.last_run, old.created_by, old.created_at
        gw.isRunning, gw.claimed = old.isRunning, old.claimed
        gw.updated_by, gw.updated_at = by, t
        GangWars.list[gw.id] = gw
        sql():mysqlExec("UPDATE `" .. TABLE .. "` SET name = ?, enabled = ?, x = ?, y = ?, z = ?, interior = ?, dimension = ?, "
            .. "trigger_radius = ?, zone_radius = ?, release_radius = ?, gang = ?, attackers = ?, reward_money = ?, reward_xp = ?, "
            .. "days = ?, hour_from = ?, hour_to = ?, updated_by = ?, updated_at = ? WHERE id = ?",
            values(gw, by, t, gw.id))
        if cb then cb(gw.id) end
        return
    end
    gw.id = nil
    MYSQL.insert(function(id)
        id = tonumber(id)
        if not id then
            if cb then cb(false) end
            return
        end
        gw.id, gw.created_by, gw.created_at, gw.updated_by, gw.updated_at = id, by, t, by, t
        GangWars.list[id] = gw
        if cb then cb(id) end
    end, "INSERT INTO `" .. TABLE .. "` (name, enabled, x, y, z, interior, dimension, trigger_radius, zone_radius, "
        .. "release_radius, gang, attackers, reward_money, reward_xp, days, hour_from, hour_to, created_by, created_at, "
        .. "updated_by, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        values(gw, by, t, by, t))
end

function GangWars.delete(id)
    id = tonumber(id)
    if not GangWars.list[id] then return false end
    GangWars.list[id] = nil
    sql():mysqlExec("DELETE FROM `" .. TABLE .. "` WHERE id = ?", id)
    return true
end

-- ts = unix time, or false: no cooldown
function GangWars.setLastRun(id, ts)
    local gw = GangWars.list[tonumber(id)]
    if not gw then return false end
    gw.last_run = ts or nil
    if ts then
        sql():mysqlExec("UPDATE `" .. TABLE .. "` SET last_run = ? WHERE id = ?", ts, gw.id)
    else
        sql():mysqlExec("UPDATE `" .. TABLE .. "` SET last_run = NULL WHERE id = ?", gw.id)
    end
    return true
end

-- isRunning = 1: the gang war runs on a server (this one or another sharing the database), nobody else may start it.
-- The flag is taken with a conditional UPDATE, so two servers cannot both get it. cb(ok)
function GangWars.claim(id, cb)
    local gw = GangWars.list[tonumber(id)]
    if not gw then return cb(false) end
    MYSQL.query(function(res, affected)
        local ok = type(res) == "table" and tonumber(affected) == 1
        if ok then gw.claimed = true end
        -- ok: ours now; a table with 0 rows changed: another server holds it
        if type(res) == "table" then gw.isRunning = true end
        cb(ok)
    end, "UPDATE `" .. TABLE .. "` SET isRunning = 1 WHERE id = ? AND isRunning = 0", gw.id)
end

-- the run of this server ended (or an admin clears a flag left behind by a crashed server)
function GangWars.release(id)
    local gw = GangWars.list[tonumber(id)]
    if not gw then return false end
    gw.isRunning, gw.claimed = false, nil
    sql():mysqlExec("UPDATE `" .. TABLE .. "` SET isRunning = 0 WHERE id = ?", gw.id)
    return true
end

-- seconds left of the cooldown (0 = available)
function GangWars.cooldownLeft(gw, t)
    if not gw.last_run then return 0 end
    return math.max(0, gw.last_run + GW.COOLDOWN - (t or now()))
end

-- may it appear now? (enabled, not running anywhere, cooldown over, day and hour window)
-- ignoreRunning: the caller holds the isRunning flag itself
function GangWars.isOpen(gw, rt, ignoreRunning)
    rt = rt or getRealTime()
    if not gw.enabled or (gw.isRunning and not ignoreRunning) or #gw.attackers == 0 then return false end
    if GangWars.cooldownLeft(gw, rt.timestamp) > 0 then return false end
    return GW.isDayAllowed(gw.days, rt.weekday) and GW.isHourAllowed(gw.hour_from, gw.hour_to, rt.hour)
end
