-- placement: semantic placement and orientation. The bridge computes the actual
-- MTA transform (ground height from the live collision, model base offset,
-- terrain pitch/roll for vehicles, road cross-section for lanes).
--
-- Placement spec (spawn_entity.placement / place_entity):
--   { mode = "ground",  position, heading, align = "terrain"|"upright", zOffset }
--   { mode = "road",    base = {x,y,z}, heading (travel direction), lane, lanePosition = lane|curb|center|sidewalk|shoulder|offset,
--                       lateralOffset, alongOffset, facing = forward|backward, road = { node, segment, ... } }   (MCP server resolves nodes)
--   { mode = "near",    target, side = front|back|left|right|front-left|..., gap, facing = same|opposite|towards|away|perpendicular|<heading> }
--   { mode = "relative",target (entity id | point), heading?, offset = { right, forward, up }, relativeHeading }
--   { mode = "raw",     position, rotation }

Placement = {}

local SIDES = {
    front = { 0, 1 }, back = { 0, -1 }, behind = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 },
    ["front-left"] = { -1, 1 }, ["front-right"] = { 1, 1 }, ["back-left"] = { -1, -1 }, ["back-right"] = { 1, -1 },
}

function Placement.apply(el, x, y, z, rx, ry, rz)
    setElementPosition(el, x, y, z)
    if getElementType(el) == "ped" then
        setElementRotation(el, 0, 0, rz, "default", true)
    else
        setElementRotation(el, rx or 0, ry or 0, rz or 0)
    end
    if getElementType(el) ~= "object" then setElementVelocity(el, 0, 0, 0) end
end

-- heading from a facing spec relative to a reference heading / point
function Placement.facingHeading(facing, refHeading, fromX, fromY, targetX, targetY)
    if facing == nil or facing == "same" or facing == "forward" then return refHeading end
    if facing == "opposite" or facing == "backward" then return M.norm(refHeading + 180) end
    if facing == "perpendicular" or facing == "left" then return M.norm(refHeading + 90) end
    if facing == "right" then return M.norm(refHeading - 90) end
    if facing == "towards" and targetX then return M.headingTo(fromX, fromY, targetX, targetY) end
    if facing == "away" and targetX then return M.headingTo(targetX, targetY, fromX, fromY) end
    if tonumber(facing) then return M.norm(tonumber(facing)) end
    fail("INVALID_PARAMS", "Unknown facing '" .. tostring(facing) .. "' (same, opposite, perpendicular, left, right, towards, away or a heading).")
end

local function ground(typ, model, x, y, z, heading, align, ignore, zOffset, ws, includeObjects)
    local pl = Probe.get()
    if not pl then
        -- no probe: keep the given z (or fail when unknown)
        if not z then
            fail("NO_PROBE_CLIENT", "Ground placement needs a probe client (no z given).",
                { retryable = true, suggestion = "Join the server, or pass an explicit z and use raw placement." })
        end
        return {
            position = { x = x, y = y, z = z + (zOffset or 0) }, rotation = { x = 0, y = 0, z = heading },
            ground = nil, warnings = { { type = "no_probe", message = "No probe client: z was not snapped to the ground." } },
        }
    end
    -- world collision is the same in every dimension; only element hits differ (ignored here)
    Probe.focus(x, y, z or select(3, getElementPosition(pl)))
    return Probe.call("placeModel", {
        type = typ, model = model, x = x, y = y, z = z, heading = heading, align = align or "terrain",
        ignore = ignore, zOffset = zOffset or 0, includeObjects = includeObjects ~= false,
    }, 15000)
end

-- -> { position, rotation, summary, details, warnings }
function Placement.compute(spec, typ, model, element, ws)
    local mode = spec.mode or "ground"
    local warnings = {}
    local x, y, z, heading
    local details = { mode = mode }
    local summary = { mode = mode }

    if mode == "raw" then
        x, y, z = P.vec(spec.position, "placement.position", true)
        local r = spec.rotation or {}
        return {
            position = { x = x, y = y, z = z },
            rotation = { x = tonumber(r.x or r[1]) or 0, y = tonumber(r.y or r[2]) or 0, z = M.norm(tonumber(spec.heading) or tonumber(r.z or r[3]) or 0) },
            summary = summary, details = details, warnings = warnings,
        }
    elseif mode == "ground" then
        x, y, z = Resolve.point(spec.position, "placement.position")
        heading = M.norm(tonumber(spec.heading) or 0)
        if spec.facing and spec.target then
            local tx, ty = Resolve.point(spec.target, "placement.target")
            heading = Placement.facingHeading(spec.facing, heading, x, y, tx, ty)
        end
    elseif mode == "road" then
        local bx, by, bz = P.vec(spec.base, "placement.base")
        local travel = M.norm(P.num(spec, "heading"))
        local facing = spec.facing or "forward"
        heading = facing == "backward" and M.norm(travel + 180) or travel
        -- along the travel direction first
        local along = tonumber(spec.alongOffset) or 0
        bx, by = M.offset(bx, by, 0, travel, 0, along, 0)
        local lanePos = spec.lanePosition or (spec.lateralOffset and "offset") or "lane"
        local lateral = tonumber(spec.lateralOffset) or 0
        local section
        if Probe.get() and lanePos ~= "offset" then
            Probe.focus(bx, by, bz)
            section = Probe.call("crossSection", { x = bx, y = by, z = bz, heading = travel, halfWidth = tonumber(spec.scanWidth) or 18, step = 0.5 })
            details.crossSection = section
        end
        local halfWidth = 1.0
        local m = Probe.get() and Models.measure(typ, model) or Models.cached(typ, model)
        if m and m.size then halfWidth = m.size.x / 2 end
        if lanePos == "offset" then
            -- lateral is relative to the node
        elseif section and section.road then
            local road = section.road
            local lanes = road.lanesPerDirection or 1
            local lane = math.max(1, math.min(lanes, math.floor(tonumber(spec.lane) or 1)))
            if spec.lane and tonumber(spec.lane) > lanes then
                warnings[#warnings + 1] = { type = "lane_clamped", message = "Requested lane " .. tostring(spec.lane) .. " but only " .. lanes .. " lane(s) per direction were detected (estimate); lane " .. lane .. " used." }
            end
            if lanePos == "lane" then
                lateral = road.rightEdge - (lane - 0.5) * road.laneWidth
            elseif lanePos == "curb" or lanePos == "shoulder" then
                lateral = road.rightEdge - halfWidth - 0.35
            elseif lanePos == "center" then
                lateral = road.center
            elseif lanePos == "sidewalk" then
                local sw = section.sidewalkRight
                lateral = sw and (sw.from + sw.to) / 2 or (road.rightEdge + 1.6)
                if not sw then warnings[#warnings + 1] = { type = "no_sidewalk", message = "No sidewalk detected right of the road; placed 1.6 m beyond the road edge." } end
            end
            lateral = lateral + (tonumber(spec.lateralOffset) or 0)
            details.lane = lane
            details.lanesPerDirectionEstimate = lanes
        else
            -- no cross-section: assume one lane per direction, 4.5 m wide, node on the centre line
            local lane = math.max(1, math.floor(tonumber(spec.lane) or 1))
            if lanePos == "lane" then lateral = (lane - 0.5) * 4.5
            elseif lanePos == "curb" or lanePos == "shoulder" then lateral = 4.5 * lane - halfWidth - 0.35
            elseif lanePos == "sidewalk" then lateral = 6.5 end
            lateral = lateral + (tonumber(spec.lateralOffset) or 0)
            warnings[#warnings + 1] = { type = "road_geometry_unknown", message = "Road width could not be measured (no probe or no road surface found); a default 4.5 m lane from the node was assumed." }
        end
        x, y = M.offset(bx, by, 0, travel, lateral, 0, 0)
        z = bz
        details.lateralOffset = M.round(lateral, 2)
        details.travelHeading = M.round(travel, 1)
        details.lanePosition = lanePos
        summary.road = spec.road
        summary.lane = details.lane
        summary.lanePosition = lanePos
        summary.facing = facing
        summary.travelHeading = M.round(travel, 1)
    elseif mode == "near" then
        local tx, ty, tz, ti = Resolve.point(spec.target, "placement.target")
        local th = ti.heading or 0
        local side = SIDES[spec.side or "front"]
        if not side then fail("INVALID_PARAMS", "Unknown side '" .. tostring(spec.side) .. "'.") end
        local gap = tonumber(spec.gap or spec.distance) or 1.0
        -- extents of target and self
        local tExt = { x = 0.5, y = 0.5 }
        if ti.element then
            local tm = Models.measure(getElementType(ti.element) == "player" and "ped" or getElementType(ti.element), getElementModel(ti.element))
            if tm and tm.size then tExt = { x = tm.size.x / 2, y = tm.size.y / 2 } end
        end
        local sm = Probe.get() and Models.measure(typ, model) or nil
        local facing = spec.facing or "same"
        -- for towards / away the final heading depends on the position: estimate it from the side
        local extFacing = facing
        if facing == "towards" or facing == "away" then
            extFacing = (side[1] ~= 0 and side[2] == 0) and "perpendicular" or (side[1] == 0 and "opposite" or "same")
        end
        local selfHeading = Placement.facingHeading(extFacing, th)
        local sExt = { x = 0.5, y = 0.5 }
        if sm and sm.size then
            -- self extent along the target's local axes (exact for parallel / perpendicular)
            local rel = math.rad(M.angleDiff(th, selfHeading))
            local c, s = math.abs(math.cos(rel)), math.abs(math.sin(rel))
            sExt = { x = sm.size.x / 2 * c + sm.size.y / 2 * s, y = sm.size.x / 2 * s + sm.size.y / 2 * c }
        end
        local ox = side[1] ~= 0 and side[1] * (tExt.x + gap + sExt.x) or 0
        local oy = side[2] ~= 0 and side[2] * (tExt.y + gap + sExt.y) or 0
        ox = ox + (tonumber(spec.lateral) or 0)
        oy = oy + (tonumber(spec.along) or 0)
        x, y, z = M.offset(tx, ty, tz, th, ox, oy, 0)
        heading = Placement.facingHeading(facing, th, x, y, tx, ty)
        details.target = ti.id
        details.side = spec.side or "front"
        details.gap = gap
        details.localOffset = { right = M.round(ox, 2), forward = M.round(oy, 2) }
        summary.relativeTo = ti.id
        summary.side = details.side
    elseif mode == "relative" then
        local tx, ty, tz, ti = Resolve.point(spec.target, "placement.target")
        local th = tonumber(spec.heading) or ti.heading or 0
        local o = spec.offset or {}
        x, y, z = M.offset(tx, ty, tz, th, tonumber(o.right or o.x) or 0, tonumber(o.forward or o.y) or 0, tonumber(o.up or o.z) or 0)
        heading = M.norm(th + (tonumber(spec.relativeHeading) or 0))
        if spec.facing then heading = Placement.facingHeading(spec.facing, th, x, y, tx, ty) end
        details.target = ti.id
        summary.relativeTo = ti.id
        summary.offset = o
    else
        fail("INVALID_PARAMS", "Unknown placement mode '" .. tostring(mode) .. "' (ground, road, near, relative, raw).")
    end

    if spec.headingOffset then heading = M.norm(heading + tonumber(spec.headingOffset)) end
    local snap = spec.snapToGround ~= false
    if not snap then
        return {
            position = { x = x, y = y, z = (z or 0) + (tonumber(spec.zOffset) or 0) }, rotation = { x = 0, y = 0, z = heading },
            summary = summary, details = details, warnings = warnings,
        }
    end
    local g = ground(typ, model, x, y, z, heading, spec.align, element, tonumber(spec.zOffset), ws, spec.includeObjects)
    for _, w in ipairs(g.warnings or {}) do warnings[#warnings + 1] = w end
    details.ground = g.ground
    summary.heading = M.round(heading, 2)
    return { position = g.position, rotation = g.rotation, summary = summary, details = details, warnings = warnings }
end

---------------------------------------------------------------- API

-- place: { id, placement = {...} }  moves an existing entity
Api.register("placement", "place", function(p)
    local el, entity = Refs.require(P.str(p, "id"))
    local typ = getElementType(el)
    if typ == "player" then typ = "ped" end
    if type(p.placement) ~= "table" then fail("INVALID_PARAMS", "placement must be an object with a mode.") end
    local r = Placement.compute(p.placement, typ, getElementModel(el), el, entity and Registry.workspaces[entity.workspace])
    Placement.apply(el, r.position.x, r.position.y, r.position.z, r.rotation.x, r.rotation.y, r.rotation.z)
    if entity then entity.placement = r.summary end
    local out = { success = true, entity = Props.describe(el, "medium"), placement = r.details, warnings = r.warnings }
    if p.verify ~= false and Probe.get() then
        local info = Entities.probeInfo({ el })
        out.entity.live = info and info[1] or nil
    end
    return out
end, { mutates = true, async = true, desc = "Semantic placement of an existing entity." })

-- compute: same as place but only returns the transform (no element needed)
Api.register("placement", "compute", function(p)
    local typ = P.str(p, "type", nil, { "vehicle", "ped", "object" })
    local model = P.int(p, "model")
    if type(p.placement) ~= "table" then fail("INVALID_PARAMS", "placement must be an object with a mode.") end
    local r = Placement.compute(p.placement, typ, model, nil, nil)
    return { position = r.position, rotation = r.rotation, heading = r.rotation.z, compass = M.compass(r.rotation.z), details = r.details, warnings = r.warnings }
end, { async = true, desc = "Dry-run: the transform a placement would produce." })

-- orient: { id, mode = heading|face_towards|face_away|parallel_to|perpendicular_to|relative|align_heading, target, heading, offset, keepGround }
Api.register("placement", "orient", function(p)
    local el, entity = Refs.require(P.str(p, "id"))
    local x, y, z = getElementPosition(el)
    local rx, ry, rz = getElementRotation(el)
    local mode = P.str(p, "mode", nil, { "heading", "face_towards", "face_away", "parallel_to", "perpendicular_to", "opposite_to", "relative", "align_heading" })
    local h = rz
    if mode == "heading" or mode == "align_heading" then
        h = P.num(p, "heading")
        if p.reverse then h = h + 180 end
    elseif mode == "relative" then
        h = rz + P.num(p, "offset")
    else
        local tx, ty, tz, ti = Resolve.point(p.target, "target")
        if mode == "face_towards" then h = M.headingTo(x, y, tx, ty)
        elseif mode == "face_away" then h = M.headingTo(tx, ty, x, y)
        else
            if not ti.heading then fail("INVALID_PARAMS", mode .. " needs an entity target (with a heading).") end
            if mode == "parallel_to" then h = ti.heading
            elseif mode == "opposite_to" then h = ti.heading + 180
            else h = ti.heading + (p.side == "right" and -90 or 90) end
        end
    end
    h = M.norm(h + (tonumber(p.offset) and mode ~= "relative" and tonumber(p.offset) or 0))
    local typ = getElementType(el)
    local placement
    if typ == "vehicle" and p.keepGround ~= false and Probe.get() then
        placement = Placement.compute({ mode = "ground", position = { x = x, y = y, z = z }, heading = h }, typ, getElementModel(el), el)
        Placement.apply(el, placement.position.x, placement.position.y, placement.position.z, placement.rotation.x, placement.rotation.y, placement.rotation.z)
    else
        Placement.apply(el, x, y, z, typ == "ped" and 0 or rx, typ == "ped" and 0 or ry, h)
    end
    local out = { success = true, previousHeading = M.round(rz, 2), heading = M.round(h, 2), compass = M.compass(h), entity = Props.describe(el, "medium") }
    if p.verify ~= false and Probe.get() then
        local info = Entities.probeInfo({ el })
        out.entity.live = info and info[1] or nil
    end
    return out
end, { mutates = true, async = true, desc = "Semantic rotation (face towards, parallel, perpendicular, heading...)." })

-- crossSection: live road / surface profile perpendicular to a heading
Api.register("roads", "crossSection", function(p)
    local x, y, z = Resolve.point(p.position, "position")
    local h = P.num(p, "heading", 0)
    Probe.focus(x, y, z, p.focus)
    return Probe.call("crossSection", { x = x, y = y, z = z, heading = h, halfWidth = P.num(p, "halfWidth", 18, 2, 60), step = P.num(p, "step", 0.5, 0.1, 5), samples = p.includeSamples == true })
end, { async = true, desc = "Road width, edges, sidewalks, surface + road models across a heading." })

-- surfaces along many points (MCP server uses it to correlate road nodes with geometry)
Api.register("roads", "probeNodes", function(p)
    if type(p.nodes) ~= "table" then fail("INVALID_PARAMS", "nodes must be a list of { id, x, y, z, heading }.") end
    if #p.nodes > 60 then fail("INVALID_PARAMS", "At most 60 nodes per call.") end
    local first = p.nodes[1]
    if first then Probe.focus(tonumber(first.x) or 0, tonumber(first.y) or 0, tonumber(first.z) or 0, p.focus) end
    return Probe.call("nodeGeometry", { nodes = p.nodes, halfWidth = P.num(p, "halfWidth", 16, 2, 60) }, 30000)
end, { async = true, desc = "Cross-section + road models at many road nodes." })
