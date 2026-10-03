-- validation: structured diagnostics for entities / workspaces.
--
-- Server-side checks: element validity, status, dimension / interior, world
-- bounds, health, scene radius. Probe checks (client/validate.lua): ground
-- contact, world-geometry intersection, element overlaps, water, free space
-- around peds, wheel contact. The MCP server adds road-alignment checks.

Validation = {}

local CHECKS = { "validity", "dimension", "bounds", "ground", "world_collision", "overlap", "water", "clearance", "scene_bounds", "health" }

local function push(list, entity, typ, message, extra)
    local d = { entity = entity, type = typ, message = message }
    if extra then for k, v in pairs(extra) do d[k] = v end end
    list[#list + 1] = d
end

-- items: list of entity records; ws: workspace or nil; opts: { checks = {..}, tolerance = {..} }
function Validation.run(items, ws, opts)
    opts = opts or {}
    local enabled = {}
    for _, c in ipairs(type(opts.checks) == "table" and opts.checks or CHECKS) do enabled[c] = true end
    local errors, warnings, info = {}, {}, {}
    local perEntity = {}
    local live = {}
    local probe = Probe.get()

    for _, e in ipairs(items) do
        local rec = { id = e.id, type = e.type, model = e.model }
        perEntity[e.id] = rec
        if not isElement(e.element) then
            push(errors, e.id, "entity_missing", "Entity's MTA element no longer exists (" .. tostring(e.lostReason or "destroyed") .. ").",
                { suggestion = "delete_entity then spawn it again" })
            rec.valid = false
        else
            local el = e.element
            local x, y, z = getElementPosition(el)
            local rx, ry, rz = getElementRotation(el)
            rec.position, rec.rotation = M.vec(x, y, z), M.vec(rx, ry, rz, 2)
            rec.heading = M.round(rz, 2)
            rec.placement = e.placement
            rec.meta = e.meta
            rec.valid = true
            if enabled.validity then
                if e.status == "exploded" or (e.type == "vehicle" and isVehicleBlown(el)) then
                    push(errors, e.id, "vehicle_blown", "Vehicle is blown up.", { suggestion = "Delete and respawn; workspace vehicles are damage-proof unless changed." })
                end
                if e.type == "ped" and isPedDead(el) then
                    push(warnings, e.id, "ped_dead", "Ped is dead (health 0); dead peds cannot animate.", { suggestion = "Respawn the ped, or keep it if a corpse is intended." })
                end
                if getElementModel(el) ~= e.model then
                    push(info, e.id, "model_changed", "Model is " .. getElementModel(el) .. " (registered " .. e.model .. ").")
                end
            end
            if enabled.health and e.type == "vehicle" then
                local hp = getElementHealth(el)
                if hp < 250 and not isVehicleDamageProof(el) then
                    push(warnings, e.id, "vehicle_burning", "Vehicle health " .. math.floor(hp) .. " < 250: it will catch fire and explode.", { suggestion = "Set health >= 300 or damageProof = true." })
                end
            end
            if enabled.dimension and ws then
                if getElementDimension(el) ~= ws.dimension then
                    push(errors, e.id, "dimension_mismatch", "Entity is in dimension " .. getElementDimension(el) .. ", workspace uses " .. ws.dimension .. ".")
                end
                if getElementInterior(el) ~= ws.interior then
                    push(errors, e.id, "interior_mismatch", "Entity is in interior " .. getElementInterior(el) .. ", workspace uses " .. ws.interior .. ".")
                end
            end
            if enabled.bounds then
                if math.abs(x) > 3000 or math.abs(y) > 3000 then
                    push(errors, e.id, "out_of_world", "Position is outside the San Andreas map (|x|,|y| > 3000).")
                elseif z < -50 then
                    push(errors, e.id, "below_world", "z = " .. M.round(z, 2) .. " is far below the map.")
                elseif z > 1000 then
                    push(warnings, e.id, "very_high", "z = " .. M.round(z, 2) .. " is unusually high.")
                end
            end
            if enabled.scene_bounds and ws and ws.center and ws.radius then
                local d = M.dist2D(ws.center.x, ws.center.y, x, y)
                rec.distanceFromCenter = M.round(d, 2)
                if d > ws.radius then
                    push(warnings, e.id, "outside_scene", string.format("Entity is %.1f m from the workspace centre (radius %.1f).", d, ws.radius))
                end
            end
            live[#live + 1] = { element = el, id = e.id, type = e.type, model = e.model, seated = e.type == "ped" and getPedOccupiedVehicle(el) ~= false and getPedOccupiedVehicle(el) ~= nil,
                pose = e.meta and (e.meta.pose or (e.meta.medical and e.meta.medical.anim)) or nil, role = e.meta and e.meta.role or nil }
        end
    end

    local probeRan = false
    if probe and #live > 0 then
        local pd = getElementDimension(probe)
        if ws and pd ~= ws.dimension then
            push(warnings, nil, "probe_dimension", "The probe player is in dimension " .. pd .. " but the workspace is in " .. ws.dimension ..
                ": element collision / overlap checks against the workspace may be incomplete.", { suggestion = "teleport_probe with dimension = " .. ws.dimension })
        end
        local els = {}
        for _, it in ipairs(live) do els[#els + 1] = it.element end
        Entities.focusOn(els)
        local r = Probe.call("validate", { items = live, checks = enabled, tolerance = opts.tolerance or {} }, 30000)
        probeRan = true
        for _, d in ipairs(r.errors or {}) do errors[#errors + 1] = d end
        for _, d in ipairs(r.warnings or {}) do warnings[#warnings + 1] = d end
        for _, d in ipairs(r.info or {}) do info[#info + 1] = d end
        for id, m in pairs(r.metrics or {}) do
            local rec = perEntity[id]
            if rec then rec.live = m end
        end
    elseif not probe then
        push(warnings, nil, "probe_missing", "No probe client: ground, collision, overlap, water and clearance checks were skipped.",
            { suggestion = "Join the server with a game client and re-run validation." })
    end

    local list = {}
    for _, e in ipairs(items) do list[#list + 1] = perEntity[e.id] end
    for _, d in ipairs(errors) do if d.entity and perEntity[d.entity] then perEntity[d.entity].valid = false end end
    return {
        valid = #errors == 0,
        errorCount = #errors, warningCount = #warnings,
        errors = errors, warnings = warnings, info = info,
        entities = list,
        checks = (function() local c = {} for k in pairs(enabled) do c[#c + 1] = k end table.sort(c) return c end)(),
        probeChecks = probeRan,
    }
end

-- run: { workspace | ids, checks, tolerance }
Api.register("validation", "run", function(p)
    local items, ws = {}, nil
    if type(p.ids) == "table" and #p.ids > 0 then
        for _, id in ipairs(p.ids) do
            local e = Registry.entities[tostring(id)]
            if not e then fail("ENTITY_NOT_FOUND", "No entity '" .. tostring(id) .. "'.", { entity = tostring(id) }) end
            items[#items + 1] = e
            ws = ws or Registry.workspaces[e.workspace]
        end
    else
        ws = Registry.requireWorkspace(p.workspace)
        for _, id in ipairs(ws.entities) do
            if Registry.entities[id] then items[#items + 1] = Registry.entities[id] end
        end
    end
    if #items == 0 then
        return { valid = true, errorCount = 0, warningCount = 1, errors = {}, info = {}, entities = {},
            warnings = { { type = "empty", message = "Nothing to validate (no entities)." } } }
    end
    local r = Validation.run(items, ws, { checks = p.checks, tolerance = p.tolerance })
    r.workspace = ws and ws.name
    return r
end, { async = true, desc = "Validates entities / a workspace; structured errors and warnings." })

Api.register("validation", "checks", function()
    return { checks = CHECKS, note = "road_alignment is added by the MCP server (road graph); medical checks by medical validate." }
end)
