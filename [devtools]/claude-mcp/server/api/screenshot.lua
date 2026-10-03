-- screenshot: real screenshots of the probe client's game view, camera views
-- around targets, and the debug overlay (labels / boxes / lines drawn in 3D on
-- the probe client, visible in screenshots).

Screens = { waiting = {}, seq = 0 }
Overlay = { state = { labels = true, boxes = true, ids = nil, lines = {}, points = {}, nodes = {} } }

addEventHandler("onPlayerScreenShot", root, function(res, status, pixels, timestamp, tag)
    if res ~= resource then return end
    local w = Screens.waiting[tag]
    if not w then return end
    Screens.waiting[tag] = nil
    w.wake(status, pixels, timestamp)
end)

-- takes one screenshot (inside a job) -> base64 jpeg
function Screens.take(player, width, height, quality)
    Screens.seq = Screens.seq + 1
    local tag = "cmcp" .. Screens.seq
    local wake = Async.waker()
    Screens.waiting[tag] = { wake = wake }
    local timer = setTimer(function()
        if Screens.waiting[tag] then
            Screens.waiting[tag] = nil
            wake("timeout")
        end
    end, CMCP.SHOT_TIMEOUT, 1)
    if not takePlayerScreenShot(player, width, height, tag, quality, 2000000, 60000) then
        Screens.waiting[tag] = nil
        if isTimer(timer) then killTimer(timer) end
        fail("SCREENSHOT_FAILED", "takePlayerScreenShot was refused.", { retryable = true })
    end
    local status, pixels = Async.wait()
    if isTimer(timer) then killTimer(timer) end
    if status == "disabled" then
        fail("SCREENSHOT_DISABLED", "The probe player's client does not allow screen uploads.",
            { retryable = false, suggestion = "In MTA: Settings > Advanced > 'Allow screen upload' = Yes, then retry." })
    elseif status == "minimized" then
        fail("SCREENSHOT_MINIMIZED", "The game window is minimized; nothing can be captured.",
            { retryable = true, suggestion = "Restore the MTA window (it may stay in the background but not minimized)." })
    elseif status == "timeout" then
        fail("SCREENSHOT_TIMEOUT", "The screenshot did not arrive in time.", { retryable = true })
    elseif status ~= "ok" or type(pixels) ~= "string" then
        fail("SCREENSHOT_FAILED", "Screenshot status: " .. tostring(status), { retryable = true })
    end
    return pixels
end

function Screens.chunks(str, size)
    local out = {}
    for i = 1, #str, size do out[#out + 1] = str:sub(i, i + size - 1) end
    return out
end

-- target spec -> centre point, heading, auto distance
local function viewTarget(p)
    if p.workspace then
        local ws = Registry.requireWorkspace(p.workspace)
        local minX, minY, minZ, maxX, maxY, maxZ = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
        local n = 0
        for _, id in ipairs(ws.entities) do
            local e = Registry.entities[id]
            if e and isElement(e.element) then
                local x, y, z = getElementPosition(e.element)
                minX, minY, minZ = math.min(minX, x), math.min(minY, y), math.min(minZ, z)
                maxX, maxY, maxZ = math.max(maxX, x), math.max(maxY, y), math.max(maxZ, z)
                n = n + 1
            end
        end
        if n == 0 then
            if ws.center then return ws.center.x, ws.center.y, ws.center.z, 0, 25 end
            fail("WORKSPACE_EMPTY", "Workspace '" .. ws.name .. "' has no entities to frame.")
        end
        local diag = M.dist2D(minX, minY, maxX, maxY)
        return (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2, 0, math.max(10, diag * 0.85 + 8)
    end
    local x, y, z, info = Resolve.point(p.target, "target")
    local dist = 10
    if info.element then
        local typ = getElementType(info.element)
        if typ == "player" then typ = "ped" end
        local m = Models.cached(typ, getElementModel(info.element))
        if m and m.size then dist = math.max(m.size.x, m.size.y, m.size.z) * 1.7 + 3 end
    end
    return x, y, z, info.heading or 0, dist
end

-- camera matrix for a view mode
function Screens.viewMatrix(p)
    local mode = P.str(p, "view", "orbit", { "orbit", "top", "front", "back", "left", "right", "free", "current" })
    if mode == "current" then return nil end
    if mode == "free" then
        local x, y, z = P.vec(p.position, "position", true)
        local tx, ty, tz = Resolve.point(p.target, "target")
        return { x, y, z, tx, ty, tz }, mode
    end
    local tx, ty, tz, th, auto = viewTarget(p)
    tz = tz + P.num(p, "targetLift", 0.5)
    local dist = P.num(p, "distance", auto, 1, 500)
    local h = p.cameraHeight ~= nil and P.num(p, "cameraHeight") or math.max(2, dist * 0.45)
    if mode == "top" then
        return { tx, ty - 0.01, tz + math.max(dist, 8) * 1.4, tx, ty, tz }, mode
    end
    local yaw = ({ front = 0, back = 180, left = 90, right = -90, orbit = P.num(p, "yaw", 35) })[mode]
    local function at(y, d, hh)
        local fx, fy = M.forward(M.norm(th + y))
        return { tx + fx * d, ty + fy * d, tz + hh, tx, ty, tz }
    end
    if p.avoidOcclusion == false or not Probe.get() then return at(yaw, dist, h), mode end
    -- try the requested yaw first, then neighbours, then closer / higher: first one with a clear line wins
    local cands = {}
    for _, dy in ipairs({ 0, 30, -30, 60, -60, 90, -90, 135, -135, 180 }) do cands[#cands + 1] = { yaw + dy, dist, h } end
    for _, dy in ipairs({ 0, 90, 180, -90 }) do cands[#cands + 1] = { yaw + dy, dist * 0.6, h * 1.6 } end
    local rays = {}
    for i, c in ipairs(cands) do
        local m = at(c[1], c[2], c[3])
        rays[i] = { tx, ty, tz + 0.3, m[1], m[2], m[3] }
    end
    Probe.focus(tx, ty, tz)
    local r = Probe.call("rays", { rays = rays, options = { vehicles = false, peds = false, objects = false } })
    for i, res in ipairs(r.results or {}) do
        if not res.hit then
            local c = cands[i]
            Screens.lastViewNote = (i > 1) and string.format("requested yaw was occluded; used yaw %.0f at %.1f m", c[1], c[2]) or nil
            return at(c[1], c[2], c[3]), mode
        end
    end
    Screens.lastViewNote = "every candidate view was occluded; used a top view"
    return { tx, ty - 0.01, tz + math.max(dist, 8) * 1.4, tx, ty, tz }, "top"
end

-- capture: { width, height, quality, view, target, workspace, distance, height, yaw, position, hideHud, daylight, settle, overlay }
Api.register("screenshot", "capture", function(p)
    local player = Probe.require()
    local w = P.int(p, "width", 1280, 160, CMCP.SHOT_MAX_W)
    local h = P.int(p, "height", 720, 120, CMCP.SHOT_MAX_H)
    local quality = P.int(p, "quality", 70, 10, 100)
    Screens.lastViewNote = nil
    local matrix, mode = Screens.viewMatrix(p)
    if matrix then
        setCameraMatrix(player, matrix[1], matrix[2], matrix[3], matrix[4], matrix[5], matrix[6], 0, P.num(p, "fov", 70, 10, 120))
        Probe.focused = player
        Async.defer(function()
            if isElement(player) then setCameraTarget(player, player) end
            Probe.focused = nil
        end)
    end
    if p.overlay ~= nil and (p.overlay == true) ~= (Overlay.state.enabled == true) then
        local before = Overlay.state.enabled
        Overlay.state.enabled = p.overlay == true
        Overlay.push()
        Async.defer(function() Overlay.state.enabled = before Overlay.push() end)
    end
    local prep = { hideHud = p.hideHud ~= false, daylight = p.daylight == true }
    Probe.call("capturePrepare", prep)
    Async.defer(function() if isElement(player) then triggerClientEvent(player, "cmcp:captureRestore", resourceRoot) end end)
    Async.sleep(matrix and P.int(p, "settle", 900, 100, 10000) or 250)
    local pixels = Screens.take(player, w, h, quality)
    local cam = Probe.clients[player].info.camera
    return {
        -- MTA JSON strings are limited to 65535 chars: the base64 image is sent in chunks
        imageChunks = Screens.chunks(encodeString("base64", pixels), 60000), mimeType = "image/jpeg", width = w, height = h, bytes = #pixels,
        view = mode or "current", viewNote = matrix and Screens.lastViewNote or nil,
        camera = matrix and { position = M.vec(matrix[1], matrix[2], matrix[3]), target = M.vec(matrix[4], matrix[5], matrix[6]) }
            or (cam and { position = M.vec(cam[1], cam[2], cam[3]), target = M.vec(cam[4], cam[5], cam[6]) }),
        overlay = Overlay.state.enabled == true,
        takenAt = getRealTime().timestamp,
    }
end, { async = true, desc = "JPEG screenshot of the probe client, optionally from a computed camera view." })

---------------------------------------------------------------- overlay

function Overlay.push()
    local pl = Probe.get()
    if not pl then return false end
    local s = Overlay.state
    local items = {}
    if s.enabled then
        local wanted
        if type(s.ids) == "table" then wanted = {} for _, id in ipairs(s.ids) do wanted[id] = true end end
        for id, e in pairs(Registry.entities) do
            if isElement(e.element) and (not wanted or wanted[id]) and (not s.workspace or s.workspace == e.workspace) then
                items[#items + 1] = { element = e.element, label = id, type = e.type }
            end
        end
    end
    triggerClientEvent(pl, "cmcp:overlay", resourceRoot, {
        enabled = s.enabled == true, labels = s.labels, boxes = s.boxes, axes = s.axes, items = items,
        lines = s.lines, points = s.points, nodes = s.nodes, maxDistance = s.maxDistance or 250,
    })
    return true
end

function Overlay.forget(ids)
    Overlay.push()
end

-- overlay: { enabled, labels, boxes, axes, workspace, ids, lines = [{from,to,color,label}], points = [{position,label,color}], nodes = [...], clear }
Api.register("screenshot", "overlay", function(p)
    local s = Overlay.state
    if p.clear then s.lines, s.points, s.nodes = {}, {}, {} end
    for _, k in ipairs({ "enabled", "labels", "boxes", "axes" }) do
        if p[k] ~= nil then s[k] = p[k] == true end
    end
    if p.enabled == nil and (p.lines or p.points or p.nodes or p.ids or p.workspace) then s.enabled = true end
    if p.workspace ~= nil then s.workspace = p.workspace ~= "" and p.workspace or nil end
    if p.ids ~= nil then s.ids = type(p.ids) == "table" and p.ids or nil end
    if p.maxDistance then s.maxDistance = tonumber(p.maxDistance) end
    local function addList(key, list, conv)
        if type(list) ~= "table" then return end
        for _, item in ipairs(list) do
            local ok, v = Util.try(conv, item)
            if ok and v then s[key][#s[key] + 1] = v end
            if #s[key] > 2000 then break end
        end
    end
    addList("lines", p.lines, function(l)
        local ax, ay, az = Resolve.point(l.from, "from")
        local bx, by, bz = Resolve.point(l.to, "to")
        return { ax, ay, az, bx, by, bz, l.color or { 255, 200, 0 }, l.label, tonumber(l.width) or 3 }
    end)
    addList("points", p.points, function(pt)
        local x, y, z = Resolve.point(pt.position or pt, "point")
        return { x, y, z, pt.label, pt.color or { 0, 200, 255 } }
    end)
    addList("nodes", p.nodes, function(n)
        return { tonumber(n.x), tonumber(n.y), tonumber(n.z), n.label or tostring(n.id or ""), n.links }
    end)
    local pushed = Overlay.push()
    return { success = true, pushed = pushed, enabled = s.enabled == true, lines = #s.lines, points = #s.points, nodes = #s.nodes,
        note = pushed and nil or "No probe client: the overlay will be sent when one connects." }
end, { mutates = true, desc = "Debug overlay on the probe client: entity labels / bounding boxes, lines, points, road nodes." })

addEventHandler("cmcp:clientReady", resourceRoot, function()
    setTimer(Overlay.push, 500, 1)
end)
