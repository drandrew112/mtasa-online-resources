if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
--  Spectate line (server/spectate.lua)
-- ------------------------------------------------------------
local function drawSpectate()
    local name = getElementData(localPlayer, "adminSpectating")
    if not name or getElementData(localPlayer, "adminPanelOpen") then return end
    local w, h = guiGetScreenSize()
    dxDrawText(L("v_admin.hud.spectating", { name = name }), 0, h * 0.86, w, h * 0.86 + 30,
        tocolor(255, 255, 255, 230), 1.4, "default-bold", "center", "center")
end
addEvent("v_admin:spectating", true)
addEventHandler("v_admin:spectating", resourceRoot, function(name)
    -- local copy for the panel's "Stop spectating" button (the server's is not synced)
    setElementData(localPlayer, "adminSpectating", name or false, false)
    removeEventHandler("onClientRender", root, drawSpectate)
    if name then addEventHandler("onClientRender", root, drawSpectate) end
end)

-- ------------------------------------------------------------
--  Admin jail HUD (centre of the screen)
-- ------------------------------------------------------------
local sx, sy = guiGetScreenSize()

local function drawJail()
    local remaining = getElementData(localPlayer, "adminjail_remTime")
    if not remaining then return end

    local admin  = getElementData(localPlayer, "adminjail_admin")  or "?"
    local reason = getElementData(localPlayer, "adminjail_indok")  or "?"

    dxDrawText(L("v_admin.hud.adminjail"),
        0, sy / 2 - 60, sx, sy / 2 - 60,
        tocolor(255, 255, 255, 255), 1.8, "default-bold",
        "center", "top", false, false, false, true)

    dxDrawText(
        L("v_admin.hud.remaining_time_min_admin_reason", { remaining = remaining, admin = tostring(admin), reason = tostring(reason) }),
        0, sy / 2 - 10, sx, sy / 2 - 10,
        tocolor(255, 255, 255, 255), 1.3, "default",
        "center", "top", false, false, false, true)
end

-- the HUD is attached only while the player is jailed
local jailHud = false
local function updateJailHud()
    local on = getElementData(localPlayer, "adminjail_remTime") and true or false
    if on == jailHud then return end
    jailHud = on
    if on then
        addEventHandler("onClientRender", root, drawJail)
    else
        removeEventHandler("onClientRender", root, drawJail)
    end
end
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "adminjail_remTime" then updateJailHud() end
end, false)
updateJailHud()
