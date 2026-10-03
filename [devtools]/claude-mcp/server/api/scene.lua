-- scene: export the verified state of a workspace (values read back from the
-- live MTA elements, never recomputed) and import it again.
--
-- Formats: generic (JSON, re-importable), map (MTA .map XML), lua (createX code).
-- The med_scenemanager format is produced by the medical module.

Scene = {}

function Scene.capture(e)
    local el = e.element
    local x, y, z = getElementPosition(el)
    local rx, ry, rz = getElementRotation(el)
    local out = {
        id = e.id, type = e.type, model = getElementModel(el),
        position = M.vec(x, y, z), rotation = M.vec(rx, ry, rz, 2),
        interior = getElementInterior(el), dimension = getElementDimension(el),
        frozen = isElementFrozen(el), alpha = getElementAlpha(el),
        meta = next(e.meta) and Util.copy(e.meta) or nil,
        placement = e.placement,
    }
    local props = {}
    if e.type == "vehicle" then
        out.modelName = Util.vehicleName(out.model)
        props.colors = { getVehicleColor(el, true) }
        props.health = M.round(getElementHealth(el), 1)
        props.plate = getVehiclePlateText(el)
        props.engine = getVehicleEngineState(el)
        props.lightsOn = getVehicleOverrideLights(el) == 2
        props.sirens = getVehicleSirensOn(el)
        props.locked = isVehicleLocked(el)
        props.damageProof = isVehicleDamageProof(el)
        props.doors, props.panels, props.lights = {}, {}, {}
        for i = 0, 5 do props.doors[i + 1] = getVehicleDoorState(el, i) end
        for i = 0, 6 do props.panels[i + 1] = getVehiclePanelState(el, i) end
        for i = 0, 3 do props.lights[i + 1] = getVehicleLightState(el, i) end
        props.wheels = { getVehicleWheelStates(el) }
        props.paintjob = getVehiclePaintjob(el)
        props.upgrades = getVehicleUpgrades(el) or {}
        out.variant = { getVehicleVariant(el) }
    elseif e.type == "ped" then
        out.sex = pedSex(out.model)
        props.health = M.round(getElementHealth(el), 1)
        if e.meta.pose then props.pose = e.meta.pose end
        local veh = getPedOccupiedVehicle(el)
        if veh then props.seat = { vehicle = Refs.of(veh), seat = getPedOccupiedVehicleSeat(el) } end
    else
        props.scale = getObjectScale(el)
        props.doubleSided = isElementDoubleSided(el)
    end
    out.properties = props
    return out
end

local function xmlEscape(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function toMap(ws, list)
    local lines = { '<map edf:definitions="editor_main">' }
    for _, e in ipairs(list) do
        local p, r = e.position, e.rotation
        local common = string.format('id="%s" dimension="%d" interior="%d" posX="%.4f" posY="%.4f" posZ="%.4f" rotX="%.4f" rotY="%.4f" rotZ="%.4f"',
            xmlEscape(e.id), e.dimension, e.interior, p.x, p.y, p.z, r.x, r.y, r.z)
        if e.type == "vehicle" then
            local c = e.properties.colors
            lines[#lines + 1] = string.format('    <vehicle %s model="%d" plate="%s" frozen="%s" color="%s" />', common, e.model,
                xmlEscape(e.properties.plate or ""), tostring(e.frozen), table.concat(c, ","))
        elseif e.type == "ped" then
            lines[#lines + 1] = string.format('    <ped %s model="%d" rotZ="%.4f" frozen="%s" />', common:gsub(' rotZ="[^"]*"', ""), e.model, r.z, tostring(e.frozen))
        else
            lines[#lines + 1] = string.format('    <object %s model="%d" scale="%.3f" frozen="%s" doublesided="%s" collisions="true" alpha="%d" />',
                common, e.model, e.properties.scale or 1, tostring(e.frozen), tostring(e.properties.doubleSided), e.alpha)
        end
    end
    lines[#lines + 1] = "</map>"
    return table.concat(lines, "\n")
end

local function toLua(ws, list)
    local lines = { "-- exported by claude-mcp from workspace '" .. ws.name .. "'", "local elements = {}" }
    for _, e in ipairs(list) do
        local p, r = e.position, e.rotation
        if e.type == "vehicle" then
            lines[#lines + 1] = string.format('elements["%s"] = createVehicle(%d, %.4f, %.4f, %.4f, %.2f, %.2f, %.2f, "%s")', e.id, e.model, p.x, p.y, p.z, r.x, r.y, r.z, e.properties.plate or "")
            lines[#lines + 1] = string.format('setVehicleColor(elements["%s"], %s)', e.id, table.concat(e.properties.colors, ", "))
        elseif e.type == "ped" then
            lines[#lines + 1] = string.format('elements["%s"] = createPed(%d, %.4f, %.4f, %.4f, %.2f)', e.id, e.model, p.x, p.y, p.z, r.z)
            local pose = e.properties.pose and CMCP.POSES[e.properties.pose]
            if pose and pose.block then
                lines[#lines + 1] = string.format('setPedAnimation(elements["%s"], "%s", "%s", -1, %s, false, false, true)', e.id, pose.block, pose.anim, tostring(pose.loop == true))
            end
        else
            lines[#lines + 1] = string.format('elements["%s"] = createObject(%d, %.4f, %.4f, %.4f, %.2f, %.2f, %.2f)', e.id, e.model, p.x, p.y, p.z, r.x, r.y, r.z)
        end
        if e.dimension ~= 0 then lines[#lines + 1] = string.format('setElementDimension(elements["%s"], %d)', e.id, e.dimension) end
        if e.interior ~= 0 then lines[#lines + 1] = string.format('setElementInterior(elements["%s"], %d)', e.id, e.interior) end
        if e.frozen then lines[#lines + 1] = string.format('setElementFrozen(elements["%s"], true)', e.id) end
    end
    return table.concat(lines, "\n")
end

function Scene.export(ws, format)
    local list, missing = {}, {}
    for _, id in ipairs(ws.entities) do
        local e = Registry.entities[id]
        if e and isElement(e.element) then list[#list + 1] = Scene.capture(e) else missing[#missing + 1] = id end
    end
    local data = {
        format = "mta-world-mcp/workspace", version = 1,
        exportedAt = getRealTime().timestamp, bridgeInstance = Api.instance(),
        workspace = { name = ws.name, kind = ws.kind, dimension = ws.dimension, interior = ws.interior, center = ws.center, radius = ws.radius, description = ws.description, meta = ws.meta },
        entities = list,
    }
    local out = { workspace = ws.name, format = format, entityCount = #list, missing = missing,
        note = "Values were read back from the live MTA elements at export time." }
    if format == "generic" then out.data = data
    elseif format == "map" then out.text = toMap(ws, list) out.data = data
    elseif format == "lua" then out.text = toLua(ws, list) out.data = data
    else fail("INVALID_PARAMS", "Unknown format '" .. tostring(format) .. "' (generic, map, lua; med_scenemanager via the medical module).") end
    return out
end

-- export: { workspace, format, save = "<file name>" }
Api.register("scene", "export", function(p)
    local ws = Registry.requireWorkspace(p.workspace)
    local out = Scene.export(ws, P.str(p, "format", "generic", { "generic", "map", "lua" }))
    if p.save then
        local name = tostring(p.save)
        if not name:match("^[%w_%-]+$") then fail("INVALID_PARAMS", "save must be a plain file name (letters, digits, _ -).") end
        local ext = out.format == "map" and ".map" or out.format == "lua" and ".lua" or ".json"
        local path = "exports/" .. name .. ext
        if fileExists(path) then fileDelete(path) end
        local f = fileCreate(path)
        if not f then fail("FILE_ERROR", "Could not create " .. path) end
        fileWrite(f, out.text or toJSON(out.data, false, "spaces"):sub(2, -2))
        fileClose(f)
        out.savedTo = "[devtools]/claude-mcp/" .. path
    end
    return out
end, { desc = "Exports a workspace with values read back from MTA (generic JSON, .map XML, Lua)." })

-- import: { data (generic export), workspace, offset = {x,y,z}, rotate (deg around the scene centre), keepIds }
Api.register("scene", "import", function(p)
    local data = p.data
    if type(data) ~= "table" or type(data.entities) ~= "table" then
        fail("INVALID_PARAMS", "data must be a generic export ({ format, entities = [...] }).")
    end
    local name = p.workspace or (data.workspace and data.workspace.name) or "imported"
    local ws = Registry.workspaces[name] or Registry.createWorkspace({
        name = name, kind = data.workspace and data.workspace.kind, dimension = p.dimension or (data.workspace and data.workspace.dimension),
        interior = data.workspace and data.workspace.interior, description = data.workspace and data.workspace.description,
    })
    local ox, oy, oz = 0, 0, 0
    if type(p.offset) == "table" then ox, oy, oz = tonumber(p.offset.x) or 0, tonumber(p.offset.y) or 0, tonumber(p.offset.z) or 0 end
    local created, failed = {}, {}
    local idMap = {}
    -- vehicles first (peds may sit in them)
    local order = {}
    for _, e in ipairs(data.entities) do if e.type == "vehicle" then order[#order + 1] = e end end
    for _, e in ipairs(data.entities) do if e.type ~= "vehicle" then order[#order + 1] = e end end
    for _, e in ipairs(order) do
        local pos, rot = e.position or {}, e.rotation or {}
        local spec = {
            type = e.type, model = e.model, id = p.keepIds ~= false and e.id or nil,
            x = (tonumber(pos.x) or 0) + ox, y = (tonumber(pos.y) or 0) + oy, z = (tonumber(pos.z) or 0) + oz,
            rx = tonumber(rot.x) or 0, ry = tonumber(rot.y) or 0, rz = tonumber(rot.z) or 0,
            frozen = e.frozen, meta = e.meta, variant = e.variant, placement = e.placement,
        }
        local ok, entity = Util.try(Registry.spawn, ws, spec)
        if ok then
            idMap[e.id] = entity.id
            local props = Util.copy(e.properties or {})
            if props.seat and props.seat.vehicle then props.seat.vehicle = idMap[props.seat.vehicle] or props.seat.vehicle end
            Util.try(Props.apply, entity.element, props, entity)
            created[#created + 1] = entity.id
        else
            failed[#failed + 1] = { id = e.id, error = Util.toError(entity) }
        end
    end
    return { success = #failed == 0, workspace = ws.name, created = created, failed = failed }
end, { mutates = true, desc = "Spawns a generic export into a workspace." })
