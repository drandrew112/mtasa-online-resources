-- Free camera. WASD move, Q/E down/up, Shift fast, Alt slow. The cursor is shown
-- for picking; holding the right mouse button looks around. The player rides
-- invisibly with the camera so the world (and the server's view of us) streams in.

Freecam = { active = false }

local F = CREATOR.FREECAM
local x, y, z, yaw, pitch = 0, 0, 0, 0, 0
local looking = false
local skipMoves = 0     -- the first cursor events after hiding the cursor jump

local function lookAt()
    local cp = math.cos(pitch)
    return x + math.cos(yaw) * cp, y + math.sin(yaw) * cp, z + math.sin(pitch)
end

function Freecam.setPosition(nx, ny, nz)
    x, y, z = nx, ny, nz
end

function Freecam.getPosition()
    return x, y, z
end

local function onCursorMove(_, _, ax, ay)
    if not looking or isCursorShowing() or inputBlocked() then return end
    if skipMoves > 0 then skipMoves = skipMoves - 1 return end
    local sw, sh = guiGetScreenSize()
    local dx, dy = ax - sw / 2, ay - sh / 2
    yaw = yaw - dx * F.sensitivity * 0.01
    pitch = math.max(-1.5, math.min(1.5, pitch - dy * F.sensitivity * 0.01))
end

local function onFrame(dt)
    local factor = dt / 16.7
    if not inputBlocked() then
        local speed = F.speed
        if getKeyState("lshift") then speed = F.fast elseif getKeyState("lalt") then speed = F.slow end
        speed = speed * factor
        local fx, fy, fz = math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch)
        local rx, ry = math.cos(yaw - math.pi / 2), math.sin(yaw - math.pi / 2)
        if getKeyState("w") then x, y, z = x + fx * speed, y + fy * speed, z + fz * speed end
        if getKeyState("s") then x, y, z = x - fx * speed, y - fy * speed, z - fz * speed end
        if getKeyState("d") then x, y = x + rx * speed, y + ry * speed end
        if getKeyState("a") then x, y = x - rx * speed, y - ry * speed end
        if getKeyState("e") then z = z + speed end
        if getKeyState("q") then z = z - speed end
    end

    -- hold the look button: hide the cursor and turn
    -- photo mode has no cursor: always looking
    local wantLook = (Editor.photo or getKeyState(CREATOR.KEYS.look)) and not inputBlocked()
    if wantLook ~= looking then
        looking = wantLook
        skipMoves = 3
        if not Editor.photo then showCursor(not looking) end
    end

    local hold = Freecam.hold
    if hold and getTickCount() < hold.untilTick then
        setCameraMatrix(unpack(hold.matrix))
    else
        Freecam.hold = nil
        local lx, ly, lz = lookAt()
        setCameraMatrix(x, y, z, lx, ly, lz)
    end
    setElementPosition(localPlayer, x, y, z - 3, false)
end

function Freecam.start()
    if Freecam.active then return end
    local cx, cy, cz, lx, ly, lz = getCameraMatrix()
    x, y, z = cx, cy, cz
    yaw = math.atan2(ly - cy, lx - cx)
    pitch = math.atan2(lz - cz, math.sqrt((lx - cx) ^ 2 + (ly - cy) ^ 2))
    Freecam.active, looking = true, false
    Editor.camMode = "free"
    toggleAllControls(false, true, false)
    setElementFrozen(localPlayer, true)
    setElementCollisionsEnabled(localPlayer, false)
    setElementAlpha(localPlayer, 0)
    iobj:setInteractionDisabled(true)
    if not Editor.photo then showCursor(true) end
    addEventHandler("onClientPreRender", root, onFrame)
    addEventHandler("onClientCursorMove", root, onCursorMove)
end

-- keepPlayer: leave the player where it is (closing the creator, the server restores it)
function Freecam.stop(keepPlayer)
    if not Freecam.active then return end
    Freecam.active = false
    Editor.camMode = "foot"
    removeEventHandler("onClientPreRender", root, onFrame)
    removeEventHandler("onClientCursorMove", root, onCursorMove)
    showCursor(false)
    if not keepPlayer then
        -- drop the player onto whatever is below the camera
        local hit, _, _, hz = processLineOfSight(x, y, z, x, y, z - 500, true, true, false, true, false, false, false, false)
        local groundZ = hit and hz or getGroundPosition(x, y, z) or z
        setElementPosition(localPlayer, x, y, groundZ + 1)
        setElementRotation(localPlayer, 0, 0, math.deg(yaw) - 90, "default", true)
    end
    setElementFrozen(localPlayer, false)
    setElementCollisionsEnabled(localPlayer, true)
    setElementAlpha(localPlayer, 255)
    toggleAllControls(true, true, false)
    setCameraTarget(localPlayer)
    iobj:setInteractionDisabled(false)
end

function Freecam.toggle()
    if Freecam.active then Freecam.stop() else Freecam.start() end
end
