-- police_system / modules/transport/server/transport.lua
-- Prisoner transport: an AI van (Enforcer 427) takes a cuffed suspect (NPC or player) to the nearest station, so the
-- unit does not have to drive there. Requested from the interact menu of a cuffed suspect (on foot or sitting in a
-- police car) or with the radio (REQUEST_TRANSPORT: the escorted / nearest cuffed suspect within REQUEST_DIST). The
-- officer first picks the charges, like at the station handover (client stop.lua "arrest:charges", mode "transport").
--
-- The van appears on the road network ARRIVAL s (navmesh travel time) away at a point nobody sees (like the tow truck), drives there
-- with emergency lights (emergency driving of ai_land_traffic) and stops next to the suspect. The suspect gets in
-- once it is within LOAD_DIST of the standing van (the officer escorts it there / parks next to it), otherwise the
-- van waits WAIT s and leaves. Loaded: the van is locked, drives to the tow point of the station (like the tow
-- truck, no lights). An NPC is handed over when the van gets there or as soon as nobody sees it (van and suspect
-- vanish together; checked here, not by ai_land_traffic's despawn, which would destroy the van first and drop the
-- suspect on the road); a player rides RIDE s (or until the station), then the screen fades out and the handover
-- (jail) happens like at the station marker (warrants served, report line, pay to the requesting officer's unit).
-- Van destroyed / gone before the end: failed, the suspect stays cuffed (out of the wreck), the officer is told.

local TR = POL.module("transport", { jobs = {} })   -- jobs[van] = { suspect, officer, unit, charges, state, ... }
local C = POLICE.TRANSPORT

local function traffic() return POL.running("ai_land_traffic") and exports.ai_land_traffic or nil end

function TR.jobOf(suspect)
    for _, j in pairs(TR.jobs) do if j.suspect == suspect then return j end end
    return nil
end

-- who can be sent: a cuffed suspect, on foot or in a vehicle that is not a transport van
local function eligible(suspect)
    if not isElement(suspect) or isPedDead(suspect) or not POL.arrest.isCuffed(suspect) or TR.jobOf(suspect) then return false end
    local veh = getPedOccupiedVehicle(suspect)
    return not (veh and TR.jobs[veh])
end

-- the suspect the radio request is about: the escorted one, else the nearest cuffed one (also in a car) close by
local function suspectNear(officer)
    local best, bd
    for t in pairs(POL.arrest.cuffed) do
        if eligible(t) then
            if POL.arrest.escorts[t] == officer then return t end
            local d = POL.dist(officer, t)
            if d <= C.REQUEST_DIST and (not bd or d < bd) then best, bd = t, d end
        end
    end
    return best
end

-- step 1: the charges menu (the officer ticks at least one, then Request transport)
function TR.ask(officer, suspect)
    if not POL.units.of(officer) then POL.notify(officer, "police_system.radio.not_in_unit") return false end
    suspect = suspect or suspectNear(officer)
    if not suspect or not eligible(suspect) then POL.notify(officer, "police_system.transport.no_suspect") return false end
    if POL.dist(officer, suspect) > C.REQUEST_DIST + 5 then POL.notify(officer, "police_system.arrest.err_too_far") return false end
    if not POL.inWorld(suspect) or not traffic() then POL.notify(officer, "police_system.transport.unavailable") return false end
    POL.records.citizenOf(suspect, function(row)
        if not isElement(officer) or not isElement(suspect) then return end
        local name = row and POL.records.nameOf(row) or "?"
        POL.send(officer, "arrest:charges", suspect, L.forPlayer(officer, "police_system.transport.charges_title", { name = name }),
            POL.arrest.chargeItems(officer), "transport")
    end)
    return true
end

local function dropBlip(job)
    if isElement(job.blip) then destroyElement(job.blip) end
    job.blip = nil
end

local function lights(van, on)
    if not POL.running("v_els") then return end
    pcall(function()
        exports.v_els:setElsLights(van, on)
        exports.v_els:setElsSiren(van, false)
    end)
end

-- the van goes (unseen) without the job; a van that is no traffic vehicle any more (crashed: physics) is removed
-- by the tick once nobody sees it
TR.leftovers = {}
local function sendAway(job)
    local t = traffic()
    local van = job.van
    if not isElement(van) then return end
    lights(van, false)
    if t and t:isScriptedVehicle(van) then
        t:continueScriptedVehicle(van)
        t:clearScriptedTargets(van)
        t:setScriptedDespawnUnseen(van, { minDist = 60 })
    else
        TR.leftovers[van] = job.driver or true
        TR.ensureTimer()
    end
end

local function fail(job, key)
    if job.done then return end
    job.done = true
    dropBlip(job)
    TR.jobs[job.van] = nil
    local s = job.suspect
    if isElement(s) and isElement(job.van) and getPedOccupiedVehicle(s) == job.van then POL.arrest.unload(s) end
    if isElement(s) and getElementType(s) == "player" then fadeCamera(s, true, 0.5) end
    sendAway(job)
    if isElement(job.officer) then POL.notify(job.officer, key or "police_system.transport.failed") end
end

-- step 2: the officer picked the charges
function TR.request(officer, suspect, charges)
    if not POL.units.of(officer) or not eligible(suspect) then POL.notify(officer, "police_system.transport.no_suspect") return false end
    local t = traffic()
    if not t or not POL.inWorld(suspect) then POL.notify(officer, "police_system.transport.unavailable") return false end
    local x, y, z = POL.pos(suspect)
    local sx, sy, sz, rot = POL.arrivalSpawn(t, C, x, y, z, "emergency", { x, y })
    if not sx then POL.notify(officer, "police_system.transport.unavailable") return false end
    local van, driver = t:createScriptedVehicle(C.MODEL, sx, sy, sz, { heading = rot, skin = C.SKIN, profile = "pursuit",
        speedFactor = C.SPEED_FACTOR, keepDriver = true })
    if not van then POL.notify(officer, "police_system.transport.unavailable") return false end
    setVehiclePlateText(van, "SAPD" .. math.random(100, 999))
    setVehicleLocked(van, true)
    setElementData(van, "pol.transport", true)
    lights(van, true)
    local job = { van = van, driver = driver, suspect = suspect, officer = officer, unit = POL.units.of(officer),
                  charges = charges, state = "coming", at = getTickCount() }
    TR.jobs[van] = job
    job.blip = createBlipAttachedTo(van, 0, 2, 255, 220, 0, 255, 5, 99999, officer)
    t:addScriptedStop(van, x, y, z, { tag = "transport_pickup", hold = true, radius = 40 })
    POL.events.logFor(officer, "transport_requested", { name = POL.stop.nameOf(suspect) })
    POL.notify(officer, "police_system.transport.coming")
    TR.ensureTimer()
    return true
end

-- the suspect is close to the standing van: in, doors shut, off to the station
local function load(job)
    local van, s = job.van, job.suspect
    if not POL.arrest.loadInto(s, van, C.SEATS) then return fail(job, "police_system.transport.failed_full") end
    job.state = "transport"
    job.loadedAt = getTickCount()
    dropBlip(job)
    lights(van, false)
    setTimer(function()
        if not isElement(van) then return end
        setVehicleDoorOpenRatio(van, 4, 0, 600)
        setVehicleDoorOpenRatio(van, 5, 0, 600)
    end, 1200, 1)
    local t = traffic()
    local x, y = POL.pos(van)
    local st = POL.nearestStation(x, y)
    job.station = st
    if t then
        t:setScriptedEmergency(van, false)
        t:continueScriptedVehicle(van)
        t:clearScriptedTargets(van)
        local p = st.tow or st.handover
        t:addScriptedStop(van, p[1], p[2], p[3], { tag = "transport_station", hold = true, radius = 60 })
        -- an NPC goes as soon as nobody sees the van (tick); a player rides along until RIDE / the station
    end
    if isElement(job.officer) then POL.notify(job.officer, "police_system.transport.loaded", { name = POL.stop.nameOf(s) }) end
    if getElementType(s) == "player" then POL.notify(s, "police_system.transport.you_are_transported") end
end

-- the van disappears at once (with its driver)
local function vanish(job)
    local van = job.van
    local t = traffic()
    if isElement(van) and not (t and t:destroyScriptedVehicle(van)) and isElement(van) then destroyElement(van) end
    if isElement(job.driver) then destroyElement(job.driver) end
end

-- the handover at the station (arrest.lua); with an NPC suspect the van vanishes with it, with a player it drives
-- off and goes when unseen
local function deliver(job)
    if job.done then return end
    job.done = true
    dropBlip(job)
    TR.jobs[job.van] = nil
    local s = job.suspect
    local npc = isElement(s) and getElementType(s) ~= "player"
    local st = job.station or (isElement(job.van) and POL.nearestStation(POL.pos(job.van))) or POLICE.STATIONS[1]
    if isElement(s) and POL.arrest.isCuffed(s) then
        if npc then
            -- hidden before it leaves the seat: the handover (async name lookup) destroys it a moment later
            setElementAlpha(s, 0)
            setElementCollisionsEnabled(s, false)
            setElementFrozen(s, true)
        end
        POL.arrest.unload(s)
        POL.arrest.handover(job.officer, s, st, job.charges)
        if isElement(job.officer) then POL.notify(job.officer, "police_system.transport.delivered", { name = POL.stop.nameOf(s) }) end
    end
    if isElement(s) and getElementType(s) == "player" then
        setTimer(function() if isElement(s) then fadeCamera(s, true, 1) end end, 2500, 1)
    end
    POL.db.stat("transports", 1)
    if npc then vanish(job) else sendAway(job) end
end

-- a player suspect: the screen fades out, the handover a moment later
local function deliverPlayer(job)
    if job.fading then return end
    job.fading = true
    fadeCamera(job.suspect, false, 1)
    setTimer(function() deliver(job) end, 1200, 1)
end

------------------------------------------------------------------------ 1 Hz check

local function tick()
    local now = getTickCount()
    local t = traffic()
    for van, driver in pairs(TR.leftovers) do
        if not isElement(van) then
            TR.leftovers[van] = nil
        elseif not (t and t:isElementSeenByPlayers(van)) then
            local x, y, z = getElementPosition(van)
            if #getElementsWithinRange(x, y, z, 60, "player") == 0 then
                TR.leftovers[van] = nil
                if isElement(driver) then destroyElement(driver) end
                destroyElement(van)
            end
        end
    end
    for van, job in pairs(TR.jobs) do
        local s = job.suspect
        if not isElement(van) or isVehicleBlown(van) then
            fail(job)
        elseif not isElement(s) or isPedDead(s) or not POL.arrest.isCuffed(s) then
            -- uncuffed / dead / gone meanwhile: nothing to take
            fail(job, job.state == "transport" and "police_system.transport.failed" or "police_system.transport.cancelled")
        elseif job.state == "waiting" then
            local sv = getPedOccupiedVehicle(s)
            if POL.dist(van, s) <= C.LOAD_DIST and (not sv or sv ~= van) then
                load(job)
            elseif now - job.waitAt > C.WAIT * 1000 then
                fail(job, "police_system.transport.left")
            end
        elseif job.state == "transport" and getElementType(s) == "player" then
            if now - job.loadedAt > C.RIDE * 1000 then deliverPlayer(job) end
        elseif job.state == "transport" then
            -- NPC: van and suspect vanish once no camera sees the van and no player is close
            local x, y, z = getElementPosition(van)
            if not (t and t:isElementSeenByPlayers(van)) and #getElementsWithinRange(x, y, z, 60, "player") == 0 then
                deliver(job)
            end
        elseif job.state == "coming" and now - job.at > 240000 then
            fail(job)   -- never got there (no route)
        end
    end
end

local timer
function TR.ensureTimer()
    if timer then return end
    timer = setTimer(function()
        if not next(TR.jobs) and not next(TR.leftovers) then killTimer(timer); timer = nil return end
        local ok, err = pcall(tick)
        if not ok then outputDebugString("[police_system] transport: " .. tostring(err), 1) end
    end, 1000, 0)
end

------------------------------------------------------------------------ ai_land_traffic events

addEvent("onTrafficVehicleTargetReached")
addEventHandler("onTrafficVehicleTargetReached", root, function(van, id, kind, tag)
    local job = TR.jobs[van]
    if not job then return end
    if tag == "transport_pickup" and job.state == "coming" then
        job.state = "waiting"
        job.waitAt = getTickCount()
        setVehicleDoorOpenRatio(van, 4, 1, 800)
        setVehicleDoorOpenRatio(van, 5, 1, 800)
        if isElement(job.officer) and POL.dist(van, job.suspect) > C.LOAD_DIST then
            POL.notify(job.officer, "police_system.transport.arrived", { seconds = C.WAIT })
        end
    elseif tag == "transport_station" and job.state == "transport" then
        if getElementType(job.suspect) == "player" then deliverPlayer(job) else deliver(job) end
    end
end)

addEvent("onTrafficVehicleRemoved")
addEventHandler("onTrafficVehicleRemoved", root, function(van, reason)
    local job = TR.jobs[van]
    if not job then return end
    if job.state == "transport" and reason ~= "vehicle_destroyed" and not (isElement(van) and isVehicleBlown(van)) then
        -- gone with the suspect (the van may already be destroyed) / crashed on the way: handed over now
        if getElementType(job.suspect) == "player" then deliverPlayer(job) else deliver(job) end
    else
        fail(job)
    end
end)

addEventHandler("onVehicleExplode", root, function()
    local job = TR.jobs[source]
    if job then fail(job) end
end)

-- nobody gets into the van
addEventHandler("onVehicleStartEnter", root, function()
    if TR.jobs[source] then cancelEvent() end
end)

addEventHandler("onPlayerQuit", root, function()
    -- a player suspect quitting: the cuffed-quit warrant is made by wanted.lua; the van leaves
    local job = TR.jobOf(source)
    if job then fail(job, "police_system.transport.cancelled") end
    for _, j in pairs(TR.jobs) do if j.officer == source then j.officer = nil end end
end)

------------------------------------------------------------------------ requests

-- the officer picked the charges in the menu (mode "transport") and pressed Request transport
POL.net("transport:request", function(officer, suspect, charges)
    if not POL.rights.has(officer) or not isElement(suspect) then return end
    local valid, seen = {}, {}
    for _, id in ipairs(type(charges) == "table" and charges or {}) do
        if POL.arrest.isCharge(id) and not seen[id] then seen[id] = true; valid[#valid + 1] = id end
    end
    if #valid == 0 then return POL.notify(officer, "police_system.arrest.err_no_charges") end
    TR.request(officer, suspect, valid)
end)

-- MDC / tests: the transport jobs of a unit
function TR.forUnit(unit)
    local out = {}
    for van, j in pairs(TR.jobs) do
        if j.unit == unit and isElement(van) then
            out[#out + 1] = { name = POL.stop.nameOf(j.suspect), state = j.state, distance = math.floor(POL.dist(van, j.suspect)) }
        end
    end
    return out
end

function TR.stop()
    for van, job in pairs(TR.jobs) do
        local s = job.suspect
        if isElement(s) and getElementType(s) == "player" then fadeCamera(s, true, 0) end
        if isElement(s) and getPedOccupiedVehicle(s) == van then removePedFromVehicle(s) end
        local t = traffic()
        if isElement(van) and not (t and t:destroyScriptedVehicle(van)) and isElement(van) then destroyElement(van) end
        if isElement(job.driver) then destroyElement(job.driver) end
    end
    for van, driver in pairs(TR.leftovers) do
        if isElement(driver) then destroyElement(driver) end
        if isElement(van) then destroyElement(van) end
    end
    TR.jobs, TR.leftovers = {}, {}
end
