-- Workspaces and the entities created through the bridge.
--
-- Every element the bridge creates belongs to a workspace and has a semantic id
-- (<prefix>_<type>_<nnn>, e.g. tmp_vehicle_001). The registry maps id <-> element.
-- When an element disappears (destroyed by another script, exploded, ...) the
-- entity stays listed with status "missing" until it is deleted or the workspace
-- is cleared. Everything lives in memory: a bridge restart drops all workspaces
-- (and the elements with them, as they belong to this resource).

Registry = { workspaces = {}, entities = {}, byElement = {}, order = {}, counters = {} }

local TYPES = { vehicle = true, ped = true, object = true }
Registry.TYPES = TYPES

local NAME_PATTERN = "^[%w_%-]+$"

local function validName(name)
    return type(name) == "string" and #name >= 1 and #name <= 40 and name:match(NAME_PATTERN) ~= nil
end

---------------------------------------------------------------- workspaces

function Registry.getWorkspace(name, create)
    name = name or CMCP.DEFAULT_WORKSPACE
    local ws = Registry.workspaces[name]
    if not ws and create then
        ws = Registry.createWorkspace({ name = name })
    end
    return ws
end

function Registry.requireWorkspace(name)
    local ws = Registry.workspaces[name or CMCP.DEFAULT_WORKSPACE]
    if not ws then
        fail("WORKSPACE_NOT_FOUND", "Workspace '" .. tostring(name) .. "' does not exist.",
            { retryable = false, suggestion = "Create it with create_workspace (or omit the workspace to use 'default')." })
    end
    return ws
end

-- p: { name, kind, dimension, interior, center, radius, description, prefix, frozen, meta }
function Registry.createWorkspace(p)
    local name = p.name or CMCP.DEFAULT_WORKSPACE
    if not validName(name) then
        fail("INVALID_PARAMS", "Workspace name must be 1-40 characters of letters, digits, _ or -.")
    end
    if Registry.workspaces[name] then
        fail("WORKSPACE_EXISTS", "Workspace '" .. name .. "' already exists.",
            { retryable = false, suggestion = "Use it as is, clear it with clear_workspace, or pick another name." })
    end
    local probe = Probe.primary()
    local prefix = p.prefix or (name == CMCP.DEFAULT_WORKSPACE and CMCP.ID_PREFIX or name)
    if not validName(prefix) then prefix = CMCP.ID_PREFIX end
    local ws = {
        name = name,
        kind = p.kind or "generic",
        prefix = prefix,
        dimension = tonumber(p.dimension) or (probe and getElementDimension(probe)) or 0,
        interior = tonumber(p.interior) or (probe and getElementInterior(probe)) or 0,
        center = p.center,
        radius = tonumber(p.radius),
        description = p.description,
        frozen = p.frozen ~= false,
        meta = type(p.meta) == "table" and p.meta or {},
        createdAt = getRealTime().timestamp,
        entities = {},
    }
    Registry.workspaces[name] = ws
    Registry.order[#Registry.order + 1] = name
    return ws
end

function Registry.workspaceSummary(ws)
    local counts, missing = { vehicle = 0, ped = 0, object = 0 }, 0
    for _, id in ipairs(ws.entities) do
        local e = Registry.entities[id]
        if e then
            counts[e.type] = (counts[e.type] or 0) + 1
            if not isElement(e.element) then missing = missing + 1 end
        end
    end
    return {
        name = ws.name, kind = ws.kind, prefix = ws.prefix,
        dimension = ws.dimension, interior = ws.interior,
        center = ws.center, radius = ws.radius, description = ws.description,
        frozenByDefault = ws.frozen,
        entityCount = #ws.entities, counts = counts, missing = missing,
        createdAt = ws.createdAt, meta = ws.meta,
    }
end

-- destroys every entity of the workspace; keep = keep the (empty) workspace
function Registry.clearWorkspace(ws, keep)
    local removed = {}
    for i = #ws.entities, 1, -1 do
        removed[#removed + 1] = ws.entities[i]
        Registry.destroy(Registry.entities[ws.entities[i]], true)
    end
    ws.entities = {}
    if not keep then
        Registry.workspaces[ws.name] = nil
        for i, n in ipairs(Registry.order) do
            if n == ws.name then table.remove(Registry.order, i) break end
        end
    end
    return removed
end

---------------------------------------------------------------- entities

local function nextId(ws, typ)
    local key = ws.prefix .. "_" .. typ
    local n = Registry.counters[key] or 0
    repeat
        n = n + 1
    until not Registry.entities[string.format("%s_%s_%03d", ws.prefix, typ, n)]
    Registry.counters[key] = n
    return string.format("%s_%s_%03d", ws.prefix, typ, n)
end

function Registry.count()
    return Util.count(Registry.entities)
end

-- Creates the element and registers it.
-- spec: { type, model, x, y, z, rx, ry, rz, id, frozen, meta, variant = {a,b}, plate }
function Registry.spawn(ws, spec)
    local typ = spec.type
    if not TYPES[typ] then
        fail("INVALID_ENTITY_TYPE", "Entity type must be vehicle, ped or object (got '" .. tostring(typ) .. "').")
    end
    if Registry.count() >= CMCP.MAX_ENTITIES then
        fail("ENTITY_LIMIT", "The bridge already manages " .. CMCP.MAX_ENTITIES .. " entities.",
            { retryable = false, suggestion = "Clear unused workspaces with clear_workspace." })
    end
    local id = spec.id
    if id ~= nil then
        id = tostring(id)
        if not validName(id) then fail("INVALID_PARAMS", "Entity id must be 1-40 characters of letters, digits, _ or -.") end
        if Registry.entities[id] then
            fail("ENTITY_EXISTS", "An entity with id '" .. id .. "' already exists.", { entity = id, suggestion = "Pick another id or omit it for an automatic one." })
        end
    else
        id = nextId(ws, typ)
    end

    local model = math.floor(tonumber(spec.model) or -1)
    local x, y, z = spec.x, spec.y, spec.z
    local rx, ry, rz = spec.rx or 0, spec.ry or 0, spec.rz or 0
    local el
    if typ == "vehicle" then
        if not getVehicleNameFromModel(model) or getVehicleNameFromModel(model) == "" then
            if model < 400 or model > 611 then
                fail("MODEL_NOT_FOUND", "Vehicle model " .. tostring(model) .. " could not be resolved.",
                    { retryable = false, suggestion = "Find valid ids with get_vehicle_models or search_models." })
            end
        end
        local v1, v2 = 255, 255
        if type(spec.variant) == "table" then v1, v2 = tonumber(spec.variant[1]) or 255, tonumber(spec.variant[2]) or 255 end
        el = createVehicle(model, x, y, z, rx, ry, rz, spec.plate, false, v1, v2)
    elseif typ == "ped" then
        el = createPed(model, x, y, z, rz, true)
    else
        el = createObject(model, x, y, z, rx, ry, rz)
    end
    if not el then
        fail("MODEL_NOT_FOUND", typ:gsub("^%l", string.upper) .. " model " .. tostring(model) .. " could not be created.",
            { retryable = false, suggestion = typ == "ped" and "Use get_ped_models for valid skins." or "Use search_models / get_model_info to find a valid model." })
    end
    setElementDimension(el, ws.dimension)
    setElementInterior(el, ws.interior)
    if typ == "ped" then setElementRotation(el, 0, 0, rz, "default", true) end
    local frozen = spec.frozen
    if frozen == nil then frozen = ws.frozen end
    setElementFrozen(el, frozen)
    if typ == "vehicle" then
        setVehicleDamageProof(el, true)
        setVehicleEngineState(el, false)
    end
    setElementData(el, "cmcp.id", id, false)

    local entity = {
        id = id, workspace = ws.name, type = typ, model = model, element = el,
        createdAt = getRealTime().timestamp, status = "ok",
        meta = type(spec.meta) == "table" and spec.meta or {},
        placement = spec.placement,
    }
    Registry.entities[id] = entity
    Registry.byElement[el] = entity
    ws.entities[#ws.entities + 1] = id
    return entity
end

-- adopts an existing element (not created by the bridge) into a workspace
function Registry.adopt(ws, el, id)
    local typ = getElementType(el)
    if not TYPES[typ] then fail("INVALID_ENTITY_TYPE", "Only vehicles, peds and objects can be adopted (got " .. typ .. ").") end
    if Registry.byElement[el] then fail("ENTITY_EXISTS", "Element is already the entity '" .. Registry.byElement[el].id .. "'.") end
    if id and Registry.entities[id] then fail("ENTITY_EXISTS", "An entity with id '" .. id .. "' already exists.") end
    id = id or nextId(ws, typ)
    local entity = { id = id, workspace = ws.name, type = typ, model = getElementModel(el), element = el,
        createdAt = getRealTime().timestamp, status = "ok", adopted = true, meta = {} }
    Registry.entities[id] = entity
    Registry.byElement[el] = entity
    ws.entities[#ws.entities + 1] = id
    local ref = Refs.byElement[el]
    if ref then Refs.byElement[el] = nil Refs.byRef[ref] = nil end
    return entity
end

-- destroys the element (adopted elements are only released unless destroyAdopted)
function Registry.destroy(entity, skipList, destroyAdopted)
    if not entity then return end
    local el = entity.element
    Registry.entities[entity.id] = nil
    if el then Registry.byElement[el] = nil end
    if isElement(el) and (not entity.adopted or destroyAdopted) then destroyElement(el) end
    if not skipList then
        local ws = Registry.workspaces[entity.workspace]
        if ws then
            for i, id in ipairs(ws.entities) do
                if id == entity.id then table.remove(ws.entities, i) break end
            end
        end
    end
end

addEventHandler("onElementDestroy", root, function()
    local entity = Registry.byElement[source]
    if entity then
        entity.status = "missing"
        entity.lostReason = "element destroyed outside the bridge"
        Registry.byElement[source] = nil
        Util.addLog("warning", "registry", "entity " .. entity.id .. " lost: element destroyed outside the bridge")
    end
end)

addEventHandler("onVehicleExplode", root, function()
    local entity = Registry.byElement[source]
    if entity then
        entity.status = "exploded"
        Util.addLog("warning", "registry", "entity " .. entity.id .. " exploded")
    end
end)

addEventHandler("onPedWasted", root, function()
    local entity = Registry.byElement[source]
    if entity then entity.status = "dead" end
end)
