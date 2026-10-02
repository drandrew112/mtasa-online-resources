-- Helpers used by both sides: per-model offsets and the load zone behind the ambulance.

-- STRETCHER[name] (a vehicle-local offset) with the vehicle model's MODEL_Y_SHIFT applied
function vehicleOffset(vehicle, name)
    local o = STRETCHER[name]
    local shift = STRETCHER.MODEL_Y_SHIFT[getElementModel(vehicle)]
    if not shift then return o end
    return { o[1], o[2] + shift, o[3], o[4] or 0, o[5] or 0, o[6] or 0 }
end

-- World position -> the element's local space
function worldToLocal(element, x, y, z)
    local m = getElementMatrix(element)
    local dx, dy, dz = x - m[4][1], y - m[4][2], z - m[4][3]
    return dx * m[1][1] + dy * m[1][2] + dz * m[1][3],
           dx * m[2][1] + dy * m[2][2] + dz * m[2][3],
           dx * m[3][1] + dy * m[3][2] + dz * m[3][3]
end

-- Vehicle-local centre (x, y) and half side of the square load zone
function getLoadZone(vehicle)
    local c = vehicleOffset(vehicle, "LOAD_ZONE_CENTER")
    return c[1], c[2], STRETCHER.LOAD_ZONE_SIZE / 2
end

-- Is the world point (the stretcher) inside the load zone of the vehicle?
function isInLoadZone(vehicle, x, y, z)
    local lx, ly, lz = worldToLocal(vehicle, x, y, z)
    local cx, cy, half = getLoadZone(vehicle)
    return math.abs(lx - cx) <= half and math.abs(ly - cy) <= half
        and math.abs(lz) <= STRETCHER.LOAD_ZONE_HEIGHT
end
