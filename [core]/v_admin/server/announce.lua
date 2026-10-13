if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
        return adminAlert(player, L.msg("v_admin.announce.usage_af_message"), 255, 90, 90)
    end

    adminBroadcast(L.msg("v_admin.announce.announcement", { player = actorName(player), message = message }), nil, nil, nil, 8000)
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
        return adminAlert(player, L.msg("v_admin.announce.usage_message", { cmd = cmd }), 255, 90, 90)
    end
    adminAnnounce(player, message)
end
addCommandHandler("af", adminCall)
addCommandHandler("adminannounce", adminCall)
