-- The player watches the world from their own dimension, where the objects and peds of
-- dimension 0 (custom maps like map_ls_shop_01, script objects, shopkeepers) do not exist - and
-- the world models those maps remove are gone everywhere. Mirror copies what is near the camera's
-- target into the introduction's dimension, client-side only, while the scene shows it.

Mirror = { dimension = nil, clones = {}, center = nil }

local function isClone(element) return Mirror.clones[element] == true end

function Mirror.clear()
    for element in pairs(Mirror.clones) do
        if isElement(element) then destroyElement(element) end
    end
    Mirror.clones, Mirror.center = {}, nil
end

local function add(element) Mirror.clones[element] = true end

local function copyObject(o)
    local x, y, z = getElementPosition(o)
    local rx, ry, rz = getElementRotation(o)
    local c = createObject(getElementModel(o), x, y, z, rx, ry, rz)
    if not c then return end
    add(c)
    setElementDimension(c, Mirror.dimension)
    setObjectScale(c, getObjectScale(o))
    setElementAlpha(c, getElementAlpha(o))
    setElementDoubleSided(c, isElementDoubleSided(o))
    setElementFrozen(c, true)
    setObjectBreakable(c, false)
end

local function copyPed(p)
    local x, y, z = getElementPosition(p)
    local _, _, rz = getElementRotation(p)
    local c = createPed(getElementModel(p), x, y, z, rz)
    if not c then return end
    add(c)
    setElementDimension(c, Mirror.dimension)
    setElementFrozen(c, true)
end

-- Copies everything within `radius` of x, y (dimension 0, interior 0). The same centre again
-- keeps the copies.
function Mirror.show(x, y, radius)
    if not Mirror.dimension then return end
    radius = radius or INTRO.MIRROR_RADIUS
    local c = Mirror.center
    if c and math.abs(c[1] - x) < 1 and math.abs(c[2] - y) < 1 and c[3] == radius then return end
    Mirror.clear()
    Mirror.center = { x, y, radius }
    local r2 = radius * radius
    local function near(e)
        if isClone(e) or getElementDimension(e) ~= 0 or getElementInterior(e) ~= 0 then return false end
        local ex, ey = getElementPosition(e)
        return (ex - x) ^ 2 + (ey - y) ^ 2 <= r2
    end
    for _, o in ipairs(getElementsByType("object")) do
        -- low LOD copies (drawdistance) are left out, the camera is close anyway
        if near(o) and not isElementLowLOD(o) then copyObject(o) end
    end
    for _, p in ipairs(getElementsByType("ped")) do
        if near(p) then copyPed(p) end
    end
end

addEventHandler("onClientResourceStop", resourceRoot, Mirror.clear)
