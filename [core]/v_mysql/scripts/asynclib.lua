-- v_mysql :: async lib for other resources (PERF-01)
--
-- A callback cannot cross an export call, so the non-blocking exports answer
-- with an event on the caller's resource root. This lib hides that: a resource
-- loads it once (server side) and gets callback-style helpers.
--
--   if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
--   (the resource needs <include resource="v_mysql" /> in its meta.xml)
--
--   MYSQL.query(cb, sql, ...)      cb(rows, numRows)  | cb(false, err)
--   MYSQL.insert(cb, sql, ...)     cb(id, nil)        | cb(false, err)   (id = true without AUTO_INCREMENT)
--   MYSQL.prefetch(cb, names)      cb(true)           | cb(false, err)
--       loads the account data of offline accounts in one query, so the
--       getAccData calls right after it do not block (see accdata.lua)
--
-- Every callback runs exactly once: with the answer, or with (false, err) when
-- v_mysql is not running, stops meanwhile, or does not answer in TIMEOUT ms.
-- `client` / `source` of the event that started the query are NOT valid in the
-- callback: keep what you need in locals, and re-check isElement(player).

ASYNC_LIB_SOURCE = [==[
MYSQL = {}
do
    local EVENT   = "v_mysql:async:" .. getResourceName(getThisResource())
    local TIMEOUT = 15000
    local pending, seq = {}, 0

    addEvent(EVENT, false)

    local function settle(id, a, b)
        local p = pending[id]
        if not p then return end
        pending[id] = nil
        if isTimer(p.timer) then killTimer(p.timer) end
        p.cb(a, b)
    end

    addEventHandler(EVENT, resourceRoot, function(id, a, b) settle(id, a, b) end, false)

    addEventHandler("onResourceStop", root, function(res)
        if getResourceName(res) ~= "v_mysql" then return end
        local ids = {}
        for id in pairs(pending) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do settle(id, false, "v_mysql stopped") end
    end)

    local function running()
        local r = getResourceFromName("v_mysql")
        return r and getResourceState(r) == "running"
    end

    local function send(fn, cb, ...)
        seq = seq + 1
        local id = seq
        pending[id] = { cb = cb or function() end }
        pending[id].timer = setTimer(settle, TIMEOUT, 1, id, false, "timeout")
        local sent = false
        if running() then
            local ex = exports.v_mysql
            sent = ex[fn](ex, EVENT, id, ...)
        end
        -- without a connection the answer event already ran (settle is a no-op then)
        if sent ~= true then settle(id, false, "not sent") end
        return id
    end

    function MYSQL.query(cb, sql, ...)  return send("mysqlQueryAsync", cb, sql, ...) end
    function MYSQL.insert(cb, sql, ...) return send("mysqlInsertAsync", cb, sql, ...) end
    function MYSQL.prefetch(cb, names)  return send("prefetchAccDataAsync", cb, names) end
end
]==]

-- exported: the lib source, run by the caller with loadstring(...)()
function importAsync()
    return ASYNC_LIB_SOURCE
end
