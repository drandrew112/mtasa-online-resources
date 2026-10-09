-- Coach windows: while the local player rides, shaders/windows.fx replaces the painted panes of
-- "mp_jet_wall" with the outside (DESIGN.md 4.2). This file feeds it every frame: scroll
-- positions from Ride.dist, sky / daylight / rain from the game, the environment class of the
-- coach's real position (Scenery) with a blend over RWP.WINDOWS.CLASS_BLEND metres on a change.

Windows = { tunnel = 0 }

local I = RWP.INTERIORS.coach
local W = RWP.WINDOWS
local L = Scenery.LAYERS

local shader
local cur, nxt               -- class ids: the shown set (0) and the one blending in (1)
local blend, blendStart = 0, 0
local tunnel = 0
local lastClassCheck = 0
local failed = false

local function setSet(slot, id)
    local s = Scenery.get(id)
    if not s then return false end
    dxSetShaderValue(shader, "gFar" .. slot, s.far)
    dxSetShaderValue(shader, "gMid" .. slot, s.mid)
    dxSetShaderValue(shader, "gNear" .. slot, s.near)
    dxSetShaderValue(shader, "gGround" .. slot, s.ground[1], s.ground[2], s.ground[3])
    dxSetShaderValue(shader, "gDepth" .. slot, s.groundDepth)
    return true
end

local function start()
    if shader or failed or not W.ENABLED then return end
    shader = dxCreateShader("shaders/windows.fx", 0, 0, false, "world")
    if not shader then
        failed = true
        if DEBUG_ENABLED then outputDebugString("[rw_passengers] windows shader could not be created (needs shader model 3)", 2) end
        return
    end
    dxSetShaderValue(shader, "gCentreX", I.centreX)
    dxSetShaderValue(shader, "gFloorZ", I.floorZ)
    dxSetShaderValue(shader, "gLayerFar", L.far.dist, L.far.period, L.far.height)
    dxSetShaderValue(shader, "gLayerMid", L.mid.dist, L.mid.period, L.mid.height)
    dxSetShaderValue(shader, "gLayerNear", L.near.dist, L.near.period, L.near.height)
    engineApplyShaderToWorldTexture(shader, I.window.texture)
    cur, nxt, blend = nil, nil, 0
end

local function stop()
    if shader then
        engineRemoveShaderFromWorldTexture(shader, I.window.texture)
        destroyElement(shader)
    end
    shader, cur, nxt, blend = nil, nil, nil, 0
    Windows.tunnel = 0
end

local function frac(x) return x - math.floor(x) end

-- daylight from the game clock: full day 8-19 h, night 21-5 h, ramps between
local function daylight()
    local h, m = getTime()
    local t = h + m / 60
    local day
    if t >= 8 and t <= 19 then day = 1
    elseif t >= 21 or t <= 5 then day = 0
    elseif t > 5 and t < 8 then day = (t - 5) / 3
    else day = 1 - (t - 19) / 2 end
    return day
end

addEventHandler("onClientPreRender", root, function(dt)
    if not Ride.active then
        if shader then stop() end
        return
    end
    start()
    if not shader then return end

    -- environment class of the coach's real position
    local now = getTickCount()
    if now - lastClassCheck > 1000 then
        lastClassCheck = now
        local id = Scenery.classAt(Ride.x, Ride.y, Ride.z)
        if not cur then
            if setSet(0, id) and setSet(1, id) then cur, nxt, blend = id, id, 0 end
        elseif id ~= nxt and id ~= cur and blend == 0 then
            if setSet(1, id) then nxt, blend, blendStart = id, 0.0001, Ride.dist end
        end
    end
    if not cur then return end

    -- blend by distance travelled (or by time while standing)
    if blend > 0 then
        local byDist = math.abs(Ride.dist - blendStart) / W.CLASS_BLEND
        blend = math.min(1, math.max(blend + dt / 2500, byDist))
        if blend >= 1 then
            setSet(0, nxt)
            cur, blend = nxt, 0
        end
    end
    dxSetShaderValue(shader, "gBlend", blend)

    -- tunnel factor follows the classes, smoothed
    local tc = (Scenery.get(cur) or {}).tunnel or 0
    local tn = (Scenery.get(nxt or cur) or {}).tunnel or 0
    local target = tc + (tn - tc) * blend
    tunnel = tunnel + (target - tunnel) * math.min(1, dt / 300)
    Windows.tunnel = tunnel
    dxSetShaderValue(shader, "gTunnel", tunnel)

    -- scrolling (fractions of each period, computed here in double precision)
    local d = Ride.dist
    dxSetShaderValue(shader, "gScrollFar", frac(d / L.far.period))
    dxSetShaderValue(shader, "gScrollMid", frac(d / L.mid.period))
    dxSetShaderValue(shader, "gScrollNear", frac(d / L.near.period))
    dxSetShaderValue(shader, "gScrollLamp", frac(d / 25))
    local blur = math.min(math.abs(Ride.vNow) / 40, 1) * 0.012 * (W.BLUR_TAPS / 4)
    dxSetShaderValue(shader, "gBlur", Ride.vNow >= 0 and blur or -blur)

    -- sky, light, weather
    local r1, g1, b1, r2, g2, b2 = getSkyGradient()
    dxSetShaderValue(shader, "gSkyTop", r1 / 255, g1 / 255, b1 / 255)
    dxSetShaderValue(shader, "gSkyBot", r2 / 255, g2 / 255, b2 / 255)
    local day = daylight()
    local rain = math.min(1, getRainLevel() or 0)
    dxSetShaderValue(shader, "gLight", 0.22 + 0.78 * day * (1 - rain * 0.3))
    dxSetShaderValue(shader, "gNight", 1 - day)
    dxSetShaderValue(shader, "gRain", rain)
    dxSetShaderValue(shader, "gTime", now / 1000 % 1000)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stop()
    Scenery.clear()
end)
