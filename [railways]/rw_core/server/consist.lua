-- Consists (trains) on top of rw_customtracks: every train is a network train (puppet vehicles
-- moved by its simulation); this keeps the old consist API of the other rw_ resources:
--   track = line id (0 main line, 3 second track), tp = line position of the lead's centre,
--   dir = +1 when the lead faces increasing tp (the train extends behind it), moveDir / speed.
-- A train off both lines (yards, Cranberry tracks 3 / 4, a crossover) has track = nil.

Consists = {}
local byVehicle = {}
local states = {}            -- [id] = latest rw_customtracks state
local sign = function(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
local function net() return exports.rw_customtracks end

addEvent("onRailConsistSpawn")      -- source: lead, (id)
addEvent("onRailConsistDestroy")    -- source: lead, (id, reason)
addEvent("onRailConsistChange")     -- source: lead, (id) - composition changed
addEvent("onNetTrainStates", false)
addEvent("onNetTrainCompositionChange", false)

local function now() return getTickCount() end

-- running numbers of the locomotives on the network: [typeId] = { [number] = true }
local usedNumbers = {}

local function allocNumber(typeId)
    local def = RW.VEHICLES[typeId]
    local range = def and def.numbers or { 1, 999 }
    local used = usedNumbers[typeId] or {}
    usedNumbers[typeId] = used
    local lo, hi = range[1], range[2]
    for _ = 1, 50 do
        local n = math.random(lo, hi)
        if not used[n] then used[n] = true return n end
    end
    for n = lo, hi do
        if not used[n] then used[n] = true return n end
    end
    return hi + 1 + math.random(0, 99)
end

local function freeNumber(c)
    if c.number and usedNumbers[c.types[1]] then usedNumbers[c.types[1]][c.number] = nil end
end

-- "BR 232 1112"
local function labelOf(c)
    local def = RW.VEHICLES[c.types[1]]
    return ("%s %d"):format(def and def.name or tostring(c.types[1]), c.number or 0)
end

-- relative extent of a consist around its lead centre, in track metres -> minOff, maxOff
local function extentOffsets(c)
    local back = -c.dirSign * (#c.cars * RW.CAR_SPACING + RW.HALF_LENGTH)
    local front = c.dirSign * RW.HALF_LENGTH
    return math.min(back, front), math.max(back, front)
end

function getConsistExtentRaw(c)
    local a, b = extentOffsets(c)
    return c.track, c.tp and c.tp + a, c.tp and c.tp + b
end

-- does consist c occupy any part of [a, b] on `track`
function consistOverlaps(c, track, a, b)
    if c.track ~= track or not c.tp then return false end
    local ra, rb = Track.delta(track, c.tp, a), Track.delta(track, c.tp, b)
    if ra > rb then ra, rb = rb, ra end
    local lo, hi = extentOffsets(c)
    return ra <= hi and rb >= lo
end

local function tagVehicles(c)
    if not isElement(c.lead) then return end
    setElementData(c.lead, "rw.consist", c.id)
    setElementData(c.lead, "rw.cars", #c.cars)
    setElementData(c.lead, "rw.type", c.types[1])
    setElementData(c.lead, "rw.number", labelOf(c))
    if c.auto then setElementData(c.lead, "rw.auto", true) end
    byVehicle[c.lead] = c
    for i, v in ipairs(c.cars) do
        if isElement(v) then
            setElementData(v, "rw.consist", c.id)
            setElementData(v, "rw.type", c.types[i + 1])
            byVehicle[v] = c
        end
    end
end

-- the vehicles / composition from a state
local function takeVehicles(c, st)
    for v in pairs(byVehicle) do if byVehicle[v] == c then byVehicle[v] = nil end end
    c.lead = st.cars[1]
    c.cars = {}
    for i = 2, #st.cars do c.cars[i - 1] = st.cars[i] end
    c.types = {}
    for i, t in ipairs(st.types) do c.types[i] = t end
    tagVehicles(c)
end

-- a network train rw_core did not spawn (e.g. /rwtrain): it is a consist too
local function adopt(st)
    local c = { id = st.id, types = {}, cars = {}, dirSign = 1, speed = 0, moveDir = 0, created = now(), auto = st.auto or nil }
    takeVehicles(c, st)
    -- the running number travels with the network train (rw_core restarts keep it)
    c.number = st.data and st.data.number
    if c.number then
        usedNumbers[c.types[1]] = usedNumbers[c.types[1]] or {}
        usedNumbers[c.types[1]][c.number] = true
    else
        c.number = allocNumber(c.types[1])
        net():setNetTrainData(c.id, "number", c.number)
    end
    Consists[c.id] = c
    tagVehicles(c)
    if isElement(c.lead) then triggerEvent("onRailConsistSpawn", c.lead, c.id) end
    return c
end

local function forget(id, reason)
    local c = Consists[id]
    if not c then return end
    outputDebugString(("[rw_core] train %d (%s) removed: %s"):format(id, labelOf(c), reason or "removed"))
    -- always announced (source = root when the vehicles are already gone) so listeners forget it
    triggerEvent("onRailConsistDestroy", isElement(c.lead) and c.lead or root, id, reason)
    for v in pairs(byVehicle) do if byVehicle[v] == c then byVehicle[v] = nil end end
    Consists[id] = nil
    states[id] = nil
    freeNumber(c)
end

-- every simulation tick of rw_customtracks
addEventHandler("onNetTrainStates", root, function(list)
    local seen = {}
    for _, st in ipairs(list) do
        seen[st.id] = true
        states[st.id] = st
        local c = Consists[st.id] or adopt(st)
        if c.lead ~= st.cars[1] or #c.cars ~= #st.cars - 1 then takeVehicles(c, st) end
        -- line position: stay on the line the train was on (single-track stretches are on both)
        local pick
        for _, l in ipairs(st.lines) do
            if l.line == c.track then pick = l break end
            if not pick and (l.line == 0 or l.line == 3) then pick = l end
        end
        -- off the main lines: any line (Cranberry hall tracks 3 / 4)
        if not pick then pick = st.lines[1] end
        if pick then
            c.track, c.tp, c.dirSign = pick.line, pick.tp, pick.dir
            c.speed = st.speed * pick.dir
        else
            c.track, c.tp = nil, nil
            c.speed = st.speed * (c.dirSign or 1)
        end
        c.moveDir = math.abs(c.speed) < 0.15 and 0 or sign(c.speed)
        c.driver = isElement(st.driver) and st.driver or nil
        c.auto = st.auto or nil
        if isElement(c.lead) then
            if getElementData(c.lead, "rw.track") ~= c.track then setElementData(c.lead, "rw.track", c.track or false) end
            if getElementData(c.lead, "rw.dir") ~= c.dirSign then setElementData(c.lead, "rw.dir", c.dirSign) end
        end
    end
    for id in pairs(Consists) do
        if not seen[id] then forget(id, "the network train is gone") end
    end
end)

addEventHandler("onNetTrainCompositionChange", root, function(id)
    local c = Consists[id]
    local st = net():getNetTrain(id)
    if c and st then
        takeVehicles(c, { cars = (function() local t = {} for k, e in ipairs(st.cars) do t[k] = e.element end return t end)(),
            types = (function() local t = {} for k, e in ipairs(st.cars) do t[k] = e.type end return t end)() })
        if isElement(c.lead) then triggerEvent("onRailConsistChange", c.lead, id) end
    end
end)

--------------------------------------------------------------------- spawning

local function resolveComposition(spec)
    local loco, cars = spec.loco, spec.cars
    if spec.preset then
        for _, p in ipairs(RW.PRESETS) do
            if p.id == spec.preset then loco, cars = p.loco, p.cars break end
        end
    end
    if not loco or not RW.VEHICLES[loco] or RW.VEHICLES[loco].kind ~= "loco" then return nil, "unknown locomotive" end
    local types = { loco }
    for _, t in ipairs(cars or {}) do
        if not RW.VEHICLES[t] or RW.VEHICLES[t].kind == "loco" then return nil, "unknown carriage " .. tostring(t) end
        types[#types + 1] = t
    end
    if #types - 1 > RW.MAX_CARRIAGES then return nil, "too many carriages" end
    return types
end

function getSpawnPoint(id)
    for _, s in ipairs(RW.SPAWNS) do if s.id == id then return s end end
end

local function resolvePlace(spec)
    local track, tp, dir = spec.track, spec.tp, spec.dir
    if spec.spawn then
        local s = getSpawnPoint(spec.spawn)
        if not s then return nil, "unknown spawn point" end
        track, dir = s.track, s.dir
        tp = Track.project(s.track, s.x, s.y, 60)
    elseif track and spec.x and spec.y then
        tp = Track.project(track, spec.x, spec.y, 60)
    end
    if not track or not Track.get(track) or not tp then return nil, "no track there" end
    return track, tp, (dir or 1) < 0 and -1 or 1
end

--[[ Spawns a consist. spec = {
        preset = "re2" | loco = "br232", cars = { "passenger", ... },
        spawn = "unity_1" | track = 0, (tp = centre | x =, y =), dir = 1 | -1,
        owner = player (optional), auto = true (scripted control, rw_auto) }
    -> id | false, reason ]]
function spawnConsist(spec)
    if type(spec) ~= "table" then return false, "bad spec" end
    local types, err = resolveComposition(spec)
    if not types then return false, err end
    local track, tp, dir = resolvePlace(spec)
    if not track then return false, tp end
    local id, e = net():spawnNetTrainOnLine(types, track, tp, dir, { auto = spec.auto and true or nil })
    if not id then return false, e end
    local st = net():getNetTrain(id)
    local cars, tps = {}, {}
    for k, v in ipairs(st.cars) do cars[k] = v.element tps[k] = v.type end
    local c = { id = id, types = {}, cars = {}, dirSign = dir, speed = 0, moveDir = 0, track = track, tp = tp,
        owner = isElement(spec.owner) and spec.owner or nil, created = now(), auto = spec.auto and true or nil }
    takeVehicles(c, { cars = cars, types = tps })
    c.number = allocNumber(types[1])
    net():setNetTrainData(id, "number", c.number)
    Consists[id] = c
    tagVehicles(c)
    triggerEvent("onRailConsistSpawn", c.lead, id)
    return id
end

-- reason: why it goes (logged; the people on board are told)
function destroyConsist(id, reason)
    local c = Consists[id]
    if not c then return false end
    reason = reason or "removed"
    local st = states[id]
    if st and isElement(st.driver) and not c.auto then
        triggerClientEvent(st.driver, "rw:notify", resourceRoot, "Your train was removed (" .. reason .. ").", false)
    end
    forget(id, reason)
    net():destroyNetTrain(id)
    return true
end

-- Adds a carriage to the end of a standing consist
function addCarriage(id, typeId)
    local c = Consists[id]
    if not c then return false, "no such train" end
    local def = RW.VEHICLES[typeId]
    if not def or def.kind == "loco" then return false, "unknown carriage" end
    if #c.cars >= RW.MAX_CARRIAGES then return false, "the train is at its maximum length" end
    local types = {}
    for i, t in ipairs(c.types) do types[i] = t end
    types[#types + 1] = typeId
    return net():setNetTrainComposition(id, types)
end

-- Removes the last carriage of a standing consist
function removeCarriage(id)
    local c = Consists[id]
    if not c then return false, "no such train" end
    if #c.cars == 0 then return false, "the locomotive has no carriages" end
    local types = {}
    for i = 1, #c.types - 1 do types[i] = c.types[i] end
    return net():setNetTrainComposition(id, types)
end

-- Old GTA-track helpers, kept so callers do not break: switches are real now and the
-- network simulates every train.
function transferConsist() return false end
function setConsistVirtual(id) local c = Consists[id] return c and c.track, c and c.tp, false end
function setConsistSpeed() return false end

function isConsistAuto(id)
    local c = Consists[id]
    return c and c.auto or false
end

--------------------------------------------------------------------- queries / exports

local function publicInfo(c)
    local passengers, seats = 0, 0
    for i = 2, #c.types do
        local def = RW.VEHICLES[c.types[i]]
        if def and def.passenger then passengers = passengers + 1 seats = seats + (def.seats or 0) end
    end
    local vehicles = { c.lead }
    for _, v in ipairs(c.cars) do vehicles[#vehicles + 1] = v end
    local x, y, z = 0, 0, 0
    if isElement(c.lead) then x, y, z = getElementPosition(c.lead) end
    local _, lo, hi = getConsistExtentRaw(c)
    return {
        id = c.id, number = c.number, label = labelOf(c), lead = c.lead, vehicles = vehicles, types = c.types, loco = c.types[1],
        carriages = #c.cars, passengerCars = passengers, seats = seats,
        track = c.track, tp = c.tp, dir = c.dirSign, moveDir = c.moveDir,
        speed = math.abs(c.speed or 0) * 3.6,           -- km/h
        speedSigned = c.speed or 0,                      -- m/s along the track
        lo = lo, hi = hi, x = x, y = y, z = z,
        driver = c.driver, owner = c.owner, building = false,
        auto = c.auto or false,
    }
end

function getConsist(id)
    local c = Consists[id]
    return c and publicInfo(c) or false
end

function getConsists()
    local list = {}
    for _, c in pairs(Consists) do
        if isElement(c.lead) then list[#list + 1] = publicInfo(c) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function getVehicleConsist(vehicle)
    local c = byVehicle[vehicle]
    return c and c.id or false
end

function getConsistByDriver(player)
    for _, c in pairs(Consists) do
        if c.driver == player then return c.id end
    end
    return false
end

-- track helpers for the other rw_ resources (call them once, not per frame)
function projectToTrack(x, y, track, maxDist)
    if track then
        local tp, d = Track.project(track, x, y, maxDist or 50)
        if tp then return track, tp, d end
        return false
    end
    local id, tp, d = Track.nearest(x, y, maxDist or 50, RW.TRACKS)
    if id then return id, tp, d end
    return false
end
function getTrackPoint(track, tp)
    local x, y, z, dx, dy = Track.pointAt(track, tp)
    return x, y, z, dx, dy
end
function getTrackLength(track) return Track.length(track) end
function getTrackDelta(track, a, b) return Track.delta(track, a, b) end
function getTrackPolyline(track, a, b, step) return Track.polyline(track, a, b, step) end

addEventHandler("onResourceStop", resourceRoot, function()
    -- the trains belong to rw_customtracks and keep running; only the bookkeeping goes
end)
