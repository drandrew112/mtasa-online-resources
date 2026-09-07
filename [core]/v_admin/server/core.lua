-- ============================================================
--  v_admin / server/core.lua
--  Loads/syncs admin data + shared helper functions.
--  Every other server-side file builds on these.
-- ============================================================

-- ------------------------------------------------------------
--  Message to a player (ui_core Alert, because chat is disabled)
--  exports.ui_core:setAlert(text [, r, g, b, duration])
-- ------------------------------------------------------------

--- Send an alert to a player / table / the root element.
--- Colour/duration are optional (a #RRGGBB code may be used in the text).
function adminAlert(target, text, r, g, b, duration)
    triggerClientEvent(target or root, ADMIN.events.alert, resourceRoot, tostring(text), r, g, b, duration)
end

--- Alert to every player.
function adminBroadcast(text, r, g, b, duration)
    triggerClientEvent(root, ADMIN.events.alert, resourceRoot, tostring(text), r, g, b, duration)
end

--- Backwards-compatible alias.
adminInfo = adminAlert

--- Uniform "no permission" alert.
function denyAccess(player, minLevel)
    if minLevel then
        adminAlert(player, "You need at least admin level " .. minLevel .. " for this.", 255, 90, 90)
    else
        adminAlert(player, "You don't have permission for this.", 255, 90, 90)
    end
end

-- ------------------------------------------------------------
--  Admin data getters
-- ------------------------------------------------------------

--- The player's admin level as a number (guest / unknown = 0).
function getAdminLevel(player)
    if not isElement(player) or getElementType(player) ~= "player" then return 0 end
    local acc = getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return 0 end
    return tonumber(getAccountData(acc, "admin_level")) or 0
end

--- Whether the player has at least `minLevel` admin level.
function hasAdminLevel(player, minLevel)
    return getAdminLevel(player) >= (tonumber(minLevel) or 0)
end

--- Coloured admin label based on the level, e.g. "[MOD]".
function getAdminTag(player)
    return ADMIN.titles[getAdminLevel(player)] or "#FFFF00Admin"
end

-- ------------------------------------------------------------
--  Resolving a target player by server-side ID
-- ------------------------------------------------------------

--- Find a player by ID. Returns: player element or false.
function getPlayerFromId(id)
    id = tonumber(id)
    if not id then return false end
    for _, player in ipairs(getElementsByType("player")) do
        if tonumber(getElementData(player, "ID")) == id then
            return player
        end
    end
    return false
end

--- Resolve a target from a command argument; also prints an error.
function resolveTarget(player, idArg)
    local target = getPlayerFromId(idArg)
    if not target then
        adminAlert(player, "Player not found (valid ID required).", 255, 90, 90)
        return false
    end
    return target
end

-- ------------------------------------------------------------
--  Load / sync admin data onto the player element
--  (the client HUD and other resources read from here)
-- ------------------------------------------------------------

function syncAdminData(player)
    if not isElement(player) then return end
    local acc = getPlayerAccount(player)

    if not acc or isGuestAccount(acc) then
        setElementData(player, "admin_level", 0)
        return
    end

    local level = tonumber(getAccountData(acc, "admin_level")) or 0
    setAccountData(acc, "admin_level", level)
    setElementData(player, "admin_level", level)
end

addEventHandler("onPlayerLogin", root, function()
    syncAdminData(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        syncAdminData(player)
    end
end)
