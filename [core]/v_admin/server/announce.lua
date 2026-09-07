-- ============================================================
--  v_admin / server/announce.lua
--  Admin call (server-wide announcement).
-- ============================================================

-- ------------------------------------------------------------
--  /af , /adminannounce  – admin call to the whole server
-- ------------------------------------------------------------
local function adminCall(player, cmd, ...)
    if not hasAdminLevel(player, ADMIN.perms.adminCall) then
        return denyAccess(player, ADMIN.perms.adminCall)
    end

    local message = table.concat({ ... }, " ")
    if message == "" then
        return adminAlert(player, "Usage: /" .. cmd .. " <message>", 255, 90, 90)
    end

    adminBroadcast("#FFFF00" .. getPlayerName(player) .. " #FFFF00announcement: #FFFFFF" .. message, nil, nil, nil, 8000)
end
addCommandHandler("af", adminCall)
addCommandHandler("adminannounce", adminCall)
