-- Reading (describe) and writing (apply) entity / element properties.

Props = {}

local function nums(list, count, default)
    local out = {}
    for i = 1, count do out[i] = tonumber(type(list) == "table" and list[i]) or default end
    return out
end

function Props.modelName(typ, model)
    if typ == "vehicle" then
        local name, source = Util.vehicleName(model)
        return name, source
    elseif typ == "ped" then
        return nil
    end
    return nil
end

-- Full description of an element (+ its entity record when it has one).
-- detail: "low" | "medium" | "high"
function Props.describe(el, detail)
    detail = detail or "medium"
    local entity = Registry.byElement[el]
    local typ = getElementType(el)
    local x, y, z = getElementPosition(el)
    local rx, ry, rz = getElementRotation(el)
    local fx, fy = M.forward(rz)
    local d = {
        id = Refs.of(el),
        type = typ,
        model = getElementModel(el),
        position = M.vec(x, y, z),
        rotation = M.vec(rx, ry, rz, 2),
        heading = M.round(rz, 2),
        compass = M.compass(rz),
        forward = { x = M.round(fx, 3), y = M.round(fy, 3) },
        interior = getElementInterior(el),
        dimension = getElementDimension(el),
    }
    if entity then
        d.workspace = entity.workspace
        d.status = entity.status
        d.adopted = entity.adopted or nil
        if next(entity.meta) then d.meta = entity.meta end
        if entity.placement then d.placement = entity.placement end
    else
        d.workspace = nil
        d.external = true
    end
    if typ == "vehicle" then
        d.modelName, d.modelNameSource = Util.vehicleName(d.model)
        d.vehicleType = getVehicleType(el)
    elseif typ == "ped" then
        d.sex = pedSex(d.model)
    elseif typ == "player" then
        d.name = getPlayerName(el)
    end
    if detail == "low" then return d end

    d.frozen = isElementFrozen(el)
    d.alpha = getElementAlpha(el)
    d.collisions = getElementCollisionsEnabled and getElementCollisionsEnabled(el) or nil
    d.health = M.round(getElementHealth(el), 1)
    d.zone = Util.zone(x, y, z)
    local vx, vy, vz = getElementVelocity(el)
    if vx then d.speed = M.round(math.sqrt(vx * vx + vy * vy + vz * vz) * 180, 1) end -- km/h (approx); objects have none

    if typ == "vehicle" then
        d.colors = { getVehicleColor(el, true) }
        d.plate = getVehiclePlateText(el)
        d.engine = getVehicleEngineState(el)
        d.lightsOverride = getVehicleOverrideLights(el)
        d.sirens = getVehicleSirensOn(el)
        d.locked = isVehicleLocked(el)
        d.damageProof = isVehicleDamageProof(el)
        d.blown = isVehicleBlown(el)
        d.maxPassengers = getVehicleMaxPassengers(el)
        local occ = {}
        for seat, ped in pairs(getVehicleOccupants(el) or {}) do occ[tostring(seat)] = Refs.of(ped) end
        d.occupants = occ
        if detail == "high" then
            d.doors, d.panels, d.lights = {}, {}, {}
            for i = 0, 5 do d.doors[i + 1] = getVehicleDoorState(el, i) end
            for i = 0, 6 do d.panels[i + 1] = getVehiclePanelState(el, i) end
            for i = 0, 3 do d.lights[i + 1] = getVehicleLightState(el, i) end
            d.wheels = { getVehicleWheelStates(el) }
            d.paintjob = getVehiclePaintjob(el)
            d.upgrades = getVehicleUpgrades(el) or {}
            d.variant = { getVehicleVariant(el) }
        end
    elseif typ == "ped" or typ == "player" then
        d.dead = isPedDead(el)
        d.armor = M.round(getPedArmor(el), 1)
        local veh = getPedOccupiedVehicle(el)
        if veh then d.vehicle = { id = Refs.of(veh), seat = getPedOccupiedVehicleSeat(el) } end
        if getPedAnimation then
            local block, anim = getPedAnimation(el)
            if block then d.animation = { block = block, anim = anim } end
        end
        if entity and entity.meta.pose then d.pose = entity.meta.pose end
    elseif typ == "object" then
        d.scale = getObjectScale(el)
        d.doubleSided = isElementDoubleSided(el)
    end
    return d
end

---------------------------------------------------------------- apply

function Props.applyPose(ped, pose)
    if pose == nil then return end
    if type(pose) == "string" then
        local def = CMCP.POSES[pose]
        if not def then
            local ids = {}
            for k in pairs(CMCP.POSES) do ids[#ids + 1] = k end
            table.sort(ids)
            fail("INVALID_PARAMS", "Unknown pose '" .. pose .. "'. Known: " .. table.concat(ids, ", "))
        end
        if getPedOccupiedVehicle(ped) then return end
        if def.block then
            setPedAnimation(ped, def.block, def.anim, -1, def.loop == true, false, false, true)
        else
            setPedAnimation(ped)
        end
    elseif type(pose) == "table" and pose.block and pose.anim then
        setPedAnimation(ped, tostring(pose.block), tostring(pose.anim), -1, pose.loop ~= false, false, false, pose.freezeLastFrame ~= false)
    else
        fail("INVALID_PARAMS", "pose must be a pose id string or { block, anim, loop }.")
    end
end

function Props.applyDamage(veh, preset)
    local d = type(preset) == "string" and CMCP.DAMAGE[preset] or (type(preset) == "table" and preset)
    if not d then fail("INVALID_PARAMS", "Unknown damage preset '" .. tostring(preset) .. "' (repair, light, heavy, wreck or a { health, doors, panels, lights, wheels } table).") end
    fixVehicle(veh)
    if d.doors then
        local doors = nums(d.doors, 6, 0)
        for i = 0, 5 do setVehicleDoorState(veh, i, doors[i + 1], false) end
    end
    if d.panels then
        local panels = nums(d.panels, 7, 0)
        for i = 0, 6 do setVehiclePanelState(veh, i, panels[i + 1]) end
    end
    if d.lights then
        local lights = nums(d.lights, 4, 0)
        for i = 0, 3 do setVehicleLightState(veh, i, lights[i + 1]) end
    end
    if d.wheels then
        local w = nums(d.wheels, 4, 0)
        setVehicleWheelStates(veh, w[1], w[2], w[3], w[4])
    end
    setElementHealth(veh, math.max(300, math.min(1000, tonumber(d.health) or 1000)))
end

-- Applies a property table. Returns list of applied keys and warnings.
function Props.apply(el, props, entity)
    local applied, warnings = {}, {}
    local typ = getElementType(el)
    local function did(k) applied[#applied + 1] = k end
    if type(props) ~= "table" then return applied, warnings end

    if props.frozen ~= nil then setElementFrozen(el, props.frozen == true) did("frozen") end
    if props.alpha ~= nil then setElementAlpha(el, math.max(0, math.min(255, tonumber(props.alpha) or 255))) did("alpha") end
    if props.collisions ~= nil then setElementCollisionsEnabled(el, props.collisions == true) did("collisions") end
    if props.health ~= nil then setElementHealth(el, tonumber(props.health) or 100) did("health") end
    if props.dimension ~= nil then setElementDimension(el, math.floor(tonumber(props.dimension) or 0)) did("dimension") end
    if props.interior ~= nil then setElementInterior(el, math.floor(tonumber(props.interior) or 0)) did("interior") end
    if props.model ~= nil then
        if setElementModel(el, math.floor(tonumber(props.model) or -1)) then
            if entity then entity.model = getElementModel(el) end
            did("model")
        else
            warnings[#warnings + 1] = { type = "model", message = "Model " .. tostring(props.model) .. " could not be applied." }
        end
    end
    if type(props.elementData) == "table" then
        for k, v in pairs(props.elementData) do setElementData(el, tostring(k), v) end
        did("elementData")
    end
    if entity and type(props.meta) == "table" then
        for k, v in pairs(props.meta) do entity.meta[k] = v end
        did("meta")
    end

    if typ == "vehicle" then
        if props.damage ~= nil then Props.applyDamage(el, props.damage) did("damage") end
        if type(props.color) == "table" then
            -- { r, g, b [, r2, g2, b2] } primary/secondary RGB
            local c = nums(props.color, 6, 255)
            setVehicleColor(el, c[1], c[2], c[3], c[4], c[5], c[6])
            did("color")
        end
        if type(props.colors) == "table" then setVehicleColor(el, unpack(nums(props.colors, 12, 0))) did("colors") end
        if props.plate ~= nil then setVehiclePlateText(el, tostring(props.plate):sub(1, 8)) did("plate") end
        if props.engine ~= nil then setVehicleEngineState(el, props.engine == true) did("engine") end
        if props.lightsOn ~= nil then setVehicleOverrideLights(el, props.lightsOn and 2 or 1) did("lightsOn") end
        if props.sirens ~= nil then setVehicleSirensOn(el, props.sirens == true) did("sirens") end
        if props.locked ~= nil then setVehicleLocked(el, props.locked == true) did("locked") end
        if props.damageProof ~= nil then setVehicleDamageProof(el, props.damageProof == true) did("damageProof") end
        if props.paintjob ~= nil then setVehiclePaintjob(el, tonumber(props.paintjob) or 3) did("paintjob") end
        if type(props.upgrades) == "table" then
            for _, u in ipairs(props.upgrades) do addVehicleUpgrade(el, tonumber(u)) end
            did("upgrades")
        end
        if type(props.doors) == "table" then for i = 0, 5 do setVehicleDoorState(el, i, tonumber(props.doors[i + 1]) or 0, false) end did("doors") end
        if type(props.panels) == "table" then for i = 0, 6 do setVehiclePanelState(el, i, tonumber(props.panels[i + 1]) or 0) end did("panels") end
        if type(props.lights) == "table" then for i = 0, 3 do setVehicleLightState(el, i, tonumber(props.lights[i + 1]) or 0) end did("lights") end
        if type(props.wheels) == "table" then
            local w = nums(props.wheels, 4, 0)
            setVehicleWheelStates(el, w[1], w[2], w[3], w[4])
            did("wheels")
        end
        if type(props.doorsOpen) == "table" then
            -- { [door index 0-5] = ratio 0..1 }
            for k, v in pairs(props.doorsOpen) do setVehicleDoorOpenRatio(el, tonumber(k) or 0, tonumber(v) or 0, 0) end
            did("doorsOpen")
        end
    elseif typ == "ped" or typ == "player" then
        if props.skin ~= nil then
            if setElementModel(el, math.floor(tonumber(props.skin) or 0)) then
                if entity then entity.model = getElementModel(el) end
                did("skin")
            else
                warnings[#warnings + 1] = { type = "skin", message = "Skin " .. tostring(props.skin) .. " is not a valid ped model." }
            end
        end
        if props.armor ~= nil then setPedArmor(el, tonumber(props.armor) or 0) did("armor") end
        if props.exitVehicle then removePedFromVehicle(el) did("exitVehicle") end
        if type(props.seat) == "table" then
            local veh = Refs.require(props.seat.vehicle, "seat.vehicle")
            local seat = math.floor(tonumber(props.seat.seat) or 0)
            if getElementType(veh) ~= "vehicle" then fail("INVALID_PARAMS", "seat.vehicle must be a vehicle.") end
            if seat > (getVehicleMaxPassengers(veh) or 0) then
                fail("INVALID_PARAMS", "Seat " .. seat .. " does not exist (max passengers " .. tostring(getVehicleMaxPassengers(veh)) .. ").")
            end
            local occupant = getVehicleOccupant(veh, seat)
            if occupant and occupant ~= el then fail("SEAT_OCCUPIED", "Seat " .. seat .. " is occupied by " .. tostring(Refs.of(occupant)) .. ".") end
            if not warpPedIntoVehicle(el, veh, seat) then
                warnings[#warnings + 1] = { type = "seat", message = "warpPedIntoVehicle failed." }
            else
                if entity then entity.meta.seat = { vehicle = Refs.of(veh), seat = seat } end
                did("seat")
            end
        end
        if props.pose ~= nil then
            Props.applyPose(el, props.pose)
            if entity then entity.meta.pose = props.pose end
            did("pose")
        end
        if props.weapon ~= nil then giveWeapon(el, tonumber(props.weapon) or 0, 100, true) did("weapon") end
    elseif typ == "object" then
        if props.scale ~= nil then setObjectScale(el, tonumber(props.scale) or 1) did("scale") end
        if props.doubleSided ~= nil then setElementDoubleSided(el, props.doubleSided == true) did("doubleSided") end
    end
    return applied, warnings
end
