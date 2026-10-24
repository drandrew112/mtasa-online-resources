-- gov_office / client/editor.lua
-- Placement editor of the government computers (/govpcs, ministers, inside the office).
-- The cursor is shown with the controls left on (the player can still walk). A ghost monitor
-- follows the cursor on whatever surface it points at:
--   wheel            rotate (Shift: fine)
--   Ctrl + wheel     raise / lower
--   left click       place (a new computer, or the one picked up)
--   right click      pick up the computer under the cursor (move it)
--   Delete           delete the computer under the cursor
--   C                hide / show the cursor (look around)
--   Backspace        put the picked one back / leave the editor
-- The server re-checks every change; this file only draws and sends.

local active = false
local ghost, picked       -- ghost object, id of the computer being moved (or nil)
local pickedObj
local rz, lift = 0, 0
local hoverObj
local cursorOn = true
local spot                -- { x, y, z } where the ghost stands now (nil = no surface)
local font = "default-bold"

local WHEEL_CONTROLS = { "next_weapon", "previous_weapon" }

local function notify(key, params)
    pcall(function() exports.ui_core:addNotification(L("gov_office.name"), L(key, params or {})) end)
end

addEvent("gov_office:notify", true)
addEventHandler("gov_office:notify", resourceRoot, function(key, params) notify(key, params) end)

local function pcId(el)
    return isElement(el) and getElementType(el) == "object" and tonumber(getElementData(el, "gov_office:pc")) or nil
end

local function makeGhost()
    if isElement(ghost) then return end
    ghost = createObject(OFFICE.pcModel, 0, 0, -50)
    setElementInterior(ghost, OFFICE.interior)
    setElementDimension(ghost, OFFICE.dimension)
    setElementCollisionsEnabled(ghost, false)
    setElementAlpha(ghost, 170)
end

local function unpick()
    if isElement(pickedObj) then setElementAlpha(pickedObj, 255) end
    picked, pickedObj = nil, nil
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

local function cursorRay()
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    if not cx then return false end
    local sw, sh = guiGetScreenSize()
    local camX, camY, camZ = getCameraMatrix()
    local fx, fy, fz = getWorldFromScreenPosition(cx * sw, cy * sh, OFFICE.rayLength)
    if not fx then return false end
    local hit, hx, hy, hz, el = processLineOfSight(camX, camY, camZ, fx, fy, fz,
        true, false, false, true, false, false, false, false, ghost)
    if not hit then return false end
    return hx, hy, hz, el
end

local function onRender()
    local hx, hy, hz, el = cursorRay()
    hoverObj = nil
    if hx then
        local id = pcId(el)
        if id and el ~= pickedObj then hoverObj = el end
        -- the origin on the surface: PC_1's visual base is its origin (its collision box starts
        -- 0.28 m higher, so the bounding box cannot be used here)
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
        if sx then
            dxDrawText(L("gov_office.ed.hover", { id = pcId(hoverObj) }), sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 200), 1, font, "center", "bottom")
            dxDrawText(L("gov_office.ed.hover", { id = pcId(hoverObj) }), sx, sy, sx, sy, tocolor(255, 210, 90), 1, font, "center", "bottom")
        end
    end

    local sw, sh = guiGetScreenSize()
    local head = picked and L("gov_office.ed.moving", { id = picked }) or L("gov_office.ed.new")
    local lines = head .. "\n" .. L("gov_office.ed.help") .. "\n" .. L("gov_office.ed.state", { rot = math.floor(rz + 0.5), lift = ("%.2f"):format(lift) })
    dxDrawRectangle(sw / 2 - 330, sh - 120, 660, 84, tocolor(0, 0, 0, 160))
    dxDrawText(lines, sw / 2 - 320, sh - 114, sw / 2 + 320, sh - 42, tocolor(255, 255, 255), 1, font, "center", "center", false, true)
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local stop

local function onKey(key, press)
    if not press then return end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        local dir = key == "mouse_wheel_up" and 1 or -1
        if getKeyState("lctrl") or getKeyState("rctrl") then
            lift = math.max(-2, math.min(2, lift + dir * OFFICE.heightStep))
        else
            local step = (getKeyState("lshift") or getKeyState("rshift")) and OFFICE.rotFine or OFFICE.rotStep
            rz = (rz + dir * step) % 360
        end
    elseif key == "mouse1" and isCursorShowing() then
        if spot then
            triggerServerEvent("gov_office:place", resourceRoot, picked or false, spot.x, spot.y, spot.z, rz)
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
        if hoverObj then triggerServerEvent("gov_office:delete", resourceRoot, pcId(hoverObj)) end
    elseif key == "c" then
        cursorOn = not cursorOn
        showCursor(cursorOn, false)
    elseif key == "backspace" then
        if picked then unpick() else stop() end
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

local function start()
    if active then return end
    active, rz, lift, cursorOn = true, 0, 0, true
    makeGhost()
    showCursor(true, false)
    for _, c in ipairs(WHEEL_CONTROLS) do toggleControl(c, false) end
    pcall(function() exports.ui_interactobject:setInteractionDisabled(true) end)
    addEventHandler("onClientRender", root, onRender)
    addEventHandler("onClientKey", root, onKey)
    alphaTimer = setTimer(restoreAlphas, 500, 0)
    notify("gov_office.ed.started")
end

--- fromServer: the server ended it (otherwise it is told, so /govpcs starts it again next time)
stop = function(fromServer)
    if not active then return end
    active = false
    if fromServer ~= true then triggerServerEvent("gov_office:stopEdit", resourceRoot) end
    unpick()
    restoreAlphas()
    if isTimer(alphaTimer) then killTimer(alphaTimer) end
    removeEventHandler("onClientRender", root, onRender)
    removeEventHandler("onClientKey", root, onKey)
    if isElement(ghost) then destroyElement(ghost) end
    ghost, spot, hoverObj = nil, nil, nil
    showCursor(false)
    for _, c in ipairs(WHEEL_CONTROLS) do toggleControl(c, true) end
    pcall(function() exports.ui_interactobject:setInteractionDisabled(false) end)
end

addEvent("gov_office:editor", true)
addEventHandler("gov_office:editor", resourceRoot, function(on)
    if on then start() else stop(true) end
end)

-- leaving the office / dying ends it locally; the server re-checks on every change anyway
addEventHandler("onClientPlayerWasted", localPlayer, function() stop() end)
addEventHandler("onClientResourceStop", resourceRoot, function() stop(true) end)
addEventHandler("onClientElementDimensionChange", localPlayer, function() stop() end)
addEventHandler("onClientElementInteriorChange", localPlayer, function() stop() end)
