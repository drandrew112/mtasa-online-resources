if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Trains on the client: places every car of every train each frame from the server snapshots
-- (extrapolated with v / a, errors blended out), runs the driver's input and HUD and the
-- passengers' camera. Other client files read the train list through TrainsClient.

TrainsClient = {}

local C = NET.CLIENT
local trains = {}          -- [id] = { snap fields..., path, t (receive tick), corr, corrT, poses, us }
local offset               -- server tick -> local tick
local input = { w = false, s = false }
local hudEnabled = true      -- rw_loco switches it off: its cab panel shows the same
local sx, sy = guiGetScreenSize()

function TrainsClient.list() return trains end

-- Per-frame train handlers (placement here, sweeper, sounds): attached only while the network is
-- ready and there is a train. Each one runs once more after removal, with the empty list, to clean
-- up (sounds stop their loops).
local frames, framesOn = {}, false

function TrainsClient.onFrame(eventName, fn)
    frames[#frames + 1] = { eventName, fn }
    if framesOn then addEventHandler(eventName, root, fn) end
end

local function syncFrames()
    local on = NetClient.ready and next(trains) ~= nil
    if on == framesOn then return end
    framesOn = on
    for _, h in ipairs(frames) do
        if on then
            addEventHandler(h[1], root, h[2])
        else
            removeEventHandler(h[1], root, h[2])
            h[2]()
        end
    end
end

local updateRideCamera

local function serverNow(now) return now - (offset or 0) end

-- head u of a train at local tick `now`
local function extrapolate(t, now)
    local dt = (serverNow(now) - t.T) / 1000
    if dt < 0 then dt = 0 elseif dt > 2 then dt = 2 end
    local v = t.v + t.a * dt
    if t.v ~= 0 and (v > 0) ~= (t.v > 0) then dt = -t.v / t.a v = 0 end   -- braking to a stop
    return t.u + t.v * dt + 0.5 * t.a * dt * dt, v
end

local function headU(t, now)
    local u, v = extrapolate(t, now)
    return u + t.corr * math.max(0, 1 - (now - t.corrT) / C.CORR_MS), v
end

addEvent("rw:net:trains", true)
addEventHandler("rw:net:trains", resourceRoot, function(list)
    local now = getTickCount()
    local seen = {}
    for _, s in ipairs(list) do
        local o = now - s.T
        if not offset or o < offset then offset = o else offset = offset + math.min(1, o - offset) end
    end
    for _, s in ipairs(list) do
        seen[s.id] = true
        local old = trains[s.id]
        s.path = TrainPath.from(s.path)
        s.corr, s.corrT = 0, now
        if old and NetClient.ready then
            local d = headU(old, now) - extrapolate(s, now)
            if math.abs(d) < 15 then s.corr = d end
        end
        s.poses = old and old.poses or {}
        s.joints = old and old.joints or {}
        for k, c in ipairs(s.cars) do
            local def = NET.STOCK[c[2]]
            s.cars[k] = { el = c[1], type = c[2], def = def, offset = c[3], flip = c[4] }
        end
        trains[s.id] = s
    end
    for id in pairs(trains) do if not seen[id] then trains[id] = nil end end
    syncFrames()
    updateRideCamera()
end)

addEventHandler("rw:net:onClientNetworkReady", resourceRoot, function() syncFrames() end)

-- Not cached per model: a mod loader (v_modloader streak.dff) can replace the model after the
-- train streamed in, and a stale value from the original model left the BR 232 floating above the
-- rails until reconnect. PERF: re-read once a second per car instead of every frame.
local BASE_REFRESH = 1000
local baseCache = {}       -- [element] = { value, tick }
local function baseOf(el, def, now)
    local c = baseCache[el]
    if c and now - c[2] < BASE_REFRESH then return c[1] end
    local b = getElementDistanceFromCentreOfMassToBaseOfModel(el)
    if not (b and b > 0.05) then b = def.base end
    if c then c[1], c[2] = b, now else baseCache[el] = { b, now } end
    return b
end

-- one matrix table per car, reused every frame (PERF: no new tables per car per frame)
local matrices = {}        -- [element] = 4x4 table
local function matrixOf(el)
    local m = matrices[el]
    if not m then
        m = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 1 } }
        matrices[el] = m
    end
    return m
end

addEventHandler("onClientElementDestroy", root, function()
    if baseCache[source] then baseCache[source] = nil end
    if matrices[source] then matrices[source] = nil end
end)

-- ------------------------------------------------------------------ placement

TrainsClient.onFrame("onClientPreRender", function()
    local now = getTickCount()
    for _, t in pairs(trains) do
        local u, v = headU(t, now)
        -- the client may run ahead of the server's route: extend it with the local switch states
        local path = t.path
        if u + 5 > path:lastU() then path:extendFront(u + 30) end
        if u - t.length - 5 < path:firstU() then path:extendBack(u - t.length - 30) end
        if path.frontEnd and u > path.frontEnd - 0.3 then u = path.frontEnd - 0.3 end
        if path.backEnd and u - t.length < path.backEnd + 0.3 then u = path.backEnd + 0.3 + t.length end
        t.uNow, t.vNow = u, v
        for k, car in ipairs(t.cars) do
            local el = car.el
            if isElement(el) and isElementStreamedIn(el) then
                local x, y, z, fx, fy, fz = path:carPose(u - car.offset, car.def.bogie)
                if car.flip then fx, fy, fz = -fx, -fy, -fz end
                local rl = math.sqrt(fx * fx + fy * fy)
                if rl < 1e-4 then rl = 1 end
                local rx, ry = fy / rl, -fx / rl
                local ux, uy, uz = ry * fz, -rx * fz, rx * fy - ry * fx
                local cz = z + baseOf(el, car.def, now) + NET.RAIL_Z
                local m = matrixOf(el)
                local m1, m2, m3, m4 = m[1], m[2], m[3], m[4]
                m1[1], m1[2], m1[3] = rx, ry, 0
                m2[1], m2[2], m2[3] = fx, fy, fz
                m3[1], m3[2], m3[3] = ux, uy, uz
                m4[1], m4[2], m4[3] = x, y, cz
                setElementMatrix(el, m)
                local p = t.poses[k]
                if not p then p = {} t.poses[k] = p end
                p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8] = x, y, z, fx, fy, fz, rx, ry
            else
                t.poses[k] = nil
            end
        end
    end
end)

-- ------------------------------------------------------------------ tunnels (PERF)
-- A car in a tunnel is drawn (and placed every frame) for everyone above it within streaming range:
-- the game has no occlusion for vehicles below the street. While the camera is above ground, a car
-- that is underground (ground well above its rails) and that the camera cannot see (world line of
-- sight blocked) is moved into HIDE_DIM on this client only: it streams out, nothing is drawn or
-- placed. It comes back as soon as the camera could see it. The local player's own train is never
-- hidden. The simulation, sync and the train itself are not touched (server side).
local HIDE_DIM = 65531
local HIDE_CHECK = 500         -- ms
local UNDER_DEPTH = 6          -- metres of ground above the rails = underground
local CAM_UNDER = 3            -- camera this far below the ground = in a tunnel / underground station
local HIDE_MIN_DIST = 30       -- never hide a car closer than this to the camera
local hiddenDim = {}           -- [element] = its own dimension while hidden

local function groundAbove(x, y, z)
    local g = getGroundPosition(x, y, z + 60)
    if g and g ~= 0 then return g - z end
    return nil
end

local function unhide(el)
    local dim = hiddenDim[el]
    hiddenDim[el] = nil
    if isElement(el) and dim then setElementDimension(el, dim) end
end

local function ownTrain(t)
    local veh = getPedOccupiedVehicle(localPlayer)
    local ride = getElementData(localPlayer, "rwn.ride")
    if ride and ride[1] == t.id then return true end
    if veh then
        for _, car in ipairs(t.cars) do if car.el == veh then return true end end
    end
    return false
end

local function tunnelCheck()
    local now = getTickCount()
    local cx, cy, cz = getCameraMatrix()
    local camDepth = groundAbove(cx, cy, cz)
    local camUnder = camDepth and camDepth > CAM_UNDER
    local seen = {}
    for _, t in pairs(trains) do
        local own = ownTrain(t)
        local u = t.uNow or headU(t, now)
        for _, car in ipairs(t.cars) do
            local el = car.el
            if isElement(el) then
                seen[el] = true
                local hide = false
                if not camUnder and not own then
                    local x, y, z = t.path:carPose(u - car.offset, car.def.bogie)
                    local dx, dy, dz = x - cx, y - cy, z - cz
                    if dx * dx + dy * dy + dz * dz > HIDE_MIN_DIST * HIDE_MIN_DIST then
                        local depth = groundAbove(x, y, z)
                        hide = depth ~= nil and depth > UNDER_DEPTH
                            and not isLineOfSightClear(cx, cy, cz, x, y, z + 2, true, false, false, true, false, true, false)
                    end
                end
                if hide and not hiddenDim[el] then
                    hiddenDim[el] = getElementDimension(el)
                    setElementDimension(el, HIDE_DIM)
                elseif not hide and hiddenDim[el] then
                    unhide(el)
                end
            end
        end
    end
    for el in pairs(hiddenDim) do
        if not seen[el] then unhide(el) end
    end
end

setTimer(function()
    if next(trains) then
        tunnelCheck()
    elseif next(hiddenDim) then
        for el in pairs(hiddenDim) do unhide(el) end
    end
end, HIDE_CHECK, 0)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for el in pairs(hiddenDim) do unhide(el) end
end)

-- ------------------------------------------------------------------ driver

local function myTrain()
    local veh = getPedOccupiedVehicle(localPlayer)
    local id = veh and getElementData(veh, "rwn.train")
    local t = id and trains[id]
    if t and t.driver == localPlayer then return t end
end

local function send(extra)
    local msg = { w = input.w, s = input.s }
    if extra then for k, v in pairs(extra) do msg[k] = v end end
    triggerServerEvent("rw:net:input", resourceRoot, msg)
end

-- input + HUD, attached only while the local player sits in a vehicle (myTrain() decides the rest)
local function driverFrame()
    local t = myTrain()
    local w, s = false, false
    if t and not isCursorShowing() and not isChatBoxInputActive() and not isMainMenuActive() then
        w, s = getKeyState("w"), getKeyState("s")
    end
    if w ~= input.w or s ~= input.s then
        input.w, input.s = w, s
        send()
    end
    if not t or not hudEnabled then return end

    -- HUD (bottom centre)
    local kmh = math.abs(t.vNow or t.v) * 3.6
    local bw, bh = 360, 92
    local x, y = (sx - bw) / 2, sy - bh - 30
    dxDrawRectangle(x, y, bw, bh, tocolor(10, 16, 30, 200))
    dxDrawText(L("rw_customtracks.trains.km_h", { kmh = kmh }), x + 14, y + 8, 0, 0, tocolor(255, 255, 255), 2, "default-bold")
    local revText = t.rev > 0 and L("rw_customtracks.trains.forward") or L("rw_customtracks.trains.reverse")
    dxDrawText(revText, x + bw - 14, y + 10, x + bw - 14, 0, tocolor(120, 200, 255), 1.2, "default-bold", "right")
    -- controller bar: centre = 0, right = power, left = brake
    local barX, barY, barW = x + 14, y + 52, bw - 28
    dxDrawRectangle(barX, barY, barW, 14, tocolor(40, 50, 70, 230))
    local mid = barX + barW / 2
    if t.ctrl > 0 then
        dxDrawRectangle(mid, barY, barW / 2 * t.ctrl, 14, tocolor(60, 200, 90))
    elseif t.ctrl < 0 then
        local col = t.emergency and tocolor(255, 40, 40) or tocolor(230, 150, 40)
        dxDrawRectangle(mid + barW / 2 * t.ctrl, barY, -barW / 2 * t.ctrl, 14, col)
    end
    dxDrawRectangle(mid - 1, barY - 2, 2, 18, tocolor(255, 255, 255))
    local label = t.emergency and L("rw_customtracks.trains.emergency_brake") or (t.ctrl > 0.01 and L("rw_customtracks.trains.power", { ctrl = t.ctrl * 100 }))
        or (t.ctrl < -0.01 and L("rw_customtracks.trains.brake", { ctrl = -t.ctrl * 100 })) or L("rw_customtracks.trains.semleges")
    local grade = t.path:grade((t.uNow or t.u) - t.length / 2) * 100
    local auth = ""
    if t.auth then
        local u = t.uNow or t.u
        local lead = t.auth[2] > 0 and u or u - t.length
        auth = L("rw_customtracks.trains.authority_m", { auth = math.max(0, (t.auth[1] - lead) * t.auth[2]), auth2 = tostring(t.auth[3]) })
    end
    dxDrawText(L("rw_customtracks.trains.gradient", { label = label, grade = grade, auth = auth }), x + 14, y + 70, 0, 0, tocolor(200, 210, 230), 1, "default")
    if t.atp then
        dxDrawText(L("rw_customtracks.trains.atp_braking"), x + bw - 14, y + 34, x + bw - 14, 0, tocolor(255, 80, 60), 1.2, "default-bold", "right")
    end
end

local driverOn = false
local function setDriverFrame(on)
    if on == driverOn then return end
    driverOn = on
    if on then
        addEventHandler("onClientRender", root, driverFrame)
    else
        removeEventHandler("onClientRender", root, driverFrame)
        if input.w or input.s then
            input.w, input.s = false, false
            send()
        end
    end
end
addEventHandler("onClientPlayerVehicleEnter", localPlayer, function() setDriverFrame(true) end, false)
addEventHandler("onClientPlayerVehicleExit", localPlayer, function() setDriverFrame(false) end, false)
addEventHandler("onClientPlayerWasted", localPlayer, function() setDriverFrame(false) end, false)
addEventHandler("onClientResourceStart", resourceRoot, function()
    setDriverFrame(isElement(getPedOccupiedVehicle(localPlayer)))
end)

bindKey("x", "down", function() if myTrain() then send({ x = true }) end end)
bindKey("r", "down", function() if myTrain() then send({ rev = true }) end end)

-- F leaves the cab / the car (the game's own exit is cancelled by the server)
bindKey("enter_exit", "down", function()
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh and getElementData(veh, "rw.consist") then return end      -- rw_loco's cab exit
    if myTrain() or getElementData(localPlayer, "rwn.ride") then
        triggerServerEvent("rw:net:leave", resourceRoot)
    end
end)

-- ------------------------------------------------------------------ passengers: camera on the car

-- re-checked when "rwn.ride" changes and on every train snapshot (the car may arrive later)
local riding
updateRideCamera = function()
    local r = getElementData(localPlayer, "rwn.ride")
    local t = r and trains[r[1]]
    local car = t and t.cars[r[2]]
    local el = car and car.el
    if el ~= riding then
        riding = el
        if isElement(el) then setCameraTarget(el) else setCameraTarget(localPlayer) end
    end
end
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "rwn.ride" then updateRideCamera() end
end, false)

addEvent("rw:net:left", true)
addEventHandler("rw:net:left", resourceRoot, function()
    riding = nil
    setCameraTarget(localPlayer)
end)

-- ------------------------------------------------------------------ client exports (rw_loco)

-- the train the local player drives -> { id, speed (m/s, +forward), ctrl, rev, emergency, atp,
-- authority = { remaining, reason } | false, cars = { elements } } | false
function netGetMyTrain()
    local t = myTrain()
    if not t then return false end
    local auth = false
    if t.auth then
        local u = t.uNow or t.u
        local lead = t.auth[2] > 0 and u or u - t.length
        auth = { remaining = math.max(0, (t.auth[1] - lead) * t.auth[2]), reason = t.auth[3] }
    end
    local cars = {}
    for k, c in ipairs(t.cars) do cars[k] = c.el end
    return { id = t.id, speed = t.vNow or t.v, ctrl = t.ctrl, rev = t.rev, emergency = t.emergency, atp = t.atp,
        authority = auth, cars = cars }
end

-- action = "lock" (reason, on) | "emergency" (on)
function netCab(action, a, b)
    if not myTrain() then return false end
    triggerServerEvent("rw:net:cab", resourceRoot, action, a, b)
    return true
end

function netSetHudEnabled(on) hudEnabled = on and true or false end
