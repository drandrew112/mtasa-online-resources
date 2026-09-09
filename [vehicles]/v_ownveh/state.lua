-- v_ownveh :: vehicle state capture / apply + spawn point selection

OwnVeh = OwnVeh or {}

--------------------------------------------------------------------------------
-- State capture / apply
--------------------------------------------------------------------------------

-- Reads everything we persist off a live vehicle element and returns it in the
-- serialised shape db.lua stores. Health is deliberately excluded.
function OwnVeh.captureState(veh)
    local model = getElementModel(veh)

    -- Colours: keep every value getVehicleColor returns (RGB mode -> up to 12).
    local colorValues = { getVehicleColor(veh, true) }

    -- Handling: only the properties that differ from the model's stock values,
    -- and only scalar ones (skip table-valued props like centerOfMass).
    local handling = {}
    local current  = getVehicleHandling(veh)
    local original = getOriginalHandling(model)
    if current and original then
        for key, value in pairs(current) do
            if type(value) ~= "table" and original[key] ~= value then
                handling[key] = value
            end
        end
    end

    -- v_customs extras: it keeps a live table on element data ("customs:extras")
    -- for anything that cannot be read back off the vehicle element.
    local extras = getElementData(veh, "customs:extras")
    local customs = (type(extras) == "table") and toJSON(extras) or "{}"

    return {
        model    = model,
        colors   = table.concat(colorValues, ","),
        paintjob = getVehiclePaintjob(veh),
        upgrades = table.concat(getVehicleUpgrades(veh) or {}, ","),
        handling = toJSON(handling),
        customs  = customs,
        plate    = getVehiclePlateText(veh) or nil,
    }
end

-- Applies a stored row onto a freshly created vehicle element.
function OwnVeh.applyState(veh, row)
    if row.colors and row.colors ~= "" then
        local nums = {}
        for _, part in ipairs(split(row.colors, ",")) do
            nums[#nums + 1] = tonumber(part)
        end
        if #nums >= 3 then
            setVehicleColor(veh, unpack(nums))
        end
    end

    local paintjob = tonumber(row.paintjob)
    if paintjob then
        setVehiclePaintjob(veh, paintjob)
    end

    if row.upgrades and row.upgrades ~= "" then
        for _, part in ipairs(split(row.upgrades, ",")) do
            local upgrade = tonumber(part)
            if upgrade then
                addVehicleUpgrade(veh, upgrade)
            end
        end
    end

    if row.handling and row.handling ~= "" then
        local handling = fromJSON(row.handling)
        if type(handling) == "table" then
            for key, value in pairs(handling) do
                pcall(setVehicleHandling, veh, key, value)
            end
        end
    end

    if row.plate and row.plate ~= "" then
        setVehiclePlateText(veh, row.plate)
    end

    -- Hand the v_customs extras back to whoever owns them. v_customs listens for
    -- "v_customs:applyExtras" and re-applies nitro / neon / air-ride / etc.; if
    -- it is not running this is a no-op and the data just sits on element data.
    if row.customs and row.customs ~= "" and row.customs ~= "{}" then
        local extras = fromJSON(row.customs)
        if type(extras) == "table" then
            setElementData(veh, "customs:extras", extras)
            local customsRes = getResourceFromName("v_customs")
            if customsRes and getResourceState(customsRes) == "running" then
                triggerEvent("v_customs:applyExtras", veh, extras)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Spawn point selection
--------------------------------------------------------------------------------

-- Which spawnpoint list a model belongs to.
function OwnVeh.categoryOf(model)
    local vtype = getVehicleType(model)
    if vtype == "Plane" then
        return "airplanes"
    elseif vtype == "Helicopter" then
        return "helicopters"
    elseif vtype == "Boat" then
        return "boats"
    end
    return "land"
end

local function isPointFree(x, y, z)
    local clear = Vehicles.config.spawnpointClearDist
    for _, veh in ipairs(getElementsByType("vehicle")) do
        local vx, vy, vz = getElementPosition(veh)
        if getDistanceBetweenPoints3D(x, y, z, vx, vy, vz) < clear then
            return false
        end
    end
    return true
end

-- Returns the closest FREE spawn point ({x,y,z,rx,ry,rz}) in the category to the
-- given position, or nil when every point in the list is occupied.
function OwnVeh.pickSpawnpoint(category, px, py, pz)
    local list = Vehicles.spawnpoints[category] or Vehicles.spawnpoints.land or {}

    local sorted = {}
    for _, point in ipairs(list) do
        sorted[#sorted + 1] = {
            point = point,
            dist  = getDistanceBetweenPoints3D(px, py, pz, point[1], point[2], point[3]),
        }
    end
    table.sort(sorted, function(a, b) return a.dist < b.dist end)

    for _, entry in ipairs(sorted) do
        local p = entry.point
        if isPointFree(p[1], p[2], p[3]) then
            return p
        end
    end
    return nil
end
