-- Copies of the SA Control interior in other dimensions (e.g. the work_atc tutorial, one dimension per
-- session). Only the interior objects of the map are copied (interior ~= 0); the outside parts stay in
-- dimension 0. Copies are reference counted: the same dimension asked twice is one copy, it goes when
-- the last user destroys it. The wall signs (client/wallsigns.lua) are drawn in the copy dimensions
-- too: the list is the resourceRoot element data "sac.copies" ({ [dimension] = true }).

local copies = {}     -- [dimension] = { users = n, objects = { element, ... } }

local function publish()
    local dims = {}
    for dim in pairs(copies) do dims[dim] = true end
    setElementData(resourceRoot, "sac.copies", dims)
end

-- the interior objects of the map file (not the copies, which are not in dimension 0)
local function mapObjects()
    local out = {}
    local mapRoot = getResourceMapRootElement(getThisResource(), "map_int_sacontrol.map") or resourceRoot
    for _, o in ipairs(getElementsByType("object", mapRoot)) do
        if getElementInterior(o) ~= 0 and getElementDimension(o) == 0 then out[#out + 1] = o end
    end
    return out
end

-- -> true | false
function createDimensionCopy(dimension)
    local dim = tonumber(dimension)
    if not dim or dim == 0 then return false end
    local c = copies[dim]
    if c then
        c.users = c.users + 1
        return true
    end
    c = { users = 1, objects = {} }
    for _, o in ipairs(mapObjects()) do
        local x, y, z = getElementPosition(o)
        local rx, ry, rz = getElementRotation(o)
        local n = createObject(getElementModel(o), x, y, z, rx, ry, rz)
        if n then
            setElementInterior(n, getElementInterior(o))
            setElementDimension(n, dim)
            setObjectScale(n, getObjectScale(o))
            setElementAlpha(n, getElementAlpha(o))
            setElementCollisionsEnabled(n, getElementCollisionsEnabled(o))
            setElementDoubleSided(n, isElementDoubleSided(o))
            setElementFrozen(n, isElementFrozen(o))
            c.objects[#c.objects + 1] = n
        end
    end
    copies[dim] = c
    publish()
    return true
end

-- -> true when the copy is gone (or was never there)
function destroyDimensionCopy(dimension)
    local dim = tonumber(dimension)
    local c = dim and copies[dim]
    if not c then return true end
    c.users = c.users - 1
    if c.users > 0 then return false end
    for _, o in ipairs(c.objects) do
        if isElement(o) then destroyElement(o) end
    end
    copies[dim] = nil
    publish()
    return true
end

addEventHandler("onResourceStart", resourceRoot, publish)
