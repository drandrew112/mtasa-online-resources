if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Objective and fail-condition types of a mission stage. Every type is polled by the runner
-- (4 Hz, only this mission's players and entities) through check(match, o, dt) -> done;
-- events (kills, interactions, script signals) only set flags the check reads.
--
--   o = { def = the stage's objective table, done = bool, t = seconds counted (stay / survive) }
--   progress(match, o) -> short text next to the objective on the HUD ("3/8", "0:12") | nil
--   target(match, o)   -> what the HUD points at: { x, y, z [, element] [, radius, height] } | nil
--
-- `who` = "any" (one player is enough, default) | "all" (every player still playing).

MissionObjectives = {}
MissionFails = {}

local O, F = MissionObjectives, MissionFails

local function zoneOf(match, id)
    for _, z in ipairs(match.job.mission.zones or {}) do
        if z.id == id then return z end
    end
end
MissionZone = zoneOf

local function pointOf(match, id)
    for _, p in ipairs(match.job.mission.points or {}) do
        if p.id == id then return p end
    end
end
MissionPoint = pointOf

local function inZone(z, x, y, zz)
    if not z or not x then return false end
    local h = z.height or 8
    return (x - z.x) ^ 2 + (y - z.y) ^ 2 <= z.radius * z.radius and zz >= z.z - 2 and zz <= z.z + h
end
MissionInZone = inZone

-- players still playing (not left, not dead, not waiting for the respawn)
local function crew(match)
    local list = {}
    for _, player in ipairs(match.players) do
        if isElement(player) and not match.left[player] and not isPedDead(player) and not Spectate.isSpectating(match, player)
            and not (match.mission.respawning[player]) then
            list[#list + 1] = player
        end
    end
    return list
end
MissionCrew = crew

-- who: any / all; test(player) -> bool
local function crewTest(match, who, test)
    local list = crew(match)
    if #list == 0 then return false, 0, 0 end
    local count = 0
    for _, player in ipairs(list) do if test(player) then count = count + 1 end end
    if who == "all" then return count == #list, count, #list end
    return count > 0, count, #list
end

local function vehicleEntry(match, id) return match.mission.ents.vehicles[id] end

local function elementPos(el)
    if not isElement(el) then return nil end
    local x, y, z = getElementPosition(el)
    return { x, y, z, el }
end

local function zoneTarget(match, id)
    local z = zoneOf(match, id)
    return z and { z.x, z.y, z.z, radius = z.radius, height = z.height or 8 } or nil
end

local function countText(n, total) return n .. "/" .. total end

local function timeText(s)
    s = math.max(0, math.floor(s + 0.5))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

--------------------------------------------------------------------------------
-- objectives
--------------------------------------------------------------------------------

O.enterZone = {
    check = function(match, o)
        local z = zoneOf(match, o.def.zone)
        local vehId = o.def.vehicle
        local ok, n, total = crewTest(match, o.def.who, function(player)
            if vehId then
                local entry = vehicleEntry(match, vehId)
                if not entry or getPedOccupiedVehicle(player) ~= entry.el then return false end
            end
            return inZone(z, getElementPosition(player))
        end)
        o.n, o.total = n, total
        return ok
    end,
    progress = function(match, o)
        if o.def.who == "all" and o.total and o.total > 1 then return countText(o.n or 0, o.total) end
    end,
    target = function(match, o) return zoneTarget(match, o.def.zone) end,
}

O.stayInZone = {
    check = function(match, o, dt)
        local z = zoneOf(match, o.def.zone)
        local ok = crewTest(match, o.def.who, function(player) return inZone(z, getElementPosition(player)) end)
        if ok then o.t = (o.t or 0) + dt end
        return (o.t or 0) >= (o.def.seconds or 30)
    end,
    progress = function(match, o) return timeText((o.def.seconds or 30) - (o.t or 0)) end,
    target = function(match, o) return zoneTarget(match, o.def.zone) end,
}

O.enterVehicle = {
    check = function(match, o)
        local entry = vehicleEntry(match, o.def.vehicle)
        if not entry or not isElement(entry.el) then return false end
        return (crewTest(match, o.def.who, function(player) return getPedOccupiedVehicle(player) == entry.el end))
    end,
    target = function(match, o)
        local entry = vehicleEntry(match, o.def.vehicle)
        return entry and elementPos(entry.el)
    end,
}

O.deliverVehicle = {
    check = function(match, o)
        local entry = vehicleEntry(match, o.def.vehicle)
        if not entry or not isElement(entry.el) or isVehicleBlown(entry.el) then return false end
        return inZone(zoneOf(match, o.def.zone), getElementPosition(entry.el))
    end,
    target = function(match, o)
        local entry = vehicleEntry(match, o.def.vehicle)
        -- the vehicle until someone sits in it, then the drop-off zone
        if entry and isElement(entry.el) then
            for _, player in ipairs(crew(match)) do
                if getPedOccupiedVehicle(player) == entry.el then return zoneTarget(match, o.def.zone) end
            end
            return elementPos(entry.el)
        end
        return zoneTarget(match, o.def.zone)
    end,
}

O.collectItem = {
    check = function(match, o)
        local carrier = MissionEntities.itemState(match, o.def.item)
        if carrier and match.mission.isCrew[carrier] then o.carrier = carrier return true end
        return false
    end,
    target = function(match, o)
        local _, x, y, z = MissionEntities.itemState(match, o.def.item)
        return x and { x, y, z } or nil
    end,
}

O.deliverItem = {
    check = function(match, o)
        local _, x, y, z = MissionEntities.itemState(match, o.def.item)
        return x and inZone(zoneOf(match, o.def.zone), x, y, z) or false
    end,
    target = function(match, o)
        local carrier, x, y, z = MissionEntities.itemState(match, o.def.item)
        if carrier and match.mission.isCrew[carrier] then return zoneTarget(match, o.def.zone) end
        return x and { x, y, z } or zoneTarget(match, o.def.zone)
    end,
}

-- peds = { ids } (each must be dead), or all = true: every enemy ped of the mission alive right now
local function killList(match, o)
    local list = {}
    if o.def.all then
        for _, entry in pairs(match.mission.ents.peds) do
            if entry.def.behaviour ~= "civilian" and not entry.removed then list[#list + 1] = entry end
        end
    else
        for _, id in ipairs(o.def.peds or {}) do
            local entry = match.mission.ents.peds[id]
            if entry then list[#list + 1] = entry end
            -- the crew of a listed vehicle counts too
            for _, e in pairs(match.mission.ents.peds) do
                if e.crewOf == id then list[#list + 1] = e end
            end
        end
    end
    return list
end

O.killPeds = {
    check = function(match, o)
        local list = killList(match, o)
        local dead = 0
        for _, entry in ipairs(list) do if entry.dead or not isElement(entry.el) then dead = dead + 1 end end
        o.n, o.total = dead, #list
        return #list > 0 and dead == #list
    end,
    progress = function(match, o) return o.total and countText(o.n or 0, o.total) end,
    target = function(match, o)
        for _, entry in ipairs(killList(match, o)) do
            if not entry.dead and isElement(entry.el) then return elementPos(entry.el) end
        end
    end,
    enemies = true,
}

O.destroyVehicle = {
    check = function(match, o)
        local entry = vehicleEntry(match, o.def.vehicle)
        return not entry or not isElement(entry.el) or isVehicleBlown(entry.el)
    end,
    target = function(match, o)
        local entry = vehicleEntry(match, o.def.vehicle)
        return entry and elementPos(entry.el)
    end,
}

O.interact = {
    check = function(match, o) return match.mission.interacted[o.def.point] == true end,
    target = function(match, o)
        local p = pointOf(match, o.def.point)
        return p and { p.x, p.y, p.z } or nil
    end,
    point = true,
}

O.survive = {
    check = function(match, o, dt)
        o.t = (o.t or 0) + dt
        return o.t >= (o.def.seconds or 60)
    end,
    progress = function(match, o) return timeText((o.def.seconds or 60) - (o.t or 0)) end,
}

O.scriptEvent = {
    check = function(match, o) return match.mission.signals[o.def.name] == true end,
}

--------------------------------------------------------------------------------
-- fail conditions (true = the mission fails)
--------------------------------------------------------------------------------

F.vehicleDestroyed = function(match, f)
    local entry = vehicleEntry(match, f.vehicle)
    return entry ~= nil and not entry.removed and (not isElement(entry.el) or isVehicleBlown(entry.el))
end

F.pedDied = function(match, f)
    local entry = match.mission.ents.peds[f.ped]
    return entry ~= nil and not entry.removed and (entry.dead or not isElement(entry.el))
end

-- every player still playing is outside the zone
F.leaveZone = function(match, f)
    local z = zoneOf(match, f.zone)
    local list = crew(match)
    if #list == 0 then return false end
    for _, player in ipairs(list) do
        if inZone(z, getElementPosition(player)) then return false end
    end
    return true
end

MISSION_OBJECTIVE_TYPES = {}
for name in pairs(O) do MISSION_OBJECTIVE_TYPES[name] = true end
MISSION_FAIL_TYPES = {}
for name in pairs(F) do MISSION_FAIL_TYPES[name] = true end
