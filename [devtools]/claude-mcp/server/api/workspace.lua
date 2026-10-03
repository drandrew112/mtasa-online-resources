-- workspace: temporary entity groups.

Api.register("workspace", "create", function(p)
    local center
    if p.center ~= nil then
        local x, y, z = Resolve.point(p.center, "center")
        center = M.vec(x, y, z)
    end
    local ws = Registry.createWorkspace({
        name = P.str(p, "name"), kind = p.kind, prefix = p.prefix, dimension = p.dimension, interior = p.interior,
        center = center, radius = p.radius, description = p.description, frozen = p.frozen, meta = p.meta,
    })
    return { success = true, workspace = Registry.workspaceSummary(ws) }
end, { mutates = true, desc = "Creates a named workspace (dimension / interior / centre / radius)." })

Api.register("workspace", "list", function()
    local out = {}
    for _, name in ipairs(Registry.order) do
        local ws = Registry.workspaces[name]
        if ws then out[#out + 1] = Registry.workspaceSummary(ws) end
    end
    return { workspaces = out, entityCount = Registry.count() }
end, { desc = "All workspaces with counts." })

-- entities: { workspace, detail }
Api.register("workspace", "entities", function(p)
    local ws = Registry.requireWorkspace(p.workspace)
    local detail = P.str(p, "detail", "low", { "low", "medium", "high" })
    local out = {}
    for _, id in ipairs(ws.entities) do
        local e = Registry.entities[id]
        if e then
            if isElement(e.element) then
                out[#out + 1] = Props.describe(e.element, detail)
            else
                out[#out + 1] = { id = e.id, type = e.type, model = e.model, status = "missing", lostReason = e.lostReason }
            end
        end
    end
    return { workspace = ws.name, count = #out, entities = out }
end, { desc = "Entities of a workspace." })

-- inspect: summary + entities + bounds + optional live info
Api.register("workspace", "inspect", function(p)
    local ws = Registry.requireWorkspace(p.workspace)
    local detail = P.str(p, "detail", "medium", { "low", "medium", "high" })
    local list, elements = {}, {}
    local minX, minY, minZ, maxX, maxY, maxZ = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
    for _, id in ipairs(ws.entities) do
        local e = Registry.entities[id]
        if e and isElement(e.element) then
            local d = Props.describe(e.element, detail)
            list[#list + 1] = d
            elements[#elements + 1] = e.element
            local x, y, z = getElementPosition(e.element)
            minX, minY, minZ = math.min(minX, x), math.min(minY, y), math.min(minZ, z)
            maxX, maxY, maxZ = math.max(maxX, x), math.max(maxY, y), math.max(maxZ, z)
        elseif e then
            list[#list + 1] = { id = e.id, type = e.type, model = e.model, status = "missing", lostReason = e.lostReason }
        end
    end
    local out = { workspace = Registry.workspaceSummary(ws), entities = list }
    if #elements > 0 then
        out.bounds = { min = M.vec(minX, minY, minZ), max = M.vec(maxX, maxY, maxZ),
            center = M.vec((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
            size = M.vec(maxX - minX, maxY - minY, maxZ - minZ) }
        out.zone = Util.zone(out.bounds.center.x, out.bounds.center.y, out.bounds.center.z)
        if p.live ~= false and Probe.get() then
            local info = Entities.probeInfo(elements)
            if info then
                for i, d in ipairs(list) do
                    for _, item in ipairs(info) do
                        if item.id == d.id then d.live = item break end
                    end
                end
            end
        end
    end
    return out
end, { async = true, desc = "Workspace summary, entities with live geometry, bounds." })

-- clear: { workspace, keep }
Api.register("workspace", "clear", function(p)
    local ws = Registry.requireWorkspace(p.workspace)
    local keep = p.keep ~= false
    local removed = Registry.clearWorkspace(ws, keep)
    if ws.name == CMCP.DEFAULT_WORKSPACE and not keep then
        -- the default workspace is recreated lazily
    end
    Overlay.forget(removed)
    return { success = true, workspace = ws.name, removed = removed, removedCount = #removed, workspaceKept = keep }
end, { mutates = true, desc = "Destroys all entities of a workspace (and optionally the workspace)." })

Api.register("workspace", "clearAll", function()
    local total = 0
    for _, name in ipairs(Util.copy(Registry.order)) do
        local ws = Registry.workspaces[name]
        if ws then total = total + #Registry.clearWorkspace(ws, false) end
    end
    Overlay.forget(nil)
    return { success = true, removedCount = total }
end, { mutates = true, desc = "Destroys every workspace." })

-- update: { workspace, center, radius, description, meta }
Api.register("workspace", "update", function(p)
    local ws = Registry.requireWorkspace(p.workspace)
    if p.center ~= nil then
        local x, y, z = Resolve.point(p.center, "center")
        ws.center = M.vec(x, y, z)
    end
    if p.radius ~= nil then ws.radius = tonumber(p.radius) end
    if p.description ~= nil then ws.description = tostring(p.description) end
    if type(p.meta) == "table" then for k, v in pairs(p.meta) do ws.meta[k] = v end end
    if p.frozen ~= nil then ws.frozen = p.frozen == true end
    return { success = true, workspace = Registry.workspaceSummary(ws) }
end, { mutates = true, desc = "Changes workspace metadata." })
