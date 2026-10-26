if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- ============================================================
--  v_admin / server/instance.lua
--  This server instance (v_main server.json) + who is online on EVERY instance.
--  Each instance keeps its own logged-in players in the shared MySQL table
--  ADMIN.instances.table (one row per player, seen = heartbeat) and reads
--  everyone else's rows into a cache, so the Accounts page can show
--  "online on #2" for a player of another instance.
--    server, server_name, account_name, player_id, since, seen
-- ============================================================

INSTANCE = {}

local CFG = ADMIN.instances
local TABLE = CFG.table
local ready = false
local remote = {}    -- account_name:lower() -> { server, serverName, id } of the OTHER instances
local mine = {}      -- player -> account name written for it (v_accounts may forget it before onPlayerQuit)

local function now() return getRealTime().timestamp end

local function vmain(fn, fallback)
    if not resourceRunning("v_main") then return fallback end
    local ok, v = pcall(function() return exports.v_main[fn](exports.v_main) end)
    return ok and v ~= nil and v or fallback
end

--- v_main instance id of this server (0 = v_main not running).
function INSTANCE.id() return tonumber(vmain("getServerInstanceId", 0)) or 0 end

--- v_main instance name of this server (false = v_main not running).
function INSTANCE.name() return vmain("getServerInstanceName", false) end

--- { server, serverName, id } when the account is online on another instance, else nil.
function INSTANCE.remoteOnline(account)
    return account and remote[tostring(account):lower()] or nil
end

--- The whole remote cache (account_name:lower() -> entry).
function INSTANCE.remoteList() return remote end

local function ensure()
    if ready then return true end
    if not resourceRunning("v_mysql") or exports.v_mysql:mysqlIsConnected() ~= true then return false end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. TABLE .. [[` (
        `server`       INT          NOT NULL DEFAULT 0,
        `server_name`  VARCHAR(96)  NOT NULL DEFAULT '',
        `account_name` VARCHAR(64)  NOT NULL,
        `player_id`    INT          NOT NULL DEFAULT 0,
        `since`        INT          NOT NULL DEFAULT 0,
        `seen`         INT          NOT NULL DEFAULT 0,
        PRIMARY KEY (`server`, `account_name`),
        KEY `idx_seen` (`seen`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    ready = true
    return true
end

local function accountOf(player)
    return resourceRunning("v_accounts") and exports.v_accounts:getName(player) or nil
end

local function put(player, account)
    if not ensure() or not account then return end
    mine[player] = account
    MYSQL.query(nil, "REPLACE INTO `" .. TABLE .. "` (server, server_name, account_name, player_id, since, seen) VALUES (?,?,?,?,?,?)",
        INSTANCE.id(), tostring(INSTANCE.name() or ""), account, tonumber(getElementData(player, "ID")) or 0, now(), now())
end

--- Rewrite this instance's rows from the players logged in right now.
local function resync()
    if not ensure() then return end
    MYSQL.query(function()
        for _, p in ipairs(getElementsByType("player")) do put(p, accountOf(p)) end
    end, "DELETE FROM `" .. TABLE .. "` WHERE server = ?", INSTANCE.id())
end

--- Heartbeat of this instance + re-read the other instances' rows.
local function tick()
    if not ensure() then return end
    local id = INSTANCE.id()
    MYSQL.query(nil, "UPDATE `" .. TABLE .. "` SET seen = ?, server_name = ? WHERE server = ?", now(), tostring(INSTANCE.name() or ""), id)
    MYSQL.query(function(rows)
        if not rows then return end
        local list = {}
        for _, r in ipairs(rows) do
            if type(r.account_name) == "string" then
                list[r.account_name:lower()] = { server = tonumber(r.server) or 0, serverName = r.server_name ~= "" and r.server_name or false,
                                                 id = tonumber(r.player_id) or 0 }
            end
        end
        remote = list
    end, "SELECT server, server_name, account_name, player_id FROM `" .. TABLE .. "` WHERE server <> ? AND seen >= ?",
        id, now() - CFG.staleAfter)
end

addEvent("onPlayerAccountLogin")
addEventHandler("onPlayerAccountLogin", root, function(account) put(source, account) end)

addEventHandler("onPlayerQuit", root, function()
    local account = mine[source] or accountOf(source)
    mine[source] = nil
    if account and ensure() then
        MYSQL.query(nil, "DELETE FROM `" .. TABLE .. "` WHERE server = ? AND account_name = ?", INSTANCE.id(), account)
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    resync()
    tick()
    setTimer(tick, CFG.heartbeat * 1000, 0)
end)

addEvent("mysql:connected")
addEventHandler("mysql:connected", root, function() resync(); tick() end)

-- v_admin stopped (not the whole server): its players are no longer tracked from here
addEventHandler("onResourceStop", resourceRoot, function()
    if ready and resourceRunning("v_mysql") then
        exports.v_mysql:mysqlExec("DELETE FROM `" .. TABLE .. "` WHERE server = ?", INSTANCE.id())
    end
end)
