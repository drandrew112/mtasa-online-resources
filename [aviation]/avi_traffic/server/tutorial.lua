-- Tutorial aircraft (work_atc training modules ADC / APC / ACC). They are normal aircraft of this
-- simulation with ac.tut = the owner player, in a world of their own (sim.lua sameWorld): they do not
-- meet the live traffic, they are left out of getTrafficSnapshot / the traffic limits / the workload
-- keeper, and their separation losses fire onAviTutorialSeparationLoss (no fine) instead of
-- onAviSeparationLoss. Their controller is the tutorial position of the owner (avi_controller tutorial
-- login, which calls setTutorialController), by the normal sector rule: a tutorial tower has its CTR
-- only, a tutorial approach its TMA, a tutorial centre the CTA (it is the only open position of every
-- centre chain); every other position is closed, so the pilots fly on their own there.
-- Parked tutorial aircraft stay until removed. setTutorialTimeScale makes the owner's aircraft fly
-- faster (sim.lua runs that many steps per tick).
--
-- spawnTutorialFlight kinds:
--   dep        at a stand of icao, departing (a flight of the database with a SID first)
--   arr        in the CTR / TMA of icao, flying to the final fix of the arrival runway, cleared for the
--              approach (as approach would hand it to the tower)
--   tma_arr    an arrival to icao from outside, in the CTA def.dist m before its TMA entry fix at
--              def.alt ft, keeping that level until a controller has it; no arrival procedure of its own
--              (def.star = true: the pilots pick the STAR of the entry fix, as without radar)
--   inbound    an arrival to icao entering the CTA def.lead m before the border; no arrival procedure of
--              its own (def.star = true: the pilots pick one as usual)
--   overflight a flight between two external points, entering def.lead m before the border
-- spawnTutorialConflict: two overflights head-on on the same leg at the same level (radar training).

local positions = {}     -- [owner] = position id of the owner's tutorial login
local scales = {}        -- [owner] = whole number of simulation steps per tick (nil = 1)

-- the tutorial position of the owner (nil = not logged in), used by controllerOf
function tutorialPosition(owner)
    return positions[owner]
end

-- the time scale of the owner's tutorial aircraft (sim.lua tick)
function tutorialTimeScale(owner)
    return scales[owner] or 1
end

-- the work_atc training: scale = 1..TR.TUTORIAL_MAX_SCALE (whole steps), 1 = real time
function setTutorialTimeScale(owner, scale)
    if not isElement(owner) then return false end
    scale = math.floor(tonumber(scale) or 1)
    scale = math.max(1, math.min(TR.TUTORIAL_MAX_SCALE, scale))
    scales[owner] = scale > 1 and scale or nil
    return true
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

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
local function bearing(ax, ay, bx, by) return math.deg(math.atan2(bx - ax, by - ay)) % 360 end

local function pick(list)
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

-- the TMA entry of an arrival flight: the STAR of icao whose fix is in the route, its index there
local function entryOf(fl, icao)
    return procedureFor(icao, "STAR", upperList(fl.route))
end

-- a flight of the database to copy (type, route, cruise level)
--   dep: departures with a SID first;  arr: any arrival
--   tma_arr / inbound: arrivals from an external point with a TMA entry fix (not def.avoidFix first)
--   overflight: neither end is an airport, at least 3 fixes
local function template(kind, icao, def)
    local best, any = {}, {}
    local avoid = def and def.avoidFix and tostring(def.avoidFix):upper()
    for _, fl in ipairs(DB.flights) do
        if kind == "dep" and fl.dep == icao then
            any[#any + 1] = fl
            if procedureFor(icao, "SID", upperList(fl.route)) then best[#best + 1] = fl end
        elseif kind == "arr" and fl.arr == icao then
            any[#any + 1] = fl
        elseif (kind == "tma_arr" or kind == "inbound") and fl.arr == icao and not airport(fl.dep) then
            local p, i = entryOf(fl, icao)
            if p and i and i >= 2 then
                any[#any + 1] = fl
                if p.fix ~= avoid then best[#best + 1] = fl end
            end
        elseif kind == "overflight" and not airport(fl.dep) and not airport(fl.arr) and #(fl.route or {}) >= 3 then
            any[#any + 1] = fl
        end
    end
    return pick(#best > 0 and best or any)
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

-- on the inbound leg of the TMA entry fix, outside the TMA (in the CTA): the farthest distance of
-- TR.TUTORIAL_TMA_DIST (or `wanted`) that is still in the CTA. -> place, STAR procedure
local function tmaPlacement(fl, icao, alt, wanted)
    local p, i = entryOf(fl, icao)
    local e = p and navPoint(p.fix)
    local prev = i and i >= 2 and navPoint(tostring(fl.route[i - 1]):upper())
    if not (e and prev) then return nil end
    local h = bearing(prev.x, prev.y, e.x, e.y)
    local legLen = dist(prev.x, prev.y, e.x, e.y)
    local dists = wanted and { wanted } or TR.TUTORIAL_TMA_DIST
    local function at(d)
        d = math.min(d, legLen)
        local r = math.rad(h)
        return { x = e.x - math.sin(r) * d, y = e.y - math.cos(r) * d, hdg = h, alt = alt }
    end
    for _, d in ipairs(dists) do
        local pt = at(d)
        local sp = airspaceAt(pt.x, pt.y, alt)
        if sp and sp.type == "CTA" then return pt, p end
    end
    return at(dists[#dists]), p
end

local function copyFlight(tpl, callsign)
    return { callsign = tostring(callsign or "TUT1"):upper(), type = tpl.type, dep = tpl.dep, arr = tpl.arr,
        cruise = tpl.cruise, route = upperList(tpl.route) }
end

-- def = { kind, icao, callsign, gateWait = s (dep), dist = m, alt = ft (tma_arr), lead = m (inbound /
--         overflight), avoidFix (tma_arr / inbound), star = true (tma_arr / inbound) }
-- -> aircraft id | false, reason
function spawnTutorialFlight(owner, def)
    if not isElement(owner) or type(def) ~= "table" then return false, "bad arguments" end
    local kind = def.kind
    local icao = tostring(def.icao or ""):upper()
    if kind ~= "overflight" and not airport(icao) then return false, "unknown airport " .. icao end
    local tpl = template(kind, icao, def)
    if not tpl then return false, "no flight to copy for " .. tostring(kind) .. " " .. icao end
    local fl = copyFlight(tpl, def.callsign)
    local opts = { tut = owner }
    local entry
    if kind == "arr" then
        local place, ff = finalPlacement(icao)
        if not place then return false, "no final fix for the runway in use at " .. icao end
        fl.route = { ff.id }       -- straight in: the final fix, then the runway
        opts.final = place
    elseif kind == "tma_arr" then
        local alt = tonumber(def.alt) or TR.TUTORIAL_TMA_ALT
        local place, p = tmaPlacement(fl, icao, alt, tonumber(def.dist))
        if not place then return false, "no TMA entry for " .. fl.callsign end
        fl.route = { p.fix }       -- to the entry fix; the arrival procedure comes from approach
        opts.place = place
        entry = p.fix
    elseif kind == "inbound" or kind == "overflight" then
        opts.lead = tonumber(def.lead) or TR.TUTORIAL_ENTRY_LEAD
    elseif kind == "dep" then
        opts.gateWait = tonumber(def.gateWait) or 3
    else
        return false, "unknown kind " .. tostring(kind)
    end
    local ac, err = spawnFlight(fl, opts)
    if not ac then return false, err end
    ac.tutSqk = ac.sqk
    -- handed over by the (closed) approach: already cleared for the approach, the tower gives the
    -- landing clearance
    if kind == "arr" then ac.appClr = true end
    if kind == "tma_arr" then
        ac.keepLevel = true
        if not def.star then ac.starTried = true end
        ac.tutEntry = entry
    end
    if kind == "inbound" and not def.star then ac.starTried = true end
    return ac.id
end

-- Two overflights head-on on one leg of an overflight route, at the same level, def.dist m (default
-- TR.TUTORIAL_CONFLICT_DIST) each side of the middle of the leg: they meet there unless the
-- controller separates them. def = { callsigns = { cs1, cs2 }, alt = ft (default: the cruise level,
-- at least TR.TUTORIAL_CONFLICT_MIN_ALT), dist = m }
-- -> id1, id2 | false, reason
function spawnTutorialConflict(owner, def)
    if not isElement(owner) then return false, "bad arguments" end
    def = type(def) == "table" and def or {}
    local d = tonumber(def.dist) or TR.TUTORIAL_CONFLICT_DIST
    local cands = {}
    for _, fl in ipairs(DB.flights) do
        if not airport(fl.dep) and not airport(fl.arr) then
            local r = upperList(fl.route)
            for i = 1, #r - 1 do
                local a, b = navPoint(r[i]), navPoint(r[i + 1])
                if a and b and dist(a.x, a.y, b.x, b.y) >= 2 * d + 1500 then
                    cands[#cands + 1] = { fl = fl, i = i, a = a, b = b }
                end
            end
        end
    end
    local c = pick(cands)
    if not c then return false, "no overflight leg long enough" end
    local route = upperList(c.fl.route)
    local alt = tonumber(def.alt) or math.max(TR.TUTORIAL_CONFLICT_MIN_ALT, c.fl.cruise)
    alt = math.floor(alt / 1000 + 0.5) * 1000
    local mx, my = (c.a.x + c.b.x) / 2, (c.a.y + c.b.y) / 2
    local h = bearing(c.a.x, c.a.y, c.b.x, c.b.y)
    local r = math.rad(h)
    local ux, uy = math.sin(r), math.cos(r)
    local cs = type(def.callsigns) == "table" and def.callsigns or {}

    -- A: towards b, then the rest of the route
    local flA = copyFlight(c.fl, cs[1] or "TUT301")
    flA.cruise = alt
    flA.route = {}
    for j = c.i + 1, #route do flA.route[#flA.route + 1] = route[j] end
    -- B: the other way, the route back to its start
    local flB = copyFlight(c.fl, cs[2] or "TUT302")
    flB.dep, flB.arr, flB.cruise = c.fl.arr, c.fl.dep, alt
    flB.route = {}
    for j = c.i, 1, -1 do flB.route[#flB.route + 1] = route[j] end

    local a, errA = spawnFlight(flA, { tut = owner, place = { x = mx - ux * d, y = my - uy * d, hdg = h, alt = alt } })
    if not a then return false, errA end
    local b, errB = spawnFlight(flB, { tut = owner,
        place = { x = mx + ux * d, y = my + uy * d, hdg = (h + 180) % 360, alt = alt } })
    if not b then
        removeAircraft(a, "tutorial")
        return false, errB
    end
    a.tutSqk, b.tutSqk = a.sqk, b.sqk
    return a.id, b.id
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
    scales[source] = nil
end)
