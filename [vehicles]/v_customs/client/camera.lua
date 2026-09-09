-- v_customs :: free orbit camera (client)
--
-- While the workshop menu is open the player owns the camera: hold the left
-- mouse button and drag to orbit the vehicle, mouse wheel to zoom. Nothing
-- moves on its own.

CustomsCam = { veh = nil, yaw = 0, pitch = 18, dist = 6, running = false }

local DRAG_SPEED = 0.35
local MIN_DIST, MAX_DIST = 3.0, 12.0
local MIN_PITCH, MAX_PITCH = -12, 82

local function render()
    local veh = CustomsCam.veh
    if not isElement(veh) then return end

    local vx, vy, vz = getElementPosition(veh)
    vz = vz + 0.35

    local yaw   = math.rad(CustomsCam.yaw)
    local pitch = math.rad(CustomsCam.pitch)
    local horiz = math.cos(pitch) * CustomsCam.dist

    local cx = vx + math.cos(yaw) * horiz
    local cy = vy + math.sin(yaw) * horiz
    local cz = vz + math.sin(pitch) * CustomsCam.dist

    setCameraMatrix(cx, cy, cz, vx, vy, vz)
end

local lastX, lastY = nil, nil
local function onMove(_, _, absX, absY)
    if not CustomsCam.running then return end
    if not getKeyState("mouse1") then lastX, lastY = absX, absY return end
    if lastX then
        CustomsCam.yaw   = (CustomsCam.yaw - (absX - lastX) * DRAG_SPEED) % 360
        CustomsCam.pitch = math.max(MIN_PITCH, math.min(MAX_PITCH,
            CustomsCam.pitch + (absY - lastY) * DRAG_SPEED))
    end
    lastX, lastY = absX, absY
end

local function onWheel(key)
    if not CustomsCam.running then return end
    local step = key == "mouse_wheel_up" and -1 or 1
    CustomsCam.dist = math.max(MIN_DIST, math.min(MAX_DIST, CustomsCam.dist + step))
end

function CustomsCam.start(veh)
    CustomsCam.veh   = veh
    local _, _, rot  = getElementRotation(veh)
    CustomsCam.yaw   = (rot + 135) % 360   -- start looking at the front-left 3/4
    CustomsCam.pitch = 18
    CustomsCam.dist  = 6

    if not CustomsCam.running then
        CustomsCam.running = true
        addEventHandler("onClientPreRender", root, render)
        addEventHandler("onClientCursorMove", root, onMove)
        bindKey("mouse_wheel_up", "down", onWheel)
        bindKey("mouse_wheel_down", "down", onWheel)
    end
    showCursor(true)
end

function CustomsCam.stop()
    if CustomsCam.running then
        CustomsCam.running = false
        removeEventHandler("onClientPreRender", root, render)
        removeEventHandler("onClientCursorMove", root, onMove)
        unbindKey("mouse_wheel_up", "down", onWheel)
        unbindKey("mouse_wheel_down", "down", onWheel)
    end
    showCursor(false)
    CustomsCam.veh = nil
    setCameraTarget(localPlayer)
end
