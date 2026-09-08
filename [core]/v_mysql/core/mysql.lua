-- v_mysql :: mysql core
--
-- Thin asynchronous wrapper around dbConnect("mysql", ...). Other resources
-- never open their own connection; they use the exported helpers below
-- (mysqlQuery / mysqlExec / mysqlEscape / mysqlIsConnected).
--
-- The raw dbQuery callback style is only fully supported for callers inside
-- this resource (accountdata.lua). Cross-resource callers should pass no
-- callback to mysqlExec, or use mysqlQuery and read the result element data.

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
