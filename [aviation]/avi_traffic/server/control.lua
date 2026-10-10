-- Who controls an aircraft: the one position whose sector it is in (no top-down cover).
--   ground at ICAO / final to ICAO / CTR of ICAO -> ICAO_TWR
--   TMA of ICAO (outside its CTR)                -> ICAO_APP
--   CTA (outside every TMA / CTR)                -> centre (radar)
-- When that position is not staffed, nobody controls the aircraft: the pilots fly their flight
-- plan on their own (automatic levels, no clearances needed), even if another position is open.
-- An early transfer ("Transfer to") gives the aircraft to the receiver while it is still in the
-- sender's sector; it stays with the receiver after that by the normal sector rule.
-- Controller commands come from avi_controller, which checks the player and the position.

local staffed = {}     -- [positionId] = true

function refreshStaffing()
    staffed = callExport("avi_controller", "getStaffedPositions") or {}
end

-- the position responsible for the aircraft where it is now (nil = outside every sector)
function sectorPosition(ac)
    if ac.phase ~= "air" and ac.phase ~= "final" then
        local icao = ac.gndApt or ac.arr
        return airport(icao) and icao .. "_TWR" or nil
    end
    -- established on final: the tower of the destination (even above the CTR ceiling)
    if ac.phase == "final" and airport(ac.arr) then return ac.arr .. "_TWR" end
    local a = airspaceAt(ac.x, ac.y, ac.alt)
    if not a then return nil end
    if a.type == "CTR" and a.airport then return a.airport .. "_TWR" end
    if a.type == "TMA" and a.airport then return a.airport .. "_APP" end
    if a.type == "CTA" then return TR.CENTER_POSITION end
    return nil
end

function controllerOf(ac)
    local own = sectorPosition(ac)
    -- early transfer: valid while the aircraft is still in the sector it was handed over from
    if ac.ctl and ac.xferFrom and ac.ctl ~= own and ac.xferFrom == own and staffed[ac.ctl] then return ac.ctl end
    if own and staffed[own] then return own end
    return nil
end

addEvent("onAviAircraftHandover")   -- source: resourceRoot, args: id, callsign, fromPos, toPos

function updateController(ac)
    local ctl = controllerOf(ac)
    if ac.xferFrom and (ctl ~= ac.ctl or ctl == sectorPosition(ac)) then ac.xferFrom = nil end
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

-- hand the aircraft to another staffed position (early transfer: the receiver has it while it is
-- still in the current sector, then the sector rule takes over)
function transferAircraft(id, pos)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    if not pos or not staffed[pos] then return false, tostring(pos) .. " is not staffed" end
    if ac.ctl == pos then return false, "already there" end
    local own = sectorPosition(ac)
    if not own then return false, "outside every sector" end
    local old = ac.ctl
    ac.ctl = pos
    ac.xferFrom = pos ~= own and own or nil
    triggerEvent("onAviAircraftHandover", resourceRoot, ac.id, ac.cs, old, pos)
    return true
end

-- tower / delivery clearances:
--   ifr (value = { alt = ft, sid = "VINEW1D 27L" | "" } or ft)
--                                     at the stand: initial level + SID ("" = no SID, own navigation;
--                                     nil = the pilots pick the SID of their route at take-off)
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
        local ft, sidSpec = tonumber(value), nil
        if type(value) == "table" then ft, sidSpec = tonumber(value.alt), value.sid end
        if not ft then return false, "no initial level" end
        if type(sidSpec) == "string" and sidSpec ~= "" then
            local sid, ident = sidSpec:upper():match("^(%S+)%s+(%S+)$")
            local pr = procedure(sid)
            if not pr or pr.type ~= "SID" or pr.airport ~= ac.gndApt or not procedureRoute(sid, ident) then
                return false, "unknown SID " .. sidSpec
            end
            ac.sid, ac.sidRwy = pr.id, ident
            ac.proc = pr.id .. " " .. ident
            ac.taxiRwy = ac.taxiRwy or ident      -- taxi without a runway = to the runway of the SID
        elseif sidSpec == "" then
            ac.sid, ac.proc = false, nil
        end
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
            ac.ri = #ac.route + 1         -- the rest of the STAR is gone
            ac.proc, ac.star, ac.procEnd, ac.starTried = nil, nil, nil, true
            local apt = airport(ac.arr)
            ac.cfl = math.max(ac.cfl or 0, (apt and apt.elevation or 0) + TR.MISSED_ALT_AGL)
        end
    else
        return false, "unknown clearance"
    end
    return true
end

-- arrival procedure (APP / centre): spec = "VINEW1A 27R" (STAR + runway). The aircraft flies it
-- from where it is (fixes already behind it are skipped) and lands on that runway.
function setArrivalProcedure(id, spec)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    if ac.phase ~= "air" then return false, "not airborne / already on final" end
    if not airport(ac.arr) then return false, "not an arrival" end
    local star, ident = tostring(spec or ""):upper():match("^(%S+)%s+(%S+)$")
    local pr = procedure(star)
    if not pr or pr.type ~= "STAR" or pr.airport ~= ac.arr then return false, "unknown STAR " .. tostring(spec) end
    if not applySTAR(ac, star, ident) then return false, "no " .. tostring(star) .. " for runway " .. tostring(ident) end
    ac.climbOut = nil
    return true
end

function clearDirectTo(id)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac then return false, "unknown aircraft" end
    ac.dct = nil
    return true
end
