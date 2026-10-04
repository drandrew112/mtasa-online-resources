-- Trains on the client: places every car of every train each frame from the server snapshots
-- (extrapolated with v / a, errors blended out), runs the driver's input and HUD and the
-- passengers' camera. Other client files read the train list through TrainsClient.

TrainsClient = {}

local C = NET.CLIENT
local trains = {}          -- [id] = { snap fields..., path, t (receive tick), corr, corrT, poses, us }
local offset               -- server tick -> local tick
local base = {}            -- [model] = height of the centre above the model base
local input = { w = false, s = false }
local hudEnabled = true      -- rw_loco switches it off: its cab panel shows the same
local sx, sy = guiGetScreenSize()

function TrainsClient.list() return trains end

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
end)

local function baseOf(el, def)
    local m = getElementModel(el)
    if base[m] then return base[m] end
    local b = getElementDistanceFromCentreOfMassToBaseOfModel(el)
    if b and b > 0.05 then base[m] = b return b end
    return def.base
end

-- ------------------------------------------------------------------ placement

addEventHandler("onClientPreRender", root, function()
    if not NetClient.ready then return end
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
                local cz = z + baseOf(el, car.def) + NET.RAIL_Z
                setElementMatrix(el, { { rx, ry, 0, 0 }, { fx, fy, fz, 0 }, { ux, uy, uz, 0 }, { x, y, cz, 1 } })
                t.poses[k] = { x, y, z, fx, fy, fz, rx, ry }
            else
                t.poses[k] = nil
            end
        end
    end
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

addEventHandler("onClientRender", root, function()
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
    dxDrawText(string.format("%.0f km/h", kmh), x + 14, y + 8, 0, 0, tocolor(255, 255, 255), 2, "default-bold")
    local revText = t.rev > 0 and "ELŐRE" or "HÁTRA"
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
    local label = t.emergency and "VÉSZFÉK" or (t.ctrl > 0.01 and string.format("vontatás %d%%", t.ctrl * 100))
        or (t.ctrl < -0.01 and string.format("fék %d%%", -t.ctrl * 100)) or "semleges"
    local grade = t.path:grade((t.uNow or t.u) - t.length / 2) * 100
    local auth = ""
    if t.auth then
        local u = t.uNow or t.u
        local lead = t.auth[2] > 0 and u or u - t.length
        auth = string.format("   engedély %.0f m (%s)", math.max(0, (t.auth[1] - lead) * t.auth[2]), tostring(t.auth[3]))
    end
    dxDrawText(string.format("%s   lejtés %.1f%%%s", label, grade, auth), x + 14, y + 70, 0, 0, tocolor(200, 210, 230), 1, "default")
    if t.atp then
        dxDrawText("ATP FÉKEZÉS", x + bw - 14, y + 34, x + bw - 14, 0, tocolor(255, 80, 60), 1.2, "default-bold", "right")
    end
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

local riding
addEventHandler("onClientRender", root, function()
    local r = getElementData(localPlayer, "rwn.ride")
    local t = r and trains[r[1]]
    local car = t and t.cars[r[2]]
    local el = car and car.el
    if el ~= riding then
        riding = el
        if isElement(el) then setCameraTarget(el) else setCameraTarget(localPlayer) end
    end
end)

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
