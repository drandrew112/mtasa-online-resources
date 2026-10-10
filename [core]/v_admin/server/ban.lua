-- ============================================================
--  v_admin / server/ban.lua
--  /ban, /unban, /kick
--  Bans are account bans handled by v_accounts and never expire
--  (see v_accounts). Banning an online player also stores their
--  serial. adminBan / adminUnban / adminKick are shared with the
--  admin panel.
-- ============================================================

-- The online player logged into `accName` (case-insensitive), or nil.
local function playerOnAccount(accName)
    local needle = tostring(accName):lower()
    for _, p in ipairs(getElementsByType("player")) do
        local n = exports.v_accounts:getName(p)
        if n and n:lower() == needle then return p end
    end
end

function adminBan(player, accName, reason)
    if not hasAdminLevel(player, ADMIN.perms.ban) then
        return denyAccess(player, ADMIN.perms.ban)
    end
    if type(accName) ~= "string" or accName == "" or type(reason) ~= "string" or reason == "" then
        return adminAlert(player, "Usage: /ban <account> <reason>", 255, 90, 90)
    end

    local online = playerOnAccount(accName)
    if online and not canPunish(player, online) then return end

    local ok, err = exports.v_accounts:banAccount(accName, reason, getPlayerName(player))
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or "Ban failed (v_accounts not reachable)"), 255, 90, 90)
    end

    adminAlert(player, "#FFFFFFYou banned account #FFFF00" .. accName .. " #FFFFFFfor #FFFFFF" .. reason)
    adminLog(player, ("banned account %s (%s)"):format(accName, reason))
end

function adminUnban(player, accName)
    if not hasAdminLevel(player, ADMIN.perms.ban) then
        return denyAccess(player, ADMIN.perms.ban)
    end
    if type(accName) ~= "string" or accName == "" then
        return adminAlert(player, "Usage: /unban <account>", 255, 90, 90)
    end

    local ok, err = exports.v_accounts:unbanAccount(accName)
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or "Unban failed"), 255, 90, 90)
    end

    adminAlert(player, "#FFFFFFYou unbanned account #FFFF00" .. accName .. "#FFFFFF.")
    adminLog(player, "unbanned account " .. accName)
end

function adminKick(player, target, reason)
    if not hasAdminLevel(player, ADMIN.perms.kick) then
        return denyAccess(player, ADMIN.perms.kick)
    end
    if not isElement(target) or type(reason) ~= "string" or reason == "" then
        return adminAlert(player, "Usage: /kick <ID> <reason>", 255, 90, 90)
    end
    if target == player then
        return adminAlert(player, "You can't kick yourself.", 255, 90, 90)
    end
    if not canPunish(player, target) then return end

    local name = getPlayerName(target)
    -- Needs function.kickPlayer: resource.v_admin is in the Admin ACL group.
    if not kickPlayer(target, player, reason) then
        return adminAlert(player, "#FF5A5AKick failed (v_admin needs the function.kickPlayer ACL right).", 255, 90, 90)
    end

    adminAlert(player, "#FFFFFFYou kicked #FFFF00" .. name .. " #FFFFFFfor #FFFFFF" .. reason)
    adminLog(player, ("kicked %s (%s)"):format(name, reason))
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
        return adminAlert(player, "Usage: /kick <ID> <reason>", 255, 90, 90)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    adminKick(player, target, reason)
end)
