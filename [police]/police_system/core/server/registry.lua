if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- police_system / core/server/registry.lua
-- The module registry and the internal bus. Every module registers its table with POL.module(name, t) and is then
-- reachable as POL.<name> from every other module (one Lua state per side: plain function calls, no exports).
-- POL.on / POL.emit: internal events between modules ("unit.signedIn", "wanted.changed", ...). MTA events are only
-- used at the client-server boundary (POL.net / POL.send) and towards other resources.

POL = POL or {}
POL.list = {}

local handlers = {}

function POL.module(name, t)
    t = t or {}
    t.name = name
    POL[name] = t
    POL.list[#POL.list + 1] = t
    return t
end

function POL.on(ev, fn)
    local h = handlers[ev]
    if not h then h = {}; handlers[ev] = h end
    h[#h + 1] = fn
end

function POL.emit(ev, ...)
    local h = handlers[ev]
    if not h then return end
    for i = 1, #h do
        local ok, err = pcall(h[i], ...)
        if not ok then outputDebugString("[police_system] " .. ev .. ": " .. tostring(err), 1) end
    end
end

-- start: every module's start() in registration order (after the scripts loaded), stop() in reverse
function POL.startAll()
    for _, m in ipairs(POL.list) do
        if m.start then
            local ok, err = pcall(m.start)
            if not ok then outputDebugString("[police_system] start " .. m.name .. ": " .. tostring(err), 1) end
        end
    end
end

function POL.stopAll()
    for i = #POL.list, 1, -1 do
        local m = POL.list[i]
        if m.stop then pcall(m.stop) end
    end
end

------------------------------------------------------------------------ client <-> server

local rate = {}     -- [player] = { t = second, n = count }
local RATE_MAX = 25 -- client events per second per player

-- client -> server handler: fn(player, ...) for "pol:<name>" (validated source, rate limited)
function POL.net(name, fn)
    local ev = "pol:" .. name
    addEvent(ev, true)
    addEventHandler(ev, resourceRoot, function(...)
        local p = client
        if not p then return end
        local now = math.floor(getTickCount() / 1000)
        local r = rate[p]
        if not r or r.t ~= now then r = { t = now, n = 0 }; rate[p] = r end
        r.n = r.n + 1
        if r.n > RATE_MAX then return end
        local ok, err = pcall(fn, p, ...)
        if not ok then outputDebugString("[police_system] " .. ev .. ": " .. tostring(err), 1) end
    end)
end

-- server -> client(s): to = player | { players } | root
function POL.send(to, name, ...)
    if not to then return end
    if type(to) == "table" and not isElement(to) then
        local list = {}
        for _, p in ipairs(to) do if isElement(p) then list[#list + 1] = p end end
        if #list == 0 then return end
        to = list
    end
    triggerClientEvent(to, "pol:" .. name, resourceRoot, ...)
end

-- ui_core notification (the text is a v_locals key, resolved in the player's language)
function POL.notify(to, key, params)
    POL.send(to, "notify", L.msg(key, params))
end

addEventHandler("onPlayerQuit", root, function() rate[source] = nil end)

------------------------------------------------------------------------ helpers

function POL.running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running" or false
end

function POL.now() return getRealTime().timestamp end

function POL.accountOf(player)
    if not isElement(player) then return nil end
    local a = getElementData(player, "accName")
    return type(a) == "string" and a ~= "" and a or nil
end

-- the display name (v_accounts displayName element data), never stored in the database
function POL.nameOf(player)
    if not isElement(player) then return "?" end
    if getElementType(player) ~= "player" then return "?" end
    local d = getElementData(player, "displayName") or getElementData(player, "accName") or getPlayerName(player)
    return (tostring(d):gsub("#%x%x%x%x%x%x", ""))
end

function POL.playerByAccount(acc)
    if not acc then return nil end
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "accName") == acc then return p end
    end
    return nil
end

-- the simulated pose of an ai_land_traffic vehicle (its server element position is only refreshed every 5 s):
-- x, y, z, speed (m/s) or nil
local function trafficPose(veh)
    if not POL.running("ai_land_traffic") then return nil end
    local x, y, z, v = exports.ai_land_traffic:getTrafficVehiclePose(veh)
    if not x then return nil end
    return x, y, z, v
end

-- position of an element; a ped in a vehicle and a traffic vehicle by the simulation
function POL.pos(el)
    local t = getElementType(el)
    if t == "ped" or t == "player" then
        local veh = getPedOccupiedVehicle(el)
        if veh then el, t = veh, "vehicle" end
    end
    if t == "vehicle" then
        local x, y, z = trafficPose(el)
        if x then return x, y, z end
    end
    return getElementPosition(el)
end

function POL.dist(a, b)
    local x1, y1, z1 = POL.pos(a)
    local x2, y2, z2 = POL.pos(b)
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2 + (z1 - z2) ^ 2)
end

function POL.dist2D(a, x, y)
    local x1, y1 = POL.pos(a)
    return math.sqrt((x1 - x) ^ 2 + (y1 - y) ^ 2)
end

function POL.inWorld(el)
    return isElement(el) and getElementDimension(el) == 0 and getElementInterior(el) == 0
end

function POL.lang(player)
    local ok, l = pcall(L.lang, player)
    return ok and type(l) == "string" and l or "en"
end

-- nearest station to a point
function POL.nearestStation(x, y)
    local best, bd
    for _, st in ipairs(POLICE.STATIONS) do
        local d = (st.handover[1] - x) ^ 2 + (st.handover[2] - y) ^ 2
        if not bd or d < bd then best, bd = st, d end
    end
    return best
end

function POL.stationById(id)
    for _, st in ipairs(POLICE.STATIONS) do if st.id == id then return st end end
    return POLICE.STATIONS[1]
end

function POL.speed(el)
    if getElementType(el) == "vehicle" then
        local x, _, _, v = trafficPose(el)
        if x then return v end
    end
    local vx, vy, vz = getElementVelocity(el)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 50   -- m/s
end

function POL.fmtTime(ts)
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

function POL.clock(ts)
    local t = getRealTime(ts)
    return ("%02d:%02d"):format(t.hour, t.minute)
end
