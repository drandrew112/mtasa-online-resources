-- world: element queries, raycasts, ground, area scans, zones, environment.

Resolve = {}

-- "player" | "probe" | "camera" | entity id | {x,y,z} | [x,y,z]
-- -> x, y, z, info { kind, heading, element, dimension, interior }
function Resolve.point(spec, name)
    name = name or "center"
    if spec == nil or spec == "player" or spec == "probe" then
        local pl = Probe.primary()
        if not pl then
            fail("NO_PROBE_CLIENT", "'" .. name .. "' defaults to the probe player, but no player is connected.",
                { retryable = true, suggestion = "Pass explicit coordinates {x, y, z} or join the server." })
        end
        local x, y, z = getElementPosition(pl)
        local _, _, rz = getElementRotation(pl)
        return x, y, z, { kind = "player", heading = rz, element = pl, dimension = getElementDimension(pl), interior = getElementInterior(pl) }
    elseif spec == "camera" then
        local pl = Probe.primary()
        if not pl then fail("NO_PROBE_CLIENT", "'camera' needs a connected probe client.", { retryable = true }) end
        local cam = Probe.clients[pl].info.camera
        if not cam then fail("PROBE_NOT_READY", "Camera position not reported yet.", { retryable = true }) end
        return cam[1], cam[2], cam[3], { kind = "camera", heading = M.headingTo(cam[1], cam[2], cam[4], cam[5]), dimension = getElementDimension(pl), interior = getElementInterior(pl) }
    elseif type(spec) == "string" then
        local el = Refs.require(spec, name)
        local x, y, z = getElementPosition(el)
        local _, _, rz = getElementRotation(el)
        return x, y, z, { kind = "entity", id = Refs.of(el), heading = rz, element = el, dimension = getElementDimension(el), interior = getElementInterior(el) }
    elseif type(spec) == "table" and (spec.entity or spec.id) then
        return Resolve.point(spec.entity or spec.id, name)
    end
    local x, y, z = P.vec(spec, name)
    return x, y, z, { kind = "point" }
end

local function probeDim()
    local pl = Probe.primary()
    return pl and getElementDimension(pl) or 0, pl and getElementInterior(pl) or 0
end

-- elements around a point (server side, no probe needed)
function Resolve.elementsNear(x, y, z, radius, types, dimension, interior, limit, detail)
    local out, counts = {}, {}
    local list = {}
    for _, typ in ipairs(types) do
        for _, el in ipairs(getElementsWithinRange(x, y, z, radius, typ)) do
            if (dimension == nil or getElementDimension(el) == dimension) and (interior == nil or getElementInterior(el) == interior) then
                local ex, ey, ez = getElementPosition(el)
                list[#list + 1] = { el = el, d = M.dist3D(x, y, z, ex, ey, ez) }
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    for i, item in ipairs(list) do
        local typ = getElementType(item.el)
        counts[typ] = (counts[typ] or 0) + 1
        if i <= (limit or 60) then
            local d = Props.describe(item.el, detail or "low")
            local ex, ey, ez = getElementPosition(item.el)
            d.distance = M.round(item.d, 2)
            d.direction = M.compass(M.headingTo(x, y, ex, ey))
            out[#out + 1] = d
        end
    end
    return out, counts, #list
end

local ALL_TYPES = { "vehicle", "ped", "player", "object", "marker", "pickup", "colshape" }

Api.register("world", "elements", function(p)
    local x, y, z = Resolve.point(p.center)
    local radius = P.num(p, "radius", 50, 1, CMCP.MAX_RADIUS)
    local types = type(p.types) == "table" and p.types or { "vehicle", "ped", "player", "object" }
    local dim, int = p.dimension, p.interior
    if dim == nil and p.anyDimension ~= true then dim = select(1, probeDim()) end
    local list, counts, total = Resolve.elementsNear(x, y, z, radius, types, dim, int, P.int(p, "limit", 80, 1, 500), P.str(p, "detail", "low"))
    return { center = M.vec(x, y, z), radius = radius, total = total, counts = counts, elements = list }
end, { desc = "MTA elements (vehicles, peds, players, objects...) near a point, nearest first." })

---------------------------------------------------------------- probe-backed

-- raycast: { mode = segment|down|direction|camera, from, to, direction{x,y,z}|heading+pitch, length, batch = [ {from,to} ], options }
Api.register("world", "raycast", function(p)
    local mode = P.str(p, "mode", "segment", { "segment", "down", "direction", "camera", "batch" })
    local rays = {}
    local opts = type(p.options) == "table" and p.options or {}
    if mode == "batch" then
        if type(p.batch) ~= "table" or #p.batch == 0 then fail("INVALID_PARAMS", "batch must be a non-empty list of { from, to }.") end
        if #p.batch > 500 then fail("INVALID_PARAMS", "At most 500 rays per batch.") end
        for i, r in ipairs(p.batch) do
            local sx, sy, sz = P.vec(r.from, "batch[" .. i .. "].from", true)
            local ex, ey, ez = P.vec(r.to, "batch[" .. i .. "].to", true)
            rays[i] = { sx, sy, sz, ex, ey, ez }
        end
    elseif mode == "down" then
        local x, y, z = Resolve.point(p.from or p.position, "position")
        local top = (p.from and z) and (z + P.num(p, "above", 2)) or (z and z + 50 or 1000)
        rays[1] = { x, y, top, x, y, top - P.num(p, "length", 1100, 1, 3000) }
    elseif mode == "segment" then
        local sx, sy, sz = Resolve.point(p.from, "from")
        local ex, ey, ez = Resolve.point(p.to, "to")
        local lift = P.num(p, "lift", 0)
        rays[1] = { sx, sy, sz + lift, ex, ey, ez + lift }
    elseif mode == "direction" then
        local sx, sy, sz, info = Resolve.point(p.from, "from")
        local len = P.num(p, "length", 50, 0.1, 3000)
        local dx, dy, dz
        if type(p.direction) == "table" then
            dx, dy, dz = P.vec(p.direction, "direction")
            dz = dz or 0
        else
            local h = P.num(p, "heading", info.heading or 0)
            local pitch = math.rad(P.num(p, "pitch", 0))
            local fx, fy = M.forward(h)
            dx, dy, dz = fx * math.cos(pitch), fy * math.cos(pitch), math.sin(pitch)
        end
        local l = math.sqrt(dx * dx + dy * dy + dz * dz)
        if l == 0 then fail("INVALID_PARAMS", "direction must not be zero.") end
        local lift = P.num(p, "lift", info.kind == "player" and 0.6 or 0)
        sz = sz + lift
        rays[1] = { sx, sy, sz, sx + dx / l * len, sy + dy / l * len, sz + dz / l * len }
    end
    if mode == "camera" then
        return Probe.call("camera", { aim = true, distance = P.num(p, "length", 300, 1, 3000), options = opts }, nil, Probe.require({ primary = true }))
    end
    if p.focus ~= false and rays[1] then Probe.focus(rays[1][1], rays[1][2], rays[1][3]) end
    local r = Probe.call("rays", { rays = rays, options = opts })
    r.mode = mode
    return r
end, { async = true, desc = "Line-of-sight raycasts with hit position, normal, surface, element and world model info." })

-- ground: { points = [ {x,y,z?} ] | position, includeObjects, includeVehicles, slopeRadius }
Api.register("world", "ground", function(p)
    local pts = {}
    if type(p.points) == "table" and #p.points > 0 then
        if #p.points > 400 then fail("INVALID_PARAMS", "At most 400 points per call.") end
        for i, pt in ipairs(p.points) do
            local x, y, z = Resolve.point(pt, "points[" .. i .. "]")
            pts[i] = { x, y, z }
        end
    else
        local x, y, z = Resolve.point(p.position, "position")
        pts[1] = { x, y, z }
    end
    if p.focus ~= false then Probe.focus(pts[1][1], pts[1][2], pts[1][3]) end
    return Probe.call("ground", {
        points = pts, includeObjects = p.includeObjects ~= false, includeVehicles = p.includeVehicles == true,
        slopeRadius = P.num(p, "slopeRadius", 1.0, 0.2, 10), above = P.num(p, "above", 3), topmost = p.topmost == true,
    })
end, { async = true, desc = "Ground height, surface material, normal, slope, water level for points." })

-- scan: { center, radius, detail, spacing, modelBounds }
Api.register("world", "scan", function(p)
    local x, y, z = Resolve.point(p.center)
    local radius = P.num(p, "radius", 50, 5, CMCP.MAX_RADIUS)
    local detail = P.str(p, "detail", "medium", { "low", "medium", "high" })
    local focused, dist = Probe.focus(x, y, z, p.focus)
    local r = Probe.call("scanArea", {
        center = { x, y, z }, radius = radius, detail = detail,
        spacing = p.spacing and P.num(p, "spacing", 4, 0.5, 50) or nil,
        modelBounds = p.modelBounds, maxModels = p.maxModels,
        includeGrid = p.includeGrid == true,
    }, 45000)
    r.focusedCamera = focused
    r.distanceFromProbe = M.round(dist, 1)
    return r
end, { async = true, desc = "Raycast-grid scan of world geometry: world models, surfaces, heights, structures, area type." })

-- inspect: elements + zone + geometry scan (roads are merged in by the MCP server)
Api.register("world", "inspect", function(p)
    local x, y, z, info = Resolve.point(p.center)
    local radius = P.num(p, "radius", 50, 5, CMCP.MAX_RADIUS)
    local detail = P.str(p, "detail", "medium", { "low", "medium", "high" })
    local include = type(p.include) == "table" and p.include or {}
    local function want(k) return include[k] ~= false end
    local dim = p.dimension or info.dimension or select(1, probeDim())
    local out = {
        center = M.vec(x, y, z), radius = radius, detail = detail,
        zone = Util.zone(x, y, z), dimension = dim, interior = info.interior or select(2, probeDim()),
    }
    if want("elements") then
        local limits = { low = 20, medium = 60, high = 200 }
        out.elements = {}
        out.elements.list, out.elements.counts, out.elements.total = Resolve.elementsNear(x, y, z, radius,
            { "vehicle", "ped", "player", "object" }, dim, nil, limits[detail], detail == "high" and "medium" or "low")
        local ws = {}
        for _, e in ipairs(out.elements.list) do
            if e.workspace then ws[e.workspace] = (ws[e.workspace] or 0) + 1 end
        end
        out.workspaceEntities = ws
    end
    if want("geometry") then
        if Probe.get() then
            local focused = Probe.focus(x, y, z, p.focus)
            out.geometry = Probe.call("scanArea", { center = { x, y, z }, radius = radius, detail = detail, modelBounds = detail == "high" }, 45000)
            out.geometry.focusedCamera = focused
        else
            out.geometry = { available = false, reason = "NO_PROBE_CLIENT" }
        end
    end
    return out
end, { async = true, desc = "Area inspection: elements + world geometry scan + zone (roads merged by the MCP server)." })

-- context: "what is around me"
Api.register("world", "context", function(p)
    local pl = Probe.primary()
    local x, y, z, info = Resolve.point(p.center)
    local detail = P.str(p, "detail", "low", { "low", "medium", "high" })
    local radius = P.num(p, "radius", detail == "low" and 40 or 70, 5, 300)
    local out = {
        position = M.vec(x, y, z),
        heading = info.heading and M.round(info.heading, 1) or nil,
        compass = info.heading and M.compass(info.heading) or nil,
        dimension = info.dimension, interior = info.interior,
        zone = Util.zone(x, y, z),
    }
    if info.kind == "player" and pl then
        local veh = getPedOccupiedVehicle(pl)
        if veh then out.vehicle = { id = Refs.of(veh), model = getElementModel(veh), modelName = Util.vehicleName(getElementModel(veh)) } end
        out.player = getPlayerName(pl)
    end
    local list, counts, total = Resolve.elementsNear(x, y, z, radius, { "vehicle", "ped", "player", "object" }, info.dimension, nil, detail == "high" and 60 or 25, "low")
    out.nearby = { radius = radius, total = total, counts = counts, elements = list }
    if pl then
        Probe.focus(x, y, z, p.focus)
        local g = Probe.call("ground", { points = { { x, y, z } }, includeObjects = true, slopeRadius = 1.5, above = 2 })
        out.ground = g.points and g.points[1]
        out.geometry = Probe.call("scanArea", { center = { x, y, z }, radius = radius, detail = detail == "high" and "medium" or "low" }, 30000)
        out.camera = Probe.clients[pl].info.camera and {
            position = M.vec(Probe.clients[pl].info.camera[1], Probe.clients[pl].info.camera[2], Probe.clients[pl].info.camera[3]),
            lookHeading = M.round(M.headingTo(Probe.clients[pl].info.camera[1], Probe.clients[pl].info.camera[2], Probe.clients[pl].info.camera[4], Probe.clients[pl].info.camera[5]), 1),
        } or nil
    else
        out.geometry = { available = false, reason = "NO_PROBE_CLIENT" }
    end
    return out
end, { async = true, desc = "Location context: position, zone, ground, nearby elements, area summary." })

-- zones: coarse zone-name grid (server only)
Api.register("world", "zones", function(p)
    local minX, minY, maxX, maxY = -3000, -3000, 3000, 3000
    if type(p.bounds) == "table" then
        minX, minY = tonumber(p.bounds.minX) or minX, tonumber(p.bounds.minY) or minY
        maxX, maxY = tonumber(p.bounds.maxX) or maxX, tonumber(p.bounds.maxY) or maxY
    end
    local cell = P.num(p, "cellSize", 250, 25, 1500)
    if ((maxX - minX) / cell) * ((maxY - minY) / cell) > 5000 then fail("INVALID_PARAMS", "Too many cells; increase cellSize or shrink bounds.") end
    local cells, cities, zones = {}, {}, {}
    for cy = minY, maxY - cell, cell do
        for cx = minX, maxX - cell, cell do
            local mx, my = cx + cell / 2, cy + cell / 2
            local zone, city = getZoneName(mx, my, 0, false), getZoneName(mx, my, 0, true)
            cells[#cells + 1] = { x = mx, y = my, zone = zone, city = city }
            cities[city] = (cities[city] or 0) + 1
            zones[zone] = zones[zone] or { city = city, cells = 0, sumX = 0, sumY = 0 }
            zones[zone].cells = zones[zone].cells + 1
            zones[zone].sumX, zones[zone].sumY = zones[zone].sumX + mx, zones[zone].sumY + my
        end
    end
    local zoneList = {}
    for name, z in pairs(zones) do
        zoneList[#zoneList + 1] = { zone = name, city = z.city, cells = z.cells, approxCenter = { x = M.round(z.sumX / z.cells, 0), y = M.round(z.sumY / z.cells, 0) } }
    end
    table.sort(zoneList, function(a, b) return a.cells > b.cells end)
    return { bounds = { minX = minX, minY = minY, maxX = maxX, maxY = maxY }, cellSize = cell, cityCells = cities, zones = zoneList, cells = p.includeCells and cells or nil }
end, { desc = "Zone / city names over a grid (world map backbone)." })

-- zone name at a point
Api.register("world", "zoneAt", function(p)
    local x, y, z = Resolve.point(p.position)
    return { position = M.vec(x, y, z), zone = Util.zone(x, y, z) }
end)

-- lineOfSight: { from, to, lift, options }
Api.register("world", "lineOfSight", function(p)
    local sx, sy, sz = Resolve.point(p.from, "from")
    local ex, ey, ez = Resolve.point(p.to, "to")
    local lift = P.num(p, "lift", 1.0)
    local ignore = {}
    for _, k in ipairs({ "from", "to" }) do
        if type(p[k]) == "string" then ignore[#ignore + 1] = Refs.resolve(p[k]) end
    end
    Probe.focus((sx + ex) / 2, (sy + ey) / 2, (sz + ez) / 2, p.focus)
    return Probe.call("los", { from = { sx, sy, sz + lift }, to = { ex, ey, ez + lift }, ignore = ignore, options = p.options })
end, { async = true, desc = "Whether two points / entities see each other, with the blocking hit." })

-- safeSpot: { near, for = ped|vehicle|object, model, radius, heading, clearance, walkable, avoidRoad }
Api.register("world", "safeSpot", function(p)
    local x, y, z, info = Resolve.point(p.near, "near")
    local kind = P.str(p, "for", "ped", { "ped", "vehicle", "object" })
    local model = p.model and P.int(p, "model") or (kind == "ped" and 0 or kind == "vehicle" and 416 or 1337)
    Probe.focus(x, y, z, p.focus)
    local ignore = {}
    if type(p.ignore) == "table" then for _, id in ipairs(p.ignore) do ignore[#ignore + 1] = Refs.resolve(id) end end
    if info.element then ignore[#ignore + 1] = info.element end
    return Probe.call("findSpot", {
        near = { x, y, z }, kind = kind, model = model, radius = P.num(p, "radius", 15, 1, 100),
        heading = p.heading and P.num(p, "heading") or nil, clearance = P.num(p, "clearance", kind == "ped" and 0.6 or 0.8, 0, 10),
        surfaces = p.surfaces, avoidRoad = p.avoidRoad == true, preferRoad = p.preferRoad == true, ignore = ignore,
        maxSlope = P.num(p, "maxSlope", kind == "vehicle" and 20 or 35, 1, 89), count = P.int(p, "count", 1, 1, 10),
    }, 30000)
end, { async = true, desc = "Nearest free, level, dry spot where a ped/vehicle/object of a model fits." })

---------------------------------------------------------------- environment

Api.register("world", "environment", function(p)
    local h, m = getTime()
    local out = {
        time = { hour = h, minute = m }, weather = getWeather(), gravity = getGravity(), gameSpeed = getGameSpeed(),
        minuteDuration = getMinuteDuration(), waveHeight = getWaveHeight(),
    }
    if p.set then
        local s = p.set
        if s.hour then setTime(math.floor(tonumber(s.hour) or 12), math.floor(tonumber(s.minute) or 0)) end
        if s.weather then setWeather(math.floor(tonumber(s.weather) or 0)) end
        if s.minuteDuration then setMinuteDuration(math.floor(tonumber(s.minuteDuration))) end
        out.changed = true
        out.note = "Server-wide change; other resources (e.g. realtime) may override it. capture_view's forceDaylight only affects the probe client."
        h, m = getTime()
        out.time, out.weather = { hour = h, minute = m }, getWeather()
    end
    return out
end, { desc = "Time, weather, gravity; optional set (mutates, server-wide)." })
