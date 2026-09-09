-- v_customs :: showroom camera (client)
--
-- A fixed 3/4 view of the vehicle's front-left corner while the workshop menu is
-- open. Menu categories can name a `camera` preset (shared/tuning.lua); hovering
-- an item slides the camera to that preset. Nothing rotates on its own.

CustomsCam = { veh = nil, cur = nil, target = nil, moveTick = 0, running = false }

-- offset / lookAt are in vehicle space: x = right, y = forward, z = up.
local PRESETS = {
    front      = { offset = { -2.8,  3.2, 1.1 }, look = {  0.0,  0.6,  0.4 } },
    engine     = { offset = { -2.0,  2.9, 1.3 }, look = {  0.0,  1.6,  0.5 } },
    boot       = { offset = { -2.0, -3.0, 1.3 }, look = {  0.0, -1.6,  0.5 } },
    side       = { offset = { -3.3,  0.0, 1.0 }, look = {  0.0,  0.0,  0.4 } },
    under      = { offset = { -3.0,  2.0, 0.5 }, look = {  0.0,  0.0, -0.1 } },
    wheel_rf   = { offset = { -2.3,  1.5, 0.7 }, look = { -0.9,  1.2,  0.1 } },
    wheel_rb   = { offset = { -2.3, -1.7, 0.7 }, look = { -0.9, -1.4,  0.1 } },
    bump_front = { offset = { -1.5,  3.7, 0.8 }, look = {  0.0,  2.1,  0.2 } },
    bump_rear  = { offset = { -1.5, -3.7, 0.8 }, look = {  0.0, -2.1,  0.2 } },
}

local function offsetToWorld(veh, o)
    local m = getElementMatrix(veh)
    return
        o[1] * m[1][1] + o[2] * m[2][1] + o[3] * m[3][1] + m[4][1],
        o[1] * m[1][2] + o[2] * m[2][2] + o[3] * m[3][2] + m[4][2],
        o[1] * m[1][3] + o[2] * m[2][3] + o[3] * m[3][3] + m[4][3]
end

function CustomsCam.start(veh)
    CustomsCam.veh    = veh
    CustomsCam.cur    = "front"
    CustomsCam.target = "front"
    CustomsCam.moveTick = getTickCount()
    if not CustomsCam.running then
        addEventHandler("onClientPreRender", root, CustomsCam.render)
        CustomsCam.running = true
    end
end

function CustomsCam.stop()
    if CustomsCam.running then
        removeEventHandler("onClientPreRender", root, CustomsCam.render)
        CustomsCam.running = false
    end
    CustomsCam.veh = nil
    setCameraTarget(localPlayer)
end

function CustomsCam.to(preset)
    if not PRESETS[preset] then preset = "front" end
    if preset == CustomsCam.target then return end
    CustomsCam.cur      = preset          -- snap (simple + reliable); no easing
    CustomsCam.target   = preset
    CustomsCam.moveTick = getTickCount()
end

function CustomsCam.render()
    local veh = CustomsCam.veh
    if not isElement(veh) then return end

    local p = PRESETS[CustomsCam.cur] or PRESETS.front
    local cx, cy, cz = offsetToWorld(veh, p.offset)
    local lx, ly, lz = offsetToWorld(veh, p.look)
    setCameraMatrix(cx, cy, cz, lx, ly, lz)
end
