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
local flushRetryQueue   -- defined with the write helpers below
local verifyConnection  -- defined below

local function scheduleReconnect()
    if reconnectPending then return end
    reconnectPending = true
    setTimer(function()
        reconnectPending = false
        connectDatabase()
    end, MYSQL_RECONNECT_INTERVAL, 1)
end

-- Flips `connected` and fires mysql:connected / mysql:disconnected, but only
-- on an actual transition - callers can call this as often as they like
-- (every failed ping, every failed reconnect attempt) without spamming the
-- event or re-freezing players who are already frozen for it.
local function setConnected(newState)
    if newState == connected then return end
    connected = newState
    if newState then
        mysqlLog("Connected to %s@%s:%d/%s",
            MYSQL_CONFIG.username, MYSQL_CONFIG.host, MYSQL_CONFIG.port, MYSQL_CONFIG.database)
        triggerEvent("mysql:connected", resourceRoot)
    else
        mysqlLog("Connection lost/unavailable")
        triggerEvent("mysql:disconnected", resourceRoot)
    end
end

-- Verifies a fresh connection with a trivial query. dbConnect() returns an
-- element immediately even when the server is unreachable, so the real check
-- has to be a round trip.
verifyConnection = function()
    dbQuery(function(qh)
        local result = dbPoll(qh, 0)
        dbFree(qh)
        if type(result) == "table" then
            setConnected(true)
            flushRetryQueue()
        else
            setConnected(false)
            mysqlLog("Connection check failed, reconnecting in %ds", MYSQL_RECONNECT_INTERVAL / 1000)
            if isElement(connection) then destroyElement(connection) end
            connection = nil
            scheduleReconnect()
        end
    end, connection, "SELECT 1")
end

function connectDatabase()
    if isElement(connection) then destroyElement(connection) end
    setConnected(false)
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
    setConnected(false)
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

-- Non-blocking SELECT for OTHER resources (a callback function cannot cross an
-- export call). The answer is delivered as an event on the caller's resource
-- root:  triggerEvent(eventName, <caller resourceRoot>, requestId, result, info)
-- with result = rows table (info = numRows) or false (info = error text).
-- The caller must addEvent(eventName) itself. Without a connection the event
-- fires right away, before this returns.
function mysqlQueryAsync(eventName, requestId, queryStr, ...)
    local caller = sourceResource
    if type(eventName) ~= "string" or type(queryStr) ~= "string" or not caller then return false end
    local target = getResourceRootElement(caller)
    return mysqlQuery(function(result, info)
        if isElement(target) then triggerEvent(eventName, target, requestId, result, info) end
    end, queryStr, ...)
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
    -- dbPoll returns (result, numAffectedRows, lastInsertId) for a statement,
    -- so the id comes from the very same round trip - no second query that a
    -- reconnect in between could answer with 0 or someone else's id.
    local res, affected, lastId = dbPoll(qh, -1)
    dbFree(qh)
    if res == false then
        mysqlLog("Insert error: %s | SQL: %s", tostring(lastId or affected), queryStr)
        return false
    end
    lastId = tonumber(lastId)
    if lastId and lastId > 0 then return lastId end
    return true
end

--------------------------------------------------------------------------------
-- Writes (async, with retry queue)
--------------------------------------------------------------------------------

-- Writes that failed because the connection dropped wait here and are resent
-- once a ping succeeds again (BUG-02). Only connection errors are retried; an
-- SQL error (syntax, duplicate key, ...) is final.
local RETRY_QUEUE_MAX = 500
local RETRY_MAX_TRIES = 5
local retryQueue = {}

local function isConnectionError(err)
    err = tostring(err or ""):lower()
    return err:find("connect", 1, true) or err:find("gone away", 1, true)
        or err:find("timed out", 1, true) or err:find("broken pipe", 1, true) or false
end

local sendWrite

local function queueWrite(job)
    if #retryQueue >= RETRY_QUEUE_MAX or job.tries >= RETRY_MAX_TRIES then
        mysqlLog("Write dropped (retry queue full or too many tries) | SQL: %s", job.sql)
        if job.cb then job.cb(false, 0, "dropped") end
        return false
    end
    retryQueue[#retryQueue + 1] = job
    return true
end

sendWrite = function(job)
    job.tries = job.tries + 1
    local qh = dbQuery(function(qh)
        local res, affected, extra = dbPoll(qh, 0)
        dbFree(qh)
        if type(res) == "table" then
            if job.cb then job.cb(true, tonumber(affected) or 0, tonumber(extra) or 0) end
            return
        end
        local err = tostring(extra or affected)
        if isConnectionError(err) then
            mysqlLog("Write failed (%s), queued for retry | SQL: %s", err, job.sql)
            queueWrite(job)
            if isElement(connection) then verifyConnection() end
            return
        end
        mysqlLog("Write error: %s | SQL: %s", err, job.sql)
        if job.cb then job.cb(false, 0, err) end
    end, connection, job.sql, unpack(job.args, 1, job.n))
    if not qh then
        queueWrite(job)
    end
end

flushRetryQueue = function()
    if #retryQueue == 0 or not isElement(connection) then return end
    local jobs = retryQueue
    retryQueue = {}
    mysqlLog("Resending %d queued write(s)", #jobs)
    for _, job in ipairs(jobs) do sendWrite(job) end
end

-- INSERT / UPDATE / DELETE with a result: cb(ok, affectedRows, lastInsertId).
-- Unlike mysqlExec it never loses the write to an outage - with no connection
-- the statement is queued and resent after the reconnect. For use inside
-- v_mysql (a callback cannot cross an export call).
function mysqlExecCb(cb, queryStr, ...)
    local job = { sql = queryStr, args = { ... }, n = select("#", ...), cb = cb, tries = 0 }
    if not isElement(connection) then
        debugLog("mysqlExecCb queued (no connection): %s", queryStr)
        return queueWrite(job)
    end
    debugLog("exec(cb): %s", queryStr)
    sendWrite(job)
    return true
end

-- Runs an INSERT / UPDATE / DELETE. Fire and forget; returns whether the
-- statement was sent (false without a connection, so callers can report it).
-- If the connection breaks while it is in flight it is retried after reconnect.
-- Placeholders (?) are escaped from the varargs.
function mysqlExec(queryStr, ...)
    if not isElement(connection) then
        debugLog("mysqlExec skipped (no connection): %s", queryStr)
        return false
    end
    debugLog("exec: %s", queryStr)
    sendWrite({ sql = queryStr, args = { ... }, n = select("#", ...), tries = 0 })
    return true
end

-- Escapes/quotes a single value for manual query building. Prefer ? placeholders.
function mysqlEscape(value)
    if isElement(connection) then
        return dbPrepareString(connection, "?", tostring(value))
    end
    return "'" .. tostring(value):gsub("'", "''") .. "'"
end
