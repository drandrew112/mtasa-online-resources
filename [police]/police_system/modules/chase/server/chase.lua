-- police_system / modules/chase/server/chase.lua
-- The pursuit module is the ONLY one that asks for AI police. Once a second it walks the wanted players (and the
-- fleeing NPCs) and computes a demand for each chase; the AI module (ai/) fulfils it: it decides where a unit appears
-- and exactly what it does. No demand = the AI units retreat and vanish unseen.
--
-- chase = { id, suspect, kind ("player" | "npc"), level, phase, startedAt, units = { [unit] = true }, blips,
--           predicted = { {x, y, z}, ... }, predAt, notStopping (s), lastSeenX/Y/Z, vehicle }
-- Player units start one with F4 / STATUS_PURSUIT on a target (the stopped vehicle / the vehicle in front) or join
-- one on the MDC Pursuits page. A player target that does not stop gets the "failure to stop" escalation.

local CH = POL.module("chase", { list = {}, seq = 0 })
local C = POLICE.CHASE

function CH.of(suspect) return CH.list[suspect] end

local function suspectVehicle(s)
    if not isElement(s) then return nil end
    if getElementType(s) == "vehicle" then return s end
    return getPedOccupiedVehicle(s)
end

local function newChase(suspect, kind)
    CH.seq = CH.seq + 1
    local c = { id = CH.seq, suspect = suspect, kind = kind, level = 0, phase = "active", startedAt = POL.now(),
                units = {}, blips = {}, notStopping = 0 }
    CH.list[suspect] = c
    POL.db.stat("pursuits", 1)
    POL.emit("chase.started", c)
    CH.ensureTimer()
    return c
end

local function playerUnits(c)
    local n = 0
    for u in pairs(c.units) do if POL.units.list[u.id] then n = n + 1 else c.units[u] = nil end end
    return n
end

------------------------------------------------------------------------ unit blips (only the unit's members)

local function refreshBlips(c)
    local hide = c.phase ~= "active"
    for unit in pairs(c.units) do
        local b = c.blips[unit]
        if hide or not POL.units.list[unit.id] then
            if b and isElement(b) then destroyElement(b) end
            c.blips[unit] = nil
        else
            if not (b and isElement(b)) then
                b = createBlipAttachedTo(c.suspect, 0, 2, 235, 64, 64, 255, 10, 99999, root)
                setElementVisibleTo(b, root, false)
                c.blips[unit] = b
            end
            for _, p in ipairs(POL.units.members(unit)) do setElementVisibleTo(b, p, true) end
        end
    end
end

------------------------------------------------------------------------ joining / leaving

function CH.join(player, c)
    local unit = POL.units.of(player)
    if not unit or not c then return false end
    if not c.units[unit] then
        c.units[unit] = true
        local inc = POL.events.open(unit, "pursuit", c.subject)
        inc.el = c.suspect
        inc.zone = getZoneName(getElementPosition(c.suspect))
        inc.level = c.level
        POL.events.log(unit, player, "pursuit_start", { name = c.name, level = c.level }, inc)
        if c.kind == "player" then POL.emit("chase.unitJoined", c.suspect, unit) end
    end
    POL.units.setStatus(unit, "pursuit", player)
    refreshBlips(c)
    POL.emit("chase.changed", c)
    return true
end

function CH.leaveUnit(unit)
    for _, c in pairs(CH.list) do
        if c.units[unit] then
            c.units[unit] = nil
            local b = c.blips[unit]
            if b and isElement(b) then destroyElement(b) end
            c.blips[unit] = nil
        end
    end
end

-- F4 / STATUS_PURSUIT: target = a vehicle or a ped / player
function CH.start(player, target)
    local unit = POL.units.of(player)
    if not unit then return false, "not_in_unit" end
    if not isElement(target) then
        -- no target: just the status (e.g. joining a chase over the radio)
        POL.units.setStatus(unit, "pursuit", player)
        return true
    end
    local suspect = target
    if getElementType(target) == "vehicle" then suspect = getVehicleController(target) or target end
    if not isElement(suspect) or POL.dist(player, suspect) > 150 then return false, "too_far" end
    if getElementType(suspect) == "player" and POL.units.isOnDuty(suspect) then return false, "bad_target" end
    local c = CH.list[suspect]
    if not c then
        c = newChase(suspect, getElementType(suspect) == "player" and "player" or "npc")
        if c.kind == "npc" then c.level = 1 end
    end
    -- subject for the incident / report
    POL.records.citizenOf(suspect, function(row)
        c.name = row and POL.records.nameOf(row) or "?"
        c.subject = { citizenId = row and row.id, name = c.name, el = suspect }
        local v = suspectVehicle(suspect)
        if v then
            c.subject.plate, c.subject.model = getVehiclePlateText(v), getElementModel(v)
        end
        CH.join(player, c)
        -- an NPC driver: runs away when its background says so, else it pulls over (the stop takes over)
        if c.kind == "npc" then CH.npcReaction(player, c, row) end
    end)
    return true
end

function CH.npcReaction(player, c, row)
    local veh = suspectVehicle(c.suspect)
    local flags = row and POL.db.unjson(row.flags) or {}
    if veh and POL.running("ai_land_traffic") and exports.ai_land_traffic:isTrafficVehicle(veh) == true then
        if flags.flee then
            exports.ai_land_traffic:setTrafficVehicleFlee(veh, getPedOccupiedVehicle(player) or player, { speedFactor = C.NPC_FLEE_SPEED })
            c.fleeing = true
        else
            CH.finish(c, "stopped")
            POL.stop.vehicle(player, veh)
        end
    end
end

-- caught / lost / cleared: the units are told, AI demand gone
function CH.finish(c, how)
    if CH.list[c.suspect] ~= c then return end
    CH.list[c.suspect] = nil
    for unit, _ in pairs(c.units) do
        if POL.units.list[unit.id] then
            local inc = POL.events.incidentOf(unit, c.suspect)
            if inc then
                POL.events.log(unit, nil, how == "caught" and "caught" or "lost", { name = c.name }, inc)
                if how ~= "caught" and how ~= "stopped" then POL.events.close(inc, how) end
            end
            POL.notify(POL.units.members(unit), "police_system.chase.ended_" .. (how == "caught" and "caught" or "lost"),
                { name = c.name or "?" })
            -- caught: the pursuit status goes off (Busy - Arrest) until the unit sets a new one
            if how == "caught" and unit.status == "pursuit" then
                POL.units.setStatus(unit, "busy")
                POL.units.setSub(unit, "arrest")
            end
        end
    end
    for _, b in pairs(c.blips) do if isElement(b) then destroyElement(b) end end
    POL.ai.release(c)
    if how == "caught" then POL.db.stat("pursuits_caught", 1) end
    POL.emit("chase.ended", c, how)
end

------------------------------------------------------------------------ tick (1 Hz, only while there are chases)

local function demandOf(c)
    local LV = POLICE.AI.LEVELS[math.max(1, math.min(6, c.level))] or POLICE.AI.LEVELS[1]
    local players = playerUnits(c)
    local inWorld = POL.inWorld(c.suspect)
    local d = { level = c.level, phase = c.phase, target = c.suspect, predicted = c.predicted, inWorld = inWorld,
                lastX = c.lastX, lastY = c.lastY, lastZ = c.lastZ, surrendered = c.surrendered }
    if not inWorld or c.level <= 0 then
        d.cars, d.tanks = 0, 0
    elseif c.kind == "npc" then
        d.cars, d.tanks = math.max(0, 1 - players), 0
    else
        -- one player unit = one AI car less
        d.cars, d.tanks = math.max(0, LV.cars - players), LV.tanks
    end
    return d
end

local function tick()
    -- every wanted player has a chase
    -- a cuffed player is in custody: no chase (and no AI) until the handover / release
    for player, st in pairs(POL.wanted.list) do
        if not CH.list[player] and isElement(player) and not POL.arrest.isCuffed(player) then
            local c = newChase(player, "player")
            c.name = POL.nameOf(player)
            POL.history.player(player, function(row)
                c.subject = { citizenId = row and row.id, name = c.name, el = player }
            end)
        end
    end
    local now = getTickCount()
    for suspect, c in pairs(CH.list) do
        if not isElement(suspect) or (getElementType(suspect) ~= "vehicle" and isPedDead(suspect)) then
            CH.finish(c, "gone")
        elseif POL.arrest.isCuffed(suspect) then
            CH.finish(c, "caught")
        else
            local st = c.kind == "player" and POL.wanted.get(suspect)
            if c.kind == "player" then
                c.level = st and st.level or 0
                c.phase = st and st.phase or "active"
                c.surrendered = st and st.surrendered
                if st then c.lastX, c.lastY, c.lastZ = st.lx, st.ly, st.lz end
                -- a chased player without a wanted level: escalates when it does not stop
                if not st then
                    if playerUnits(c) == 0 then
                        CH.finish(c, "lost")
                    else
                        local moving = POL.speed(suspectVehicle(suspect) or suspect) > POLICE.WANTED.MOVING_SPEED
                        c.notStopping = moving and c.notStopping + 1 or 0
                        if c.notStopping >= POLICE.WANTED.MOVING_TIME then POL.wanted.add(suspect, "failure_to_stop", 1) end
                    end
                end
            else
                local x, y, z = getElementPosition(suspect)
                c.lastX, c.lastY, c.lastZ = x, y, z
                -- an NPC chase ends when no unit is within 400 m any more (lost) or it is held / out of the vehicle
                local near = false
                for unit in pairs(c.units) do
                    for _, p in ipairs(POL.units.members(unit)) do if POL.dist(p, suspect) < 400 then near = true end end
                end
                if not near and playerUnits(c) > 0 then CH.finish(c, "lost") end
            end
            if CH.list[suspect] then
                if c.level >= POLICE.AI.INTERCEPT_LEVEL and c.phase == "active" and now - (c.predAt or 0) >= C.PREDICT_EVERY then
                    c.predAt = now
                    POL.prediction.update(c)
                elseif c.phase ~= "active" then
                    c.predicted = nil
                end
                refreshBlips(c)
                POL.ai.request(c, demandOf(c))
            end
        end
    end
    POL.ai.tickRequests()
end

local timer
function CH.ensureTimer()
    if timer then return end
    timer = setTimer(function()
        if not next(CH.list) and not next(POL.wanted.list) then
            killTimer(timer)
            timer = nil
            POL.ai.tickRequests()
            return
        end
        tick()
    end, C.TICK, 0)
end

POL.on("wanted.changed", function(player, level, old)
    CH.ensureTimer()
    local c = CH.list[player]
    if c and level > old then
        for unit in pairs(c.units) do
            local inc = POL.events.incidentOf(unit, player)
            if inc then
                inc.level = math.max(inc.level or 0, level)
                POL.events.log(unit, nil, "pursuit_level", { level = level }, inc)
            end
        end
    end
end)

POL.on("wanted.cleared", function(player, old, why)
    local c = CH.list[player]
    if not c then return end
    CH.finish(c, (why == "arrest") and "caught" or (why == "evaded" and "lost" or why))
end)

POL.on("wanted.phase", function(player, phase)
    local c = CH.list[player]
    if not c then return end
    for unit in pairs(c.units) do
        local inc = POL.events.incidentOf(unit, player)
        if inc and phase == "evading" then POL.events.log(unit, nil, "evading", {}, inc) end
    end
end)

-- cuffs on = the pursuit is over (the AI units retreat; the incident stays open for the handover)
POL.on("arrest.cuffed", function(target)
    local c = CH.list[target]
    if c then CH.finish(c, "caught") end
end)

-- a unit that is not in pursuit any more leaves its chases
POL.on("unit.status", function(unit, status)
    if status ~= "pursuit" then CH.leaveUnit(unit) end
end)
POL.on("unit.signedOff", function(unit) CH.leaveUnit(unit) end)

-- MDC Pursuits page
function CH.publicList()
    local out = {}
    for _, c in pairs(CH.list) do
        if c.level > 0 or next(c.units) then
            local units, ai = {}, 0
            for u in pairs(c.units) do units[#units + 1] = u.callsign end
            ai = POL.ai.countFor(c)
            local v = suspectVehicle(c.suspect)
            local x, y, z = getElementPosition(c.suspect)
            out[#out + 1] = { id = c.id, name = c.name or "?", level = c.level, phase = c.phase, kind = c.kind,
                vehicle = v and exports.veh_manager:getModelName(getElementModel(v)) or false, plate = v and getVehiclePlateText(v) or false,
                units = units, ai = ai, since = c.startedAt, zone = getZoneName(x, y, z) }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function CH.byId(id)
    for _, c in pairs(CH.list) do if c.id == tonumber(id) then return c end end
    return nil
end
