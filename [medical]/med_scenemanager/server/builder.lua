-- Turns scene entries into elements and back (used by live scenes and the editor).
--
-- Vehicle entry: { id, model, pos, rot, colors (12), health, doors (6), panels (7),
--   lights (4), wheels (4), engine, lightsOn, sirens, locked, frozen, plate,
--   paintjob, upgrades, variant (2) }
-- Ped entry: { id, skin, pos, rot, anim, frozen, vehicle (vehicle id), seat,
--   injuries = { { type, severity } }, state = { [medsys key] = value } }

Builder = {}

local MIN_HEALTH = 300 -- below ~250 a vehicle catches fire and explodes

local function nums(list, count, default)
    local out = {}
    for i = 1, count do
        out[i] = tonumber(type(list) == "table" and list[i]) or default
    end
    return out
end

local function place(element, entry, interior, dimension)
    setElementInterior(element, interior or 0)
    setElementDimension(element, dimension or 0)
end

---------------------------------------------------------------- vehicles

-- Reads every stored property of a vehicle element into the entry (in place).
function Builder.captureVehicle(vehicle, entry)
    local x, y, z = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    entry.model = getElementModel(vehicle)
    entry.pos = { msmRound(x), msmRound(y), msmRound(z) }
    entry.rot = { msmRound(rx, 2), msmRound(ry, 2), msmRound(rz, 2) }
    entry.colors = { getVehicleColor(vehicle, true) }
    entry.health = math.max(MIN_HEALTH, math.floor(getElementHealth(vehicle)))
    entry.doors, entry.panels, entry.lights = {}, {}, {}
    for i = 0, 5 do entry.doors[i + 1] = getVehicleDoorState(vehicle, i) end
    for i = 0, 6 do entry.panels[i + 1] = getVehiclePanelState(vehicle, i) end
    for i = 0, 3 do entry.lights[i + 1] = getVehicleLightState(vehicle, i) end
    entry.wheels = { getVehicleWheelStates(vehicle) }
    entry.plate = getVehiclePlateText(vehicle)
    entry.paintjob = getVehiclePaintjob(vehicle)
    entry.upgrades = getVehicleUpgrades(vehicle) or {}
    entry.variant = { getVehicleVariant(vehicle) }
    -- engine / lights / sirens / locked / frozen are editor options, kept as set
    return entry
end

-- Applies the entry's look and state to an existing vehicle element.
function Builder.applyVehicle(vehicle, entry)
    if type(entry.colors) == "table" and #entry.colors >= 6 then
        setVehicleColor(vehicle, unpack(nums(entry.colors, 12, 0)))
    end
    if entry.paintjob and tonumber(entry.paintjob) ~= 3 then
        setVehiclePaintjob(vehicle, tonumber(entry.paintjob))
    end
    for _, upgrade in ipairs(type(entry.upgrades) == "table" and entry.upgrades or {}) do
        addVehicleUpgrade(vehicle, tonumber(upgrade))
    end
    if entry.plate and entry.plate ~= "" then setVehiclePlateText(vehicle, tostring(entry.plate)) end

    fixVehicle(vehicle)
    local doors = nums(entry.doors, 6, 0)
    local panels = nums(entry.panels, 7, 0)
    local lights = nums(entry.lights, 4, 0)
    for i = 0, 5 do setVehicleDoorState(vehicle, i, doors[i + 1], false) end
    for i = 0, 6 do setVehiclePanelState(vehicle, i, panels[i + 1]) end
    for i = 0, 3 do setVehicleLightState(vehicle, i, lights[i + 1]) end
    if type(entry.wheels) == "table" then
        local w = nums(entry.wheels, 4, 0)
        setVehicleWheelStates(vehicle, w[1], w[2], w[3], w[4])
    end
    setElementHealth(vehicle, math.max(MIN_HEALTH, math.min(1000, tonumber(entry.health) or 1000)))
    Builder.applyVehicleOptions(vehicle, entry)
end

-- engine / lights / sirens / locked (frozen is applied on creation)
function Builder.applyVehicleOptions(vehicle, entry)
    setVehicleEngineState(vehicle, entry.engine == true)
    setVehicleOverrideLights(vehicle, entry.lightsOn and 2 or 1)
    if entry.sirens ~= nil then setVehicleSirensOn(vehicle, entry.sirens == true) end
    setVehicleLocked(vehicle, entry.locked == true)
end

function Builder.createVehicle(entry, interior, dimension, frozen)
    local p, r = entry.pos, entry.rot
    local variant = nums(entry.variant, 2, 255)
    local vehicle = createVehicle(entry.model, p[1], p[2], p[3], r[1], r[2], r[3], nil, false, variant[1], variant[2])
    if not vehicle then return nil end
    place(vehicle, entry, interior, dimension)
    Builder.applyVehicle(vehicle, entry)
    if frozen ~= nil then
        setElementFrozen(vehicle, frozen)
    else
        setElementFrozen(vehicle, entry.frozen == true)
    end
    return vehicle
end

-- Damage presets of the editor -> writes health / doors / panels / lights into the entry
function Builder.damagePreset(entry, preset)
    if preset == "repair" then
        entry.health, entry.doors, entry.panels, entry.lights, entry.wheels = 1000, nil, nil, nil, nil
    elseif preset == "light" then
        entry.health = 750
        entry.doors = { 0, 0, 0, 0, 0, 0 }
        entry.panels = { 1, 0, 0, 0, 0, 1, 0 }
        entry.lights = { 1, 0, 0, 0 }
    elseif preset == "heavy" then
        entry.health = 420
        entry.doors = { 2, 0, 2, 3, 0, 0 }
        entry.panels = { 3, 2, 2, 1, 2, 3, 1 }
        entry.lights = { 1, 1, 0, 0 }
    elseif preset == "wreck" then
        entry.health = MIN_HEALTH
        entry.doors = { 3, 2, 4, 4, 2, 3 }
        entry.panels = { 3, 3, 3, 3, 3, 3, 3 }
        entry.lights = { 1, 1, 1, 1 }
        entry.wheels = { 1, 0, 0, 0 }
    else
        return false
    end
    return true
end

---------------------------------------------------------------- peds

function Builder.applyPedPose(ped, entry)
    if getPedOccupiedVehicle(ped) then return end
    local def = msmAnimById(entry.anim)
    if def and def.anim then
        setPedAnimation(ped, def.anim[1], def.anim[2], -1, def.loop == true, false, false, true)
    else
        setPedAnimation(ped)
    end
end

-- Puts the ped into its vehicle (entry.vehicle -> vehiclesById) or onto its position.
function Builder.seatPed(ped, entry, vehiclesById)
    local vehicle = entry.vehicle and vehiclesById and vehiclesById[entry.vehicle]
    if isElement(vehicle) then
        local seat = math.floor(tonumber(entry.seat) or 0)
        if seat <= (getVehicleMaxPassengers(vehicle) or 0) and not getVehicleOccupant(vehicle, seat) then
            if warpPedIntoVehicle(ped, vehicle, seat) then return true end
        end
    end
    if getPedOccupiedVehicle(ped) then removePedFromVehicle(ped) end
    local p = entry.pos
    setElementPosition(ped, p[1], p[2], p[3])
    setElementRotation(ped, 0, 0, entry.rot or 0, "default", true)
    return false
end

function Builder.createPed(entry, interior, dimension, vehiclesById, frozen)
    local p = entry.pos
    local ped = createPed(entry.skin or 0, p[1], p[2], p[3], entry.rot or 0)
    if not ped then
        ped = createPed(0, p[1], p[2], p[3], entry.rot or 0) -- invalid skin
        if not ped then return nil end
    end
    place(ped, entry, interior, dimension)
    Builder.seatPed(ped, entry, vehiclesById)
    if frozen ~= nil then
        setElementFrozen(ped, frozen)
    else
        setElementFrozen(ped, entry.frozen == true)
    end
    return ped
end

-- Injuries + preset vitals through medsys. Only for live scenes (the editor never
-- starts a simulation). Returns false when medsys is not running.
function Builder.applyMedical(ped, entry)
    if not isElement(ped) or not msmResourceRunning(MSM.MEDSYS) then return false end
    local medsys = exports[MSM.MEDSYS]
    for _, injury in ipairs(entry.injuries or {}) do
        medsys:applyInjury(ped, injury.type, injury.severity)
    end
    local state = type(entry.state) == "table" and entry.state or {}
    for _, key in ipairs(MSM_STATE_ORDER) do
        if state[key] ~= nil then medsys:setMedicalState(ped, key, state[key]) end
    end
    return true
end
