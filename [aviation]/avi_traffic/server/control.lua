-- Who controls an aircraft: the most specific staffed position of the airspace it is in.
--   CTR of ICAO -> ICAO_TWR, ICAO_APP, centre      (aircraft on the ground: the same chain)
--   TMA of ICAO -> ICAO_APP, centre
--   CTA         -> centre
-- Nobody staffed = the pilots fly their flight plan on their own (automatic levels).
-- Controller commands come from avi_controller, which checks the player and the position.

local staffed = {}     -- [positionId] = true

function refreshStaffing()
    staffed = callExport("avi_controller", "getStaffedPositions") or {}
end

local function chainFor(ac)
    if ac.phase ~= "air" and ac.phase ~= "final" then
        local icao = ac.gndApt or ac.arr
        if airport(icao) then return { icao .. "_TWR", icao .. "_APP", TR.CENTER_POSITION } end
    end
    -- established on final: the tower of the destination (even above the CTR ceiling)
    if ac.phase == "final" and airport(ac.arr) then
        return { ac.arr .. "_TWR", ac.arr .. "_APP", TR.CENTER_POSITION }
    end
    local a = airspaceAt(ac.x, ac.y, ac.alt)
    if not a then return {} end
    if a.type == "CTR" and a.airport then return { a.airport .. "_TWR", a.airport .. "_APP", TR.CENTER_POSITION } end
    if a.type == "TMA" and a.airport then return { a.airport .. "_APP", TR.CENTER_POSITION } end
    return { TR.CENTER_POSITION }
end

-- An aircraft stays with its controller until transferred (or the position is closed). Aircraft
-- without a staffed controller are picked up by the most specific staffed position of their airspace.
local function inAirspace(ac, id, checkAlt)
    for _, a in ipairs(WORLD.airspaces) do
        if a.id == id then
            if checkAlt and (ac.alt < (a.floor or 0) or ac.alt > (a.ceiling or 99999)) then return false end
            return pointInPolygon(ac.x, ac.y, a.polygon)
        end
    end
    return false
end

-- is the aircraft still in the sector of the position: TWR = its CTR (+ ground, + final to it),
-- APP = its TMA / CTR, centre = the CTA. Leaving it releases the aircraft to the next staffed
-- position, or to the automatic (pilot own) mode when nobody is there.
local function inSector(ac, pos)
    local icao, kind = pos:match("^(%w+)_(%u+)$")
    if pos == TR.CENTER_POSITION then
        for _, a in ipairs(WORLD.airspaces) do
            if a.type == "CTA" then return pointInPolygon(ac.x, ac.y, a.polygon) end
        end
        return true
    end
    if not icao then return false end
    local onGround = ac.phase ~= "air" and ac.phase ~= "final"
    if onGround then return (ac.gndApt or ac.arr) == icao end
    if ac.phase == "final" and ac.arr == icao then return true end
    if kind == "TWR" then return inAirspace(ac, icao .. "_CTR", true) end
    if kind == "APP" then return inAirspace(ac, icao .. "_TMA", true) or inAirspace(ac, icao .. "_CTR", true) end
    return false
end

function controllerOf(ac)
    if ac.ctl and staffed[ac.ctl] and inSector(ac, ac.ctl) then return ac.ctl end
    for _, pos in ipairs(chainFor(ac)) do
        if staffed[pos] then return pos end
    end
    return nil
end

addEvent("onAviAircraftHandover")   -- source: resourceRoot, args: id, callsign, fromPos, toPos

function updateController(ac)
    local ctl = controllerOf(ac)
    if ctl ~= ac.ctl then
        local old = ac.ctl
        ac.ctl = ctl
        triggerEvent("onAviAircraftHandover", resourceRoot, ac.id, ac.cs, old, ctl)
    end
end

-- ---------------------------------------------------------------- exports
function getTrafficSnapshot()
    local list = {}
    for _, ac in pairs(AIRCRAFT) do list[#list + 1] = snapshot(ac) end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function getAircraft(id)
    local ac = AIRCRAFT[tonumber(id)]
    return ac and snapshot(ac)
end

function getAircraftByCallsign(cs)
    cs = tostring(cs or ""):upper()
    for _, ac in pairs(AIRCRAFT) do
        if ac.cs == cs then return snapshot(ac) end
    end
end

function getAircraftController(id)
    local ac = AIRCRAFT[tonumber(id)]
    return ac and ac.ctl
end

-- cleared altitude (feet, rounded to 100). Only airborne aircraft take level clearances.
function setClearedAltitude(id, ft)
    local ac = AIRCRAFT[tonumber(id)]
    ft = tonumber(ft)
    if not ac or not ft then return false, "unknown aircraft" end
    if ac.phase ~= "air" then return false, "not in cruise / climb / descent" end
    ft = math.floor(math.max(0, math.min(30000, ft)) / 100 + 0.5) * 100
    ac.cfl = ft
    ac.climbOut = nil      -- a clearance ends the runway-heading climb-out
    ac.missed = nil
    return true
end

-- direct to a nav point (FIX / VOR / NDB id). The flight plan resumes after it.
function setDirectTo(id, navId)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    if ac.phase ~= "air" then return false, "not airborne" end
    navId = tostring(navId or ""):upper()
    if not navPoint(navId) then return false, "unknown waypoint " .. navId end
    ac.dct = navId
    ac.ahdg = nil          -- a waypoint replaces the heading
    ac.via = nil
    ac.climbOut = nil
    return true
end

-- radar heading (1..360). Replaces the waypoint; the aircraft flies it until a waypoint, "resume own
-- navigation" or it intercepts the final of its arrival runway.
function setHeading(id, hdg)
    local ac = AIRCRAFT[tonumber(id)]
    hdg = tonumber(hdg)
    if not ac or not hdg then return false, "unknown aircraft" end
    if ac.phase ~= "air" then return false, "not airborne" end
    hdg = math.floor(hdg + 0.5) % 360
    ac.ahdg = hdg == 0 and 360 or hdg
    ac.dct, ac.via, ac.approach, ac.climbOut, ac.missed = nil, nil, nil, nil, nil
    return true
end

function clearHeading(id)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    ac.ahdg = nil
    return true
end

-- hand the aircraft to another staffed position
function transferAircraft(id, pos)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    if not pos or not staffed[pos] then return false, tostring(pos) .. " is not staffed" end
    if ac.ctl == pos then return false, "already there" end
    local old = ac.ctl
    ac.ctl = pos
    triggerEvent("onAviAircraftHandover", resourceRoot, ac.id, ac.cs, old, pos)
    return true
end

-- tower / delivery clearances:
--   ifr (value = initial level, ft)  at the stand: accepts the flight plan route
--   push                              at the stand, after the IFR clearance
--   taxi (value = runway end | stand) departures after pushback, arrivals after landing
--   cross                             holding short of a runway it only crosses
--   lineup / backtrack                holding short of its departure runway (enter, roll to the
--                                     threshold, turn round = lined up)
--   takeoff                           holding short (no backtrack needed) / lined up
--   land                              airborne arrival
--   vacate (value = taxiway id)       arrival: leave the runway there
--   goaround                          arrival on approach / final
function giveClearance(id, kind, value)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    local p = ac.phase
    ac.rwyClr = ac.rwyClr or {}
    if kind == "ifr" then
        if p ~= "gate" then return false, "IFR clearance only at the stand" end
        local ft = tonumber(value)
        if not ft then return false, "no initial level" end
        ac.ifr = true
        ac.initAlt = math.floor(math.max(1000, math.min(ac.cruise, ft)) / 100 + 0.5) * 100
    elseif kind == "push" then
        if p ~= "gate" then return false, "not at the stand" end
        if not ac.ifr then return false, "IFR clearance first" end
        ac.pushClr = true
    elseif kind == "taxi" then
        local resume = p == "hold" and ac.holdResume or p
        if resume == "pushback" or resume == "pushed" then
            if value and value ~= "" then
                if not callExport("avi_airports", "getRunwayEnd", ac.gndApt, value) then return false, "unknown runway " .. tostring(value) end
                ac.taxiRwy = value
            end
            ac.taxiClr = true
        elseif resume == "landing" or resume == "vacate" or resume == "vacated" then
            ac.taxiGate = (value and value ~= "") and value or nil
            ac.taxiInClr = true
        elseif p == "gate" then
            return false, "pushback first"
        else
            return false, "not waiting for taxi"
        end
    elseif kind == "cross" then
        if p ~= "hold" then return false, "not holding short" end
        ac.rwyClr[ac.holdRwy] = true
    elseif kind == "lineup" then
        if p ~= "hold" or ac.holdKind ~= "TO" then return false, "not holding short of its runway" end
        ac.rwyClr[ac.holdRwy] = true
    elseif kind == "backtrack" then
        if p ~= "hold" or ac.holdKind == "CROSS" then return false, "not holding short of its runway" end
        ac.rwyClr[ac.holdRwy] = true
    elseif kind == "takeoff" then
        if p == "hold" then
            if ac.holdKind == "BKTRK" then return false, "backtrack first" end
            if ac.holdKind == "CROSS" then return false, "holding short of another runway" end
            ac.rwyClr[ac.holdRwy] = true
        elseif p ~= "lined" then
            return false, "take-off clearance at the runway only (holding short / lined up)"
        end
        ac.toClr = true
    elseif kind == "land" then
        if (p ~= "air" and p ~= "final") or not airport(ac.arr) then return false, "not an arrival" end
        ac.landClr = true
    elseif kind == "vacate" then
        if (p ~= "air" and p ~= "final" and p ~= "landing") or not airport(ac.arr) then return false, "not landing" end
        local ok
        for _, a in pairs({ airport(ac.arr) }) do
            for _, rw in ipairs(a.runways) do
                for _, x in ipairs(runwayExits(a, rw.id)) do if x.tw == value then ok = true end end
            end
        end
        if not ok then return false, "no runway exit " .. tostring(value) end
        ac.vacateVia = value
    elseif kind == "goaround" then
        if p ~= "final" and not (p == "air" and ac.approach) then return false, "not on approach" end
        if p == "final" then
            trafficGoAround(ac)
        else
            ac.approach, ac.via = nil, nil
            local apt = airport(ac.arr)
            ac.cfl = math.max(ac.cfl or 0, (apt and apt.elevation or 0) + TR.MISSED_ALT_AGL)
        end
    else
        return false, "unknown clearance"
    end
    return true
end

function clearDirectTo(id)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    ac.dct = nil
    return true
end
