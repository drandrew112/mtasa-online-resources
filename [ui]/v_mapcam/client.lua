-- v_mapcam (client): runs the cinematic camera. Server decides when (exports), this animates.
-- The HUD/minimap (v_radar, gated by "enableall") is hidden while the animation runs.

local HIGH        = 500            -- top altitude above the target
local MID         = { 250, 100 }   -- intermediate phase altitudes (descent order)
local PHASE_TIME  = 1100           -- ms per camera phase
local HOLD_TIME   = 500            -- ms hold at the top at the start of a spawn
local STREAM_WAIT = 900            -- ms to let the world stream in after a teleport
local CLOSE_DIST, CLOSE_UP = 5, 2

addEvent("v_mapcam:start", true)
addEvent("v_mapcam:preSpawn", true)
addEvent("v_mapcam:arrived", true)
addEvent("v_mapcam:stop", true)

local active, segs, idx, segStart, cur, from, arrivedFlag
local savedHud, holding

local function ease(t) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end

-- camera hovering h above (x,y,z), looking at it (small y offset avoids a degenerate straight-down matrix)
local function above(x, y, z, h)
    return { x, y - h * 0.02, z + h, x, y, z }
end

local function closeCam(x, y, z, rot)
    local r = math.rad(rot)
    return { x + math.sin(r) * CLOSE_DIST, y - math.cos(r) * CLOSE_DIST, z + CLOSE_UP, x, y, z + 0.6 }
end

local function hideHud()
    if savedHud == nil then savedHud = getElementData(localPlayer, "enableall") or false end
    setElementData(localPlayer, "enableall", false, false)
    pcall(function()
        if exports.v_radar:isPauseBigmapOpen() then exports.v_radar:closePauseBigmap() end
    end)
end

local function restoreHud()
    if savedHud ~= nil then
        setElementData(localPlayer, "enableall", savedHud, false)
        savedHud = nil
    end
end

local onRender

local function cleanup()
    if active then removeEventHandler("onClientRender", root, onRender) end
    active, segs, idx, holding = false, nil, nil, false
    toggleAllControls(true)
    restoreHud()
    setCameraTarget(localPlayer)
end

local function finish()
    cleanup()
    triggerServerEvent("v_mapcam:done", resourceRoot)
end

local function nextSeg()
    idx = idx + 1
    segStart = getTickCount()
    from = { unpack(cur) }
end

onRender = function()
    if not active then return end
    local s = segs[idx]
    if not s then return finish() end
    if s.fn then
        s.fn()
        return nextSeg()
    end
    if s.hold then return setCameraMatrix(unpack(cur)) end
    if s.waitFor then
        if arrivedFlag then return nextSeg() end
        return setCameraMatrix(unpack(cur))
    end
    local t = (getTickCount() - segStart) / s.dur
    if s.to then
        local k = ease(math.min(t, 1))
        for i = 1, 6 do cur[i] = lerp(from[i], s.to[i], k) end
    end
    setCameraMatrix(unpack(cur))
    if t >= 1 then nextSeg() end
end

local function go(list, startCam)
    if active and holding then
        holding = false
        segs, idx, arrivedFlag = list, 0, false
        cur = startCam
        nextSeg()
        return
    end
    if active then cleanup() end
    segs, idx, arrivedFlag = list, 0, false
    cur = startCam
    active = true
    hideHud()
    toggleAllControls(false, true, false)
    nextSeg()
    setCameraMatrix(unpack(cur))
    addEventHandler("onClientRender", root, onRender)
end

local function seg(to, dur) return { to = to, dur = dur or PHASE_TIME } end

addEventHandler("v_mapcam:preSpawn", resourceRoot, function(x, y, z)
    fadeCamera(true)
    go({ { hold = true } }, above(x, y, z, HIGH))
    holding = true
end)

addEventHandler("v_mapcam:start", resourceRoot, function(mode, x, y, z, rot)
    fadeCamera(true)
    local list = {}

    if mode == "spawn" then
        list[#list + 1] = { dur = HOLD_TIME }
        for _, h in ipairs(MID) do list[#list + 1] = seg(above(x, y, z, h)) end
        list[#list + 1] = seg(closeCam(x, y, z, rot), PHASE_TIME * 1.3)
        go(list, above(x, y, z, HIGH))
    else
        local cx, cy, cz, tx, ty, tz = getCameraMatrix()
        local ax, ay, az = getElementPosition(localPlayer)
        -- up in 3 phases
        list[#list + 1] = seg(above(ax, ay, az, MID[2]))
        list[#list + 1] = seg(above(ax, ay, az, MID[1]))
        list[#list + 1] = seg(above(ax, ay, az, HIGH))
        -- fly over to the destination
        local dist = getDistanceBetweenPoints2D(ax, ay, x, y)
        list[#list + 1] = seg(above(x, y, z, HIGH), math.max(1500, math.min(4000, dist / 0.8)))
        list[#list + 1] = { fn = function() triggerServerEvent("v_mapcam:ready", resourceRoot) end }
        list[#list + 1] = { waitFor = true }
        list[#list + 1] = { dur = STREAM_WAIT }
        -- down in 3 phases
        list[#list + 1] = seg(above(x, y, z, MID[1]))
        list[#list + 1] = seg(above(x, y, z, MID[2]))
        list[#list + 1] = seg(closeCam(x, y, z, rot), PHASE_TIME * 1.3)
        go(list, { cx, cy, cz, tx, ty, tz })
    end
end)

addEventHandler("v_mapcam:arrived", resourceRoot, function() arrivedFlag = true end)

addEventHandler("v_mapcam:stop", resourceRoot, function()
    if active then cleanup() end
end)

-- invulnerable while the camera is running
addEventHandler("onClientPlayerDamage", localPlayer, function()
    if active or getElementData(localPlayer, "mapcam:active") then cancelEvent() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then cleanup() end
end)
