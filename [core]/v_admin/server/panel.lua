if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/panel.lua
--  Admin panel (O key) – server side.
--
--  * panelRequest (client -> server): open / refresh. The server
--    answers with every online player's data + the caller's level.
--    Data is never hidden from an admin who can open the panel.
--  * panelAction (client -> server): runs the SAME functions as the
--    commands (adminMute, adminKick, adminBan, ...), so the level
--    checks of ADMIN.perms apply here too.
-- ============================================================

local E = ADMIN.events

local ACCOUNT_CACHE_MS = 60000
local accountCache = {}     -- [lower account name] = { tick, row }
local lastRequest  = {}     -- [admin] = tick (flood guard)

local function stripColors(text)
    return (tostring(text or ""):gsub("#%x%x%x%x%x%x", ""))
end

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- { id, email, created_at } of an account row (cached), or false.
local function getAccountRow(accName)
    local key = accName:lower()
    local cached = accountCache[key]
    if cached and getTickCount() - cached.tick < ACCOUNT_CACHE_MS then
        return cached.row
    end

    local row = false
    if resourceRunning("v_mysql") then
        local ok, res = pcall(function()
            return exports.v_mysql:mysqlQuerySync(
                "SELECT id, email, created_at FROM `accounts` WHERE account_name = ? LIMIT 1", accName)
        end)
        if ok and type(res) == "table" and res[1] then
            row = { id = tonumber(res[1].id), email = res[1].email, created = tonumber(res[1].created_at) }
        end
    end
    accountCache[key] = { tick = getTickCount(), row = row }
    return row
end

local function getWorkName(player)
    if not resourceRunning("work_core") then return false end
    local ok, work = pcall(function() return exports.work_core:getPlayerWork(player) end)
    return ok and work or false
end

local function collectPlayer(player)
    local now = getRealTime().timestamp
    local x, y, z = getElementPosition(player)
    local veh = getPedOccupiedVehicle(player)
    local accName = exports.acc_auth:getName(player)
    local level = getAdminLevel(player)

    local muteUntil = tonumber(getElementData(player, "mute_until"))
    local muteLeft = muteUntil and math.max(0, muteUntil - now) or 0

    local d = {
        id        = tonumber(getElementData(player, "ID")) or 0,
        name      = stripColors(getPlayerName(player)),
        -- account
        logged    = accName and true or false,
        account   = accName or false,
        adminLevel = level,
        rank      = ADMIN.rankNames[level] or L.msg("v_admin.config.player"),
        -- connection
        serial    = getPlayerSerial(player),
        ip        = getPlayerIP(player),
        ping      = getPlayerPing(player),
        version   = getPlayerVersion(player),
        -- character
        health    = math.floor(getElementHealth(player)),
        armor     = math.floor(getPedArmor(player)),
        dead      = isPedDead(player),
        skin      = getElementModel(player),
        cash      = getPlayerMoney(player),
        bank      = tonumber(getElementData(player, "bank_money")) or false,
        level     = tonumber(getElementData(player, "level")) or false,
        xp        = tonumber(getElementData(player, "xp")) or false,
        playtime  = getElementData(player, "Játékidő") or false,
        work      = getWorkName(player),
        -- location
        pos       = { math.floor(x * 10) / 10, math.floor(y * 10) / 10, math.floor(z * 10) / 10 },
        zone      = getZoneName(x, y, z) .. ", " .. getZoneName(x, y, z, true),
        interior  = getElementInterior(player),
        dimension = getElementDimension(player),
        vehicle   = veh and getVehicleName(veh) or false,
        vehicleHp = veh and math.floor(getElementHealth(veh)) or false,
        -- sanctions
        muted      = muteLeft > 0,
        muteLeft   = muteLeft,
        muteReason = getElementData(player, "mute_reason") or false,
        muteAdmin  = getElementData(player, "mute_admin") or false,
        jailed     = getElementData(player, "adminjail") and true or false,
        jailLeft   = tonumber(getElementData(player, "adminjail_remTime")) or 0,
        jailReason = getElementData(player, "adminjail_indok") or false,
        jailAdmin  = getElementData(player, "adminjail_admin") or false,
        banned     = getElementData(player, "banned") == true,
        banAccount = getElementData(player, "banned_account") or false,
        banReason  = getElementData(player, "banned_reason") or false,
        banAdmin   = getElementData(player, "banned_admin") or false,
        banDate    = getElementData(player, "banned_date") or false,
    }

    if accName then
        local row = getAccountRow(accName)
        if row then
            d.accountId = row.id
            d.email     = row.email or false
            d.created   = row.created or false
        end
    end
    return d
end

--- Data of every online player (panel + web panel). Texts are resolved to English when
--- `english` is set (the web page cannot resolve message objects).
function adminPlayerList(english)
    local list = {}
    for _, player in ipairs(getElementsByType("player")) do
        local d = collectPlayer(player)
        if english then d.rank = L.resolveFor("en", d.rank) end
        list[#list + 1] = d
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function sendPanel(admin, isRefresh, tab, arg)
    if not isElement(admin) then return end
    if not hasAdminLevel(admin, ADMIN.perms.panel) then
        triggerClientEvent(admin, E.panelData, resourceRoot, false)
        return
    end

    local list = adminPlayerList()

    triggerClientEvent(admin, E.panelData, resourceRoot, list, getAdminLevel(admin), isRefresh and true or false, tab or false, arg)
end

--- Open the panel for an admin on a given page (/reports, /weekly, /news, /mail).
--- arg goes to the page (e.g. an account name for "accounts").
function openAdminPanel(admin, tab, arg)
    if not hasAdminLevel(admin, ADMIN.perms.panel) then
        return denyAccess(admin, ADMIN.perms.panel)
    end
    sendPanel(admin, false, tab, arg)
end

addEvent(E.panelRequest, true)
addEventHandler(E.panelRequest, resourceRoot, function(isRefresh)
    if not client then return end
    local now = getTickCount()
    if lastRequest[client] and now - lastRequest[client] < 500 then return end
    lastRequest[client] = now

    if not hasAdminLevel(client, ADMIN.perms.panel) then
        if not isRefresh then denyAccess(client, ADMIN.perms.panel) end
        triggerClientEvent(client, E.panelData, resourceRoot, false)
        return
    end
    sendPanel(client, isRefresh)
end)

-- ------------------------------------------------------------
--  Actions
-- ------------------------------------------------------------

local function text(v)
    v = type(v) == "string" and v:gsub("^%s+", ""):gsub("%s+$", "") or ""
    return v ~= "" and v or nil
end

-- action = function(admin, target, a, b)
local ACTIONS = {
    ["goto"]    = function(admin, t)       adminGoto(admin, t) end,
    ["gethere"] = function(admin, t)       adminGethere(admin, t) end,
    ["heal"]    = function(admin, t)       adminHeal(admin, t) end,
    ["spectate"] = function(admin, t)      adminSpectate(admin, t) end,
    ["skin"]    = function(admin, t, a)    adminSetSkin(admin, t, a) end,
    ["mute"]    = function(admin, t, a, b) adminMute(admin, t, a, text(b)) end,
    ["unmute"]  = function(admin, t)       adminUnmute(admin, t) end,
    ["fixveh"]  = function(admin, t)       adminFixVeh(admin, t) end,
    ["flipveh"] = function(admin, t)       adminFlipVeh(admin, t) end,
    ["getout"]  = function(admin, t)       adminGetOut(admin, t) end,
    ["jail"]    = function(admin, t, a, b) adminJail(admin, t, a, text(b)) end,
    ["unjail"]  = function(admin, t)       adminUnjail(admin, t) end,
    ["kick"]    = function(admin, t, a)    adminKick(admin, t, text(a)) end,
    ["ban"]     = function(admin, t, a)
        local accName = exports.acc_auth:getName(t)
        if not accName then
            return adminAlert(admin, L.msg("v_admin.panel.that_player_is_not_logged_in"), 255, 90, 90)
        end
        adminBan(admin, accName, text(a))
    end,
    ["unban"]   = function(admin, t)
        local accName = getElementData(t, "banned_account") or exports.acc_auth:getName(t)
        if not accName then
            return adminAlert(admin, L.msg("v_admin.panel.no_banned_account_on_that_player"), 255, 90, 90)
        end
        adminUnban(admin, accName)
    end,
    ["setlevel"] = function(admin, t, a)   adminSetLevel(admin, t, a) end,
}

-- Actions without a target player.
local GLOBAL_ACTIONS = {
    ["unbanAccount"] = function(admin, a) adminUnban(admin, text(a)) end,
    ["announce"]     = function(admin, a) adminAnnounce(admin, text(a)) end,
    ["specoff"]      = function(admin) adminSpectateStop(admin) end,
}

--- Run a panel action for an admin (player element or web actor). Returns false for an
--- unknown action. Level checks happen inside the admin* functions.
function adminRunAction(admin, action, targetId, a, b)
    if GLOBAL_ACTIONS[action] then
        GLOBAL_ACTIONS[action](admin, a)
    elseif ACTIONS[action] then
        local target = getPlayerFromId(targetId)
        if not target then
            adminAlert(admin, L.msg("v_admin.panel.that_player_is_no_longer_online"), 255, 90, 90)
        else
            ACTIONS[action](admin, target, a, b)
        end
    else
        return false
    end
    return true
end

addEvent(E.panelAction, true)
addEventHandler(E.panelAction, resourceRoot, function(action, targetId, a, b)
    if not client then return end
    if not hasAdminLevel(client, ADMIN.perms.panel) then
        return denyAccess(client, ADMIN.perms.panel)
    end

    local admin = client
    if not adminRunAction(admin, action, targetId, a, b) then return end

    -- Fresh data right away (kick removes the player a frame later).
    setTimer(sendPanel, 200, 1, admin, true)
end)

addEventHandler("onPlayerQuit", root, function()
    lastRequest[source] = nil
end)
