-- The local player's own condition: controls are locked while down, the screen shows
-- what the character experiences (dazed vignette, unconscious / clinical death blackout).

addEvent("medic:selfStatus", true)

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)

local LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger", "next_weapon", "previous_weapon",
    "look_behind", "action" }
local DAZED_SHAKE = 40

local status
local deathTick -- getTickCount() when the resuscitation window ends
local lockedControls
local fonts

local function lockControls(locked)
    if locked and not lockedControls then
        lockedControls = {}
        for _, control in ipairs(LOCK_CONTROLS) do
            if isControlEnabled(control) then
                toggleControl(control, false)
                lockedControls[#lockedControls + 1] = control
            end
        end
    elseif not locked and lockedControls then
        for _, control in ipairs(lockedControls) do toggleControl(control, true) end
        lockedControls = nil
    end
end

local function render()
    local now = getTickCount()
    if status == "dazed" then
        local pulse = 70 + math.sin(now / 400) * 30
        local edge = screenH * 0.18
        dxDrawRectangle(0, 0, screenW, edge * 0.5, tocolor(0, 0, 0, pulse))
        dxDrawRectangle(0, screenH - edge * 0.5, screenW, edge * 0.5, tocolor(0, 0, 0, pulse))
        dxDrawRectangle(0, 0, screenW, screenH, tocolor(40, 0, 0, pulse * 0.35))
        return
    end

    dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, 235))
    local title, sub, color
    if status == "clinical_death" then
        local left = math.max(0, math.ceil((deathTick - now) / 1000))
        title = "CLINICAL DEATH"
        sub = ("Your heart has stopped. Resuscitation window: %02d:%02d"):format(math.floor(left / 60), left % 60)
        color = tocolor(235, 70, 70)
    else
        title = "UNCONSCIOUS"
        sub = "You passed out. Wait for medical help."
        color = tocolor(235, 238, 245)
    end
    dxDrawText(title, 0, 0, screenW, screenH - 40 * scale, color, 1, fonts.title, "center", "center")
    dxDrawText(sub, 0, 60 * scale, screenW, screenH, tocolor(160, 165, 175), 1, fonts.sub, "center", "center")
end

local function setStatus(newStatus, deathTimeLeft)
    local wasShown = status == "dazed" or status == "unconscious" or status == "clinical_death"
    status = newStatus or nil
    deathTick = deathTimeLeft and getTickCount() + deathTimeLeft * 1000 or nil

    local shown = status == "dazed" or status == "unconscious" or status == "clinical_death"
    if shown and not fonts then
        fonts = {
            title = dxCreateFont("assets/fonts/RobotoB.ttf", math.floor(34 * scale), false, "cleartype") or "default-bold",
            sub = dxCreateFont("assets/fonts/Roboto.ttf", math.floor(14 * scale), false, "cleartype") or "default",
        }
    end
    if shown and not wasShown then
        addEventHandler("onClientRender", root, render)
    elseif not shown and wasShown then
        removeEventHandler("onClientRender", root, render)
    end

    lockControls(status == "unconscious" or status == "clinical_death")
    setCameraShakeLevel(status == "dazed" and DAZED_SHAKE or 0)
end

addEventHandler("medic:selfStatus", resourceRoot, function(newStatus, deathTimeLeft)
    -- "dead" is left to the death / respawn system
    if newStatus == "dead" then newStatus = nil end
    setStatus(newStatus, deathTimeLeft)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    setStatus(nil)
end)
