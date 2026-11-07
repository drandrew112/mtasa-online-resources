-- Mouse control of the interaction / temp menus.
--
-- While a menu is open (and MenuState.mouse ~= false) the cursor is shown:
--   * hovering a row selects it (only when the cursor moved, so a resting cursor
--     never fights the keyboard; a long list does not scroll under the cursor)
--   * left click = ENTER; on a "< value >" row the arrows step the value
--   * left click on the arrow bar under the list = up / down
--   * mouse wheel over the menu = up / down
--   * right click = BACKSPACE (back / close)
-- createTempMenu{ mouse = false } opts out (e.g. v_jobcreator: mouse1 / mouse2
-- place and look in its freecam). Controls are left to ui_core toggleMoveControls.

InacMouse = {}

local zones = {}           -- rebuilt every drawn frame: { x, y, w, h, hover = fn(), click = fn(cx, cy) }
local rect  = nil          -- whole menu box of the last frame { x, y, w, h }
local cursorShown = false
local lastX, lastY = false, false

local function enabled()
    return MenuState.open and MenuState.mouse ~= false
end

local function cursorPos()
    if not isCursorShowing() then return nil end
    local rx, ry = getCursorPosition()
    if not rx then return nil end
    local sw, sh = guiGetScreenSize()
    return rx * sw, ry * sh
end

local function inside(r, cx, cy)
    return r and cx >= r.x and cx <= r.x + r.w and cy >= r.y and cy <= r.y + r.h
end

local function zoneAt(cx, cy)
    for i = #zones, 1, -1 do
        if inside(zones[i], cx, cy) then return zones[i] end
    end
end

-- shows / hides our cursor to match the menu state (per resource in MTA)
function InacMouse.sync()
    local want = enabled() and true or false
    if want == cursorShown then return end
    cursorShown = want
    showCursor(want, false)
    lastX, lastY = false, false
    if not want then zones, rect = {}, nil end
end

function InacMouse.beginFrame()
    zones = {}
    rect = nil
end

function InacMouse.addZone(x, y, w, h, handlers)
    if not enabled() then return end
    handlers.x, handlers.y, handlers.w, handlers.h = x, y, w, h
    zones[#zones + 1] = handlers
end

function InacMouse.setRect(x, y, w, h)
    rect = { x = x, y = y, w = w, h = h }
end

-- after the frame was drawn: hover selects the row under a moved cursor
function InacMouse.endFrame()
    InacMouse.sync()
    if not enabled() then return end
    local cx, cy = cursorPos()
    if not cx then return end
    if lastX == false then lastX, lastY = cx, cy return end
    if cx == lastX and cy == lastY then return end
    lastX, lastY = cx, cy
    local z = zoneAt(cx, cy)
    if z and z.hover then z.hover() end
end

-- exports.ui_inac:isMouseOverMenu() - true while the cursor is over an open,
-- mouse-enabled menu (camera scripts skip their drag / zoom then)
function isMouseOverMenu()
    if not enabled() then return false end
    local cx, cy = cursorPos()
    return cx and inside(rect, cx, cy) or false
end

local function typing()
    return getElementData(localPlayer, "showChatInput") or getElementData(localPlayer, "textInputOpen")
end

addEventHandler("onClientClick", root, function(button, state, cx, cy)
    if state ~= "up" or not enabled() or typing() then return end
    if button == "right" then
        MenuState.mouseScroll = false
        InacNav.back()
    elseif button == "left" then
        local z = zoneAt(cx, cy)
        if z and z.click then z.click(cx, cy) end
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not press or (key ~= "mouse_wheel_up" and key ~= "mouse_wheel_down") then return end
    if not enabled() or typing() or not isMouseOverMenu() then return end
    cancelEvent()
    MenuState.mouseScroll = false
    InacNav.move(key == "mouse_wheel_up" and -1 or 1)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if cursorShown then showCursor(false, false) end
end)
