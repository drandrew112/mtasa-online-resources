if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
function adminHeal(player, target)
    if not hasAdminLevel(player, ADMIN.perms.heal) then
        return denyAccess(player, ADMIN.perms.heal)
    end
    if not isElement(target) then return end

    if isPedDead(target) then
        return adminAlert(player, L.msg("v_admin.misc.is_dead", { player = getPlayerName(target) }), 255, 90, 90)
    end

    setElementHealth(target, 100)
    setPedArmor(target, 100)
    local medsys = getResourceFromName("medsys")
    if medsys and getResourceState(medsys) == "running" then
        exports.medsys:healCompletely(target) -- injuries, bleeding, vitals back to baseline
    end

    if target ~= player then
        adminAlert(target, L.msg("v_admin.misc.healed_you", { player = actorName(player) }))
        adminAlert(player, L.msg("v_admin.misc.you_healed", { player = getPlayerName(target) }))
    else
        adminAlert(player, L.msg("v_admin.misc.you_healed_yourself"))
    end
end

addCommandHandler("heal", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.heal) then
        return denyAccess(player, ADMIN.perms.heal)
    end
    local target = resolveTarget(player, idArg)
    if target then adminHeal(player, target) end
end)

-- ------------------------------------------------------------
--  /setskin <ID> <skin>  – change a player's skin (ped model)
--  A player on work duty is taken off duty first, so the new skin
--  is the civilian one (that is what acc_savesys saves).
-- ------------------------------------------------------------
local validSkins = {}
for _, id in ipairs(getValidPedModels()) do validSkins[id] = true end

function adminSetSkin(player, target, skin)
    if not hasAdminLevel(player, ADMIN.perms.skin) then
        return denyAccess(player, ADMIN.perms.skin)
    end
    if not isElement(target) then return end

    skin = tonumber(skin)
    if not skin or not validSkins[skin] then
        return adminAlert(player, L.msg("v_admin.misc.invalid_skin_id"), 255, 90, 90)
    end
    if getElementModel(target) == skin then
        return adminAlert(player, L.msg("v_admin.misc.already_wears_skin", { player = getPlayerName(target), skin = skin }), 255, 90, 90)
    end

    local workCore = getResourceFromName("work_core")
    if workCore and getResourceState(workCore) == "running" and exports.work_core:getPlayerWork(target) then
        exports.work_core:setPlayerOffDuty(target)
    end

    if not setElementModel(target, skin) then
        return adminAlert(player, L.msg("v_admin.misc.invalid_skin_id"), 255, 90, 90)
    end
    adminLog(player, ("set %s skin to %d"):format(getPlayerName(target), skin), target)

    if target ~= player then
        adminAlert(target, L.msg("v_admin.misc.changed_your_skin", { player = actorName(player), skin = skin }))
        adminAlert(player, L.msg("v_admin.misc.you_changed_skin", { player = getPlayerName(target), skin = skin }))
    else
        adminAlert(player, L.msg("v_admin.misc.you_changed_your_skin", { skin = skin }))
    end
end

addCommandHandler("setskin", function(player, cmd, idArg, skinArg)
    if not hasAdminLevel(player, ADMIN.perms.skin) then
        return denyAccess(player, ADMIN.perms.skin)
    end
    if not skinArg then
        return adminAlert(player, L.msg("v_admin.misc.usage_setskin"), 255, 90, 90)
    end
    local target = resolveTarget(player, idArg)
    if target then adminSetSkin(player, target, skinArg) end
end)

-- ------------------------------------------------------------
--  /money  – test money (admin)
-- ------------------------------------------------------------
addCommandHandler("money", function(player)
    if not hasAdminLevel(player, ADMIN.perms.money) then
        return denyAccess(player, ADMIN.perms.money)
    end
    givePlayerMoney(player, 1000000)
    exports.ui_core:showMoney(player, "add", 1000000, "cash")
    adminAlert(player, L.msg("v_admin.misc.2000"))
end)

-- ------------------------------------------------------------
--  /getid <name>  – a player's ID by name (or name fragment)
-- ------------------------------------------------------------
addCommandHandler("getid", function(player, cmd, name)
    if not name then
        return adminAlert(player, L.msg("v_admin.misc.usage_getid_name"), 255, 90, 90)
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
        return adminAlert(player, L.msg("v_admin.misc.player_not_found"), 255, 90, 90)
    end
    adminAlert(player, L.msg("v_admin.misc.id", { player = getPlayerName(target), target = tostring(getElementData(target, "ID")) }))
end)

-- ------------------------------------------------------------
--  /listacc  – all accounts to the server log (high level)
-- ------------------------------------------------------------
addCommandHandler("listacc", function(player)
    if not hasAdminLevel(player, ADMIN.perms.listAccounts) then
        return denyAccess(player, ADMIN.perms.listAccounts)
    end

    local n = 0
    for _, name in ipairs(exports.acc_auth:getAllAccountNames()) do
        outputServerLog("[v_admin] Account: " .. name)
        n = n + 1
    end
    adminAlert(player, L.msg("v_admin.misc.accounts_written_to_server_log", { n = n }))
end)

-- chat command database (v_chat)
CMD.register("fly", "", ADMIN.perms.noclip, "Toggle noclip flying")
CMD.register("heal", "[id]", ADMIN.perms.heal, "Heal yourself or the given player")
CMD.register("setskin", "<id> <skin>", ADMIN.perms.skin, "Change the skin of a player")
CMD.register("money", "", ADMIN.perms.money, "Gives you test money")
CMD.register("getid", "<name>", 0, "Finds the ID of a player by name")
CMD.register("listacc", "", ADMIN.perms.listAccounts, "Writes all accounts to the server log")
