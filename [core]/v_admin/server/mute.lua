if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/mute.lua
--  /mute, /unmute  – chat mute handled by v_chat. A mute also
--  runs out on its own.
--  adminMute / adminUnmute are shared with the admin panel.
-- ============================================================

function adminMute(player, target, minutes, reason)
    if not hasAdminLevel(player, ADMIN.perms.mute) then
        return denyAccess(player, ADMIN.perms.mute)
    end
    minutes = tonumber(minutes)
    if not isElement(target) or not minutes or type(reason) ~= "string" or reason == "" then
        return adminAlert(player, L.msg("v_admin.mute.usage_mute_id_minutes_reason"), 255, 90, 90)
    end
    if not canPunish(player, target) then return end
    minutes = math.max(1, math.floor(minutes))

    local ok, err = exports.v_chat:mutePlayer(target, minutes, reason, actorName(player))
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or L.msg("v_admin.mute.mute_failed")), 255, 90, 90)
    end

    -- The muted player is told by v_chat ("Muted by <admin> (<n> min) for <reason>").
    adminAlert(player, L.msg("v_admin.mute.you_muted_min_for", { player = getPlayerName(target), minutes = minutes, reason = reason }))
    adminLog(player, ("muted %s for %d min (%s)"):format(getPlayerName(target), minutes, reason), target)
end

function adminUnmute(player, target)
    if not hasAdminLevel(player, ADMIN.perms.mute) then
        return denyAccess(player, ADMIN.perms.mute)
    end
    if not isElement(target) then return end

    local ok, err = exports.v_chat:unmutePlayer(target, actorName(player))
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or L.msg("v_admin.mute.unmute_failed")), 255, 90, 90)
    end

    -- The player is told by v_chat ("Unmuted by <admin>").
    adminAlert(player, L.msg("v_admin.mute.you_unmuted", { player = getPlayerName(target) }))
    adminLog(player, "unmuted " .. getPlayerName(target), target)
end

-- ------------------------------------------------------------
--  /mute <ID> <minutes> <reason...>
-- ------------------------------------------------------------
addCommandHandler("mute", function(player, cmd, idArg, minutesArg, ...)
    if not hasAdminLevel(player, ADMIN.perms.mute) then
        return denyAccess(player, ADMIN.perms.mute)
    end

    local reason = table.concat({ ... }, " ")
    if not idArg or not tonumber(minutesArg) or reason == "" then
        return adminAlert(player, L.msg("v_admin.mute.usage_mute_id_minutes_reason"), 255, 90, 90)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    adminMute(player, target, minutesArg, reason)
end)

-- ------------------------------------------------------------
--  /unmute <ID>
-- ------------------------------------------------------------
addCommandHandler("unmute", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.mute) then
        return denyAccess(player, ADMIN.perms.mute)
    end
    if not idArg then
        return adminAlert(player, L.msg("v_admin.mute.usage_unmute_id"), 255, 90, 90)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    adminUnmute(player, target)
end)

-- chat command database (v_chat)
CMD.register("mute", "<id> <minutes> [reason]", ADMIN.perms.mute, "Mute a player in chat")
CMD.register("unmute", "<id>", ADMIN.perms.mute, "Unmute a player")
