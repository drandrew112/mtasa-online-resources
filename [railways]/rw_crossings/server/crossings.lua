-- Level crossings. The game's own barriers (models 1373 post / 1374 arm, every placement
-- in shared/crossings_data.lua) are removed and replaced by script objects. Each crossing
-- gets a detection zone along its track(s): CROSS.APPROACH metres of rail on both sides of
-- the road, cut short so it never reaches into a station's platform zone. The barriers
-- close while any train is in a zone and open CROSS.OPEN_DELAY after the last one left.
--
-- The zone is a stretch of track, not a sphere: rw_core knows the extent of every train
-- (driven, standing or automatic - automatic trains have no synced vehicle position on the
-- server), and a stretch follows curves and stops exactly where the station begins.

local core = exports.rw_core
Crossings = {}
local lengths, closedTrack = {}, { [0] = true }

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function rel(track, a, b)
    local d = b - a
    if closedTrack[track] then
        local L = lengths[track]
        d = d % L
        if d > L / 2 then d = d - L end
    end
    return d
end

-- zone on one track: [tp - before, tp + after] shortened at station platform zones
local function buildZone(track, tp, stationZones)
    local before, after = CROSS.APPROACH, CROSS.APPROACH
    for _, z in ipairs(stationZones) do
        if z.track == track then
            local dLo, dHi = rel(track, tp, z.lo), rel(track, tp, z.hi)
            if dLo > 0 then after = math.min(after, dLo - CROSS.STATION_GAP) end       -- station ahead (+)
            if dHi < 0 then before = math.min(before, -dHi - CROSS.STATION_GAP) end    -- station behind (-)
        end
    end
    return { track = track, tp = tp, lo = tp - math.max(CROSS.MIN_ZONE, before), hi = tp + math.max(CROSS.MIN_ZONE, after) }
end

local function setArms(cr, closed)
    for _, arm in ipairs(cr.arms) do
        if isElement(arm.obj) then
            local x, y, z = getElementPosition(arm.obj)
            local target = closed and 0 or CROSS.ARM_UP
            local delta = target - arm.rx
            if delta ~= 0 then
                stopObject(arm.obj)
                moveObject(arm.obj, CROSS.MOVE_TIME, x, y, z, delta, 0, 0, "InOutQuad")
                arm.rx = target
            end
        end
    end
    cr.closed = closed
    setElementData(cr.element, "rw.crossing", closed)
end

local function occupied(cr, consists)
    for _, z in ipairs(cr.zones) do
        for _, c in ipairs(consists) do
            if c.track == z.track and rel(z.track, z.lo, c.hi) >= 0 and rel(z.track, c.lo, z.hi) >= 0 then return true end
        end
    end
    return false
end

local function tick()
    local ok, consists = pcall(function() return core:getConsists() end)
    if not ok or type(consists) ~= "table" then return end
    local t = getTickCount()
    for _, cr in ipairs(Crossings) do
        if #cr.zones > 0 then
            if occupied(cr, consists) then
                cr.clearSince = nil
                if not cr.closed then setArms(cr, true) end
            elseif cr.closed then
                cr.clearSince = cr.clearSince or t
                if t - cr.clearSince >= CROSS.OPEN_DELAY then setArms(cr, false) end
            end
        end
    end
end

local function build()
    for _, track in ipairs(CROSS.TRACKS) do lengths[track] = core:getTrackLength(track) end
    local stationZones = running("rw_timetable") and exports.rw_timetable:getStationZones() or {}
    for i, def in ipairs(RW_CROSSING_DATA) do
        local cr = { id = i, x = def.x, y = def.y, arms = {}, posts = {}, zones = {}, closed = false }
        -- the crossing element carries the state for the clients' lights
        cr.element = createElement("rwcrossing", "rwcrossing" .. i)
        setElementPosition(cr.element, def.x, def.y, 0)
        for _, o in ipairs(def.objs) do
            local model, x, y, z, rz = o[1], o[2], o[3], o[4], o[5]
            removeWorldModel(model, 1.5, x, y, z)
            if model == 1374 then
                local obj = createObject(model, x, y, z, CROSS.ARM_UP, 0, rz)
                if obj then
                    setElementFrozen(obj, true)
                    setElementParent(obj, cr.element)
                    cr.arms[#cr.arms + 1] = { obj = obj, rx = CROSS.ARM_UP }
                end
            else
                local obj = createObject(model, x, y, z, 0, 0, rz)
                if obj then
                    setElementFrozen(obj, true)
                    setElementParent(obj, cr.element)
                    cr.posts[#cr.posts + 1] = obj
                end
            end
        end
        for _, track in ipairs(CROSS.TRACKS) do
            local t, tp = core:projectToTrack(def.x, def.y, track, CROSS.TRACK_RANGE)
            if t then cr.zones[#cr.zones + 1] = buildZone(track, tp, stationZones) end
        end
        setElementData(cr.element, "rw.crossing", false)
        Crossings[#Crossings + 1] = cr
    end
    local active = 0
    for _, cr in ipairs(Crossings) do if #cr.zones > 0 then active = active + 1 end end
    outputDebugString(("[rw_crossings] %d crossings replaced, %d on a used track"):format(#Crossings, active))
end

addEventHandler("onResourceStart", resourceRoot, function()
    build()
    setTimer(tick, CROSS.TICK, 0)
end)

-- give the game's barriers back
addEventHandler("onResourceStop", resourceRoot, function()
    for _, def in ipairs(RW_CROSSING_DATA) do
        for _, o in ipairs(def.objs) do restoreWorldModel(o[1], 1.5, o[2], o[3], o[4]) end
    end
end)

function getCrossings()
    local t = {}
    for _, cr in ipairs(Crossings) do
        local zones = {}
        for _, z in ipairs(cr.zones) do zones[#zones + 1] = { track = z.track, lo = z.lo, hi = z.hi } end
        t[#t + 1] = { id = cr.id, x = cr.x, y = cr.y, closed = cr.closed, zones = zones }
    end
    return t
end
