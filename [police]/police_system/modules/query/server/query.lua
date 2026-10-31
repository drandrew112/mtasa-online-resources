-- police_system / modules/query/server/query.lua
-- Queries: the radio (QUERY_PERSON / QUERY_VEHICLE: the nearest person / vehicle) and the stop menu (Personal
-- details / Vehicle details). The server picks and checks the target (distance), the History module generates an
-- NPC's background when needed, and a compact result goes to the unit's members (the query window left of the mini
-- panel; Backspace hides it, 30 s auto hide). Every query is logged and kept for the MDC (unit.queries).

local Q = POL.module("query", {})

local function keep(unit, r)
    unit.queries = unit.queries or {}
    table.insert(unit.queries, 1, r)
    if #unit.queries > 20 then unit.queries[21] = nil end
end

local function send(unit, r)
    keep(unit, r)
    POL.send(POL.units.members(unit), "query:result", r)
end

function Q.person(officer, el)
    local unit = POL.units.of(officer)
    if not unit or not isElement(el) then return false end
    POL.records.citizenOf(el, function(row)
        if not row then return POL.notify(officer, "police_system.query.no_data") end
        POL.warrants.activeFor(row.id, function(warrants)
            local f = POL.db.unjson(row.flags)
            local name = POL.records.nameOf(row)
            local wanted = getElementType(el) == "player" and getPlayerWantedLevel(el) or 0
            local r = { kind = "person", id = tonumber(row.id), name = name, npc = row.kind == "npc", gender = row.gender,
                birth = row.birth_date, licence = row.kind == "player" and "valid" or (f.licence or "valid"),
                warrants = #warrants, wanted = wanted, at = POL.now() }
            send(unit, r)
            local inc = POL.events.incidentOf(unit, el) or POL.events.incidentOf(unit, getPedOccupiedVehicle(el))
            POL.events.log(unit, officer, "query_person", { name = name, warrant = #warrants > 0 }, inc)
        end)
    end)
    return true
end

function Q.vehicle(officer, veh)
    local unit = POL.units.of(officer)
    if not unit or not isElement(veh) then return false end
    POL.records.vehicleOf(veh, function(row)
        if not row then return POL.notify(officer, "police_system.query.no_data") end
        POL.records.vehicleProfile(row.id, function(prof)
            if not prof then return end
            local r = { kind = "vehicle", id = prof.id, plate = prof.plate or getVehiclePlateText(veh), model = prof.model,
                color = prof.color, owner = prof.owner and prof.owner.name or "-", ownerNpc = prof.owner and prof.owner.kind == "npc",
                ownerWarrants = prof.owner and prof.owner.warrants or 0, registration = prof.registration,
                inspection = prof.inspection, stolen = prof.stolen, at = POL.now() }
            send(unit, r)
            POL.events.log(unit, officer, "query_vehicle", { plate = r.plate, model = r.model, stolen = r.stolen,
                inspection = (tostring(r.inspection):find("expired")) and r.inspection or nil }, POL.events.incidentOf(unit, veh))
        end)
    end)
    return true
end

-- nearest person (not the officer, not police on duty) / vehicle (not the officer's own)
local function nearest(officer, kind, range)
    local x, y, z = getElementPosition(officer)
    local own = getPedOccupiedVehicle(officer)
    local best, bd
    local function consider(el)
        if el == officer or el == own then return end
        if kind ~= "vehicle" and (isPedDead(el) or (getElementType(el) == "player" and POL.units.isOnDuty(el))) then return end
        local d = POL.dist(officer, el)
        if d <= range and (not bd or d < bd) then best, bd = el, d end
    end
    if kind == "vehicle" then
        for _, v in ipairs(getElementsWithinRange(x, y, z, range, "vehicle")) do consider(v) end
    else
        for _, t in ipairs({ "ped", "player" }) do
            for _, e in ipairs(getElementsWithinRange(x, y, z, range, t)) do consider(e) end
        end
    end
    return best
end

function Q.nearestPerson(officer)
    local el = nearest(officer, "person", 12)
    if not el then return POL.notify(officer, "police_system.query.nobody_near") end
    -- someone in a vehicle: the driver is the person
    Q.person(officer, el)
end

function Q.nearestVehicle(officer)
    local el = nearest(officer, "vehicle", 18)
    if not el then return POL.notify(officer, "police_system.query.no_vehicle_near") end
    Q.vehicle(officer, el)
end
