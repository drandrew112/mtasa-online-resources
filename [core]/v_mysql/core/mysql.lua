-- v_mysql :: mysql core
--
-- Thin wrapper around dbConnect("mysql", ...). Other resources never open their
-- own connection; they use the exported helpers below (mysqlQuery /
-- mysqlQuerySync / mysqlInsert / mysqlExec / mysqlEscape / mysqlIsConnected).
--
-- The async mysqlQuery callback style is only fully supported for callers
-- inside this resource. Cross-resource callers should use mysqlQuerySync /
-- mysqlInsert (they block for the round trip) or fire-and-forget mysqlExec.

local connection = nil
local connected  = false
local pingTimer  = nil

--------------------------------------------------------------------------------
-- Logging
--------------------------------------------------------------------------------

function mysqlLog(fmt, ...)
    outputServerLog("[v_mysql] " .. fmt:format(...))
end

local function debugLog(fmt, ...)
    if MYSQL_DEBUG then
        outputServerLog("[v_mysql] " .. fmt:format(...))
    end
end

--------------------------------------------------------------------------------
-- Connection handling
--------------------------------------------------------------------------------

local function hostString()
    return ("dbname=%s;host=%s;port=%d;charset=%s"):format(
        MYSQL_CONFIG.database, MYSQL_CONFIG.host, MYSQL_CONFIG.port, MYSQL_CONFIG.charset)
end

local reconnectPending = false

local function scheduleReconnect()
    if reconnectPending then return end
    reconnectPending = true
    setTimer(function()
        reconnectPending = false
        connectDatabase()
    end, MYSQL_RECONNECT_INTERVAL, 1)
end

-- Verifies a fresh connection with a trivial query. dbConnect() returns an
-- element immediately even when the server is unreachable, so the real check
-- has to be a round trip.
local function verifyConnection()
    dbQuery(function(qh)
        local result = dbPoll(qh, 0)
        dbFree(qh)
        if type(result) == "table" then
            if not connected then
                connected = true
                mysqlLog("Connected to %s@%s:%d/%s",
                    MYSQL_CONFIG.username, MYSQL_CONFIG.host, MYSQL_CONFIG.port, MYSQL_CONFIG.database)
                triggerEvent("mysql:connected", resourceRoot)
            end
        else
            connected = false
            mysqlLog("Connection check failed, reconnecting in %ds", MYSQL_RECONNECT_INTERVAL / 1000)
            if isElement(connection) then destroyElement(connection) end
            connection = nil
            scheduleReconnect()
        end
    end, connection, "SELECT 1")
end

function connectDatabase()
    if isElement(connection) then destroyElement(connection) end
    connected  = false
    connection = dbConnect("mysql", hostString(), MYSQL_CONFIG.username, MYSQL_CONFIG.password,
        "share=1;autoreconnect=1")

    if not connection then
        mysqlLog("dbConnect() failed outright, retrying in %ds", MYSQL_RECONNECT_INTERVAL / 1000)
        scheduleReconnect()
        return
    end

    verifyConnection()
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not MYSQL_ENABLE_SYNC then
        mysqlLog("Sync disabled (MYSQL_ENABLE_SYNC = false) - not connecting to any database")
        return
    end
    connectDatabase()
    pingTimer = setTimer(function()
        if isElement(connection) then verifyConnection() end
    end, MYSQL_PING_INTERVAL, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(pingTimer) then killTimer(pingTimer) end
    if isElement(connection) then destroyElement(connection) end
    connection = nil
    connected  = false
end)

--------------------------------------------------------------------------------
-- Public helpers (also exported)
--------------------------------------------------------------------------------

-- true once the initial round-trip check has succeeded.
function mysqlIsConnected()
    return connected and isElement(connection) or false
end

-- Runs a SELECT (or any query whose rows you want). `callback` receives
-- (result, numRows) on success or (false, errText) on failure. Placeholders
-- (?) in `queryStr` are substituted and escaped from the varargs.
function mysqlQuery(callback, queryStr, ...)
    if not isElement(connection) then
        debugLog("mysqlQuery skipped (no connection): %s", queryStr)
        if callback then callback(false, "no connection") end
        return false
    end

    debugLog("query: %s", queryStr)
    local handler = function(qh)
        local result, a, b = dbPoll(qh, 0)
        dbFree(qh)
        if type(result) ~= "table" then
            mysqlLog("Query error: %s | SQL: %s", tostring(b or a), queryStr)
            if callback then callback(false, b or a) end
            return
        end
        if callback then callback(result, a) end
    end
    return dbQuery(handler, connection, queryStr, ...) ~= false
end

-- Runs a SELECT and BLOCKS until the result is in (dbPoll with no timeout).
-- Returns the result table (possibly empty), or false when there is no
-- connection or the query failed. Use only for small, latency-tolerant
-- lookups - it stalls the server thread for the whole round trip. Safe to call
-- from other resources (unlike mysqlQuery's callback style).
function mysqlQuerySync(queryStr, ...)
    if not isElement(connection) then
        debugLog("mysqlQuerySync skipped (no connection): %s", queryStr)
        return false
    end
    debugLog("query(sync): %s", queryStr)
    local qh = dbQuery(connection, queryStr, ...)
    if not qh then return false end
    local result = dbPoll(qh, -1)
    dbFree(qh)
    if type(result) ~= "table" then
        mysqlLog("Query error: %s | SQL: %s", tostring(result), queryStr)
        return false
    end
    return result
end

-- Runs an INSERT synchronously and returns the AUTO_INCREMENT id it produced
-- (LAST_INSERT_ID()), or false on failure. Blocks for the round trip. The id
-- lookup runs on the same connection with no yield in between, so nothing can
-- slip a query ahead of it.
function mysqlInsert(queryStr, ...)
    if not isElement(connection) then
        debugLog("mysqlInsert skipped (no connection): %s", queryStr)
        return false
    end
    debugLog("insert(sync): %s", queryStr)
    local qh = dbQuery(connection, queryStr, ...)
    if not qh then return false end
    local ok = dbPoll(qh, -1)
    dbFree(qh)
    if ok == false then
        mysqlLog("Insert error | SQL: %s", queryStr)
        return false
    end
    local idqh = dbQuery(connection, "SELECT LAST_INSERT_ID() AS id")
    local res  = dbPoll(idqh, -1)
    dbFree(idqh)
    if type(res) == "table" and res[1] then
        return tonumber(res[1].id)
    end
    return true
end

-- Runs an INSERT / UPDATE / DELETE. Fire and forget; returns whether the
-- statement was queued. Placeholders (?) are escaped from the varargs.
function mysqlExec(queryStr, ...)
    if not isElement(connection) then
        debugLog("mysqlExec skipped (no connection): %s", queryStr)
        return false
    end
    debugLog("exec: %s", queryStr)
    return dbExec(connection, queryStr, ...) ~= false
end

-- Escapes/quotes a single value for manual query building. Prefer ? placeholders.
function mysqlEscape(value)
    if isElement(connection) then
        return dbPrepareString(connection, "?", tostring(value))
    end
    return "'" .. tostring(value):gsub("'", "''") .. "'"
end
