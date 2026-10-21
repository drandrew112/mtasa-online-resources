if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/ban.lua
--  /ban, /unban, /kick
--  Bans are account bans handled by acc_bans and never expire
--  (see acc_bans). Banning an online player also stores their
--  serial. adminBan / adminUnban / adminKick are shared with the
--  admin panel.
-- ============================================================

-- The online player logged into `accName` (case-insensitive), or nil.
local function playerOnAccount(accName)
    local needle = tostring(accName):lower()
    for _, p in ipairs(getElementsByType("player")) do
        local n = exports.acc_auth:getName(p)
        if n and n:lower() == needle then return p end
    end
end

function adminBan(player, accName, reason)
    if not hasAdminLevel(player, ADMIN.perms.ban) then
        return denyAccess(player, ADMIN.perms.ban)
    end
    if type(accName) ~= "string" or accName == "" or type(reason) ~= "string" or reason == "" then
        return adminAlert(player, L.msg("v_admin.ban.usage_ban_account_reason"), 255, 90, 90)
    end

    local online = playerOnAccount(accName)
    if online and not canPunish(player, online) then return end

    local ok, err = exports.acc_bans:banAccount(accName, reason, actorName(player))
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or L.msg("v_admin.ban.ban_failed_v_accounts_not_reachable")), 255, 90, 90)
    end

    adminAlert(player, L.msg("v_admin.ban.you_banned_account_for", { acc_name = accName, reason = reason }))
    adminLog(player, ("banned account %s (%s)"):format(accName, reason), accName)
end

function adminUnban(player, accName)
    if not hasAdminLevel(player, ADMIN.perms.ban) then
        return denyAccess(player, ADMIN.perms.ban)
    end
    if type(accName) ~= "string" or accName == "" then
        return adminAlert(player, L.msg("v_admin.ban.usage_unban_account"), 255, 90, 90)
    end

    local ok, err = exports.acc_bans:unbanAccount(accName, actorName(player))
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or L.msg("v_admin.ban.unban_failed")), 255, 90, 90)
    end

    adminAlert(player, L.msg("v_admin.ban.you_unbanned_account", { acc_name = accName }))
    adminLog(player, "unbanned account " .. accName, accName)
end

function adminKick(player, target, reason)
    if not hasAdminLevel(player, ADMIN.perms.kick) then
        return denyAccess(player, ADMIN.perms.kick)
    end
    if not isElement(target) or type(reason) ~= "string" or reason == "" then
        return adminAlert(player, L.msg("v_admin.ban.usage_kick_id_reason"), 255, 90, 90)
    end
    if target == actorPlayer(player) then
        return adminAlert(player, L.msg("v_admin.ban.you_can_t_kick_yourself"), 255, 90, 90)
    end
    if not canPunish(player, target) then return end

    local name = getPlayerName(target)
    local acc = actorAccount(target)
    -- Needs function.kickPlayer: resource.v_admin is in the Admin ACL group.
    if not kickPlayer(target, actorName(player), reason) then
        return adminAlert(player, L.msg("v_admin.ban.kick_failed_v_admin_needs_function"), 255, 90, 90)
    end

    adminAlert(player, L.msg("v_admin.ban.you_kicked_for", { name = name, reason = reason }))
    adminLog(player, ("kicked %s (%s)"):format(name, reason), acc)
end

-- ------------------------------------------------------------
--  /ban <account> <reason...>
-- ------------------------------------------------------------
addCommandHandler("ban", function(player, cmd, accName, ...)
    adminBan(player, accName, table.concat({ ... }, " "))
end)

-- ------------------------------------------------------------
--  /unban <account>
-- ------------------------------------------------------------
addCommandHandler("unban", function(player, cmd, accName)
    adminUnban(player, accName)
end)

-- ------------------------------------------------------------
--  /kick <ID> <reason...>
-- ------------------------------------------------------------
addCommandHandler("kick", function(player, cmd, idArg, ...)
    if not hasAdminLevel(player, ADMIN.perms.kick) then
        return denyAccess(player, ADMIN.perms.kick)
    end

    local reason = table.concat({ ... }, " ")
    if not idArg or reason == "" then
        return adminAlert(player, L.msg("v_admin.ban.usage_kick_id_reason"), 255, 90, 90)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    adminKick(player, target, reason)
end)
