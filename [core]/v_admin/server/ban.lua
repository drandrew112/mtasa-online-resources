-- ============================================================
--  v_admin / server/ban.lua
--  /ban, /unban  – account bans handled by v_accounts.
--  Bans never expire (see v_accounts). Banning an online player
--  also stores their serial.
-- ============================================================

-- ------------------------------------------------------------
--  /ban <account> <reason...>
-- ------------------------------------------------------------
addCommandHandler("ban", function(player, cmd, accName, ...)
    if not hasAdminLevel(player, ADMIN.perms.ban) then
        return denyAccess(player, ADMIN.perms.ban)
    end

    local reason = table.concat({ ... }, " ")
    if not accName or reason == "" then
        return adminAlert(player, "Usage: /ban <account> <reason>", 255, 90, 90)
    end

    local ok, err = exports.v_accounts:banAccount(accName, reason, getPlayerName(player))
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or "Ban failed (v_accounts not reachable)"), 255, 90, 90)
    end

    adminAlert(player, "#FFFFFFYou banned account #FFFF00" .. accName .. " #FFFFFFfor #FFFFFF" .. reason)
end)

-- ------------------------------------------------------------
--  /unban <account>
-- ------------------------------------------------------------
addCommandHandler("unban", function(player, cmd, accName)
    if not hasAdminLevel(player, ADMIN.perms.ban) then
        return denyAccess(player, ADMIN.perms.ban)
    end

    if not accName then
        return adminAlert(player, "Usage: /unban <account>", 255, 90, 90)
    end

    local ok, err = exports.v_accounts:unbanAccount(accName)
    if not ok then
        return adminAlert(player, "#FF5A5A" .. tostring(err or "Unban failed"), 255, 90, 90)
    end

    adminAlert(player, "#FFFFFFYou unbanned account #FFFF00" .. accName .. "#FFFFFF.")
end)
