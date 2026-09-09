-- ============================================================
--  v_admin / server/misc.lua
--  Smaller admin helper commands + noclip gate.
-- ============================================================

-- ------------------------------------------------------------
--  /fly  – noclip mode (movement happens client-side)
-- ------------------------------------------------------------
addCommandHandler("fly", function(player)
    if not hasAdminLevel(player, ADMIN.perms.noclip) then
        return denyAccess(player, ADMIN.perms.noclip)
    end
    triggerClientEvent(player, ADMIN.events.toggleNoclip, player)
end)
-- The N key is handled entirely client-side (it reads the synced
-- "admin_level" element data), so there is no server event for it.

-- ------------------------------------------------------------
--  /heal <ID>  – restore a player's health and armour
-- ------------------------------------------------------------
addCommandHandler("heal", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.heal) then
        return denyAccess(player, ADMIN.perms.heal)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end

    if isPedDead(target) then
        return adminAlert(player, "#FFFF00" .. getPlayerName(target) .. " #FFFFFFis dead.", 255, 90, 90)
    end

    setElementHealth(target, 100)
    setPedArmor(target, 100)

    if target ~= player then
        adminAlert(target, "#FFFF00" .. getPlayerName(player) .. " #FFFFFFhealed you.")
        adminAlert(player, "#FFFFFFYou healed #FFFF00" .. getPlayerName(target) .. "#FFFFFF.")
    else
        adminAlert(player, "#FFFFFFYou healed yourself.")
    end
end)

-- ------------------------------------------------------------
--  /money  – test money (admin)
-- ------------------------------------------------------------
addCommandHandler("money", function(player)
    if not hasAdminLevel(player, ADMIN.perms.money) then
        return denyAccess(player, ADMIN.perms.money)
    end
    givePlayerMoney(player, 2000)
    adminAlert(player, "#55FF55+2000 $")
end)

-- ------------------------------------------------------------
--  /getid <name>  – a player's ID by name (or name fragment)
-- ------------------------------------------------------------
addCommandHandler("getid", function(player, cmd, name)
    if not name then
        return adminAlert(player, "Usage: /getid <name>", 255, 90, 90)
    end

    local target = getPlayerFromName(name)
    if not target then
        local needle = name:lower()
        for _, p in ipairs(getElementsByType("player")) do
            if getPlayerName(p):lower():find(needle, 1, true) then
                target = p
                break
            end
        end
    end

    if not target then
        return adminAlert(player, "Player not found.", 255, 90, 90)
    end
    adminAlert(player, getPlayerName(target) .. " #FFFFFF| ID: #CCFFCC" .. tostring(getElementData(target, "ID")))
end)

-- ------------------------------------------------------------
--  /listacc  – all accounts to the server log (high level)
-- ------------------------------------------------------------
addCommandHandler("listacc", function(player)
    if not hasAdminLevel(player, ADMIN.perms.listAccounts) then
        return denyAccess(player, ADMIN.perms.listAccounts)
    end

    local n = 0
    for _, name in ipairs(exports.v_accounts:getAllAccountNames()) do
        outputServerLog("[v_admin] Account: " .. name)
        n = n + 1
    end
    adminAlert(player, "#55FF55" .. n .. " accounts written to the server log.")
end)
