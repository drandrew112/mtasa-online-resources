-- ============================================================
--  v_admin / client/hud.lua
--  Server -> player messages (ui_core Alert) + admin jail HUD.
--  (Report system UI + its sound ping live in client/report.lua.)
-- ============================================================

-- ------------------------------------------------------------
--  Show messages through the ui_core Alert element
--  (chat is disabled: showChat(false))
-- ------------------------------------------------------------
addEvent(ADMIN.events.alert, true)
addEventHandler(ADMIN.events.alert, root, function(text, r, g, b, duration)
    if type(text) ~= "string" then return end
    exports.ui_core:setAlert(text, r, g, b, duration)
end)

-- ------------------------------------------------------------
--  Admin jail HUD (centre of the screen)
-- ------------------------------------------------------------
local sx, sy = guiGetScreenSize()

addEventHandler("onClientRender", root, function()
    local remaining = getElementData(localPlayer, "adminjail_remTime")
    if not remaining then return end

    local admin  = getElementData(localPlayer, "adminjail_admin")  or "?"
    local reason = getElementData(localPlayer, "adminjail_indok")  or "?"

    dxDrawText("#ff2525ADMINJAIL",
        0, sy / 2 - 60, sx, sy / 2 - 60,
        tocolor(255, 255, 255, 255), 1.8, "default-bold",
        "center", "top", false, false, false, true)

    dxDrawText(
        "#ffaaaaRemaining time: #FFFFFF" .. remaining .. " min" ..
        "\n#ffaaaaAdmin: #FFFFFF" .. tostring(admin) ..
        "\n#ffaaaaReason: #FFFFFF" .. tostring(reason),
        0, sy / 2 - 10, sx, sy / 2 - 10,
        tocolor(255, 255, 255, 255), 1.3, "default",
        "center", "top", false, false, false, true)
end)
