-- drawdistance / scripts/main_c.lua
--
-- Increases how far the world and mapped objects are drawn.
--
-- Two things happen:
--
--   1. Global render distance. setFarClipDistance / setFogDistance /
--      setPedsLODDistance / setVehiclesLODDistance are raised so the default
--      GTA world (and peds / vehicles) keep rendering far away. These are the
--      only levers that affect built-in map geometry.
--
--   2. Low-LOD clones for mapped objects. Objects that come from .map files
--      (loaded by other resources) do not have LOD models, so GTA stops
--      drawing them at a short distance. For every such object that is exterior
--      and big (MIN_CLONE_RADIUS) - and for the objects maps_loader registers
--      with registerLowLOD - we create a
--      low-LOD twin with createObject(..., true) and link it with
--      setLowLODElement, then push the model's LOD switch distance out with
--      engineSetModelLODDistance. The clone is what you see from far away.
--
-- Four values are adjustable independently, each with its own export. ui_pause
-- Graphics settings drives them:
--
--      exports.drawdistance:setFarClip(1600)     -- 400 .. 3400   (fog = farClip - 200)
--      exports.drawdistance:setModelLOD(600)     -- 200 .. 2800
--      exports.drawdistance:setPedLOD(500)       -- 200 .. 500   (engine hard cap)
--      exports.drawdistance:setVehicleLOD(500)   -- 200 .. 500   (engine hard cap)
--      exports.drawdistance:getFarClip() / getModelLOD() / getPedLOD() / getVehicleLOD()
--      exports.drawdistance:resetDrawDistance()  -- all back to defaults
--
-- Originally by IIYAMA ("Draw distance increase", v1.0.2); rewritten to use
-- plain timers and to expose the values individually.

--------------------------------------------------------------------------------
-- configuration
--------------------------------------------------------------------------------

-- Allowed range for each value. Peds and vehicles are clamped to 0-500 by the
-- engine itself, so there is no point offering more.
local RANGE = {
    farClip    = { min = 400, max = 3400 },
    modelLOD   = { min = 200, max = 2800 },
    pedLOD     = { min = 200, max = 500 },
    vehicleLOD = { min = 200, max = 500 },
}

local DEFAULT = {
    farClip    = 1400,
    modelLOD   = 400,
    pedLOD     = 500,
    vehicleLOD = 500,
}

-- Fog trails the far clip at a fixed offset behind it.
local FOG_OFFSET = 200

-- Object cloning pace.
local CLONE_BUDGET_MS = 2      -- stop a tick after this many ms of work
local CLONE_TICK_MS   = 100

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local current = {
    farClip    = DEFAULT.farClip,
    modelLOD   = DEFAULT.modelLOD,
    pedLOD     = DEFAULT.pedLOD,
    vehicleLOD = DEFAULT.vehicleLOD,
}

-- res -> { parents = { mapRoot -> parentElement }, clones = count }
local tracked = {}

-- parentElement -> res, so the break / stream handlers can tell "our" clones apart
local parentOwner = {}

-- model id -> true, every model we have pushed a LOD distance onto
local loadedModels = {}

-- Pending clone work: array of { object, parent, res }.
local queue = {}
local queueTimer = nil

--------------------------------------------------------------------------------
-- applying the values
--------------------------------------------------------------------------------

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- id -> { distance, res }: other resources may pull the fog closer (wx_snow blizzard).
-- The nearest override wins; it never pushes the fog past farClip - FOG_OFFSET.
local fogOverrides = {}

local function fogDistance()
    local fog = math.max(current.farClip - FOG_OFFSET, 100)
    for _, o in pairs(fogOverrides) do
        if o.distance < fog then fog = o.distance end
    end
    return math.max(fog, 20)
end

local function applyFarClip()
    setFarClipDistance(current.farClip)
    setFogDistance(fogDistance())
end

local function applyPedLOD()
    setPedsLODDistance(current.pedLOD)
end

local function applyVehicleLOD()
    setVehiclesLODDistance(current.vehicleLOD, current.vehicleLOD)
end

-- Re-apply the model LOD switch distance to every model we have cloned so far.
local function applyModelLOD()
    for model in pairs(loadedModels) do
        engineSetModelLODDistance(model, current.modelLOD, true)
    end
end

local APPLY = {
    farClip    = applyFarClip,
    modelLOD   = applyModelLOD,
    pedLOD     = applyPedLOD,
    vehicleLOD = applyVehicleLOD,
}

local function applyAll()
    applyFarClip()
    applyPedLOD()
    applyVehicleLOD()
    applyModelLOD()
end

-- Clamp, store and apply one value. Returns the value actually applied.
local function setValue(key, value)
    value = tonumber(value)
    if not value then return false end

    local range = RANGE[key]
    value = clamp(value, range.min, range.max)
    current[key] = value
    APPLY[key]()
    return value
end

-- Apply the defaults straight away, at script-load time. This runs before any
-- onClientResourceStart, so a value pushed later by ui_pause (the player's saved
-- Graphics settings) is never overwritten by our own start-up.
applyAll()

--------------------------------------------------------------------------------
-- object cloning
--------------------------------------------------------------------------------

-- PERF (2026-11-09): only exterior objects of at least this bounding radius (x scale) get a low LOD
-- twin. The twin uses the same full model and is drawn up to the far clip, and the model's LOD
-- distance is raised for every instance of that model in the world - worth it for buildings, not
-- for furniture and street props (those keep the game's own draw distance).
local MIN_CLONE_RADIUS = 10

local function worthCloning(object)
    if getElementInterior(object) ~= 0 then return false end
    local r = getElementRadius(object)
    return r and r * (getObjectScale(object) or 1) >= MIN_CLONE_RADIUS
end

-- Create the low-LOD twin for one mapped object.
local function cloneObject(object, parent)
    if not isElement(object) or getElementType(object) ~= "object" then return end
    if getElementAlpha(object) ~= 255 then return end
    if getLowLODElement(object) then return end
    if not worthCloning(object) then return end

    local model = getElementModel(object)
    local x, y, z = getElementPosition(object)
    local rx, ry, rz = getElementRotation(object)

    local clone = createObject(model, x, y, z, rx, ry, rz, true)
    if not clone then return end

    setElementParent(clone, parent)

    local interior = getElementInterior(object)
    if interior ~= 0 then setElementInterior(clone, interior) end

    local dimension = getElementDimension(object)
    if dimension ~= 0 then setElementDimension(clone, dimension) end

    if isElementDoubleSided(object) then
        setElementDoubleSided(clone, true)
    end

    setLowLODElement(object, clone)

    if not loadedModels[model] then
        loadedModels[model] = true
        engineSetModelLODDistance(model, current.modelLOD, true)
    end

    local scale = getObjectScale(object) or 1
    if scale ~= 1 then setObjectScale(clone, scale) end

    if isObjectBreakable(object) then
        attachElements(clone, object)
        setObjectBreakable(clone, false)
    end
    return clone
end

--------------------------------------------------------------------------------
-- objects of other resources (maps_loader): registerLowLOD / unregisterLowLOD
--------------------------------------------------------------------------------

-- client-side objects created by scripts are no map elements; maps_loader decides which of its
-- objects deserve a low LOD twin and asks for it here. The twin follows the object: it is removed
-- when the object is destroyed or unregistered.
local registered = {}          -- object -> clone
local registeredParent = nil

function registerLowLOD(object)
    if not isElement(object) or getElementType(object) ~= "object" then return false end
    if registered[object] and isElement(registered[object]) then return true end
    if not isElement(registeredParent) then
        registeredParent = createElement("lowLODParent")
        parentOwner[registeredParent] = "registered"
    end
    local clone = cloneObject(object, registeredParent)
    if not clone then return false end
    registered[object] = clone
    return true
end

function unregisterLowLOD(object)
    local clone = registered[object]
    registered[object] = nil
    if clone and isElement(clone) then destroyElement(clone) end
    return true
end

addEventHandler("onClientElementDestroy", root, function()
    local clone = registered[source]
    if clone then
        registered[source] = nil
        if isElement(clone) then destroyElement(clone) end
    end
end)

local function processQueue()
    local deadline = getTickCount() + CLONE_BUDGET_MS
    while #queue > 0 do
        local item = table.remove(queue)
        local info = tracked[item.res]
        if info and isElement(item.parent) then
            cloneObject(item.object, item.parent)
            info.clones = info.clones + 1
        end
        if getTickCount() >= deadline then break end
    end

    if #queue == 0 and queueTimer then
        if isTimer(queueTimer) then killTimer(queueTimer) end
        queueTimer = nil
    end
end

local function ensureQueueTimer()
    if not queueTimer or not isTimer(queueTimer) then
        queueTimer = setTimer(processQueue, CLONE_TICK_MS, 0)
    end
end

-- Queue every mapped object of a resource for cloning.
local function loadResource(res, resourceRoot)
    if res == resource or tracked[res] then return end

    local mapRoots = getElementsByType("map", resourceRoot)
    if #mapRoots == 0 then return end

    local info = { parents = {}, clones = 0 }

    for _, mapRoot in ipairs(mapRoots) do
        local objects = getElementsByType("object", mapRoot)
        if #objects > 0 then
            local parent = createElement("lowLODParent")
            info.parents[mapRoot] = parent
            parentOwner[parent] = res
            for _, object in ipairs(objects) do
                queue[#queue + 1] = { object = object, parent = parent, res = res }
            end
        end
    end

    if next(info.parents) then
        tracked[res] = info
        ensureQueueTimer()
    end
end

-- Drop all clones of a resource. destroyElement on the parent cuts the whole
-- subtree at once and lets MTA clean up the children.
local function unloadResource(res)
    local info = tracked[res]
    if not info then return end
    tracked[res] = nil

    for _, parent in pairs(info.parents) do
        parentOwner[parent] = nil
        if isElement(parent) then destroyElement(parent) end
    end

    -- Forget queued work that belonged to this resource.
    for i = #queue, 1, -1 do
        if queue[i].res == res then table.remove(queue, i) end
    end
end

--------------------------------------------------------------------------------
-- breakable object handling
--------------------------------------------------------------------------------

-- A breakable clone is attached to its HD object; hide it while broken and show
-- it again once the HD object streams back out (which resets the break state).
addEventHandler("onClientObjectBreak", root, function()
    local clone = getLowLODElement(source)
    if clone and parentOwner[getElementParent(clone)] then
        setElementAlpha(clone, 0)
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "object" and getLowLODElement(source) and isObjectBreakable(source) then
        local clone = getLowLODElement(source)
        if clone and parentOwner[getElementParent(clone)] then
            setElementAlpha(clone, 255)
        end
    end
end)

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

addEventHandler("onClientResourceStart", root, function(res)
    if res ~= resource then
        loadResource(res, source)
        return
    end

    -- The game re-asserts its own distances in some states (interiors, water,
    -- cutscenes); a slow timer keeps ours in place. Model LOD is sticky.
    setTimer(function()
        applyFarClip()
        applyPedLOD()
        applyVehicleLOD()
    end, 2000, 0)

    -- Clone objects for resources that were already running before us.
    for _, resourceRoot in ipairs(getElementsByType("resource")) do
        local name = getElementID(resourceRoot)
        local other = name and getResourceFromName(name)
        if other and other ~= resource and getResourceState(other) == "running" then
            loadResource(other, resourceRoot)
        end
    end
end)

addEventHandler("onClientResourceStop", root, function(res)
    if res == resource then
        if queueTimer and isTimer(queueTimer) then killTimer(queueTimer) end
        queueTimer = nil
        queue = {}
        resetFarClipDistance()
        if resetFogDistance then resetFogDistance() end
        resetPedsLODDistance()
        resetVehiclesLODDistance()
        for model in pairs(loadedModels) do
            if engineResetModelLODDistance then
                engineResetModelLODDistance(model)
            else
                engineSetModelLODDistance(model, 170)
            end
        end
    else
        unloadResource(res)
        -- fog overrides of the stopped resource
        local changed = false
        for id, o in pairs(fogOverrides) do
            if o.res == res then fogOverrides[id] = nil; changed = true end
        end
        if changed then applyFarClip() end
        -- twins of registered objects whose resource stopped (its elements go after this event)
        setTimer(function()
            for object, clone in pairs(registered) do
                if not isElement(object) then
                    registered[object] = nil
                    if isElement(clone) then destroyElement(clone) end
                end
            end
        end, 50, 1)
    end
end)

--------------------------------------------------------------------------------
-- exports  (used by ui_pause Graphics settings)
--------------------------------------------------------------------------------

-- Far clip / render distance, 400 .. 3400. Fog is kept 200 units behind it.
function setFarClip(value) return setValue("farClip", value) end
function getFarClip() return current.farClip end

-- LOD switch distance for cloned mapped objects, 200 .. 2800.
function setModelLOD(value) return setValue("modelLOD", value) end
function getModelLOD() return current.modelLOD end

-- Ped LOD distance, 200 .. 500 (the engine clamps to 500).
function setPedLOD(value) return setValue("pedLOD", value) end
function getPedLOD() return current.pedLOD end

-- Vehicle LOD distance, 200 .. 500 (the engine clamps to 500).
function setVehicleLOD(value) return setValue("vehicleLOD", value) end
function getVehicleLOD() return current.vehicleLOD end

-- Fog override: setFogOverride(id, distance) pulls the fog to `distance` metres (nearest
-- override wins), setFogOverride(id, false) removes it. Removed when the caller stops.
function setFogOverride(id, distance)
    if type(id) ~= "string" then return false end
    distance = tonumber(distance)
    if distance then
        fogOverrides[id] = { distance = math.max(distance, 20), res = sourceResource }
    else
        fogOverrides[id] = nil
    end
    applyFarClip()
    return true
end

function getFogDistance() return fogDistance() end

function resetDrawDistance()
    for key, value in pairs(DEFAULT) do
        current[key] = value
    end
    applyAll()
    return true
end
