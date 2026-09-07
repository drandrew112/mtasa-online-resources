-- ============================================================
--  v_admin / server/mute.lua
--  /mute  – chat mute handled by v_chat. No /unmute: a mute
--  runs out on its own.
-- ============================================================

-- ------------------------------------------------------------
--  /mute <ID> <minutes> <reason...>
-- ------------------------------------------------------------
addCommandHandler("mute", function(player, cmd, idArg, minutesArg, ...)
    if not hasAdminLevel(player, ADMIN.perms.mute) then
        return denyAccess(player, ADMIN.perms.mute)
    end

    local minutes = tonumber(minutesArg)
    local reason  = table.concat({ ... }, " ")
    if not idArg or not minutes or reason == "" then
        return adminAlert(player, "Usage: /mute <ID> <minutes> <reason>", 255, 90, 90)
    end
    minutes = math.max(1, math.floor(minutes))

    local target = resolveTarget(player, idArg)
    if not target then return end

    local ok, err = exports.v_chat:mutePlayer(target, minutes, reason, getPlayerName(player))
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or "Mute failed"), 255, 90, 90)
    end

    -- The muted player is told by v_chat ("Muted by <admin> (<n> min) for <reason>").
    adminAlert(player, ("#FFFFFFYou muted #FFFF00%s #FFFFFF(%d min) for #FFFFFF%s")
        :format(getPlayerName(target), minutes, reason))
end)
