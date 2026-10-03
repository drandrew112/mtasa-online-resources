-- entities: spawn / delete / transform / modify / inspect workspace entities.

Entities = {}

-- moves the probe camera near a set of elements when they are far away (inside a job)
function Entities.focusOn(elements)
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, el in ipairs(elements) do
        if isElement(el) then
            local x, y, z = getElementPosition(el)
            sx, sy, sz, n = sx + x, sy + y, sz + z, n + 1
        end
    end
    if n > 0 then Probe.focus(sx / n, sy / n, sz / n) end
end

-- live check through the probe: bounds, ground gap, wheel contact, streamed state
function Entities.probeInfo(elements, opts)
    if not Probe.get() then return nil end
    local list = {}
    for _, el in ipairs(elements) do
        if isElement(el) then list[#list + 1] = el end
    end
    if #list == 0 then return nil end
    Entities.focusOn(list)
    local r = Probe.call("elementInfo", { elements = list, options = opts or {} }, 12000)
    for _, item in ipairs(r.items or {}) do
        if isElement(item.element) then item.id = Refs.of(item.element) end
        item.element = nil
    end
    return r.items
end

-- describe + live info for one element
function Entities.full(el, detail, live)
    local d = Props.describe(el, detail or "medium")
    if live ~= false then
        local info = Entities.probeInfo({ el })
        if info and info[1] then d.live = info[1] end
    end
    return d
end

local function resolveRotation(p, typ, defaultHeading)
    local rx, ry, rz = 0, 0, defaultHeading or 0
    if type(p.rotation) == "table" then
        rx = tonumber(p.rotation.x or p.rotation[1]) or 0
        ry = tonumber(p.rotation.y or p.rotation[2]) or 0
        rz = tonumber(p.rotation.z or p.rotation[3]) or rz
    end
    if p.heading ~= nil then rz = P.num(p, "heading") end
    if typ == "ped" then rx, ry = 0, 0 end
    return rx, ry, M.norm(rz)
end

-- spawn: { workspace, type, model, id, position, rotation, heading, placement, frozen, properties, meta, verify }
Api.register("entities", "spawn", function(p)
    local typ = P.str(p, "type", nil, { "vehicle", "ped", "object" })
    local model = P.int(p, "model")
    local ws = Registry.getWorkspace(p.workspace, true)
    if p.workspace and not Registry.workspaces[p.workspace] then ws = Registry.requireWorkspace(p.workspace) end

    local spec = { type = typ, model = model, id = p.id, frozen = p.frozen, meta = p.meta, variant = p.variant, plate = p.plate }
    local placementResult
    if type(p.placement) == "table" then
        placementResult = Placement.compute(p.placement, typ, model, nil, ws)
        spec.x, spec.y, spec.z = placementResult.position.x, placementResult.position.y, placementResult.position.z
        spec.rx, spec.ry, spec.rz = placementResult.rotation.x, placementResult.rotation.y, placementResult.rotation.z
        spec.placement = placementResult.summary
    else
        local x, y, z = Resolve.point(p.position, "position")
        local rx, ry, rz = resolveRotation(p, typ)
        if p.position == nil or p.position == "player" or p.position == "probe" or z == nil or p.snapToGround then
            -- no explicit z: put it on the ground under x, y
            placementResult = Placement.compute({ mode = "ground", position = { x = x, y = y, z = z }, heading = rz }, typ, model, nil, ws)
            spec.x, spec.y, spec.z = placementResult.position.x, placementResult.position.y, placementResult.position.z
            spec.rx, spec.ry, spec.rz = placementResult.rotation.x, placementResult.rotation.y, placementResult.rotation.z
            spec.placement = placementResult.summary
        else
            spec.x, spec.y, spec.z, spec.rx, spec.ry, spec.rz = x, y, z, rx, ry, rz
            spec.placement = { mode = "raw" }
        end
    end

    local entity = Registry.spawn(ws, spec)
    local applied, warnings = {}, {}
    if type(p.properties) == "table" then
        applied, warnings = Props.apply(entity.element, p.properties, entity)
    end
    if placementResult and placementResult.warnings then
        for _, w in ipairs(placementResult.warnings) do warnings[#warnings + 1] = w end
    end
    local out = {
        success = true,
        entity = Props.describe(entity.element, "medium"),
        appliedProperties = applied,
        warnings = warnings,
        placement = placementResult and placementResult.details or nil,
    }
    if p.verify ~= false and Probe.get() then
        local info = Entities.probeInfo({ entity.element })
        out.entity.live = info and info[1] or nil
        if out.entity.live then out.entity.groundContact = out.entity.live.groundContact end
    end
    return out
end, { mutates = true, async = true, desc = "Creates a vehicle / ped / object in a workspace (raw or semantic placement)." })

Api.register("entities", "delete", function(p)
    local ids = type(p.ids) == "table" and p.ids or { P.str(p, "id") }
    local deleted, notFound, released = {}, {}, {}
    for _, id in ipairs(ids) do
        local entity = Registry.entities[tostring(id)]
        if entity then
            if entity.adopted and p.destroyAdopted ~= true then released[#released + 1] = entity.id end
            Registry.destroy(entity, false, p.destroyAdopted == true)
            deleted[#deleted + 1] = tostring(id)
        else
            notFound[#notFound + 1] = tostring(id)
        end
    end
    return { success = #notFound == 0, deleted = deleted, notFound = notFound, releasedAdopted = released, remaining = Registry.count() }
end, { mutates = true, desc = "Destroys workspace entities (adopted elements are only released)." })

-- transform: { id, position, rotation, heading, move = {x,y,z} | {forward,right,up}, rotate = {x,y,z}, snapToGround }
Api.register("entities", "transform", function(p)
    local el, entity = Refs.require(P.str(p, "id"))
    local typ = getElementType(el)
    local x, y, z = getElementPosition(el)
    local rx, ry, rz = getElementRotation(el)
    local before = { position = M.vec(x, y, z), rotation = M.vec(rx, ry, rz, 2) }
    if p.position ~= nil then
        local nx, ny, nz = Resolve.point(p.position, "position")
        x, y, z = nx, ny, nz or z
    end
    if type(p.move) == "table" then
        local m = p.move
        if m.forward or m.right or m.up then
            x, y, z = M.offset(x, y, z, rz, tonumber(m.right) or 0, tonumber(m.forward) or 0, tonumber(m.up) or 0)
        else
            x, y, z = x + (tonumber(m.x) or 0), y + (tonumber(m.y) or 0), z + (tonumber(m.z) or 0)
        end
    end
    if type(p.rotation) == "table" or p.heading ~= nil then
        rx, ry, rz = resolveRotation(p, typ, rz)
    end
    if type(p.rotate) == "table" then
        rx = rx + (tonumber(p.rotate.x) or 0)
        ry = ry + (tonumber(p.rotate.y) or 0)
        rz = M.norm(rz + (tonumber(p.rotate.z) or 0))
    end
    local placement
    if p.snapToGround then
        placement = Placement.compute({ mode = "ground", position = { x = x, y = y, z = z }, heading = rz, align = p.align }, typ, getElementModel(el), el)
        x, y, z = placement.position.x, placement.position.y, placement.position.z
        rx, ry, rz = placement.rotation.x, placement.rotation.y, placement.rotation.z
    end
    Placement.apply(el, x, y, z, rx, ry, rz)
    if entity then entity.placement = placement and placement.summary or { mode = "raw" } end
    local out = { success = true, before = before, entity = Props.describe(el, "medium"), placement = placement and placement.details or nil }
    if p.verify ~= false and Probe.get() then
        local info = Entities.probeInfo({ el })
        out.entity.live = info and info[1] or nil
    end
    return out
end, { mutates = true, async = true, desc = "Absolute / relative move and rotate." })

Api.register("entities", "modify", function(p)
    local el, entity = Refs.require(P.str(p, "id"))
    if type(p.properties) ~= "table" then fail("INVALID_PARAMS", "properties must be an object.") end
    local applied, warnings = Props.apply(el, p.properties, entity)
    return { success = #applied > 0, applied = applied, warnings = warnings, entity = Props.describe(el, "high") }
end, { mutates = true, desc = "Changes properties (colour, damage, pose, seat, frozen, alpha, ...)." })

Api.register("entities", "get", function(p)
    local el = Refs.require(P.str(p, "id"))
    return Props.describe(el, P.str(p, "detail", "high", { "low", "medium", "high" }))
end, { desc = "Registry + element state without probe round trip." })

-- inspect: { id, detail, nearbyRadius }
Api.register("entities", "inspect", function(p)
    local el, entity = Refs.require(P.str(p, "id"))
    local detail = P.str(p, "detail", "high", { "low", "medium", "high" })
    local d = Entities.full(el, detail, Probe.get() ~= nil)
    local x, y, z = getElementPosition(el)
    local radius = P.num(p, "nearbyRadius", 15, 1, 200)
    local near = Resolve.elementsNear(x, y, z, radius, { "vehicle", "ped", "player", "object" }, getElementDimension(el), nil, 30, "low")
    local _, _, rz = getElementRotation(el)
    for i = #near, 1, -1 do
        if near[i].id == d.id then table.remove(near, i)
        else
            local n = near[i]
            n.relation = M.relation(x, y, z, rz, n.position.x, n.position.y, n.position.z)
        end
    end
    d.nearby = near
    d.zone = Util.zone(x, y, z)
    local pl = Probe.get()
    if pl then
        local px, py, pz = getElementPosition(pl)
        d.fromProbePlayer = M.relation(px, py, pz, select(3, getElementRotation(pl)), x, y, z)
    end
    return d
end, { async = true, desc = "Full entity state + live geometry (bounds, ground gap, contact) + neighbours." })

Api.register("entities", "adopt", function(p)
    local el = Refs.require(P.str(p, "ref"))
    local ws = p.workspace and Registry.requireWorkspace(p.workspace) or Registry.getWorkspace(nil, true)
    local entity = Registry.adopt(ws, el, p.id)
    return { success = true, entity = Props.describe(entity.element, "medium"),
        note = "Adopted elements are released (not destroyed) by delete_entity / clear_workspace unless destroyAdopted is set." }
end, { mutates = true, desc = "Puts an existing element under a workspace id." })

-- relation: { from, to } -> distance, direction, relative side, clearance
Api.register("entities", "relation", function(p)
    local ax, ay, az, ai = Resolve.point(p.from, "from")
    local bx, by, bz, bi = Resolve.point(p.to, "to")
    local h = ai.heading or P.num(p, "heading", 0)
    local r = M.relation(ax, ay, az, h, bx, by, bz)
    r.from = { position = M.vec(ax, ay, az), heading = M.round(h, 1), id = ai.id }
    r.to = { position = M.vec(bx, by, bz), heading = bi.heading and M.round(bi.heading, 1), id = bi.id }
    if bi.heading then
        r.headingDifference = M.round(M.angleDiff(h, bi.heading), 1)
        local a = math.abs(r.headingDifference)
        r.orientation = (a < 20 and "parallel_same_direction") or (a > 160 and "parallel_opposite") or ((a > 70 and a < 110) and "perpendicular") or "angled"
    end
    if ai.element and bi.element and Probe.get() then
        local info = Entities.probeInfo({ ai.element, bi.element })
        if info and info[1] and info[2] and info[1].obb and info[2].obb then
            local oa, ob = info[1].obb, info[2].obb
            r.overlapping = M.obbOverlap(oa, ob)
            r.clearance2D = M.round(M.obbClearance2D(oa, ob), 2)
        end
    end
    return r
end, { async = true, desc = "Spatial relation between two entities / points." })
