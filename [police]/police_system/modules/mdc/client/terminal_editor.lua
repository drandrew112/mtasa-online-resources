-- police_system / modules/mdc/client/terminal_editor.lua
-- Placement editor of the MDC computers (/mdcpc, admins; the same as gov_office /govpcs). The cursor is shown with
-- the controls left on (the admin can still walk). A ghost monitor follows the cursor on whatever surface it points at:
--   wheel            rotate (Shift: fine)
--   Ctrl + wheel     raise / lower
--   left click       place (a new computer, or the one picked up)
--   right click      pick up the computer under the cursor (move it)
--   Delete           delete the computer under the cursor
--   C                hide / show the cursor (look around)
--   Backspace        put the picked one back / leave the editor
-- The server re-checks every change (server/terminals.lua); this file only draws and sends.

local C = POLICE.TERMINALS
local ED = POL.module("terminalEditor", { active = false })

local ghost, picked, pickedObj
local rz, lift = 0, 0
local hoverObj
local cursorOn = true
local spot                -- { x, y, z } where the ghost stands now (nil = no surface)

local WHEEL_CONTROLS = { "next_weapon", "previous_weapon" }

local function pcId(el)
    return isElement(el) and getElementType(el) == "object" and tonumber(getElementData(el, "pol:terminal")) or nil
end

local function makeGhost()
    if isElement(ghost) then destroyElement(ghost) end
    ghost = createObject(C.MODEL, 0, 0, -50)
    setElementInterior(ghost, getElementInterior(localPlayer))
    setElementDimension(ghost, getElementDimension(localPlayer))
    setElementCollisionsEnabled(ghost, false)
    setElementAlpha(ghost, 170)
end

local function unpick()
    if isElement(pickedObj) then setElementAlpha(pickedObj, 255) end
    picked, pickedObj = nil, nil
end

------------------------------------------------------------------------ frame

local function cursorRay()
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    if not cx then return false end
    local camX, camY, camZ = getCameraMatrix()
    local fx, fy, fz = getWorldFromScreenPosition(cx * POL.sw, cy * POL.sh, C.RAY)
    if not fx then return false end
    local hit, hx, hy, hz, el = processLineOfSight(camX, camY, camZ, fx, fy, fz,
        true, false, false, true, false, false, false, false, ghost)
    if not hit then return false end
    return hx, hy, hz, el
end

local function shadowText(text, x, y, color)
    local font = POL.font(10, true)
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 200), 1, font, "center", "bottom")
    dxDrawText(text, x, y, x, y, color, 1, font, "center", "bottom")
end

local function frame()
    local hx, hy, hz, el = cursorRay()
    hoverObj = nil
    if hx then
        if pcId(el) and el ~= pickedObj then hoverObj = el end
        spot = { x = hx, y = hy, z = hz + lift }
        setElementPosition(ghost, spot.x, spot.y, spot.z)
        setElementRotation(ghost, 0, 0, rz)
    else
        spot = nil
        setElementPosition(ghost, 0, 0, -50)
    end
    if hoverObj then
        local x, y, z = getElementPosition(hoverObj)
        local sx, sy = getScreenFromWorldPosition(x, y, z + 0.6)
        if sx then shadowText(L("police_system.terminals.ed_hover", { id = pcId(hoverObj) }), sx, sy, POL.colors.yellow) end
    end
    local head = picked and L("police_system.terminals.ed_moving", { id = picked }) or L("police_system.terminals.ed_new")
    local lines = head .. "\n" .. L("police_system.terminals.ed_help") .. "\n"
        .. L("police_system.terminals.ed_state", { rot = math.floor(rz + 0.5), lift = ("%.2f"):format(lift) })
    local w, h = POL.px(700), POL.px(90)
    local x, y = (POL.sw - w) / 2, POL.sh - h - POL.px(36)
    dxDrawRectangle(x, y, w, h, POL.colors.bg)
    dxDrawRectangle(x, y, w, POL.px(2), POL.colors.accent)
    dxDrawText(lines, x + POL.px(10), y, x + w - POL.px(10), y + h, POL.colors.white, 1, POL.font(9, true), "center", "center", false, true)
end
POL.layers.add("terminal_editor", frame, 90)

------------------------------------------------------------------------ input

local function onKey(key, press)
    if not press then return end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        local dir = key == "mouse_wheel_up" and 1 or -1
        if getKeyState("lctrl") or getKeyState("rctrl") then
            lift = math.max(-2, math.min(2, lift + dir * C.HEIGHT_STEP))
        else
            local step = (getKeyState("lshift") or getKeyState("rshift")) and C.ROT_FINE or C.ROT_STEP
            rz = (rz + dir * step) % 360
        end
    elseif key == "mouse1" and isCursorShowing() then
        if spot then
            POL.send("terminals:place", picked or false, spot.x, spot.y, spot.z, rz)
            if picked then picked, pickedObj = nil, nil end   -- the server moves it; alpha comes back below
        end
    elseif key == "mouse2" and isCursorShowing() then
        if hoverObj then
            unpick()
            picked, pickedObj = pcId(hoverObj), hoverObj
            setElementAlpha(pickedObj, 60)
            local _, _, r = getElementRotation(pickedObj)
            rz, lift = r or 0, 0
        end
    elseif key == "delete" then
        if hoverObj then POL.send("terminals:delete", pcId(hoverObj)) end
    elseif key == "c" then
        cursorOn = not cursorOn
        showCursor(cursorOn, false)
    elseif key == "backspace" then
        if picked then unpick() else ED.stop() end
    else
        return
    end
    cancelEvent()
end

-- the moved computer is visible again once the server has moved it (or deleted it)
local function restoreAlphas()
    for _, o in ipairs(getElementsByType("object", resourceRoot)) do
        if o ~= pickedObj and o ~= ghost and pcId(o) and getElementAlpha(o) ~= 255 then setElementAlpha(o, 255) end
    end
end

local alphaTimer

function ED.begin()
    if ED.active then return end
    ED.active, rz, lift, cursorOn = true, 0, 0, true
    makeGhost()
    showCursor(true, false)
    for _, c in ipairs(WHEEL_CONTROLS) do toggleControl(c, false) end
    addEventHandler("onClientKey", root, onKey)
    alphaTimer = setTimer(restoreAlphas, 500, 0)
    POL.layers.set("terminal_editor", true)
    POL.notify(L("police_system.terminals.ed_started"))
end

-- fromServer: the server ended it (otherwise it is told, so /mdcpc starts it again next time)
function ED.stop(fromServer)
    if not ED.active then return end
    ED.active = false
    if fromServer ~= true then POL.send("terminals:stopEdit") end
    unpick()
    restoreAlphas()
    if isTimer(alphaTimer) then killTimer(alphaTimer) end
    POL.layers.set("terminal_editor", false)
    removeEventHandler("onClientKey", root, onKey)
    if isElement(ghost) then destroyElement(ghost) end
    ghost, spot, hoverObj = nil, nil, nil
    showCursor(false)
    for _, c in ipairs(WHEEL_CONTROLS) do toggleControl(c, true) end
end

POL.handle("terminals:editor", function(on) if on then ED.begin() else ED.stop(true) end end)

addEventHandler("onClientPlayerWasted", localPlayer, function() ED.stop() end)
addEventHandler("onClientResourceStop", resourceRoot, function() ED.stop(true) end)
-- the ghost lives in the admin's world
addEventHandler("onClientElementDimensionChange", localPlayer, function() if ED.active then makeGhost() end end)
addEventHandler("onClientElementInteriorChange", localPlayer, function() if ED.active then makeGhost() end end)
