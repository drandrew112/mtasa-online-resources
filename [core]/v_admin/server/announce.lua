-- ============================================================
--  v_admin / server/announce.lua
--  Admin call (server-wide announcement). adminAnnounce is shared
--  with the admin panel's Server tab.
-- ============================================================

function adminAnnounce(player, message)
    if not hasAdminLevel(player, ADMIN.perms.adminCall) then
        return denyAccess(player, ADMIN.perms.adminCall)
    end
    if type(message) ~= "string" or message == "" then
        return adminAlert(player, "Usage: /af <message>", 255, 90, 90)
    end

    adminBroadcast("#FFFF00" .. getPlayerName(player) .. " #FFFF00announcement: #FFFFFF" .. message, nil, nil, nil, 8000)
    adminLog(player, "announcement: " .. message)
end

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
    adminAnnounce(player, message)
end
addCommandHandler("af", adminCall)
addCommandHandler("adminannounce", adminCall)
