-- police_system / modules/ai/server/tactics.lua
-- What an AI unit does (2 Hz while there are units):
--   chase      far: the lane pursuit of the traffic simulation; near: physics, steered by the syncer (chase motor
--              of ai_land_traffic: follow / box / pit / ram by the level)
--   intercept  (level >= 2, not while evading) drives to a point on the predicted path ahead of the suspect, then
--              blocks it
--   roadblock  (level >= 4) two units park across the predicted path ROADBLOCK_AHEAD m ahead, the crews get out
--   foot       the suspect stopped / is on foot within FOOT_DIST: the crew gets out (ai_peds "police"); level 1 walks
--              up and arrests after ARREST_TIME next to it ("Busted"), from level 2 they shoot (accuracy by level)
--              unless the suspect surrendered. The suspect drives off: back in, chase on.
--   search     evading: lights only, the units drive around the last known position, no interception
-- Tank (levels 5-6): rams, fires the cannon in front of it.

local T = {}
POL.ai.tactics = T
local A = POLICE.AI
local AI = POL.ai

local function traffic() return POL.running("ai_land_traffic") and exports.ai_land_traffic or nil end
local function aipeds() return POL.running("ai_peds") and exports.ai_peds or nil end

local function levelOf(c) return A.LEVELS[math.max(1, math.min(6, c and c.level or 1))] end

local function crew(unit)
    local list = {}
    if unit.driver and isElement(unit.driver) and not isPedDead(unit.driver) then list[#list + 1] = unit.driver end
    if unit.partner and isElement(unit.partner) and not isPedDead(unit.partner) then list[#list + 1] = unit.partner end
    return list
end

function T.crewOut(unit)
    for _, p in ipairs(crew(unit)) do
        if getPedOccupiedVehicle(p) ~= unit.veh then return true end
    end
    return false
end

local function suspectVehicle(s)
    return isElement(s) and getElementType(s) ~= "vehicle" and getPedOccupiedVehicle(s) or nil
end

function T.motorOpts(unit, mode)
    local c = unit.chase
    local L = levelOf(c)
    if unit.tank then return { mode = "ram", aggression = 1, maxSpeed = 70, fire = c and c.level >= 5 } end
    return { mode = mode or L.mode, aggression = L.aggression, maxSpeed = 200 }
end

-- (re)start chasing the suspect (siren on, chase motor)
function T.engage(unit, physics)
    local t = traffic()
    local c = unit.chase
    if not t or not c or not isElement(unit.veh) or not isElement(c.suspect) then return end
    unit.state = "chase"
    if unit.parked then setElementFrozen(unit.veh, false); unit.parked = false end
    POL.ai.sirens.on(unit)
    t:setScriptedChase(unit.veh, c.suspect, T.motorOpts(unit, unit.role == "intercept" and "block" or nil))
end

------------------------------------------------------------------------ crew in / out

function T.board(unit)
    local p = aipeds()
    unit.state = unit.state == "retreat" and "retreat" or "boarding"
    unit.boardAt = getTickCount()
    for _, ped in ipairs(crew(unit)) do
        if getPedOccupiedVehicle(ped) ~= unit.veh and p then
            p:aiPedEnterVehicle(ped, unit.veh, ped == unit.driver and 0 or 1)
        end
    end
end

local function footArgs(unit)
    local c = unit.chase
    local L = levelOf(c)
    local armed = L.armed and not (c and c.surrendered)
    return { target = c and c.suspect, armed = armed, accuracy = L.accuracy, arrestDist = A.ARREST_DIST,
             arrestTime = A.ARREST_TIME }, armed, L
end

local function toFoot(unit)
    local t, p = traffic(), aipeds()
    if not t or not p then return end
    unit.state = "foot"
    -- physics vehicle with its crew, kept by the chase motor without switching back into the simulation
    t:setScriptedChase(unit.veh, unit.chase.suspect, { mode = "follow", auto = false, maxSpeed = 0 })
    -- the partner sat in a simulated vehicle without syncing (its server position is the spawn point): it needs a
    -- syncer near the vehicle to get out
    if unit.partner and isElement(unit.partner) and getPedOccupiedVehicle(unit.partner) == unit.veh then
        local x, y, z = getElementPosition(unit.veh)
        setElementPosition(unit.partner, x, y, z + 0.6, false)
        setElementSyncer(unit.partner, true)
    end
    local args, armed, L = footArgs(unit)
    for _, ped in ipairs(crew(unit)) do
        if p:isAIPed(ped) then
            unit.pendingArgs = args
            if getPedOccupiedVehicle(ped) then p:aiPedExitVehicle(ped) else p:setAIPedBehaviour(ped, "police", args) end
        else
            p:adoptTrafficDriver(ped, unit.veh, { behaviour = "police", args = args, keep = true, group = "police" })
        end
        p:setAIPedGroup(ped, "police")
        if armed and L.weapon then p:giveAIPedWeapon(ped, L.weapon, 9999) end
    end
end

-- the crew of a unit got its behaviour arguments again (level / surrender changed)
local function refreshFoot(unit)
    local p = aipeds()
    if not p then return end
    local args, armed, L = footArgs(unit)
    local key = tostring(args.armed) .. ":" .. tostring(args.accuracy)
    if unit.footKey == key then return end
    unit.footKey = key
    for _, ped in ipairs(crew(unit)) do
        if not getPedOccupiedVehicle(ped) and p:isAIPed(ped) then
            if armed and L.weapon then p:giveAIPedWeapon(ped, L.weapon, 9999) end
            p:setAIPedBehaviour(ped, "police", args)
        end
    end
end

addEvent("onAIPedExitedVehicle")
addEventHandler("onAIPedExitedVehicle", root, function()
    local unit = AI.peds[source]
    if unit and unit.state == "foot" and unit.pendingArgs and POL.running("ai_peds") then
        exports.ai_peds:setAIPedBehaviour(source, "police", unit.pendingArgs)
    end
end)

addEvent("onAIPedEnteredVehicle")
addEventHandler("onAIPedEnteredVehicle", root, function(veh)
    local unit = AI.peds[source]
    if not unit or veh ~= unit.veh or T.crewOut(unit) then return end
    unit.footKey = nil
    if unit.state == "retreat" then
        AI.leave(unit)
    elseif unit.chase then
        T.engage(unit, true)
    end
end)

-- level 1: the officer stood next to the suspect long enough
addEvent("onAIPedArrestTarget")
addEventHandler("onAIPedArrestTarget", root, function(target)
    local unit = AI.peds[source]
    if not unit or not unit.chase or unit.chase.suspect ~= target then return end
    local c = unit.chase
    if c.level <= 1 or c.surrendered then POL.arrest.aiArrest(target, unit) end
end)

------------------------------------------------------------------------ search (evading)

local function searchPoint(unit)
    local t = traffic()
    local c = unit.chase
    if not t or not c or not c.lastX then return end
    if not t:isScriptedVehicle(unit.veh) then return end
    local a = math.random() * math.pi * 2
    local r = math.random(30, A.SEARCH_RADIUS)
    t:clearScriptedTargets(unit.veh)
    t:addScriptedTurnPoint(unit.veh, c.lastX + math.cos(a) * r, c.lastY + math.sin(a) * r, c.lastZ, { tag = "search", radius = 80 })
    unit.searchAt = getTickCount()
end

local function toSearch(unit)
    local t = traffic()
    if not t then return end
    if T.crewOut(unit) then T.board(unit) return end
    unit.state = "search"
    POL.ai.sirens.off(unit, false)
    t:setScriptedChase(unit.veh, false)
    searchPoint(unit)
end

------------------------------------------------------------------------ intercept / roadblock

-- point on the predicted path `ahead` metres from its start
local function pointAhead(pts, ahead)
    if not pts or #pts < 2 then return nil end
    local d = 0
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        d = d + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        if d >= ahead then
            local rot = math.deg(math.atan2(b[2] - a[2], b[1] - a[1])) - 90
            return b[1], b[2], b[3], rot
        end
    end
    local l = pts[#pts]
    return l[1], l[2], l[3], 0
end

local function interceptStep(unit, now)
    local t = traffic()
    local c = unit.chase
    if not t or not c.predicted then return end
    local d = POL.dist(unit.veh, c.suspect)
    if d < POLICE.AI.FOOT_DIST * 3 then
        -- close: block it with the chase motor
        if not unit.blocking then unit.blocking = true; T.engage(unit, false) end
        return
    end
    unit.blocking = false
    if now - (unit.interceptAt or 0) < 4000 then return end
    unit.interceptAt = now
    local x, y, z = pointAhead(c.predicted, math.min(300, d * 0.6))
    if not x then return end
    t:setScriptedChase(unit.veh, false)
    if t:isScriptedVehicle(unit.veh) then
        t:clearScriptedTargets(unit.veh)
        t:addScriptedTurnPoint(unit.veh, x, y, z, { tag = "intercept", radius = 60 })
    end
end

local function roadblockStep(c, now)
    local L = levelOf(c)
    if not L.roadblock or c.phase ~= "active" or not c.predicted then return end
    local rb = c.roadblock
    if rb then
        -- passed or old: the road block units chase again
        local sx, sy = getElementPosition(c.suspect)
        if now - rb.at > 90000 or ((sx - rb.x) ^ 2 + (sy - rb.y) ^ 2 > 350 ^ 2 and rb.parked) then
            for _, u in ipairs(rb.units) do
                if AI.units[u.veh] and u.state ~= "retreat" then u.role = "tail"; T.board(u) end
            end
            c.roadblock = nil
        end
        return
    end
    local x, y, z, rot = pointAhead(c.predicted, A.ROADBLOCK_AHEAD)
    if not x then return end
    local pick = {}
    for _, u in pairs(AI.units) do
        if u.chase == c and not u.tank and u.state == "chase" and isElement(u.veh) and POL.dist(u.veh, c.suspect) > 150 then
            pick[#pick + 1] = u
        end
    end
    if #pick < 2 then return end
    local t = traffic()
    rb = { x = x, y = y, z = z, rot = rot, at = now, units = { pick[1], pick[2] } }
    c.roadblock = rb
    for i, u in ipairs(rb.units) do
        u.role = "roadblock"
        u.state = "roadblock"
        u.rbSlot = i
        t:setScriptedChase(u.veh, false)
        if t:isScriptedVehicle(u.veh) then
            t:clearScriptedTargets(u.veh)
            t:addScriptedStop(u.veh, x, y, z, { tag = "roadblock", hold = true, radius = 60 })
        end
    end
end

addEvent("onTrafficVehicleTargetReached")
addEventHandler("onTrafficVehicleTargetReached", root, function(veh, id, kind, tag, x, y, z)
    local unit = AI.units[veh]
    if not unit then return end
    if tag == "search" and unit.state == "search" then
        searchPoint(unit)
    elseif tag == "roadblock" and unit.state == "roadblock" and unit.chase and unit.chase.roadblock then
        local rb = unit.chase.roadblock
        local a = math.rad(rb.rot)
        local off = unit.rbSlot == 1 and -2.8 or 2.8
        -- across the road: rotated 90 degrees, side by side
        local t = traffic()
        if t and t:parkScriptedVehicle(veh, rb.x + math.cos(a) * off, rb.y + math.sin(a) * off, rb.z, rb.rot + 90) then
            unit.parked = true
            rb.parked = true
            toFoot(unit)
        end
    end
end)

------------------------------------------------------------------------ the 2 Hz loop

function T.update(unit, d)
    unit.demand = d
    T.ensureTimer()
end

local function step(unit, now)
    local c = unit.chase
    if not c or unit.state == "retreat" then return end
    if unit.dead or not isElement(unit.veh) or isVehicleBlown(unit.veh) then return AI.retreat(unit) end
    local d = unit.demand or {}
    local s = c.suspect
    if not isElement(s) then return end
    POL.ai.sirens.tick(unit, now)
    -- not in the world (interior): the unit waits where it is
    if not d.inWorld then return end
    if d.phase ~= "active" then
        if unit.state ~= "search" and unit.state ~= "boarding" then toSearch(unit) end
        if unit.state == "search" and now - (unit.searchAt or 0) > 20000 then searchPoint(unit) end
        return
    end
    if unit.state == "search" then
        unit.role = "tail"
        T.engage(unit, false)
        return
    end
    if unit.state == "boarding" then
        if now - (unit.boardAt or 0) > 15000 and not T.crewOut(unit) then T.engage(unit, true) end
        return
    end
    local sveh = suspectVehicle(s)
    local dist = POL.dist(unit.veh, s)
    if unit.state == "foot" or unit.state == "roadblock" and unit.parked then
        refreshFoot(unit)
        -- the suspect drove off: back in
        if sveh and POL.speed(sveh) > 6 and dist > A.BACK_TO_CAR and not c.surrendered then T.board(unit) end
        return
    end
    if unit.state == "roadblock" then return end
    -- crew out when the suspect stands / is on foot / surrendered close by
    local still = not sveh or POL.speed(sveh) < 1 or c.surrendered
    if still and dist < A.FOOT_DIST and not unit.tank then return toFoot(unit) end
    if unit.role == "intercept" then interceptStep(unit, now) end
end

local timer
function T.ensureTimer()
    if timer then return end
    timer = setTimer(function()
        if not next(AI.units) then killTimer(timer); timer = nil return end
        local now = getTickCount()
        local chases = {}
        for _, u in pairs(AI.units) do
            local ok, err = pcall(step, u, now)
            if not ok then outputDebugString("[police_system] ai: " .. tostring(err), 1) end
            if u.chase then chases[u.chase] = true end
        end
        for c in pairs(chases) do pcall(roadblockStep, c, now) end
    end, A.TICK, 0)
end

-- the second and further units of a chase from level 2 cut it off
POL.on("ai.spawned", function(unit) end)
local spawn = AI.spawn
function AI.spawn(c, tank)
    local unit = spawn(c, tank)
    if unit and not tank and c.level >= A.INTERCEPT_LEVEL then
        local tails = 0
        for _, u in pairs(AI.units) do if u.chase == c and u.role == "tail" and u ~= unit then tails = tails + 1 end end
        if tails >= 1 and math.random() < 0.6 then unit.role = "intercept" end
    end
    if unit then T.ensureTimer() end
    return unit
end
