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

-- Vehicle-local centre (x, y), half width (x) and half length (y) of the load zone
function getLoadZone(vehicle)
    local c = vehicleOffset(vehicle, "LOAD_ZONE_CENTER")
    return c[1], c[2], STRETCHER.LOAD_ZONE_WIDTH / 2, STRETCHER.LOAD_ZONE_LENGTH / 2
end

-- Is the world point (the stretcher) inside the load zone of the vehicle?
function isInLoadZone(vehicle, x, y, z)
    local lx, ly, lz = worldToLocal(vehicle, x, y, z)
    local cx, cy, halfW, halfL = getLoadZone(vehicle)
    return math.abs(lx - cx) <= halfW and math.abs(ly - cy) <= halfL
        and math.abs(lz) <= STRETCHER.LOAD_ZONE_HEIGHT
end

-- Does a stretcher with this world yaw point into the vehicle (within LOAD_ZONE_MAX_ANGLE of the
-- stowed direction)?
function isLoadAligned(vehicle, yaw)
    local _, _, vrz = getElementRotation(vehicle)
    local diff = (yaw - (vrz + STRETCHER.STOW_OFFSET[6]) + 180) % 360 - 180
    return math.abs(diff) <= STRETCHER.LOAD_ZONE_MAX_ANGLE
end
