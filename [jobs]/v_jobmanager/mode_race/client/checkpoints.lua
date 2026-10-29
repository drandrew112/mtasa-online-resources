if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Race checkpoints drawn by the racer's own client. The server's GTA checkpoint marker is
-- invisible and only counts the hit (mode_race/server.lua).
--
--   current checkpoint: shader wall (fx/cp_wall.fx) + ground disc (fx/cp_ground.fx) + a 3D arrow
--                       above it that points at the next checkpoint (a chequered flag at the finish)
--   next checkpoint:    the same, faded, with a small arrow towards the one after it
--
-- One state is set per checkpoint (jobmanager:raceCp); nothing is rebuilt per frame except the
-- arrow's bobbing. Also used by v_jobcreator test runs through the client exports
-- raceCheckpointsShow(data) / raceCheckpointsClear().

local CP = {
    segments = 40,
    radiusScale = 0.5,              -- ring radius = checkpoint size * radiusScale
    heightScale = 0.9,              -- wall height = size * heightScale ...
    minHeight = 3, maxHeight = 9,   -- ... clamped
    arrowAbove = 1.6,               -- m above the wall top
    colour = { 255, 200, 0, 230 },
    finishColour = { 70, 220, 120, 230 },
    previewAlpha = 0.35,            -- the next checkpoint
    maxPitch = 35,                  -- arrow tilt towards a higher / lower next checkpoint
    drawDistance = 900,
}

local cos, sin, rad, sqrt, max, min = math.cos, math.sin, math.rad, math.sqrt, math.max, math.min
local TWO_PI = math.pi * 2

local state = nil       -- { main = drawable, preview = drawable | nil, blips = {} }
local wallShader, groundShader
local shadersTried = false
local rendering = false
local render

local function ensureShaders()
    if shadersTried then return wallShader ~= nil end
    shadersTried = true
    wallShader = dxCreateShader("mode_race/fx/cp_wall.fx")
    groundShader = dxCreateShader("mode_race/fx/cp_ground.fx")
    if not wallShader or not groundShader then
        if isElement(wallShader) then destroyElement(wallShader) end
        if isElement(groundShader) then destroyElement(groundShader) end
        wallShader, groundShader = nil, nil
        outputDebugString("[v_jobmanager] checkpoint shaders failed, drawing plain gradients", 2)
    end
    return wallShader ~= nil
end

local function groundZ(x, y, z)
    local hit, _, _, hz = processLineOfSight(x, y, z + 2, x, y, z - 12, true, false, false, true, false, false, false, false)
    return hit and hz or (z - 1)
end

-- p = {x, y, z, size}; target = the point the arrow points at (nil: finish flag)
local function build(p, target, isFinish, alphaMul, arrowScale)
    local base = isFinish and CP.finishColour or CP.colour
    local a = base[4] * alphaMul
    local colour = tocolor(base[1], base[2], base[3], a)
    local fade = tocolor(base[1], base[2], base[3], 0)
    local size = p[4] or 5
    local x, y = p[1], p[2]
    local gz = groundZ(x, y, p[3])
    local radius = size * CP.radiusScale
    local height = max(CP.minHeight, min(CP.maxHeight, size * CP.heightScale))
    local wall, ground = {}, { { x, y, gz + 0.04, colour, 0, 0 } }
    for i = 0, CP.segments do
        local t = i / CP.segments
        local ang = t * TWO_PI
        local px, py = x + cos(ang) * radius, y + sin(ang) * radius
        wall[#wall + 1] = { px, py, gz, colour, t, 0 }
        wall[#wall + 1] = { px, py, gz + height, wallShader and colour or fade, t, 1 }
        ground[#ground + 1] = { px, py, gz + 0.04, colour, t, 1 }
    end
    local d = {
        x = x, y = y, gz = gz, height = height, wall = wall, ground = ground, isFinish = isFinish,
        rgb = base, alpha = a, arrowScale = arrowScale * min(1.6, max(0.8, size / 5)),
    }
    if target and not isFinish then
        local dx, dy, dz = target[1] - x, target[2] - y, target[3] - p[3]
        d.yaw = math.atan2(dy, dx)
        local horizontal = sqrt(dx * dx + dy * dy)
        d.pitch = max(-rad(CP.maxPitch), min(rad(CP.maxPitch), math.atan2(dz, max(horizontal, 0.01))))
    end
    return d
end

--------------------------------------------------------------------------------
-- arrow + flag meshes (vertex coloured, dxDrawPrimitive3D)
--------------------------------------------------------------------------------

-- arrow outline in its own plane: x = right, y = forward; extruded by THICK
local ARROW = { { -0.16, -0.55 }, { 0.16, -0.55 }, { 0.16, 0.05 }, { 0.36, 0.05 }, { 0, 0.55 }, { -0.36, 0.05 }, { -0.16, 0.05 } }
local ARROW_TRIS = { { 1, 2, 3 }, { 1, 3, 7 }, { 6, 4, 5 } }
local THICK = 0.14

local function shade(rgb, k, a)
    return tocolor(min(255, rgb[1] * k), min(255, rgb[2] * k), min(255, rgb[3] * k), a)
end

local function drawArrow(d, cx, cy, cz, scale)
    local cy_, sy_ = cos(d.yaw), sin(d.yaw)
    local cp, sp = cos(d.pitch), sin(d.pitch)
    local f = { cp * cy_, cp * sy_, sp }            -- forward
    local r = { sy_, -cy_, 0 }                      -- right
    local u = { r[2] * f[3] - r[3] * f[2], r[3] * f[1] - r[1] * f[3], r[1] * f[2] - r[2] * f[1] }  -- up
    local function at(lx, ly, lz)
        lx, ly, lz = lx * scale, ly * scale, lz * scale
        return cx + r[1] * lx + f[1] * ly + u[1] * lz, cy + r[2] * lx + f[2] * ly + u[2] * lz, cz + r[3] * lx + f[3] * ly + u[3] * lz
    end
    local a = d.alpha
    local top, bottom, side = shade(d.rgb, 1.15, a), shade(d.rgb, 0.55, a), shade(d.rgb, 0.8, a)
    local verts = {}
    local function tri(p1, p2, p3, col)
        verts[#verts + 1] = { p1[1], p1[2], p1[3], col }
        verts[#verts + 1] = { p2[1], p2[2], p2[3], col }
        verts[#verts + 1] = { p3[1], p3[2], p3[3], col }
    end
    local upper, lower = {}, {}
    for i, p in ipairs(ARROW) do
        upper[i] = { at(p[1], p[2], THICK / 2) }
        lower[i] = { at(p[1], p[2], -THICK / 2) }
    end
    for _, t in ipairs(ARROW_TRIS) do
        tri(upper[t[1]], upper[t[2]], upper[t[3]], top)
        tri(lower[t[1]], lower[t[3]], lower[t[2]], bottom)
    end
    for i = 1, #ARROW do
        local j = i % #ARROW + 1
        tri(upper[i], upper[j], lower[j], side)
        tri(upper[i], lower[j], lower[i], side)
    end
    dxDrawPrimitive3D("trianglelist", false, unpack(verts))
end

-- chequered flag on a pole, turned towards the camera
local function drawFlag(d, cx, cy, cz, scale)
    local camX, camY = getCameraMatrix()
    local yaw = math.atan2(camY - cy, camX - cx) + math.pi / 2
    local rx, ry = cos(yaw), sin(yaw)
    local a = d.alpha
    local white, black, pole = tocolor(255, 255, 255, a), tocolor(20, 20, 20, a), tocolor(200, 200, 200, a)
    local w, h, cols, rows = 1.6 * scale, 1.0 * scale, 6, 4
    local x0, y0, z0 = cx - rx * w / 2, cy - ry * w / 2, cz
    local verts = {}
    local function quad(u0, v0, u1, v1, col)
        local ax, ay, az = x0 + rx * u0, y0 + ry * u0, z0 + v0
        local bx, by = x0 + rx * u1, y0 + ry * u1
        local cz1 = z0 + v1
        verts[#verts + 1] = { ax, ay, az, col }
        verts[#verts + 1] = { bx, by, az, col }
        verts[#verts + 1] = { bx, by, cz1, col }
        verts[#verts + 1] = { ax, ay, az, col }
        verts[#verts + 1] = { bx, by, cz1, col }
        verts[#verts + 1] = { ax, ay, cz1, col }
    end
    local t = getTickCount() / 300
    for i = 0, cols - 1 do
        for j = 0, rows - 1 do
            -- a little wave along the flag
            local wave = sin(t + i * 0.9) * 0.04 * scale
            quad(i * w / cols, j * h / rows + wave, (i + 1) * w / cols, (j + 1) * h / rows + wave, (i + j) % 2 == 0 and white or black)
        end
    end
    quad(-0.06 * scale, -1.4 * scale, 0, h, pole)
    dxDrawPrimitive3D("trianglelist", false, unpack(verts))
end

local function drawOne(d, camX, camY, camZ)
    local dx, dy = d.x - camX, d.y - camY
    if dx * dx + dy * dy > CP.drawDistance * CP.drawDistance then return end
    if wallShader then
        dxDrawMaterialPrimitive3D("trianglefan", groundShader, false, unpack(d.ground))
        dxDrawMaterialPrimitive3D("trianglestrip", wallShader, false, unpack(d.wall))
    else
        dxDrawPrimitive3D("trianglestrip", false, unpack(d.wall))
    end
    local bob = sin(getTickCount() / 420) * 0.25
    local az = d.gz + d.height + CP.arrowAbove + bob
    if d.isFinish then
        drawFlag(d, d.x, d.y, az, d.arrowScale)
    elseif d.yaw then
        drawArrow(d, d.x, d.y, az, d.arrowScale * 3.2)
    end
end

render = function()
    if not state then return end
    local camX, camY, camZ = getCameraMatrix()
    if state.preview then drawOne(state.preview, camX, camY, camZ) end
    drawOne(state.main, camX, camY, camZ)
    if state.flashUntil then
        local left = state.flashUntil - getTickCount()
        if wallShader then dxSetShaderValue(wallShader, "gFlash", left > 0 and left / 400 or 0) end
        if left <= 0 then state.flashUntil = nil end
    end
end

local function setRendering(on)
    if on == rendering then return end
    rendering = on
    if on then addEventHandler("onClientRender", root, render) else removeEventHandler("onClientRender", root, render) end
end

local function clearBlips()
    if not state then return end
    for _, blip in ipairs(state.blips) do if isElement(blip) then destroyElement(blip) end end
    state.blips = {}
end

local function blipAt(p, size, r, g, b, a)
    local blip = createBlip(p[1], p[2], p[3], 0, size, r, g, b, a)
    if blip then setElementDimension(blip, getElementDimension(localPlayer)) end
    return blip
end

-- data = { cp, isFinish, next, nextFinish, after } (points {x, y, z, size}); false clears
function raceCheckpointsShow(data)
    clearBlips()
    if type(data) ~= "table" or type(data.cp) ~= "table" then
        state = nil
        setRendering(false)
        return true
    end
    ensureShaders()
    local main = build(data.cp, data.next or nil, data.isFinish, 1, 1)
    local preview
    if data.next and not data.isFinish then
        preview = build(data.next, data.after or nil, data.nextFinish, CP.previewAlpha, 0.7)
    end
    state = { main = main, preview = preview, blips = {}, flashUntil = getTickCount() + 400 }
    local col = data.isFinish and CP.finishColour or CP.colour
    state.blips[1] = blipAt(data.cp, 3, col[1], col[2], col[3], 255)
    if data.next and not data.isFinish then state.blips[2] = blipAt(data.next, 1, col[1], col[2], col[3], 150) end
    setRendering(true)
    return true
end

function raceCheckpointsClear()
    return raceCheckpointsShow(false)
end

addEvent("jobmanager:raceCp", true)
addEventHandler("jobmanager:raceCp", resourceRoot, function(data)
    raceCheckpointsShow(data)
end)

addEvent("jobmanager:raceCpHit", true)
addEventHandler("jobmanager:raceCpHit", resourceRoot, function(isFinish)
    playSoundFrontEnd(isFinish and 45 or 43)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    clearBlips()
end)
