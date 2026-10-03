-- Probe validation ops: live element info, placement diagnostics, EMS access.

local LYING = { lie_back = true, lie_front = true, ko_back = true, ko_front = true, injured = true }
local SITTING = { sit_ground = true, sit = true, crouch = true, cpr = true }

-- waits until every element is streamed in with a bounding box (max ~2.5 s), then fn()
local function whenStreamed(elements, fn)
    local tries = 0
    local timer
    local function ready()
        for _, el in ipairs(elements) do
            if isElement(el) and (not getElementBoundingBox(el) or not isElementStreamedIn(el)) then return false end
        end
        return true
    end
    if ready() then return fn(false) end
    timer = setTimer(function()
        tries = tries + 1
        if ready() or tries >= 50 then
            killTimer(timer)
            fn(tries >= 50)
        end
    end, 50, 0)
end

local function corners(el)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(el)
    if not x1 then return nil end
    local m = getElementMatrix(el)
    local out = {}
    for _, lx in ipairs({ x1, x2 }) do
        for _, ly in ipairs({ y1, y2 }) do
            for _, lz in ipairs({ z1, z2 }) do
                out[#out + 1] = {
                    m[4][1] + lx * m[1][1] + ly * m[2][1] + lz * m[3][1],
                    m[4][2] + lx * m[1][2] + ly * m[2][2] + lz * m[3][2],
                    m[4][3] + lx * m[1][3] + ly * m[2][3] + lz * m[3][3],
                }
            end
        end
    end
    return out, { x1, y1, z1, x2, y2, z2 }, m
end

local function localToWorld(m, lx, ly, lz)
    return m[4][1] + lx * m[1][1] + ly * m[2][1] + lz * m[3][1],
        m[4][2] + lx * m[1][2] + ly * m[2][2] + lz * m[3][2],
        m[4][3] + lx * m[1][3] + ly * m[2][3] + lz * m[3][3]
end

local WHEELS = { { "wheel_lf_dummy", "front_left" }, { "wheel_rf_dummy", "front_right" }, { "wheel_lb_dummy", "rear_left" }, { "wheel_rb_dummy", "rear_right" } }
local WHEEL_INDEX = { front_left = 0, rear_left = 1, front_right = 2, rear_right = 3 }

-- live geometry of one element
function CMCPC.elementInfo(el, ignoreSet)
    local typ = getElementType(el)
    local x, y, z = getElementPosition(el)
    local info = {
        element = el, streamed = isElementStreamedIn(el), onScreen = isElementOnScreen(el),
        distanceToCamera = (function() local cx, cy, cz = getCameraMatrix() return M.round(M.dist3D(cx, cy, cz, x, y, z), 1) end)(),
    }
    local cs, bb, m = corners(el)
    if not cs then
        info.note = "Element not streamed in on the probe client (too far, other dimension/interior, or just created)."
        return info
    end
    info.bbox = { min = M.vec(bb[1], bb[2], bb[3]), max = M.vec(bb[4], bb[5], bb[6]) }
    info.size = M.vec(bb[4] - bb[1], bb[5] - bb[2], bb[6] - bb[3])
    info.obb = CMCPC.obbOf(el)
    local mnx, mny, mnz, mxx, mxy, mxz = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
    for _, c in ipairs(cs) do
        mnx, mny, mnz = math.min(mnx, c[1]), math.min(mny, c[2]), math.min(mnz, c[3])
        mxx, mxy, mxz = math.max(mxx, c[1]), math.max(mxy, c[2]), math.max(mxz, c[3])
    end
    info.worldBounds = { min = M.vec(mnx, mny, mnz, 2), max = M.vec(mxx, mxy, mxz, 2) }
    ignoreSet = ignoreSet or {}
    ignoreSet[el] = true
    local g = CMCPC.groundHit(x, y, z, { above = 0.5, includeObjects = true, depth = 30 }, ignoreSet)
    if g then
        info.groundZ = M.round(g.z, 3)
        info.groundSurface = CMCPC.surfaceOf(g)
        info.groundMaterial = surfaceName(g.material)
    end
    if typ == "vehicle" then
        local wheels, gaps = {}, {}
        local model = getElementModel(el)
        local wsize = getVehicleModelWheelSize and getVehicleModelWheelSize(model, "front_axle") or 0.7
        for _, w in ipairs(WHEELS) do
            local lx, ly, lz = getVehicleComponentPosition(el, w[1])
            if lx then
                local wx, wy, wz = localToWorld(m, lx, ly, lz)
                local gh = CMCPC.groundHit(wx, wy, wz, { above = 1.0, includeObjects = true, depth = 6 }, ignoreSet)
                local bottom = wz - wsize / 2
                local gap = gh and (bottom - gh.z) or nil
                wheels[w[2]] = {
                    onGround = isVehicleWheelOnGround(el, WHEEL_INDEX[w[2]]),
                    gap = gap and M.round(gap, 3) or nil,
                }
                if gap then gaps[#gaps + 1] = gap end
            end
        end
        info.wheels = wheels
        if #gaps > 0 then
            local mx, mn = -math.huge, math.huge
            for _, v in ipairs(gaps) do mx, mn = math.max(mx, v), math.min(mn, v) end
            info.maxWheelGap, info.minWheelGap = M.round(mx, 3), M.round(mn, 3)
            info.groundContact = mx < 0.3 and mn > -0.35
        end
        info.baseOffset = M.round(getElementDistanceFromCentreOfMassToBaseOfModel(el) or 0, 3)
        if #gaps == 0 then info.note = "Wheel positions unavailable (vehicle not streamed in on the probe)." end
    else
        local base = mnz
        if typ == "ped" or typ == "player" then
            base = z - (getElementDistanceFromCentreOfMassToBaseOfModel(el) or 1.0)
            if getPedOccupiedVehicle(el) then info.seated = true end
        end
        if g then
            info.groundGap = M.round(base - g.z, 3)
            info.groundContact = math.abs(base - g.z) < 0.35
        end
    end
    local w = getWaterLevel(x, y, z + 2)
    if w and g and w > g.z + 0.2 then
        info.waterLevel = M.round(w, 2)
        info.submergedDepth = M.round(math.max(0, w - mnz), 2)
    end
    return info
end

CMCPC.ops.elementInfo = function(a, reply)
    local list = {}
    for _, el in ipairs(a.elements or {}) do if isElement(el) then list[#list + 1] = el end end
    whenStreamed(list, function(timedOut)
        local items = {}
        for _, el in ipairs(list) do
            local ok, r = pcall(CMCPC.elementInfo, el, {})
            items[#items + 1] = ok and r or { element = el, error = tostring(r) }
        end
        reply(true, { items = items, streamTimeout = timedOut or nil })
    end)
end

---------------------------------------------------------------- validate

-- rays along the box edges / diagonals (shrunk) -> first world hit
local function boxRays(el, shrink, bottomLift, opt, ignoreSet)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(el)
    if not x1 then return nil end
    local m = getElementMatrix(el)
    x1, y1, z1 = x1 + shrink, y1 + shrink, z1 + bottomLift
    x2, y2, z2 = x2 - shrink, y2 - shrink, z2 - shrink
    if x1 >= x2 or y1 >= y2 or z1 >= z2 then return nil end
    local P = {}
    for i, c in ipairs({ { x1, y1, z1 }, { x2, y1, z1 }, { x2, y2, z1 }, { x1, y2, z1 }, { x1, y1, z2 }, { x2, y1, z2 }, { x2, y2, z2 }, { x1, y2, z2 } }) do
        P[i] = { localToWorld(m, c[1], c[2], c[3]) }
    end
    local edges = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 }, { 1, 7 }, { 2, 8 }, { 3, 5 }, { 4, 6 } }
    for _, e in ipairs(edges) do
        local a, b = P[e[1]], P[e[2]]
        local h = CMCPC.rayIgnoring(a[1], a[2], a[3], b[1], b[2], b[3], opt, ignoreSet)
        if h then return h end
        h = CMCPC.rayIgnoring(b[1], b[2], b[3], a[1], a[2], a[3], opt, ignoreSet)
        if h then return h end
    end
    return nil
end

-- validate: { items = { {element,id,type,model,seated,pose,role} }, checks = {name=true}, tolerance }
CMCPC.ops.validate = function(a, reply)
    local items = a.items or {}
    local checks = a.checks or {}
    local tol = a.tolerance or {}
    local gapTol = tonumber(tol.groundGap) or 0.35
    local els = {}
    for _, it in ipairs(items) do if isElement(it.element) then els[#els + 1] = it.element end end
    whenStreamed(els, function(timedOut)
        local errors, warnings, info, metrics = {}, {}, {}, {}
        local function add(list, id, typ, msg, extra)
            local d = { entity = id, type = typ, message = msg }
            if extra then for k, v in pairs(extra) do d[k] = v end end
            list[#list + 1] = d
        end
        if timedOut then add(warnings, nil, "not_streamed", "Some entities did not stream in on the probe client; their geometry checks are incomplete.") end
        local itemByEl = {}
        for _, it in ipairs(items) do itemByEl[it.element] = it end
        local obbs = {}

        for _, it in ipairs(items) do
            local el = it.element
            if isElement(el) then
                local ok, li = pcall(CMCPC.elementInfo, el, {})
                if not ok then
                    add(warnings, it.id, "probe_error", tostring(li))
                else
                    li.element = nil
                    metrics[it.id] = li
                    if not li.bbox then
                        add(warnings, it.id, "not_streamed", li.note or "Entity not streamed in on the probe.")
                    else
                        obbs[it.id] = li.obb
                        local lying = it.pose and LYING[it.pose]
                        local sitting = it.pose and SITTING[it.pose]
                        -- ground contact
                        if checks.ground and not li.seated then
                            if it.type == "vehicle" and li.maxWheelGap then
                                if li.minWheelGap < -0.45 then
                                    add(errors, it.id, "below_ground", string.format("Wheels are up to %.2f m inside the ground.", -li.minWheelGap), { value = li.minWheelGap, suggestion = "place_entity mode ground (snaps to terrain)" })
                                elseif li.maxWheelGap > 2.0 then
                                    add(errors, it.id, "floating", string.format("Vehicle floats %.2f m above the ground.", li.maxWheelGap), { value = li.maxWheelGap, suggestion = "place_entity mode ground" })
                                elseif li.maxWheelGap > gapTol then
                                    add(warnings, it.id, "wheel_gap", string.format("At least one wheel is %.2f m above the ground.", li.maxWheelGap), { value = li.maxWheelGap })
                                end
                            elseif li.groundGap then
                                local g = li.groundGap
                                local lo, hi = -gapTol, gapTol
                                if it.type == "ped" and (lying or sitting) then lo, hi = -1.1, 0.6 end
                                if it.type == "object" then lo = -math.huge end
                                if g < lo - 0.4 then
                                    add(errors, it.id, "below_ground", string.format("Base is %.2f m below the ground.", -g), { value = g })
                                elseif g > 2.0 and it.type ~= "object" then
                                    add(errors, it.id, "floating", string.format("Base is %.2f m above the ground.", g), { value = g })
                                elseif g > hi then
                                    add(warnings, it.id, "ground_gap", string.format("Base is %.2f m above the ground.", g), { value = g })
                                elseif g < lo then
                                    add(warnings, it.id, "sunk", string.format("Base is %.2f m below the ground.", -g), { value = g })
                                end
                            elseif not li.groundZ then
                                add(warnings, it.id, "no_ground", "No ground found under the entity (collision not loaded or over a void).")
                            end
                        end
                        -- vehicles standing on sidewalks / pavements
                        if checks.ground and it.type == "vehicle" and not li.seated and li.groundSurface == "sidewalk" then
                            add(warnings, it.id, "vehicle_on_sidewalk", "Vehicle stands on a sidewalk / pavement surface.", { suggestion = "place_entity mode road (lane / curb) if it should be on the road" })
                        end
                        -- world geometry intersection
                        if checks.world_collision and not li.seated then
                            local lift = (it.type == "vehicle" and 0.45) or (it.type == "ped" and (lying and 0.25 or 0.5)) or 0.1
                            local ign = { [el] = true, [localPlayer] = true }
                            local h = boxRays(el, it.type == "ped" and 0.05 or 0.12, lift, { buildings = true, vehicles = false, players = false, objects = false, dummies = false }, ign)
                            if h then
                                local name = h.worldModel and CMCPC.modelName(h.worldModel)
                                add(errors, it.id, "world_collision", "Intersects world geometry" .. (name and (" (" .. name .. ", model " .. h.worldModel .. ")") or "") .. ".",
                                    { at = M.vec(h.x, h.y, h.z), worldModel = h.worldModel, worldModelName = name, suggestion = "Move it a little (place_entity mode near/relative, or set_entity_transform move) and re-validate." })
                            end
                            local h2 = boxRays(el, 0.12, lift, { buildings = false, vehicles = false, players = false, objects = true, dummies = false }, ign)
                            if h2 and h2.element and not itemByEl[h2.element] and getElementAttachedTo(h2.element) ~= el then
                                add(warnings, it.id, "object_collision", "Intersects a non-workspace object (model " .. tostring(getElementModel(h2.element)) .. ").",
                                    { at = M.vec(h2.x, h2.y, h2.z) })
                            end
                        end
                        -- water
                        if checks.water and li.submergedDepth and li.submergedDepth > 0.3 then
                            add(it.type == "vehicle" and errors or warnings, it.id, "underwater", string.format("Entity is %.1f m under water.", li.submergedDepth), { value = li.submergedDepth })
                        end
                        -- clearance around peds
                        if checks.clearance and it.type == "ped" and not li.seated then
                            local x, y = getElementPosition(el)
                            local gz = li.groundZ or select(3, getElementPosition(el)) - 1
                            local free, dirs = 0, {}
                            local ign = { [el] = true, [localPlayer] = true }
                            for k = 0, 7 do
                                local fx, fy = M.forward(k * 45)
                                local h = CMCPC.rayIgnoring(x, y, gz + 0.4, x + fx * 1.2, y + fy * 1.2, gz + 0.4, { vehicles = true, players = true, objects = true, dummies = false }, ign)
                                if not h then free = free + 1 dirs[#dirs + 1] = M.compass(k * 45) end
                            end
                            li.clearance = { freeDirections = dirs, free = free, of = 8, radius = 1.2 }
                            if free <= 2 then
                                add(warnings, it.id, "cramped", "Only " .. free .. " of 8 directions are free within 1.2 m of the ped.", { free = dirs })
                            end
                        end
                    end
                end
            end
        end

        -- overlaps between items and with other elements
        if checks.overlap then
            local ids = {}
            for id in pairs(obbs) do ids[#ids + 1] = id end
            table.sort(ids)
            local byId = {}
            for _, it in ipairs(items) do byId[it.id] = it end
            for i = 1, #ids do
                for j = i + 1, #ids do
                    local A, B = byId[ids[i]], byId[ids[j]]
                    local skip = (A.type == "ped" and A.seated) or (B.type == "ped" and B.seated)
                    if not skip then
                        local hit, pen = M.obbOverlap(obbs[ids[i]], obbs[ids[j]])
                        if hit then
                            local kinds = A.type .. "/" .. B.type
                            local msg = string.format("%s and %s overlap (≈%.2f m).", ids[i], ids[j], pen)
                            local ped = (A.type == "ped" and A) or (B.type == "ped" and B)
                            local veh = (A.type == "vehicle" and A) or (B.type == "vehicle" and B)
                            if ped and veh and ped.pose and LYING[ped.pose] then
                                add(errors, ped.id, "ped_under_vehicle", ped.id .. " lies inside / under " .. veh.id .. ".", { other = veh.id, penetration = M.round(pen, 2) })
                            elseif pen > 0.15 or kinds == "vehicle/vehicle" and pen > 0.08 then
                                add(errors, ids[i], "entity_overlap", msg, { other = ids[j], penetration = M.round(pen, 2) })
                            else
                                add(warnings, ids[i], "entity_touching", msg, { other = ids[j], penetration = M.round(pen, 2) })
                            end
                        end
                    end
                end
            end
            -- foreign elements nearby
            for _, it in ipairs(items) do
                local o = obbs[it.id]
                if o and not (it.type == "ped" and it.seated) then
                    local x, y, z = getElementPosition(it.element)
                    for _, typ in ipairs({ "vehicle", "object", "ped" }) do
                        for _, other in ipairs(getElementsWithinRange(x, y, z, 15, typ)) do
                            if not itemByEl[other] and other ~= it.element and getElementDimension(other) == getElementDimension(it.element)
                                and getElementAttachedTo(other) ~= it.element and getElementAttachedTo(it.element) ~= other then
                                local ob = CMCPC.obbOf(other)
                                if ob then
                                    local hit, pen = M.obbOverlap(o, ob)
                                    if hit and pen > 0.05 then
                                        add(warnings, it.id, "foreign_overlap", string.format("Overlaps a non-workspace %s (model %d) by ≈%.2f m.", typ, getElementModel(other), pen),
                                            { otherType = typ, otherModel = getElementModel(other), other = other })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        for id, m in pairs(metrics) do m.obb = nil end
        reply(true, { errors = errors, warnings = warnings, info = info, metrics = metrics })
    end)
end

---------------------------------------------------------------- EMS access (medical)

-- medicalAccess: { patients = { {element,id} }, ambulanceModel }
CMCPC.ops.medicalAccess = function(a, reply)
    return CMCPC.withMeasure("vehicle", a.ambulanceModel or 416, reply, function(amb)
        local errors, warnings, info, out = {}, {}, {}, {}
        for _, p in ipairs(a.patients or {}) do
            local el = p.element
            if isElement(el) then
                local x, y, z = getElementPosition(el)
                local ign = { [el] = true, [localPlayer] = true }
                local g = CMCPC.groundHit(x, y, z, { above = 0.5, includeObjects = true, depth = 10 }, ign)
                local gz = g and g.z or z - 1
                -- stretcher / medic space: free distance in 12 directions
                local minFree, free = math.huge, {}
                for k = 0, 11 do
                    local h = k * 30
                    local fx, fy = M.forward(h)
                    local hit = CMCPC.rayIgnoring(x, y, gz + 0.35, x + fx * 2.0, y + fy * 2.0, gz + 0.35, { vehicles = true, players = true, objects = true, dummies = false }, ign)
                    local d = hit and hit.distance or 2.0
                    minFree = math.min(minFree, d)
                    if d >= 1.2 then free[#free + 1] = h end
                end
                local r = { id = p.id, groundSurface = g and CMCPC.surfaceOf(g) or nil, minFreeDistance = M.round(minFree, 2), headingsWithStretcherRoom = free, headingNote = "MTA headings (0 = N, 90 = W) with >= 1.2 m free at 0.35 m height" }
                if #free < 4 then
                    warnings[#warnings + 1] = { entity = p.id, type = "stretcher_space", message = "Little room around the patient for medics / stretcher (" .. #free .. " of 12 directions have 1.2 m)." }
                end
                if r.groundSurface == "road" then
                    info[#info + 1] = { entity = p.id, type = "patient_on_road", message = "Patient lies on the road surface (traffic / scene safety)." }
                end
                -- ambulance parking spot on road within 35 m with a line of sight to the patient
                local spot
                for rad = 5, 35, 2.5 do
                    local n = math.max(8, math.floor(2 * math.pi * rad / 3))
                    for k = 0, n - 1 do
                        local ang = k * 2 * math.pi / n
                        local sx, sy = x + math.cos(ang) * rad, y + math.sin(ang) * rad
                        local sg = CMCPC.groundHit(sx, sy, gz + 2, { above = 3, includeObjects = true, depth = 12 }, ign)
                        if sg and CMCPC.surfaceOf(sg) == "road" and math.abs(sg.z - gz) < 4 then
                            for _, hd in ipairs({ M.headingTo(sx, sy, x, y) + 90, M.headingTo(sx, sy, x, y) }) do
                                local box = CMCPC.obbAt(amb, sx, sy, sg.z + (amb.baseOffset or 1), hd, 0.3)
                                local blocked = false
                                for _, typ in ipairs({ "vehicle", "object" }) do
                                    for _, other in ipairs(getElementsWithinRange(sx, sy, sg.z, 12, typ)) do
                                        local ob = CMCPC.obbOf(other)
                                        if ob and M.obbOverlap(box, ob) then blocked = true break end
                                    end
                                    if blocked then break end
                                end
                                if not blocked then
                                    local los = CMCPC.rayIgnoring(sx, sy, sg.z + 1.0, x, y, gz + 0.6, { vehicles = true, players = false, objects = true, dummies = false }, ign)
                                    spot = { position = M.vec(sx, sy, sg.z), heading = M.round(M.norm(hd), 1), distance = M.round(rad, 1), lineOfSight = los == nil,
                                        blockedBy = los and (los.worldModel and CMCPC.modelName(los.worldModel) or (los.element and getElementType(los.element))) or nil }
                                    if spot.lineOfSight then break end
                                end
                            end
                        end
                        if spot and spot.lineOfSight then break end
                    end
                    if spot and spot.lineOfSight then break end
                end
                r.ambulanceSpot = spot
                if not spot then
                    errors[#errors + 1] = { entity = p.id, type = "no_ambulance_access", message = "No free road spot for an ambulance within 35 m of the patient." }
                elseif not spot.lineOfSight then
                    warnings[#warnings + 1] = { entity = p.id, type = "no_direct_path", message = string.format("Nearest ambulance spot (%.0f m) has no direct line to the patient (blocked by %s).", spot.distance, tostring(spot.blockedBy)) }
                end
                out[#out + 1] = r
            end
        end
        return { patients = out, errors = errors, warnings = warnings, info = info }
    end)
end
