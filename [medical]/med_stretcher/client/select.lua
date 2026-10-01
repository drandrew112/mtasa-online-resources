-- Patient selector ("Place patient on stretcher"). The cursor appears and every ped / player within
-- STRETCHER.PATIENT_RANGE of the stretcher gets a round button above the head; clicking one sends
-- the pick to the server, which re-checks it. RMB hides / shows the cursor (so the medic can look
-- around), Backspace cancels.

addEvent("stretcher:selectPatient", true)

local D = STRETCHER_DATA

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.7, screenH / 1080)
local RADIUS = 15 * scale
local LOCKED_CONTROLS = { "fire", "aim_weapon" } -- RMB / LMB must not shoot while selecting

local sel = nil -- { stretcher, buttons = { { ped, x, y } }, hovered, lockedControls }

-- ---------------------------------------------------------------------------------------------
-- Candidates (the server applies the same rules in isPatientCandidate)
-- ---------------------------------------------------------------------------------------------

local function isCandidate(ped)
    return ped ~= localPlayer and not isPedDead(ped)
        and not getPedOccupiedVehicle(ped) and not isElementAttached(ped)
        and not getElementData(ped, D.ON) and not getElementData(ped, D.PUSHING)
end

local function isDown(ped)
    local status = getElementData(ped, "medic.status")
    return status == "unconscious" or status == "clinical_death" or status == "dead"
end

-- Button anchor above the head; falls back to the element position if the bone is not available
local function headPosition(ped)
    local x, y, z = getPedBonePosition(ped, 8)
    if x and (x ~= 0 or y ~= 0 or z ~= 0) then return x, y, z + 0.45 end
    x, y, z = getElementPosition(ped)
    return x, y, z + 1.2
end

-- Streamed-in peds / players near the stretcher, filtered by hand (not getElementsWithinRange)
local function collectButtons()
    local x, y, z = getElementPosition(sel.stretcher)
    local int, dim = getElementInterior(sel.stretcher), getElementDimension(sel.stretcher)
    local buttons = {}
    for _, elementType in ipairs({ "player", "ped" }) do
        for _, ped in ipairs(getElementsByType(elementType, root, true)) do
            if getElementInterior(ped) == int and getElementDimension(ped) == dim and isCandidate(ped) then
                local px, py, pz = getElementPosition(ped)
                if getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= STRETCHER.PATIENT_RANGE then
                    local sx, sy = getScreenFromWorldPosition(headPosition(ped))
                    if sx then buttons[#buttons + 1] = { ped = ped, x = sx, y = sy } end
                end
            end
        end
    end
    return buttons
end

-- ---------------------------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------------------------

local function setIOEnabled(enabled)
    local res = getResourceFromName("ui_interactobject")
    if res and getResourceState(res) == "running" then
        exports.ui_interactobject:setInteractionDisabled(not enabled)
    end
end

local stopSelection -- forward declaration

local function toggleCursor()
    if sel then showCursor(not isCursorShowing()) end
end

local function cancel()
    stopSelection()
end

local function startSelection(stretcher)
    if sel then stopSelection() end
    sel = { stretcher = stretcher, buttons = {}, lockedControls = {} }
    for _, control in ipairs(LOCKED_CONTROLS) do
        if isControlEnabled(control) then
            toggleControl(control, false)
            sel.lockedControls[#sel.lockedControls + 1] = control
        end
    end
    setIOEnabled(false)
    showCursor(true)
    bindKey("mouse2", "down", toggleCursor)
    bindKey("backspace", "down", cancel)
end

function stopSelection()
    if not sel then return end
    for _, control in ipairs(sel.lockedControls) do toggleControl(control, true) end
    sel = nil
    unbindKey("mouse2", "down", toggleCursor)
    unbindKey("backspace", "down", cancel)
    showCursor(false)
    setIOEnabled(true)
end

-- Ends the selection when it no longer makes sense
local function stillValid()
    local obj = sel.stretcher
    if not isElement(obj) or getElementData(obj, D.STATE) ~= "ground" or getElementData(obj, D.PATIENT) then return false end
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then return false end
    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z = getElementPosition(obj)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= STRETCHER.SELECT_MAX_DISTANCE
end

addEventHandler("stretcher:selectPatient", resourceRoot, function(stretcher)
    if isElement(stretcher) then startSelection(stretcher) end
end)

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local function drawText(text, y, color, textScale, font)
    dxDrawText(text, 1, y + 1, screenW + 1, y + 1, tocolor(0, 0, 0, 200), textScale, font, "center", "top")
    dxDrawText(text, 0, y, screenW, y, color, textScale, font, "center", "top")
end

addEventHandler("onClientRender", root, function()
    if not sel then return end
    if not stillValid() then return stopSelection() end

    sel.buttons = collectButtons()
    sel.hovered = nil

    local cx, cy
    if isCursorShowing() then
        local rx, ry = getCursorPosition()
        if rx then cx, cy = rx * screenW, ry * screenH end
    end

    for _, button in ipairs(sel.buttons) do
        local hovered = cx and getDistanceBetweenPoints2D(cx, cy, button.x, button.y) <= RADIUS
        if hovered then sel.hovered = button.ped end

        local fill
        if hovered then fill = tocolor(80, 170, 255, 235)
        elseif isDown(button.ped) then fill = tocolor(225, 70, 75, 220)   -- injured: red
        else fill = tocolor(235, 238, 245, 200) end

        dxDrawCircle(button.x, button.y, RADIUS + 3 * scale, 0, 360, tocolor(0, 0, 0, 170), tocolor(0, 0, 0, 170), 32)
        dxDrawCircle(button.x, button.y, RADIUS, 0, 360, fill, fill, 32)
        dxDrawCircle(button.x, button.y, RADIUS * 0.35, 0, 360, tocolor(255, 255, 255, 230), tocolor(255, 255, 255, 230), 16)
    end

    local top = screenH * 0.12
    drawText("Select patient", top, tocolor(255, 255, 255, 245), 2 * scale, "default-bold")
    drawText("(RMB to toggle mouse)", top + 34 * scale, tocolor(200, 205, 215, 220), 1 * scale, "default")
end)

-- ---------------------------------------------------------------------------------------------
-- Picking
-- ---------------------------------------------------------------------------------------------

addEventHandler("onClientClick", root, function(button, state)
    if not sel or button ~= "left" or state ~= "down" or not sel.hovered then return end
    triggerServerEvent("stretcher:pickPatient", resourceRoot, sel.stretcher, sel.hovered)
    stopSelection()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopSelection()
end)
