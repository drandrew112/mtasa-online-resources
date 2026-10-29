-- Helpers used by both sides: offsets, side point, names.

-- Local offset of an element -> world position
function bagOffsetOf(element, ox, oy, oz)
    local m = getElementMatrix(element)
    return ox * m[1][1] + oy * m[2][1] + oz * m[3][1] + m[4][1],
           ox * m[1][2] + oy * m[2][2] + oz * m[3][2] + m[4][2],
           ox * m[1][3] + oy * m[2][3] + oz * m[3][3] + m[4][3]
end

-- World position -> the element's local space
function bagWorldToLocal(element, x, y, z)
    local m = getElementMatrix(element)
    local dx, dy, dz = x - m[4][1], y - m[4][2], z - m[4][3]
    return dx * m[1][1] + dy * m[1][2] + dz * m[1][3],
           dx * m[2][1] + dy * m[2][2] + dz * m[2][3],
           dx * m[3][1] + dy * m[3][2] + dz * m[3][3]
end

-- Vehicle-local side-door point of an ambulance model
function bagSidePoint(vehicle)
    return BAG.SIDE_POINT[getElementModel(vehicle)] or BAG.DEFAULT_SIDE_POINT
end

-- World position of the side-door point
function bagSideWorld(vehicle)
    local p = bagSidePoint(vehicle)
    return bagOffsetOf(vehicle, p[1], p[2], p[3])
end

function bagSameWorld(a, b)
    return getElementDimension(a) == getElementDimension(b) and getElementInterior(a) == getElementInterior(b)
end

function bagItemName(kind)
    return BAG.ITEM_NAMES[kind] or kind
end
