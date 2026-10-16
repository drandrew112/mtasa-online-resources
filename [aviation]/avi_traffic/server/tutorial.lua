-- Tutorial aircraft (work_atc tutorial). They are normal aircraft of this simulation with
-- ac.tut = the owner player, in a world of their own (sim.lua sameWorld): they do not meet the live
-- traffic, they are left out of getTrafficSnapshot / the traffic limits / the workload keeper, and
-- their separation losses fire onAviTutorialSeparationLoss (no fine) instead of onAviSeparationLoss.
-- Their controller is the tutorial position of the owner (avi_controller tutorial login, which calls
-- setTutorialController), by the normal sector rule, also in the approach sector of its airport
-- (ac.tutCover). Parked tutorial aircraft stay until removed.

local positions = {}     -- [owner] = position id of the owner's tutorial login

-- the tutorial position of the owner (nil = not logged in), used by controllerOf
function tutorialPosition(owner)
    return positions[owner]
end

-- avi_controller: the owner logged in to (posId) / out of (nil) the tutorial position
function setTutorialController(owner, posId)
    if not isElement(owner) then return false end
    positions[owner] = posId and tostring(posId) or nil
    return true
end

local function upperList(list)
    local out = {}
    for i, f in ipairs(list or {}) do out[i] = tostring(f):upper() end
    return out
end

-- a flight of the database to copy (type, route, cruise level): departures with a SID first
local function template(kind, icao)
    local best, any = {}, {}
    for _, fl in ipairs(DB.flights) do
        if kind == "dep" and fl.dep == icao then
            any[#any + 1] = fl
            if procedureFor(icao, "SID", upperList(fl.route)) then best[#best + 1] = fl end
        elseif kind == "arr" and fl.arr == icao then
            any[#any + 1] = fl
        end
    end
    local list = #best > 0 and best or any
    return list[math.random(#list)]
end

-- in the CTR / TMA of the airport, flying to the final fix of the arrival runway in use: straight in
-- on the extended centre line when the airspace reaches out there, else from the side
-- (TR.TUTORIAL_FINAL_ANGLES x TR.TUTORIAL_FINAL_DIST), level at TR.FINAL_AGL + 300 ft
local function finalPlacement(icao)
    local a = airport(icao)
    local rwy = callExport("avi_airports", "getActiveRunway", icao, "arr")
    local ff = rwy and navPoint(rwy.final)
    if not (a and ff) then return nil end
    local alt = math.floor((a.elevation + TR.FINAL_AGL + 300) / 100 + 0.5) * 100
    local function at(angle, d)
        local h = math.rad(rwy.hdg + 180 + angle)       -- from the final fix back out
        local x, y = ff.x + math.sin(h) * d, ff.y + math.cos(h) * d
        local toFix = math.deg(math.atan2(ff.x - x, ff.y - y)) % 360
        return { x = x, y = y, hdg = toFix, alt = alt, rwy = rwy }
    end
    -- the farthest point first (time for the clearances), the straightest one at that distance
    for _, d in ipairs(TR.TUTORIAL_FINAL_DIST) do
        for _, angle in ipairs(TR.TUTORIAL_FINAL_ANGLES) do
            local p = at(angle, d)
            local sp = airspaceAt(p.x, p.y, alt)
            if sp and (sp.type == "CTR" or sp.type == "TMA") and sp.airport == icao then return p, ff end
        end
    end
    local dists = TR.TUTORIAL_FINAL_DIST
    return at(0, dists[#dists]), ff
end

-- def = { kind = "dep" | "arr", icao, callsign, gateWait = s (departures) }
-- -> aircraft id | false, reason
function spawnTutorialFlight(owner, def)
    if not isElement(owner) or type(def) ~= "table" then return false, "bad arguments" end
    local icao = tostring(def.icao or ""):upper()
    if not airport(icao) then return false, "unknown airport " .. icao end
    local tpl = template(def.kind, icao)
    if not tpl then return false, "no flight to copy at " .. icao end
    local fl = { callsign = tostring(def.callsign or "TUT1"):upper(), type = tpl.type, dep = tpl.dep, arr = tpl.arr,
        cruise = tpl.cruise, route = tpl.route }
    local opts = { tut = owner }
    if def.kind == "arr" then
        local place, ff = finalPlacement(icao)
        if not place then return false, "no final fix for the runway in use at " .. icao end
        fl.route = { ff.id }       -- straight in: the final fix, then the runway
        opts.final = place
    else
        opts.gateWait = tonumber(def.gateWait) or 3
    end
    local ac, err = spawnFlight(fl, opts)
    if not ac then return false, err end
    ac.tutSqk = ac.sqk
    -- the tutorial tower covers the closed approach position of the airport for its aircraft: the
    -- tower CTR is often only a strip along the runway (SASF: 2000 ft high), too small to practise
    -- levels / headings after take-off or an approach
    ac.tutCover = icao .. "_APP"
    return ac.id
end

-- -> { snapshot, ... } of the owner's tutorial aircraft
function getTutorialSnapshot(owner)
    local list = {}
    for _, ac in pairs(AIRCRAFT) do
        if ac.tut == owner then list[#list + 1] = snapshot(ac) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- the owner player of a tutorial aircraft (nil = live traffic / unknown)
function getTutorialOwner(id)
    local ac = AIRCRAFT[tonumber(id)]
    return ac and ac.tut or nil
end

-- the alert demonstration: code = "7700" / "7600" / ..., nil = back to the own squawk
function setTutorialSquawk(owner, id, code)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac or ac.tut ~= owner then return false, "not a tutorial aircraft of this player" end
    code = code and tostring(code) or ac.tutSqk
    if not tostring(code):match("^[0-7][0-7][0-7][0-7]$") then return false, "bad squawk" end
    ac.sqk = code
    return true
end

function removeTutorialFlight(owner, id)
    local ac = AIRCRAFT[tonumber(id)]
    if not ac or ac.tut ~= owner then return false end
    removeAircraft(ac, "tutorial")
    return true
end

function removeTutorialFlights(owner)
    for _, ac in pairs(AIRCRAFT) do
        if ac.tut == owner then removeAircraft(ac, "tutorial") end
    end
    return true
end

addEventHandler("onPlayerQuit", root, function()
    removeTutorialFlights(source)
    positions[source] = nil
end)
