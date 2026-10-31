-- police_system / modules/db/server/db.lua
-- MySQL through v_mysql's async lib (MYSQL.query / MYSQL.insert, never blocking). Start: CREATE TABLE IF NOT
-- EXISTS in order, after v_mysql is connected (retried on mysql:connected), then the pools are loaded and the
-- other modules get "db.ready".

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

local DBM = POL.module("db", { ready = false })
DBM.NOT_POOL = "is_pool = 0"

function DBM.instance()
    local ok, id = pcall(function() return exports.v_main:getServerInstanceId() end)
    return tostring(ok and id or "1")
end

-- cb(rows | false, err)
function DBM.query(cb, sql, ...)
    return MYSQL.query(cb or function() end, sql, ...)
end

function DBM.exec(sql, ...)
    return MYSQL.query(function(ok, err)
        if ok == false then outputDebugString("[police_system] SQL failed: " .. tostring(err) .. " :: " .. sql:sub(1, 120), 2) end
    end, sql, ...)
end

function DBM.json(t) return toJSON(t or {}, true) end

function DBM.unjson(s)
    if type(s) ~= "string" or s == "" then return {} end
    local ok, t = pcall(fromJSON, s)
    return ok and type(t) == "table" and t or {}
end

-- JSON lines column (append-only, CONCAT on the server)
function DBM.appendLine(tbl, col, id, entry)
    DBM.exec("UPDATE " .. tbl .. " SET " .. col .. " = CONCAT(COALESCE(" .. col .. ", ''), ?) WHERE id = ?",
        toJSON(entry, true) .. "\n", id)
end

function DBM.lines(s)
    local list = {}
    for line in tostring(s or ""):gmatch("[^\n]+") do
        local ok, e = pcall(fromJSON, line)
        if ok and type(e) == "table" then list[#list + 1] = e end
    end
    return list
end

local function connected()
    local res = getResourceFromName("v_mysql")
    if not res or getResourceState(res) ~= "running" then return false end
    local ok, c = pcall(function() return exports.v_mysql:mysqlIsConnected() end)
    return ok and c == true
end

local starting = false
function DBM.init()
    if DBM.ready or starting or not connected() then return end
    starting = true
    local function run(i)
        if i > #POL_SCHEMA then
            DBM.ready = true
            starting = false
            DBM.pool.load(function()
                POL.emit("db.ready")
            end)
            return
        end
        MYSQL.query(function(ok, err)
            if ok == false then
                outputDebugString("[police_system] schema " .. i .. " failed: " .. tostring(err), 1)
                starting = false
                setTimer(DBM.init, 10000, 1)
                return
            end
            run(i + 1)
        end, POL_SCHEMA[i])
    end
    run(1)
end

function DBM.start()
    DBM.init()
end

addEvent("mysql:connected")
addEventHandler("mysql:connected", root, function() DBM.init() end)

-- "YYYY-MM-DD" of an epoch
function DBM.day(ts)
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

-- pol_stats: +n to today's counter
function DBM.stat(key, n)
    if not DBM.ready then return end
    DBM.exec("INSERT INTO pol_stats (day, stat, amount) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)",
        DBM.day(POL.now()), key, n or 1)
end
