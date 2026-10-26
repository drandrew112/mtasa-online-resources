if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- One account, one server: the login asks the shared MySQL `online_players` table
-- whether the account is online on ANOTHER v_main server instance.
--
-- The table is kept by v_admin (server/instance.lua) on every instance: one row per
-- logged-in player, `seen` refreshed by a heartbeat. Rows of an instance that has
-- not refreshed for AUTH.ONLINE_STALE seconds belong to a crashed server and are
-- ignored, so a crash cannot lock an account out for longer than that.

local TABLE = AUTH.ONLINE_TABLE or "online_players"
local STALE = AUTH.ONLINE_STALE or 120

-- v_main instance id of this server (0 = v_main not running); pool.lua uses it too
function serverInstanceId()
    if not resourceRunning("v_main") then return 0 end
    local ok, id = pcall(function() return exports.v_main:getServerInstanceId() end)
    return ok and tonumber(id) or 0
end

--- cb(entry | false): entry = { server, serverName } when `account` is online on
--- another instance. A failed query (no table yet, DB hiccup) answers false: the
--- login must not depend on v_admin having created the table.
function onlineElsewhere(account, cb)
    if AUTH.ONLINE_CHECK == false or not resourceRunning("v_mysql") then return cb(false) end
    MYSQL.query(function(rows)
        local r = type(rows) == "table" and rows[1] or nil
        if rows == false then
            outputServerLog(("[acc_auth] online_players check failed for '%s', login allowed"):format(account))
        end
        if not r then return cb(false) end
        cb({ server = tonumber(r.server) or 0, serverName = r.server_name ~= "" and r.server_name or false })
    end, "SELECT server, server_name FROM `" .. TABLE .. "` WHERE account_name = ? AND server <> ? AND seen >= ? LIMIT 1",
        account, serverInstanceId(),getRealTime().timestamp - STALE)
end
