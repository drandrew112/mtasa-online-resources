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
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    if not isLogged(source) or not getData(source, "adminjail") then return end

    setElementData(source, "adminjail", true)
    setElementData(source, "adminjail_remTime", tonumber(getData(source, "adminjail_remTime")) or 0)
    setElementData(source, "adminjail_admin", getData(source, "adminjail_admin") or "?")
    setElementData(source, "adminjail_indok", getData(source, "adminjail_indok") or "?")
    setElementInterior(source, J.interior)
    setElementPosition(source, J.inside.x, J.inside.y, J.inside.z)
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
    adminLog(player, ("jailed %s for %d min (%s)"):format(getPlayerName(target), minutes, reason))
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
    adminLog(player, "released " .. getPlayerName(target) .. " from admin jail")
end

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
