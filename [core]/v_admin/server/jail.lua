-- ============================================================
--  v_admin / server/jail.lua
--  Admin jail: lock in, release, escape check, time countdown.
--
--  Account data:  adminjail (bool), adminjail_remTime, adminjail_admin, adminjail_indok
--  Element data :  same keys + the client HUD draws from them
-- ============================================================

local J = ADMIN.jail

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
    local acc = getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return end

    if state then
        local veh = getPedOccupiedVehicle(player)
        if veh then
            setElementVelocity(veh, 0, 0, 0)
            removePedFromVehicle(player)
        end

        setAccountData(acc, "adminjail", true)
        setElementData(player, "adminjail", true)
        setElementInterior(player, J.interior)
        setElementPosition(player, J.inside.x, J.inside.y, J.inside.z)

        if minutes then
            setAccountData(acc, "adminjail_remTime", minutes)
            setElementData(player, "adminjail_remTime", minutes)
        end
    else
        for _, key in ipairs({ "adminjail", "adminjail_remTime", "adminjail_admin", "adminjail_indok" }) do
            setAccountData(acc, key, false)
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
    local acc = getPlayerAccount(source)
    if not acc or not getAccountData(acc, "adminjail") then return end

    setElementData(source, "adminjail", true)
    setElementData(source, "adminjail_remTime", tonumber(getAccountData(acc, "adminjail_remTime")) or 0)
    setElementData(source, "adminjail_admin", getAccountData(acc, "adminjail_admin") or "?")
    setElementData(source, "adminjail_indok", getAccountData(acc, "adminjail_indok") or "?")
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
        local acc = getPlayerAccount(player)
        if acc and getElementData(player, "adminjail") then
            local remaining = (tonumber(getAccountData(acc, "adminjail_remTime")) or 0) - 1
            if remaining <= 0 then
                setPlayerInAJ(player, false)
                adminAlert(player, "Your admin jail time is up, you have been released.", 85, 255, 85)
            else
                setAccountData(acc, "adminjail_remTime", remaining)
                setElementData(player, "adminjail_remTime", remaining)
            end
        end
    end
end, 60000, 0)

-- ------------------------------------------------------------
--  /ajail <ID> <minutes> <reason...>
-- ------------------------------------------------------------
addCommandHandler("ajail", function(player, cmd, idArg, minutesArg, ...)
    if not hasAdminLevel(player, ADMIN.perms.jail) then
        return denyAccess(player, ADMIN.perms.jail)
    end

    local minutes = tonumber(minutesArg)
    local reason  = table.concat({ ... }, " ")
    if not idArg or not minutes or reason == "" then
        return adminAlert(player, "Usage: /ajail <ID> <minutes> <reason>", 255, 90, 90)
    end
    minutes = math.max(1, math.floor(minutes))

    local target = resolveTarget(player, idArg)
    if not target then return end

    local acc = getPlayerAccount(target)
    if not acc or isGuestAccount(acc) then
        return adminAlert(player, "That player is not logged in.", 255, 90, 90)
    end

    local adminName = getPlayerName(player)
    setPlayerInAJ(target, true, minutes)

    setAccountData(acc, "adminjail_admin", adminName)
    setAccountData(acc, "adminjail_indok", reason)
    setElementData(target, "adminjail_admin", adminName)
    setElementData(target, "adminjail_indok", reason)

    adminAlert(target, ("#FFFFFFJailed by #FFFF00%s #FFFFFF(%d min) for #FFFFFF%s")
        :format(adminName, minutes, reason), 255, 90, 90, 8000)
    adminAlert(player, ("#FFFFFFYou jailed #FFFF00%s #FFFFFF(%d min) for #FFFFFF%s")
        :format(getPlayerName(target), minutes, reason))
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

    if not getElementData(target, "adminjail") then
        return adminAlert(player, "That player is not in admin jail.", 255, 90, 90)
    end

    setPlayerInAJ(target, false)
    adminAlert(target, "#FFFFFFReleased from admin jail by #FFFF00" .. getPlayerName(player) .. "#FFFFFF.", 85, 255, 85)
    adminAlert(player, "#FFFFFFYou released #FFFF00" .. getPlayerName(target) .. " #FFFFFFfrom admin jail.")
end)
