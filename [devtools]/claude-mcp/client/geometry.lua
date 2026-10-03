-- Probe geometry ops: area scan, road cross-sections, model placement, free-spot search.

local ray, groundHit, hitOut = CMCPC.ray, CMCPC.groundHit, CMCPC.hitOut

-- oriented box of an element from its live matrix -> M.obb shaped table | nil
function CMCPC.obbOf(el, margin)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(el)
    if not x1 then return nil end
    margin = margin or 0
    local m = getElementMatrix(el)
    if not m then return nil end
    local cx, cy, cz = (x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2
    return {
        c = {
            m[4][1] + cx * m[1][1] + cy * m[2][1] + cz * m[3][1],
            m[4][2] + cx * m[1][2] + cy * m[2][2] + cz * m[3][2],
            m[4][3] + cx * m[1][3] + cy * m[2][3] + cz * m[3][3],
        },
        axes = { { m[1][1], m[1][2], m[1][3] }, { m[2][1], m[2][2], m[2][3] }, { m[3][1], m[3][2], m[3][3] } },
        half = { (x2 - x1) / 2 + margin, (y2 - y1) / 2 + margin, (z2 - z1) / 2 + margin },
    }
end

-- OBB of a model at a hypothetical transform (yaw only)
function CMCPC.obbAt(measure, x, y, z, heading, margin)
    local b = measure.bbox
    margin = margin or 0
    return M.obb(x, y, z, 0, 0, heading, b.min.x - margin, b.min.y - margin, b.min.z, b.max.x + margin, b.max.y + margin, b.max.z)
end

---------------------------------------------------------------- area scan

local function classifyArea(pct)
    local road, side = pct.road or 0, (pct.sidewalk or 0) + (pct.concrete or 0)
    local covered = pct.covered or 0
    local natural = (pct.grass or 0) + (pct.dirt or 0) + (pct.rock or 0)
    if (pct.water or 0) > 40 then return "water / coast" end
    if (pct.sand or 0) > 40 then return "desert / beach" end
    if road + side > 35 and covered > 12 then return "urban" end
    if road > 25 and side < 6 and covered < 8 then return "road / highway" end
    if natural > 60 and covered < 6 then return "rural / natural" end
    if covered > 30 then return "dense built-up" end
    return "suburban / mixed"
end

-- scanArea: { center = {x,y,z}, radius, detail, spacing, modelBounds, maxModels, includeGrid }
CMCPC.ops.scanArea = function(a, reply)
    local cx, cy, cz = a.center[1], a.center[2], a.center[3]
    local radius = a.radius or 50
    local detail = a.detail or "medium"
    local spacing = a.spacing or math.max(({ low = 4, medium = 2.5, high = 1.5 })[detail] or 2.5, radius / ({ low = 12, medium = 22, high = 40 })[detail])
    local pts = {}
    for gx = -radius, radius, spacing do
        for gy = -radius, radius, spacing do
            if gx * gx + gy * gy <= radius * radius then pts[#pts + 1] = { cx + gx, cy + gy } end
        end
    end
    while #pts > 9000 do
        spacing = spacing * 1.3
        pts = {}
        for gx = -radius, radius, spacing do
            for gy = -radius, radius, spacing do
                if gx * gx + gy * gy <= radius * radius then pts[#pts + 1] = { cx + gx, cy + gy } end
            end
        end
    end

    local ignoreSet = { [localPlayer] = true }
    local pv = getPedOccupiedVehicle(localPlayer)
    if pv then ignoreSet[pv] = true end
    local models, classes, materials, elementsHit = {}, {}, {}, {}
    local zs, slopes, noHit, covered, samples = {}, {}, 0, 0, 0
    local grid = a.includeGrid and {} or nil
    local i = 1

    local function addModel(h, isTop)
        if not h or not h.worldModel then return end
        local key = h.worldModel .. ":" .. math.floor(h.wpos[1] + 0.5) .. ":" .. math.floor(h.wpos[2] + 0.5)
        local m = models[key]
        if not m then
            m = { id = h.worldModel, wpos = h.wpos, wrot = h.wrot, lod = h.lod, hits = 0, top = 0,
                minX = h.x, maxX = h.x, minY = h.y, maxY = h.y, minZ = h.z, maxZ = h.z, mats = {} }
            models[key] = m
        end
        m.hits = m.hits + 1
        if isTop then m.top = m.top + 1 end
        m.minX, m.maxX = math.min(m.minX, h.x), math.max(m.maxX, h.x)
        m.minY, m.maxY = math.min(m.minY, h.y), math.max(m.maxY, h.y)
        m.minZ, m.maxZ = math.min(m.minZ, h.z), math.max(m.maxZ, h.z)
        local cls = surfaceClass(h.material)
        m.mats[cls] = (m.mats[cls] or 0) + 1
    end

    local function step()
        local budget = 500
        while i <= #pts and budget > 0 do
            local x, y = pts[i][1], pts[i][2]
            local top = CMCPC.rayIgnoring(x, y, cz + 120, x, y, cz - 120, { vehicles = false, players = false, objects = true, dummies = false }, ignoreSet)
            local ground = top
            if top and top.z > cz + 4 then
                ground = CMCPC.rayIgnoring(x, y, cz + 4, x, y, cz - 60, { vehicles = false, players = false, objects = true, dummies = false }, ignoreSet) or top
            end
            samples = samples + 1
            if not top then
                noHit = noHit + 1
                if grid then grid[#grid + 1] = { M.round(x, 1), M.round(y, 1), false } end
            else
                addModel(top, true)
                if ground ~= top then addModel(ground, false) end
                local cls = surfaceClass(ground.material)
                if cls == "default" and ground.worldModel then
                    -- many road / building models use the DEFAULT surface: classify by model name
                    local kind = modelKind(CMCPC.modelName(ground.worldModel))
                    if kind == "road" or kind == "bridge" then cls = "road" elseif kind == "building" then cls = "structure" end
                end
                local w = getWaterLevel(x, y, ground.z + 1)
                if w and w > ground.z + 0.3 then cls = "water" end
                classes[cls] = (classes[cls] or 0) + 1
                local mname = surfaceName(ground.material)
                materials[mname] = (materials[mname] or 0) + 1
                zs[#zs + 1] = ground.z
                slopes[#slopes + 1] = math.deg(math.acos(math.max(-1, math.min(1, ground.nz or 1))))
                if top.z - ground.z > 2.5 then covered = covered + 1 end
                for _, h in ipairs({ top, ground }) do
                    if h.element and isElement(h.element) then
                        elementsHit[h.element] = (elementsHit[h.element] or 0) + 1
                    end
                end
                if grid then grid[#grid + 1] = { M.round(x, 1), M.round(y, 1), M.round(ground.z, 2), cls, M.round(top.z, 2) } end
            end
            i = i + 1
            budget = budget - (detail == "low" and 1 or 2)
        end
        return i > #pts
    end

    local function finish()
        local total = math.max(1, samples - noHit)
        local pct = {}
        for k, v in pairs(classes) do pct[k] = M.round(v / total * 100, 1) end
        pct.covered = M.round(covered / total * 100, 1)
        local minZ, maxZ, sumZ, sumS = math.huge, -math.huge, 0, 0
        for k, z in ipairs(zs) do minZ, maxZ, sumZ, sumS = math.min(minZ, z), math.max(maxZ, z), sumZ + z, sumS + slopes[k] end
        local list = {}
        for _, m in pairs(models) do
            local name = CMCPC.modelName(m.id)
            local bestCls, bestN = nil, 0
            for c, n in pairs(m.mats) do if n > bestN then bestCls, bestN = c, n end end
            local kind = modelKind(name)
            local evidence = "name"
            if bestCls == "road" and bestN >= m.hits * 0.5 then
                if kind == "unknown" or kind == "terrain" then kind = "road" end
                evidence = "surface"
            elseif bestCls == "sidewalk" and kind == "unknown" then
                kind = "sidewalk"
                evidence = "surface"
            end
            list[#list + 1] = {
                id = m.id, name = name, kind = kind, kindSource = evidence == "surface" and "surface_material" or "name_heuristic",
                position = M.vec(m.wpos[1], m.wpos[2], m.wpos[3]), rotation = M.vec(m.wrot[1], m.wrot[2], m.wrot[3], 2),
                lodId = m.lod ~= 0 and m.lod or nil,
                hits = m.hits, topHits = m.top, dominantSurface = bestCls,
                hitExtent = { min = M.vec(m.minX, m.minY, m.minZ, 1), max = M.vec(m.maxX, m.maxY, m.maxZ, 1),
                    note = "extent of ray hits on this model inside the scan, not its full bounds" },
                distance = M.round(M.dist2D(cx, cy, m.wpos[1], m.wpos[2]), 1),
                direction = M.compass(M.headingTo(cx, cy, m.wpos[1], m.wpos[2])),
            }
        end
        table.sort(list, function(p, q) return p.hits > q.hits end)
        local maxModels = a.maxModels or ({ low = 15, medium = 40, high = 150 })[detail]
        local totalModels = #list
        while #list > maxModels do table.remove(list) end

        local kinds = {}
        for _, m in ipairs(list) do kinds[m.kind] = (kinds[m.kind] or 0) + 1 end
        local elems = {}
        for el, n in pairs(elementsHit) do
            if isElement(el) then elems[#elems + 1] = { element = el, type = getElementType(el), model = getElementModel(el), hits = n } end
        end

        local out = {
            center = M.vec(cx, cy, cz), radius = radius, detail = detail, spacing = M.round(spacing, 2),
            samples = samples, noCollisionSamples = noHit,
            collisionLoaded = noHit < samples * 0.5,
            surfaces = pct, materials = materials,
            terrain = #zs > 0 and { minZ = M.round(minZ, 2), maxZ = M.round(maxZ, 2), meanZ = M.round(sumZ / #zs, 2), meanSlope = M.round(sumS / #zs, 1), heightRange = M.round(maxZ - minZ, 2) } or nil,
            areaType = classifyArea(pct), areaTypeSource = "heuristic from surface / coverage ratios",
            worldModels = list, worldModelCount = totalModels, modelKinds = kinds,
            elementsHit = elems, grid = grid,
        }
        if noHit > samples * 0.5 then
            out.hint = "Most rays hit nothing: collision is probably not loaded here (too far from the probe camera). Use teleport_probe."
        end

        -- horizontal ring: open / blocked directions around the centre
        if detail ~= "low" then
            local dirs = {}
            local n = detail == "high" and 36 or 16
            local hz = (out.terrain and math.min(cz, out.terrain.maxZ) or cz) + 1.2
            for k = 0, n - 1 do
                local h = k * 360 / n
                local fx, fy = M.forward(h)
                local hit = CMCPC.rayIgnoring(cx, cy, hz, cx + fx * radius, cy + fy * radius, hz, { vehicles = true, players = false, objects = true, dummies = false }, ignoreSet)
                local d = { heading = M.round(h, 1), compass = M.compass(h), open = hit == nil }
                if hit then
                    d.distance = M.round(hit.distance, 1)
                    if hit.worldModel then
                        local name = CMCPC.modelName(hit.worldModel)
                        d.blockedBy = { worldModel = hit.worldModel, name = name, kind = modelKind(name) }
                    elseif hit.element and isElement(hit.element) then
                        d.blockedBy = { element = hit.element, type = getElementType(hit.element), model = getElementModel(hit.element) }
                    end
                end
                dirs[#dirs + 1] = d
            end
            out.directions = dirs
            out.directionsHeight = M.round(hz, 2)
        end

        -- optional real model bounds (measured from a local copy of the model)
        if a.modelBounds then
            local queue = {}
            for k = 1, math.min(#list, a.maxBoundsModels or 12) do queue[#queue + 1] = list[k] end
            local function nextModel(k)
                local m = queue[k]
                if not m then return reply(true, out) end
                CMCPC.ops.measureModel({ type = "object", model = m.id }, function(ok, r)
                    if ok then
                        m.modelBounds = r.bbox
                        m.modelSize = r.size
                        local b = r.bbox
                        local corners = M.boxCorners(m.position.x, m.position.y, m.position.z, m.rotation.x, m.rotation.y, m.rotation.z,
                            b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z)
                        local mnx, mny, mnz, mxx, mxy, mxz = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
                        for _, c in ipairs(corners) do
                            mnx, mny, mnz = math.min(mnx, c[1]), math.min(mny, c[2]), math.min(mnz, c[3])
                            mxx, mxy, mxz = math.max(mxx, c[1]), math.max(mxy, c[2]), math.max(mxz, c[3])
                        end
                        m.worldBounds = { min = M.vec(mnx, mny, mnz, 2), max = M.vec(mxx, mxy, mxz, 2) }
                    end
                    nextModel(k + 1)
                end)
            end
            return nextModel(1)
        end
        reply(true, out)
    end

    local function tick()
        local ok, done = pcall(step)
        if not ok then return reply(false, { code = "PROBE_ERROR", message = tostring(done) }) end
        if done then
            local ok2, err = pcall(finish)
            if not ok2 then reply(false, { code = "PROBE_ERROR", message = tostring(err) }) end
        else
            setTimer(tick, 50, 1)
        end
    end
    tick()
end

---------------------------------------------------------------- road cross-section

local ROADLIKE = { road = true }

function CMCPC.crossSection(x, y, z, heading, halfWidth, step, keepSamples)
    halfWidth, step = halfWidth or 18, step or 0.5
    local samples = {}
    local o = { vehicles = false, players = false, objects = false, dummies = false }
    for off = -halfWidth, halfWidth + 0.001, step do
        local px, py = M.offset(x, y, 0, heading, off, 0, 0)
        local h = ray(px, py, z + 4, px, py, z - 12, o)
        local s = { o = M.round(off, 2) }
        if h then
            s.z = h.z
            s.cls = surfaceClass(h.material)
            s.mat = h.material
            s.model = h.worldModel
            if s.cls == "default" then s.cls = CMCPC.surfaceOf(h) end
        else
            s.cls = "none"
        end
        samples[#samples + 1] = s
    end
    -- runs of equal class
    local runs = {}
    for _, s in ipairs(samples) do
        local cls = ROADLIKE[s.cls] and "road" or s.cls
        local r = runs[#runs]
        if r and r.cls == cls then
            r.to = s.o
            r.n = r.n + 1
        else
            runs[#runs + 1] = { cls = cls, from = s.o, to = s.o, n = 1 }
        end
    end
    -- the road run containing / nearest to the node
    local best, bestD
    for k, r in ipairs(runs) do
        if r.cls == "road" then
            local d = (r.from <= 0 and r.to >= 0) and 0 or math.min(math.abs(r.from), math.abs(r.to))
            if d <= 6 and (not bestD or d < bestD) then best, bestD = k, d end
        end
    end
    -- merge road runs separated by a thin non-road strip (painted lines / median <= 1 m)
    local out = { heading = M.round(heading, 1), halfWidth = halfWidth, step = step, origin = M.vec(x, y, z) }
    if best then
        local r = runs[best]
        local from, to = r.from, r.to
        local k = best - 1
        while k >= 2 and runs[k].to - runs[k].from <= 1.0 and runs[k - 1].cls == "road" do from = runs[k - 1].from k = k - 2 end
        k = best + 1
        while k <= #runs - 1 and runs[k].to - runs[k].from <= 1.0 and runs[k + 1].cls == "road" do to = runs[k + 1].to k = k + 2 end
        local leftEdge, rightEdge = from - step / 2, to + step / 2
        local width = rightEdge - leftEdge
        local center = (leftEdge + rightEdge) / 2
        local twoWay = math.abs(center) < math.max(1.5, width * 0.15)
        local per, laneWidth
        if twoWay then
            per = math.max(1, math.floor((width / 2) / 4.0 + 0.25))
            laneWidth = (width / 2) / per
        else
            per = math.max(1, math.floor(width / 4.0 + 0.25))
            laneWidth = width / per
        end
        local czs, models = {}, {}
        for _, s in ipairs(samples) do
            if s.o >= leftEdge and s.o <= rightEdge and s.z then
                czs[#czs + 1] = s.z
                if s.model then models[s.model] = (models[s.model] or 0) + 1 end
            end
        end
        local modelList = {}
        for id, n in pairs(models) do modelList[#modelList + 1] = { id = id, name = CMCPC.modelName(id), samples = n } end
        table.sort(modelList, function(p, q) return p.samples > q.samples end)
        local sumZ = 0
        for _, v in ipairs(czs) do sumZ = sumZ + v end
        out.road = {
            leftEdge = M.round(leftEdge, 2), rightEdge = M.round(rightEdge, 2), width = M.round(width, 2), center = M.round(center, 2),
            surfaceZ = #czs > 0 and M.round(sumZ / #czs, 3) or nil,
            layout = twoWay and "two-way (node near the centre)" or "one-way / separate carriageway (node off-centre)",
            twoWay = twoWay, lanesPerDirection = per, laneWidth = M.round(laneWidth, 2),
            lanesSource = "estimated from the measured road width (no lane data in vehiclenodes)",
            models = modelList,
        }
        -- sidewalks next to the edges
        local function sidewalk(dir)
            local idx = dir > 0 and #runs or 1
            for k2 = (dir > 0 and best + 1 or best - 1), idx, dir do
                local r2 = runs[k2]
                local edge = dir > 0 and rightEdge or leftEdge
                local near = dir > 0 and r2.from or r2.to
                if math.abs(near - edge) > 2.5 then break end
                if r2.cls == "sidewalk" or r2.cls == "concrete" then
                    local zs2 = {}
                    for _, s in ipairs(samples) do if s.o >= r2.from and s.o <= r2.to and s.z then zs2[#zs2 + 1] = s.z end end
                    local avg = 0
                    for _, v in ipairs(zs2) do avg = avg + v end
                    avg = #zs2 > 0 and avg / #zs2 or nil
                    return { from = M.round(math.min(r2.from, r2.to), 2), to = M.round(math.max(r2.from, r2.to), 2), width = M.round(math.abs(r2.to - r2.from) + step, 2),
                        curbHeight = (avg and out.road.surfaceZ) and M.round(avg - out.road.surfaceZ, 2) or nil, surface = r2.cls }
                end
                if r2.cls == "road" then break end
            end
            return nil
        end
        out.sidewalkRight = sidewalk(1)
        out.sidewalkLeft = sidewalk(-1)
    else
        out.road = nil
        out.note = "No road surface found within 6 m of the reference point across this heading."
    end
    local compact = {}
    for _, r in ipairs(runs) do compact[#compact + 1] = { surface = r.cls, from = r.from, to = r.to } end
    out.profile = compact
    out.offsets = "negative = left of the heading, positive = right (metres)"
    if keepSamples then
        local s2 = {}
        for _, s in ipairs(samples) do s2[#s2 + 1] = { o = s.o, z = s.z and M.round(s.z, 2), surface = s.cls, model = s.model } end
        out.samples = s2
    end
    return out
end

CMCPC.ops.crossSection = function(a)
    return CMCPC.crossSection(a.x, a.y, a.z, a.heading or 0, a.halfWidth, a.step, a.samples)
end

-- nodeGeometry: { nodes = { {id,x,y,z,heading} }, halfWidth }
CMCPC.ops.nodeGeometry = function(a)
    local out = {}
    for _, n in ipairs(a.nodes or {}) do
        local s = CMCPC.crossSection(n.x, n.y, n.z, n.heading or 0, a.halfWidth or 16, 0.5, false)
        out[#out + 1] = {
            id = n.id, road = s.road, sidewalkLeft = s.sidewalkLeft, sidewalkRight = s.sidewalkRight,
            nodeOffsetFromRoadCenter = s.road and -s.road.center or nil, note = s.note,
        }
    end
    return { nodes = out }
end

---------------------------------------------------------------- placement

local function ignoreSetFrom(list)
    local set = CMCPC.toIgnoreSet(type(list) == "table" and list or (isElement(list) and { list } or {}))
    set[localPlayer] = true
    local v = getPedOccupiedVehicle(localPlayer)
    if v then set[v] = true end
    return set
end

-- placeModel: { type, model, x, y, z?, heading, align, ignore, zOffset, includeObjects }
CMCPC.ops.placeModel = function(a, reply)
    return CMCPC.withMeasure(a.type, a.model, reply, function(m)
        local ignoreSet = ignoreSetFrom(a.ignore)
        local gopt = { above = 3, includeObjects = a.includeObjects ~= false }
        local g = groundHit(a.x, a.y, a.z, gopt, ignoreSet)
        if not g and a.z then g = groundHit(a.x, a.y, nil, gopt, ignoreSet) end
        if not g then
            return reply(false, { code = "NO_GROUND", message = "No ground found under the position (collision not loaded or void).", retryable = true,
                suggestion = "teleport_probe near the location, or use raw placement with an explicit z." })
        end
        local warnings = {}
        local h = a.heading or 0
        local rx, ry = 0, 0
        local z
        if a.type == "vehicle" then
            local halfL, halfW = m.size.y / 2 * 0.75, m.size.x / 2 * 0.75
            local function gz(ox, oy)
                local px, py = M.offset(a.x, a.y, 0, h, ox, oy, 0)
                local hh = groundHit(px, py, g.z, { above = 2, includeObjects = gopt.includeObjects, depth = 8 }, ignoreSet)
                return hh and hh.z or g.z
            end
            local zf, zb, zl, zr = gz(0, halfL), gz(0, -halfL), gz(-halfW, 0), gz(halfW, 0)
            -- a sample more than 0.3 m off the centre is a step / curb / object edge, not a slope
            local uneven = false
            local function sane(v) if math.abs(v - g.z) > 0.3 then uneven = true return g.z end return v end
            zf, zb, zl, zr = sane(zf), sane(zb), sane(zl), sane(zr)
            if uneven then
                warnings[#warnings + 1] = { type = "uneven_ground", message = "Step, curb or object edge under the vehicle footprint; kept level there. Check with validate_workspace." }
            end
            if a.align ~= "upright" then
                rx = math.deg(math.atan2(zf - zb, 2 * halfL))
                ry = math.deg(math.atan2(zl - zr, 2 * halfW))
                rx, ry = math.max(-35, math.min(35, rx)), math.max(-35, math.min(35, ry))
            end
            local base = math.max(g.z, (zf + zb + zl + zr) / 4)
            z = base + (m.baseOffset or 1) + 0.03
            if math.abs(rx) > 15 or math.abs(ry) > 15 then
                warnings[#warnings + 1] = { type = "steep", message = string.format("Terrain is steep here (pitch %.1f°, roll %.1f°).", rx, ry) }
            end
        elseif a.type == "ped" then
            local base = (m.baseOffset and m.baseOffset > 0.3) and m.baseOffset or 1.0
            z = g.z + base
        else
            z = g.z - m.bbox.min.z
            if a.align == "terrain" and a.alignObjects then
                local nx, ny, nz = g.nx, g.ny, g.nz
                rx = math.deg(math.atan2(ny * math.cos(math.rad(h)) - nx * math.sin(math.rad(h)), nz))
            end
        end
        z = z + (a.zOffset or 0)
        local o = hitOut(g)
        if o.slope > 30 and a.type ~= "object" then
            warnings[#warnings + 1] = { type = "slope", message = "Surface slope is " .. o.slope .. "°." }
        end
        local w = getWaterLevel(a.x, a.y, g.z + 1)
        if w and w > g.z + 0.3 then
            warnings[#warnings + 1] = { type = "water", message = string.format("Position is under %.1f m of water.", w - g.z) }
        end
        if a.z and a.z - g.z > 5 then
            warnings[#warnings + 1] = { type = "drop", message = string.format("Ground is %.1f m below the given z.", a.z - g.z) }
        end
        if o.element then
            warnings[#warnings + 1] = { type = "on_element", message = "Placed on top of a " .. tostring(o.elementType) .. " (model " .. tostring(o.elementModel) .. ")." }
        end
        return {
            position = M.vec(a.x, a.y, z), rotation = M.vec(rx, ry, M.norm(h), 2),
            ground = { z = M.round(g.z, 3), material = o.material, materialName = o.materialName, surfaceClass = o.surfaceClass, slope = o.slope,
                worldModel = o.worldModel, onElement = o.element and { element = o.element, type = o.elementType } or nil },
            measured = { size = m.size, baseOffset = m.baseOffset },
            warnings = warnings,
        }
    end)
end

---------------------------------------------------------------- free spot

local function footprintBlocked(m, x, y, gz, heading, clearance, ignoreSet)
    -- world / object geometry inside the footprint: rays along edges + diagonals at two heights
    local b = m.bbox
    local hx, hy = (b.max.x - b.min.x) / 2 + clearance, (b.max.y - b.min.y) / 2 + clearance
    local height = math.max(0.6, m.size.z)
    local corners = {}
    for _, c in ipairs({ { -hx, -hy }, { hx, -hy }, { hx, hy }, { -hx, hy } }) do
        local px, py = M.offset(x, y, 0, heading, c[1], c[2], 0)
        corners[#corners + 1] = { px, py }
    end
    local o = { vehicles = true, players = true, objects = true, dummies = false }
    for _, lift in ipairs({ 0.45, math.min(height, 1.6) }) do
        local z = gz + lift
        for k = 1, 4 do
            local p1, p2 = corners[k], corners[k % 4 + 1]
            local h = CMCPC.rayIgnoring(p1[1], p1[2], z, p2[1], p2[2], z, o, ignoreSet)
            if h then return true, h end
        end
        for _, d in ipairs({ { 1, 3 }, { 2, 4 } }) do
            local p1, p2 = corners[d[1]], corners[d[2]]
            local h = CMCPC.rayIgnoring(p1[1], p1[2], z, p2[1], p2[2], z, o, ignoreSet)
            if h then return true, h end
        end
    end
    return false
end

-- findSpot: { near, kind, model, radius, heading, clearance, surfaces, avoidRoad, preferRoad, ignore, maxSlope, count }
CMCPC.ops.findSpot = function(a, reply)
    return CMCPC.withMeasure(a.kind, a.model, reply, function(m)
        local nx, ny, nz = a.near[1], a.near[2], a.near[3]
        local ignoreSet = ignoreSetFrom(a.ignore)
        local allowed
        if type(a.surfaces) == "table" then allowed = {} for _, s in ipairs(a.surfaces) do allowed[s] = true end end
        local found, tested = {}, 0
        local rejected = {}
        local function reject(why) rejected[why] = (rejected[why] or 0) + 1 end
        local headingList = a.heading and { a.heading } or { 0, 90, 45, 135 }
        local r = 0
        while r <= a.radius and #found < (a.count or 1) do
            local n = r == 0 and 1 or math.max(6, math.floor(2 * math.pi * r / 1.0))
            for k = 0, n - 1 do
                local ang = k * 2 * math.pi / n
                local x, y = nx + math.cos(ang) * r, ny + math.sin(ang) * r
                tested = tested + 1
                local g = groundHit(x, y, nz, { above = 3, includeObjects = true }, ignoreSet)
                if not g then reject("no_ground")
                else
                    local cls = CMCPC.surfaceOf(g)
                    local slope = math.deg(math.acos(math.max(-1, math.min(1, g.nz))))
                    local w = getWaterLevel(x, y, g.z + 1)
                    if w and w > g.z + 0.2 then reject("water")
                    elseif slope > a.maxSlope then reject("slope")
                    elseif allowed and not allowed[cls] then reject("surface")
                    elseif a.avoidRoad and cls == "road" then reject("road")
                    elseif a.kind == "ped" and not WALKABLE[cls] then reject("not_walkable")
                    elseif g.element then reject("on_element")
                    elseif math.abs(g.z - nz) > 6 then reject("height_jump")
                    else
                        local okHeading
                        for _, h in ipairs(headingList) do
                            if not footprintBlocked(m, x, y, g.z, h, a.clearance or 0.5, ignoreSet) then okHeading = h break end
                        end
                        if okHeading == nil then reject("blocked")
                        else
                            local spot = {
                                position = M.vec(x, y, g.z + (a.kind == "ped" and math.max(m.baseOffset or 1, 0.9) or a.kind == "vehicle" and (m.baseOffset or 1) or -m.bbox.min.z)),
                                ground = { z = M.round(g.z, 3), surfaceClass = cls, materialName = surfaceName(g.material), slope = M.round(slope, 1) },
                                heading = okHeading, distance = M.round(r, 2),
                            }
                            if a.preferRoad and cls ~= "road" then spot.note = "not on road" end
                            found[#found + 1] = spot
                            if #found >= (a.count or 1) then break end
                        end
                    end
                end
            end
            r = r + (r < 4 and 0.75 or 1.25)
        end
        return {
            found = #found > 0, spots = found, tested = tested, rejected = rejected,
            footprint = { size = m.size, clearance = a.clearance },
            suggestion = #found == 0 and "Increase radius, reduce clearance or relax surfaces / maxSlope." or nil,
        }
    end)
end
