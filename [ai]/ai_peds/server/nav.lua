-- navmesh wrappers (server). Every call goes through pcall: without navmesh the peds still work with straight lines.

Nav = { pending = {} }   -- [job id] = callback

local function running()
    local res = getResourceFromName("navmesh")
    return res and getResourceState(res) == "running"
end

local function call(fn, ...)
    if not running() then return nil end
    local args = { ... }
    local ok, a, b = pcall(function() return exports.navmesh[fn](exports.navmesh, unpack(args)) end)
    if not ok then return nil end
    return a, b
end

function Nav.available() return running() end

-- walkable floor z near a point (or nil)
function Nav.ground(x, y, z, maxDz)
    local gz, info = call("getWalkableGround", x, y, z, maxDz or 3)
    if not gz then return nil end
    return gz, info
end

-- sidewalk edges around a point: { {edge, kind, a, b, length, width, x1..z2, distance}, ... } or {}
function Nav.edgesNear(x, y, z, radius)
    return call("getPedEdgesNear", x, y, z, radius, AIPEDS.WALK_KINDS, 10, 600) or {}
end

-- random walk on the sidewalks (opts: node, prev); result {points, nodes, widths, crossings, length} or nil
function Nav.randomWalk(x, y, z, length, opts)
    opts = opts or {}
    opts.kinds = AIPEDS.WALK_KINDS
    return call("getPedRandomWalk", x, y, z, length, "civilian", opts) or nil
end

function Nav.nearestPedPath(x, y, z, radius)
    local px, py, pz, info = call("getNearestPedPath", x, y, z, radius)
    if not px then return nil end
    return px, py, pz, info
end

function Nav.isCrossingOpen(phase)
    local open = call("isCrossingOpen", phase)
    if open == nil then return true end
    return open
end

-- async ped route; cb(result | false, reason) later. Returns false when navmesh is not running (cb not called).
function Nav.requestPedRoute(x1, y1, z1, x2, y2, z2, role, cb)
    local id = call("requestRoute", "ped", x1, y1, z1, x2, y2, z2, { role = role or "free" })
    if not id then return false end
    Nav.pending[id] = cb
    return true
end

addEvent("onNavmeshRouteReady")
addEventHandler("onNavmeshRouteReady", resourceRoot, function(id, result, reason)
    local cb = Nav.pending[id]
    if not cb then return end
    Nav.pending[id] = nil
    cb(result, reason)
end)

-- navmesh restarted: running requests are gone
addEvent("onNavmeshReady")
addEventHandler("onNavmeshReady", root, function()
    local cbs = Nav.pending
    Nav.pending = {}
    for _, cb in pairs(cbs) do cb(false, "navmesh_restart") end
end)
