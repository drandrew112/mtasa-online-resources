-- Keeps the player inside the introduction: no movement, no weapons, no damage, and only the
-- panel the current scene teaches may open.
--
-- Panel gate: the local element data "intro.allow" is a table { panelId = true } while the
-- introduction runs (nil otherwise). The panels check it before opening:
--   phone (ui_phone), social (v_socialpanel), interaction (ui_inac), pause (ui_pause),
--   browser (ui_browser), chat (v_chat)

Lock = { active = false }

local CONTROLS = {
    "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "next_weapon", "previous_weapon", "action", "enter_exit",
    "enter_passenger", "change_camera", "vehicle_fire", "vehicle_secondary_fire",
    -- the practice vehicle stays where it is
    "accelerate", "brake_reverse", "vehicle_left", "vehicle_right", "steer_forward", "steer_back",
    "handbrake", "special_control_left", "special_control_right",
}

-- the panels whose open flag blocks Continue (the player closes them first)
Lock.PANEL_FLAGS = {
    { data = "phoneOpen", name = "phone" },
    { data = "socialPanelOpen", name = "social panel" },
    { data = "interactionMenuOpen", name = "menu" },
    { data = "paused", name = "pause menu" },
    { data = "browserOpen", name = "browser" },
    { data = "showChatInput", name = "chat" },
    { data = "reportPanelOpen", name = "report panel" },
    { data = "textInputOpen", name = "text input" },
}

local controlTimer

local function applyControls()
    for _, c in ipairs(CONTROLS) do toggleControl(c, false) end
end

function Lock.enable()
    if Lock.active then return end
    Lock.active = true
    Lock.allow(nil)
    applyControls()
    -- panels give the controls back when they close: take them again
    controlTimer = setTimer(applyControls, 400, 0)
end

function Lock.disable()
    if not Lock.active then return end
    Lock.active = false
    if isTimer(controlTimer) then killTimer(controlTimer) end
    controlTimer = nil
    for _, c in ipairs(CONTROLS) do toggleControl(c, true) end
    setElementData(localPlayer, "intro.allow", nil, false)
    setElementData(localPlayer, "hideHUD", false)
end

-- ids = { "phone", ... } | nil (nothing allowed)
function Lock.allow(ids)
    local t = {}
    for _, id in ipairs(ids or {}) do t[id] = true end
    setElementData(localPlayer, "intro.allow", t, false)
end

function Lock.setHud(visible)
    setElementData(localPlayer, "hideHUD", not visible)
end

-- -> name of an open panel | nil
function Lock.openPanel()
    for _, p in ipairs(Lock.PANEL_FLAGS) do
        if getElementData(localPlayer, p.data) then return p.name end
    end
end

addEventHandler("onClientPlayerDamage", localPlayer, function()
    if Lock.active then cancelEvent() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    Lock.disable()
end)
