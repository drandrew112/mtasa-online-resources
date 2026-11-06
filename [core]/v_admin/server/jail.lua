if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/jail.lua
--  Admin jail: lock in, release, escape check, time countdown.
--
--  Account data:  adminjail (bool), adminjail_remTime, adminjail_admin, adminjail_indok
--                 in the shared `accounts` table (exports.v_mysql:getAccData /
--                 setAccData, keyed by player element)
--  Element data :  same keys + the client HUD draws from them
-- ============================================================

local J = ADMIN.jail

local function getData(player, key) return exports.v_mysql:getAccData(player, key) end
local function setData(player, key, value) return exports.v_mysql:setAccData(player, key, value) end
local function isLogged(player) return exports.v_accounts:isLoggedIn(player) end

local ajCol = createColCuboid(
    J.colOrigin.x, J.colOrigin.y, J.colOrigin.z,
    J.colSize, J.colSize, J.colSize
)
setElementInterior(ajCol, J.interior)

-- ------------------------------------------------------------
--  Set jail state (lock in / release)
-- ------------------------------------------------------------
function setPlayerInAJ(player, state, minutes)
    if not isElement(player) then return end
    if not isLogged(player) then return end

    if state then
        local veh = getPedOccupiedVehicle(player)
        if veh then
            setElementVelocity(veh, 0, 0, 0)
            removePedFromVehicle(player)
        end

        setData(player, "adminjail", true)
        setElementData(player, "adminjail", true)
        setElementInterior(player, J.interior)
        setElementPosition(player, J.inside.x, J.inside.y, J.inside.z)

        if minutes then
            setData(player, "adminjail_remTime", minutes)
            setElementData(player, "adminjail_remTime", minutes)
        end
    else
        for _, key in ipairs({ "adminjail", "adminjail_remTime", "adminjail_admin", "adminjail_indok" }) do
            setData(player, key, false)
            setElementData(player, key, false)
        end
        setElementInterior(player, 0)
        setElementPosition(player, J.release.x, J.release.y, J.release.z)
    end
end

-- ------------------------------------------------------------
--  Restore jail state once the player is fully loaded
--  (onPlayerLoaded fires after the shared MySQL account-data sync)
-- ------------------------------------------------------------
-- onPlayerLoaded comes after the loading screen and the v_mapcam spawn camera
-- (v_loading flow.lua), so a jail given while offline starts right there.
-- adminjail_offline = jailed while offline (tell them once)
-- adminjail_release = released while offline (the saved position is still the cell)
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    if not isLogged(source) then return end
    if not getData(source, "adminjail") then
        if getData(source, "adminjail_release") then
            setData(source, "adminjail_release", false)
            if getElementInterior(source) == J.interior then
                setElementInterior(source, 0)
                setElementPosition(source, J.release.x, J.release.y, J.release.z)
            end
        end
        return
    end

    local remTime = tonumber(getData(source, "adminjail_remTime")) or 0
    local admin, reason = getData(source, "adminjail_admin") or "?", getData(source, "adminjail_indok") or "?"
    setElementData(source, "adminjail", true)
    setElementData(source, "adminjail_remTime", remTime)
    setElementData(source, "adminjail_admin", admin)
    setElementData(source, "adminjail_indok", reason)
    local veh = getPedOccupiedVehicle(source)
    if veh then removePedFromVehicle(source) end
    setElementInterior(source, J.interior)
    setElementPosition(source, J.inside.x, J.inside.y, J.inside.z)

    if getData(source, "adminjail_offline") then
        setData(source, "adminjail_offline", false)
        adminAlert(source, L.msg("v_admin.jail.jailed_by_min_for", { admin_name = admin, minutes = remTime, reason = reason }), 255, 90, 90, 8000)
    end
end)

-- ------------------------------------------------------------
--  Escape check (1 s)
-- ------------------------------------------------------------
setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, "adminjail") then
            if not isElementWithinColShape(player, ajCol) then
                local veh = getPedOccupiedVehicle(player)
                if veh then
                    setElementVelocity(veh, 0, 0, 0)
                    removePedFromVehicle(player)
                end
                setElementInterior(player, J.interior)
                setElementPosition(player, J.inside.x, J.inside.y, J.inside.z)
            end
        end
    end
end, 1000, 0)

-- ------------------------------------------------------------
--  Time countdown (1 min)
-- ------------------------------------------------------------
setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do
        if isLogged(player) and getElementData(player, "adminjail") then
            local remaining = (tonumber(getData(player, "adminjail_remTime")) or 0) - 1
            if remaining <= 0 then
                setPlayerInAJ(player, false)
                adminAlert(player, L.msg("v_admin.jail.your_admin_jail_time_is_up"), 85, 255, 85)
            else
                setData(player, "adminjail_remTime", remaining)
                setElementData(player, "adminjail_remTime", remaining)
            end
        end
    end
end, 60000, 0)

-- ------------------------------------------------------------
--  adminJail / adminUnjail  (shared with the admin panel)
-- ------------------------------------------------------------
function adminJail(player, target, minutes, reason)
    if not hasAdminLevel(player, ADMIN.perms.jail) then
        return denyAccess(player, ADMIN.perms.jail)
    end
    minutes = tonumber(minutes)
    if not isElement(target) or not minutes or type(reason) ~= "string" or reason == "" then
        return adminAlert(player, L.msg("v_admin.jail.usage_ajail_id_minutes_reason"), 255, 90, 90)
    end
    minutes = math.max(1, math.floor(minutes))

    if not isLogged(target) then
        return adminAlert(player, L.msg("v_admin.admin_manage.that_player_is_not_logged_in"), 255, 90, 90)
    end
    if not canPunish(player, target) then return end

    local adminName = actorName(player)
    setPlayerInAJ(target, true, minutes)

    setData(target, "adminjail_admin", adminName)
    setData(target, "adminjail_indok", reason)
    setElementData(target, "adminjail_admin", adminName)
    setElementData(target, "adminjail_indok", reason)

    adminAlert(target, L.msg("v_admin.jail.jailed_by_min_for", { admin_name = adminName, minutes = minutes, reason = reason }), 255, 90, 90, 8000)
    adminAlert(player, L.msg("v_admin.jail.you_jailed_min_for", { player = getPlayerName(target), minutes = minutes, reason = reason }))
    adminLog(player, ("jailed %s for %d min (%s)"):format(getPlayerName(target), minutes, reason), target)
end

function adminUnjail(player, target)
    if not hasAdminLevel(player, ADMIN.perms.jail) then
        return denyAccess(player, ADMIN.perms.jail)
    end
    if not isElement(target) then return end

    if not getElementData(target, "adminjail") then
        return adminAlert(player, L.msg("v_admin.jail.that_player_is_not_in_admin"), 255, 90, 90)
    end

    setPlayerInAJ(target, false)
    adminAlert(target, L.msg("v_admin.jail.released_from_admin_jail_by", { player = actorName(player) }), 85, 255, 85)
    adminAlert(player, L.msg("v_admin.jail.you_released_from_admin_jail", { player = getPlayerName(target) }))
    adminLog(player, "released " .. getPlayerName(target) .. " from admin jail", target)
end

-- ------------------------------------------------------------
--  By account name: online here -> adminJail / adminUnjail, offline -> account
--  data (applied on the next onPlayerLoaded). Online on another instance:
--  refused (that instance keeps the account data in memory and would save over it).
--  Returns true, or false + message object (also sent to the actor).
-- ------------------------------------------------------------
local function playerOnAccount(accName)
    if not resourceRunning("v_accounts") then return nil end
    local needle = tostring(accName):lower()
    for _, p in ipairs(getElementsByType("player")) do
        local n = exports.v_accounts:getName(p)
        if n and n:lower() == needle then return p end
    end
end

local function offlineCheck(actor, accName)
    if type(accName) ~= "string" or accName == "" then
        return false, L.msg("v_admin.page.no_such_account")
    end
    local remote = INSTANCE and INSTANCE.remoteOnline(accName)
    if remote then
        return false, L.msg("v_admin.jail.online_on_other_server", { server = remote.server, id = remote.id })
    end
    local rows = exports.v_mysql:mysqlQuerySync("SELECT account_name FROM `accounts` WHERE account_name = ? LIMIT 1", accName)
    if not rows or not rows[1] then return false, L.msg("v_admin.page.no_such_account") end
    local realName = rows[1].account_name
    local myLevel = getAdminLevel(actor)
    if myLevel < ADMIN.maxLevel and (tonumber(exports.v_mysql:getAccData(realName, "admin_level")) or 0) >= myLevel then
        return false, L.msg("v_admin.core.you_can_t_do_that_to")
    end
    return realName
end

local function failMsg(actor, msg)
    adminAlert(actor, msg, 255, 90, 90)
    return false, msg
end

function adminJailAccount(actor, accName, minutes, reason)
    if not hasAdminLevel(actor, ADMIN.perms.jail) then
        return false, denyAccess(actor, ADMIN.perms.jail)
    end
    minutes = tonumber(minutes)
    if not minutes or type(reason) ~= "string" or reason == "" then
        return failMsg(actor, L.msg("v_admin.jail.usage_oajail"))
    end
    minutes = math.max(1, math.floor(minutes))

    local player = playerOnAccount(accName)
    if player and getElementData(player, "loaded") == true then
        adminJail(actor, player, minutes, reason)
        return true
    end

    -- offline, or logged in but still in the main menu / loading: account data
    -- only, the jail starts on onPlayerLoaded
    local name, err
    if player then
        if not canPunish(actor, player) then return false end
        name = exports.v_accounts:getName(player)
    else
        name, err = offlineCheck(actor, accName)
        if not name then return failMsg(actor, err) end
    end
    local key = player or name

    local adminName = actorName(actor)
    local ok = exports.v_mysql:setAccData(key, "adminjail", true)
    if not ok then return failMsg(actor, L.msg("v_admin.page.save_failed")) end
    exports.v_mysql:setAccData(key, "adminjail_remTime", minutes)
    exports.v_mysql:setAccData(key, "adminjail_admin", adminName)
    exports.v_mysql:setAccData(key, "adminjail_indok", reason)
    exports.v_mysql:setAccData(key, "adminjail_offline", true)
    exports.v_mysql:setAccData(key, "adminjail_release", false)

    adminAlert(actor, L.msg("v_admin.jail.you_jailed_offline", { player = name, minutes = minutes, reason = reason }))
    adminLog(actor, ("jailed offline account %s for %d min (%s)"):format(name, minutes, reason), name)
    return true
end

function adminUnjailAccount(actor, accName)
    if not hasAdminLevel(actor, ADMIN.perms.jail) then
        return false, denyAccess(actor, ADMIN.perms.jail)
    end
    local player = playerOnAccount(accName)
    if player and getElementData(player, "loaded") == true then
        if not getElementData(player, "adminjail") then
            return failMsg(actor, L.msg("v_admin.jail.that_player_is_not_in_admin"))
        end
        adminUnjail(actor, player)
        return true
    end

    local name
    if player then
        name = exports.v_accounts:getName(player)
    else
        if type(accName) ~= "string" or accName == "" then return failMsg(actor, L.msg("v_admin.page.no_such_account")) end
        local remote = INSTANCE and INSTANCE.remoteOnline(accName)
        if remote then
            return failMsg(actor, L.msg("v_admin.jail.online_on_other_server", { server = remote.server, id = remote.id }))
        end
        local rows = exports.v_mysql:mysqlQuerySync("SELECT account_name FROM `accounts` WHERE account_name = ? LIMIT 1", accName)
        if not rows or not rows[1] then return failMsg(actor, L.msg("v_admin.page.no_such_account")) end
        name = rows[1].account_name
    end
    local target = player or name
    if not exports.v_mysql:getAccData(target, "adminjail") then
        return failMsg(actor, L.msg("v_admin.jail.that_player_is_not_in_admin"))
    end

    for _, key in ipairs({ "adminjail", "adminjail_remTime", "adminjail_admin", "adminjail_indok", "adminjail_offline" }) do
        exports.v_mysql:setAccData(target, key, false)
    end
    exports.v_mysql:setAccData(target, "adminjail_release", true)

    adminAlert(actor, L.msg("v_admin.jail.you_released_from_admin_jail", { player = name }))
    adminLog(actor, "released " .. name .. " from admin jail", name)
    return true
end

-- ------------------------------------------------------------
--  /oajail <account> <minutes> <reason...>   (offline or online)
--  /oajailout <account>
-- ------------------------------------------------------------
addCommandHandler("oajail", function(player, cmd, accName, minutesArg, ...)
    adminJailAccount(player, accName, minutesArg, table.concat({ ... }, " "))
end)

addCommandHandler("oajailout", function(player, cmd, accName)
    adminUnjailAccount(player, accName)
end)

-- ------------------------------------------------------------
--  /ajail <ID> <minutes> <reason...>
-- ------------------------------------------------------------
addCommandHandler("ajail", function(player, cmd, idArg, minutesArg, ...)
    if not hasAdminLevel(player, ADMIN.perms.jail) then
        return denyAccess(player, ADMIN.perms.jail)
    end

    local reason = table.concat({ ... }, " ")
    if not idArg or not tonumber(minutesArg) or reason == "" then
        return adminAlert(player, L.msg("v_admin.jail.usage_ajail_id_minutes_reason"), 255, 90, 90)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    adminJail(player, target, minutesArg, reason)
end)

-- ------------------------------------------------------------
--  /ajailout <ID>
-- ------------------------------------------------------------
addCommandHandler("ajailout", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.jail) then
        return denyAccess(player, ADMIN.perms.jail)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    adminUnjail(player, target)
end)

-- chat command database (v_chat)
CMD.register("ajail", "<id> <minutes> [reason]", ADMIN.perms.jail, "Put a player in admin jail")
CMD.register("ajailout", "<id>", ADMIN.perms.jail, "Release a player from admin jail")
CMD.register("oajail", "<account> <minutes> [reason]", ADMIN.perms.jail, "Admin jail an account (also offline)")
CMD.register("oajailout", "<account>", ADMIN.perms.jail, "Release an account from admin jail (also offline)")
