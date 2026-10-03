-- Probe client: answers geometry queries from the bridge server.
-- Ops: CMCPC.ops[name] = function(args, reply) -> result table (sync) or nil (async, calls reply(ok, result))

CMCPC = { ops = {}, nameCache = {} }

local function reply(rid, ok, result)
    -- big payloads go latent so they do not block the connection
    triggerLatentServerEvent("cmcp:probeReply", 4000000, false, resourceRoot, rid, ok, result)
end

addEvent("cmcp:probe", true)
addEventHandler("cmcp:probe", resourceRoot, function(rid, op, args)
    local fn = CMCPC.ops[op]
    if not fn then
        return reply(rid, false, { code = "UNKNOWN_PROBE_OP", message = "Probe op '" .. tostring(op) .. "' is not implemented by this client." })
    end
    local done = false
    local function cb(ok, result)
        if done then return end
        done = true
        reply(rid, ok == true, result)
    end
    local ok, result = pcall(fn, type(args) == "table" and args or {}, cb)
    if not ok then
        cb(false, type(result) == "table" and result or { code = "PROBE_ERROR", message = tostring(result) })
    elseif result ~= nil then
        cb(true, result)
    end
end)

---------------------------------------------------------------- helpers

function CMCPC.modelName(id)
    if not id then return nil end
    local n = CMCPC.nameCache[id]
    if n == nil then
        n = engineGetModelNameFromID(id) or false
        CMCPC.nameCache[id] = n
    end
    return n or nil
end

-- one raycast -> hit table | nil
-- opt: buildings, vehicles, players(peds), objects, dummies, seeThrough, shootThrough, ignore (element)
function CMCPC.ray(sx, sy, sz, ex, ey, ez, opt)
    opt = opt or {}
    local hit, hx, hy, hz, el, nx, ny, nz, mat, _, piece, wid, wx, wy, wz, wrx, wry, wrz, wlod = processLineOfSight(
        sx, sy, sz, ex, ey, ez,
        opt.buildings ~= false, opt.vehicles ~= false, opt.players ~= false, opt.objects ~= false, opt.dummies ~= false,
        opt.seeThrough == true, false, opt.shootThrough == true, opt.ignore, true, false)
    if not hit then return nil end
    local r = {
        x = hx, y = hy, z = hz, nx = nx, ny = ny, nz = nz, material = mat, piece = piece, element = el,
        distance = M.dist3D(sx, sy, sz, hx, hy, hz),
    }
    if wid and wid ~= 0 and not el then
        r.worldModel = wid
        r.wpos = { wx, wy, wz }
        r.wrot = { wrx, wry, wrz }
        r.lod = wlod
    end
    return r
end

-- ray with several ignored elements (processLineOfSight takes one): re-cast past ignored hits
function CMCPC.rayIgnoring(sx, sy, sz, ex, ey, ez, opt, ignoreSet)
    if not ignoreSet or not next(ignoreSet) then return CMCPC.ray(sx, sy, sz, ex, ey, ez, opt) end
    local dx, dy, dz = ex - sx, ey - sy, ez - sz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len == 0 then return nil end
    dx, dy, dz = dx / len, dy / len, dz / len
    local cx, cy, cz = sx, sy, sz
    for _ = 1, 8 do
        local h = CMCPC.ray(cx, cy, cz, ex, ey, ez, opt)
        if not h then return nil end
        if not (h.element and ignoreSet[h.element]) then
            h.distance = M.dist3D(sx, sy, sz, h.x, h.y, h.z)
            return h
        end
        cx, cy, cz = h.x + dx * 0.05, h.y + dy * 0.05, h.z + dz * 0.05
        if M.dist3D(sx, sy, sz, cx, cy, cz) >= len then return nil end
    end
    return nil
end

-- surface class of a hit: many road / building models use the DEFAULT material,
-- so DEFAULT is refined by the hit world model's name
function CMCPC.surfaceOf(h)
    if not h then return "none" end
    local cls = surfaceClass(h.material)
    if cls == "default" and h.worldModel then
        local kind = modelKind(CMCPC.modelName(h.worldModel))
        if kind == "road" or kind == "bridge" then return "road" end
        if kind == "building" then return "structure" end
    end
    return cls
end

-- serialisable hit
function CMCPC.hitOut(h)
    if not h then return { hit = false } end
    local out = {
        hit = true,
        position = M.vec(h.x, h.y, h.z),
        normal = M.vec(h.nx, h.ny, h.nz, 3),
        distance = M.round(h.distance, 3),
        material = h.material, materialName = surfaceName(h.material), surfaceClass = CMCPC.surfaceOf(h),
        slope = M.round(math.deg(math.acos(math.max(-1, math.min(1, h.nz or 1)))), 1),
    }
    if h.element and isElement(h.element) then
        out.element = h.element
        out.elementType = getElementType(h.element)
        out.elementModel = getElementModel(h.element)
        out.piece = h.piece
    end
    if h.worldModel then
        local name = CMCPC.modelName(h.worldModel)
        out.worldModel = {
            id = h.worldModel, name = name, kind = modelKind(name), kindSource = "name_heuristic",
            position = M.vec(h.wpos[1], h.wpos[2], h.wpos[3]), rotation = M.vec(h.wrot[1], h.wrot[2], h.wrot[3], 2),
            lodId = h.lod ~= 0 and h.lod or nil,
        }
    end
    return out
end

function CMCPC.toIgnoreSet(list)
    local set = {}
    for _, el in ipairs(type(list) == "table" and list or {}) do
        if isElement(el) then set[el] = true end
    end
    return set
end

-- ground under (x, y) starting at z + above; returns hit (world + objects by default)
function CMCPC.groundHit(x, y, z, opt, ignoreSet)
    opt = opt or {}
    local top = z and (z + (opt.above or 3)) or 1100
    local o = { vehicles = opt.includeVehicles == true, players = false, objects = opt.includeObjects ~= false, dummies = false }
    return CMCPC.rayIgnoring(x, y, top, x, y, top - (opt.depth or (z and 60 or 1200)), o, ignoreSet)
end

---------------------------------------------------------------- basic ops

CMCPC.ops.ping = function()
    return { pong = true, tick = getTickCount() }
end

CMCPC.ops.camera = function(a)
    local cx, cy, cz, tx, ty, tz, roll, fov = getCameraMatrix()
    local dx, dy, dz = tx - cx, ty - cy, tz - cz
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    local out = {
        position = M.vec(cx, cy, cz), target = M.vec(tx, ty, tz), roll = roll, fov = fov,
        lookHeading = M.round(M.headingFromVector(dx, dy), 1), compass = M.compass(M.headingFromVector(dx, dy)),
        pitch = M.round(math.deg(math.asin(dz / math.max(l, 0.0001))), 1),
        interior = getCameraInterior(),
    }
    if a.aim ~= false and l > 0 then
        local d = a.distance or 300
        local h = CMCPC.ray(cx, cy, cz, cx + dx / l * d, cy + dy / l * d, cz + dz / l * d, { ignore = localPlayer })
        out.aim = CMCPC.hitOut(h)
    end
    return out
end

CMCPC.ops.rays = function(a)
    local out = {}
    local opt = a.options or {}
    local ignoreSet = CMCPC.toIgnoreSet(opt.ignore)
    if opt.ignoreProbe ~= false then ignoreSet[localPlayer] = true local v = getPedOccupiedVehicle(localPlayer) if v then ignoreSet[v] = true end end
    local o = { buildings = opt.buildings, vehicles = opt.vehicles, players = opt.peds, objects = opt.objects, dummies = opt.dummies, seeThrough = opt.seeThrough, shootThrough = opt.shootThrough }
    for i, r in ipairs(a.rays or {}) do
        local h = CMCPC.rayIgnoring(r[1], r[2], r[3], r[4], r[5], r[6], o, ignoreSet)
        local res = CMCPC.hitOut(h)
        res.from = M.vec(r[1], r[2], r[3])
        res.to = M.vec(r[4], r[5], r[6])
        res.length = M.round(M.dist3D(r[1], r[2], r[3], r[4], r[5], r[6]), 2)
        out[i] = res
    end
    local px, py = getElementPosition(localPlayer)
    local first = a.rays and a.rays[1]
    local far = first and M.dist2D(px, py, first[1], first[2]) > 300
    return { results = out, count = #out,
        warning = far and "Ray starts >300 m from the probe player; collision there may not be loaded." or nil }
end

CMCPC.ops.los = function(a)
    local f, t = a.from, a.to
    local ignoreSet = CMCPC.toIgnoreSet(a.ignore)
    local o = a.options or {}
    local h = CMCPC.rayIgnoring(f[1], f[2], f[3], t[1], t[2], t[3], { vehicles = o.vehicles, players = o.peds, objects = o.objects, dummies = false }, ignoreSet)
    local total = M.dist3D(f[1], f[2], f[3], t[1], t[2], t[3])
    return {
        clear = h == nil, distance = M.round(total, 2),
        blockedAt = h and M.round(h.distance, 2) or nil,
        blocker = h and CMCPC.hitOut(h) or nil,
    }
end

-- ground: { points = { {x,y,z?} }, includeObjects, includeVehicles, slopeRadius, above, topmost }
CMCPC.ops.ground = function(a)
    local out = {}
    local px, py, pz = getElementPosition(localPlayer)
    local ignoreSet = { [localPlayer] = true }
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh then ignoreSet[veh] = true end
    for i, pt in ipairs(a.points or {}) do
        local x, y, z = pt[1], pt[2], pt[3]
        if a.topmost then z = nil end
        local h = CMCPC.groundHit(x, y, z, { above = a.above, includeObjects = a.includeObjects, includeVehicles = a.includeVehicles }, ignoreSet)
        local r = { x = M.round(x), y = M.round(y) }
        if h then
            r.groundZ = M.round(h.z, 3)
            local o = CMCPC.hitOut(h)
            r.material, r.materialName, r.surfaceClass, r.normal, r.slope = o.material, o.materialName, o.surfaceClass, o.normal, o.slope
            r.worldModel = o.worldModel
            r.onElement = o.element and { element = o.element, type = o.elementType, model = o.elementModel } or nil
            -- slope over a radius (4 samples)
            local s = a.slopeRadius or 1
            local zs = {}
            for k, d in ipairs({ { s, 0 }, { -s, 0 }, { 0, s }, { 0, -s } }) do
                local hh = CMCPC.groundHit(x + d[1], y + d[2], h.z, { above = 1.5, includeObjects = a.includeObjects, depth = 6 }, ignoreSet)
                zs[k] = hh and hh.z or h.z
            end
            local gx, gy = (zs[1] - zs[2]) / (2 * s), (zs[3] - zs[4]) / (2 * s)
            r.areaSlope = M.round(math.deg(math.atan(math.sqrt(gx * gx + gy * gy))), 1)
            r.downhillHeading = (gx ~= 0 or gy ~= 0) and M.round(M.headingFromVector(-gx, -gy), 1) or nil
            if z then r.heightAboveGround = M.round(z - h.z, 3) end
        else
            r.groundZ = nil
            r.noCollision = true
        end
        local gp = getGroundPosition(x, y, (z or pz) + 3)
        if gp and gp ~= 0 then r.getGroundPositionZ = M.round(gp, 3) end
        local w = getWaterLevel(x, y, (r.groundZ or z or 0) + 1)
        if w then
            r.waterLevel = M.round(w, 3)
            r.underwater = r.groundZ and w > r.groundZ + 0.2 or false
            r.waterDepth = r.groundZ and M.round(math.max(0, w - r.groundZ), 2) or nil
        end
        r.distanceFromProbe = M.round(M.dist2D(px, py, x, y), 1)
        if r.noCollision and r.distanceFromProbe > 250 then
            r.hint = "No collision hit: the area is probably not streamed in (far from the probe). Use teleport_probe."
        end
        out[i] = r
    end
    return { points = out }
end

-- modelNames: { from, to } -> { names = { {id, name} } }
CMCPC.ops.modelNames = function(a)
    local out = {}
    for id = a.from or 0, a.to or 19999 do
        local n = engineGetModelNameFromID(id)
        if n and n ~= "" then out[#out + 1] = { id, n } end
    end
    return { names = out, count = #out }
end

-- exec: { code } runs on this client
CMCPC.ops.exec = function(a)
    local fn, err = loadstring("return " .. a.code, "mcp_exec_client")
    if not fn then fn, err = loadstring(a.code, "mcp_exec_client") end
    if not fn then return { success = false, error = "syntax: " .. tostring(err) } end
    local printed = {}
    setfenv(fn, setmetatable({ print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, "\t")
    end }, { __index = _G }))
    local res = { pcall(fn) }
    if not res[1] then return { success = false, error = tostring(res[2]), printed = printed } end
    local out = {}
    for i = 2, table.maxn(res) do
        local v = res[i]
        local t = type(v)
        out[i - 1] = (t == "table" or t == "string" or t == "number" or t == "boolean" or (t == "userdata" and isElement(v))) and v or tostring(v)
    end
    return { success = true, results = out, printed = printed }
end

---------------------------------------------------------------- measure model

local measureCache = {}

-- measureModel: { type, model } (async: the model has to stream in)
CMCPC.ops.measureModel = function(a, reply)
    local key = a.type .. ":" .. a.model
    if measureCache[key] then return reply(true, measureCache[key]) end
    -- created under the camera: streaming follows the camera (which may be focused far from the player)
    local x, y, z = getCameraMatrix()
    z = z - 60
    local el
    if a.type == "vehicle" then el = createVehicle(a.model, x, y, z)
    elseif a.type == "ped" then el = createPed(a.model, x, y, z)
    else el = createObject(a.model, x, y, z) end
    if not el then
        return reply(false, { code = "MODEL_NOT_FOUND", message = a.type .. " model " .. tostring(a.model) .. " could not be created on the client." })
    end
    setElementDimension(el, getElementDimension(localPlayer))
    setElementInterior(el, getElementInterior(localPlayer))
    setElementAlpha(el, 0)
    setElementCollisionsEnabled(el, false)
    setElementFrozen(el, true)
    local tries = 0
    local timer
    timer = setTimer(function()
        tries = tries + 1
        local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(el)
        if x1 or tries >= 160 then
            killTimer(timer)
            if not x1 then
                destroyElement(el)
                return reply(false, { code = "MODEL_NOT_LOADED", message = "The model did not stream in within 8 s.", retryable = true })
            end
            local r = {
                type = a.type, model = a.model, name = CMCPC.modelName(a.model),
                bbox = { min = M.vec(x1, y1, z1), max = M.vec(x2, y2, z2) },
                size = M.vec(x2 - x1, y2 - y1, z2 - z1),
                radius = M.round(getElementRadius(el) or 0, 3),
                -- only valid for streamed-in game entities; otherwise the bbox bottom is used
                baseOffset = M.round((function()
                    local b = getElementDistanceFromCentreOfMassToBaseOfModel(el) or 0
                    if b < 0.05 then b = -z1 end
                    return b
                end)(), 3),
                axes = "size.x = width (left-right), size.y = length (back-front), size.z = height; +y of the bbox is the model's front",
            }
            if a.type == "vehicle" then
                r.vehicleType = getVehicleType(el)
                r.maxPassengers = getVehicleMaxPassengers(el)
                local wheels = {}
                for _, w in ipairs({ "wheel_lf_dummy", "wheel_rf_dummy", "wheel_lb_dummy", "wheel_rb_dummy" }) do
                    local wx, wy, wz = getVehicleComponentPosition(el, w)
                    if wx then wheels[w] = M.vec(wx, wy, wz) end
                end
                r.wheels = wheels
                local dummies = {}
                for _, d in ipairs({ "seat_front", "seat_rear", "light_front_main", "light_rear_main", "exhaust", "engine", "gas_cap", "trailer_attach" }) do
                    local ok, dx, dy, dz = pcall(getVehicleModelDummyPosition, a.model, d)
                    if ok and dx then dummies[d] = M.vec(dx, dy, dz) end
                end
                r.dummies = dummies
                local comps = {}
                for name in pairs(getVehicleComponents(el) or {}) do comps[#comps + 1] = name end
                table.sort(comps)
                r.components = comps
                local fw = getVehicleModelWheelSize and getVehicleModelWheelSize(a.model, "front_axle")
                if fw then r.wheelSize = M.round(fw, 3) end
            end
            destroyElement(el)
            measureCache[key] = r
            reply(true, r)
        end
    end, 50, 0)
end

function CMCPC.measureSync(typ, model)
    return measureCache[typ .. ":" .. model]
end

-- measure, then call fn(result) (or reply error)
function CMCPC.withMeasure(typ, model, reply, fn)
    local m = measureCache[typ .. ":" .. model]
    if m then return fn(m) end
    CMCPC.ops.measureModel({ type = typ, model = model }, function(ok, r)
        if not ok then return reply(false, r) end
        local ok2, res = pcall(fn, r)
        if not ok2 then reply(false, type(res) == "table" and res or { code = "PROBE_ERROR", message = tostring(res) })
        elseif res ~= nil then reply(true, res) end
    end)
end

---------------------------------------------------------------- lifecycle

local frames, fps = 0, 0
addEventHandler("onClientPreRender", root, function() frames = frames + 1 end)

local function info()
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    local sw, sh = guiGetScreenSize()
    return { camera = { cx, cy, cz, tx, ty, tz }, fps = fps, screen = { sw, sh }, windowActive = isMTAWindowActive and isMTAWindowActive() or false }
end

setTimer(function()
    fps = frames
    frames = 0
end, 1000, 0)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("cmcp:clientReady", resourceRoot, info())
    setTimer(function() triggerServerEvent("cmcp:heartbeat", resourceRoot, info()) end, 5000, 0)
end)

-- debug message forwarding (the server keeps only the probe's)
local logBuffer = {}
addEventHandler("onClientDebugMessage", root, function(message, level, file, line)
    if #logBuffer >= 50 then return end
    logBuffer[#logBuffer + 1] = { message = message, level = ({ [0] = "custom", [1] = "error", [2] = "warning", [3] = "info" })[level] or level, file = file, line = line }
end)
setTimer(function()
    if #logBuffer > 0 then
        triggerServerEvent("cmcp:clientLog", resourceRoot, logBuffer)
        logBuffer = {}
    end
end, 2000, 0)
