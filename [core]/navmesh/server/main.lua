-- navmesh: loading + exports. See README.md for the export reference.

addEvent("onNavmeshReady")             -- (root) all networks loaded
addEvent("onNavmeshRouteReady")        -- (caller resource root) id, result|false, reason

addEventHandler("onResourceStart", resourceRoot, function()
    Roads.load()
    Peds.load()
    Boats.load()
    Walk.load()
    triggerEvent("onNavmeshReady", resourceRoot)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if Walk.file then fileClose(Walk.file) end
end)


------------------------------------------------------------------------ routes

-- vehicle route on the lane network. opts: profile ("car" | "truck" | "bike" | "bus" | "emergency" | "offroad" | "gps"),
-- heading, destHeading, radius, gpsNodes (true: add v_radar node ids), startLane / startU, goalLane / goalU (lane ids
-- instead of the nearest lanes; u = 0..1 along the lane), lanesOnly (lanes + connections only, no geometry)
function findVehicleRoute(x1, y1, z1, x2, y2, z2, opts)
    local r, why = Nav.vehicleRoute(x1, y1, z1, x2, y2, z2, opts)
    if not r then return false, why end
    return r
end

-- ped route: sidewalks / crossings / paths of the ped graph + open terrain. opts: role ("civilian" | "emergency" |
-- "police" | "hiker" | "free"), gridOnly, graphOnly
function findPedRoute(x1, y1, z1, x2, y2, z2, opts)
    local r, why = Nav.pedRoute(x1, y1, z1, x2, y2, z2, opts)
    if not r then return false, why end
    return r
end

function findBoatRoute(x1, y1, z1, x2, y2, z2)
    local r, why = Nav.boatRoute(x1, y1, z1, x2, y2, z2)
    if not r then return false, why end
    return r
end

-- GPS route for v_radar: car route with turn instructions and the v_radar vehiclenodes ids
function findGpsRoute(x1, y1, z1, x2, y2, z2, opts)
    opts = opts or {}
    opts.profile = opts.profile or "gps"
    opts.gpsNodes = true
    return findVehicleRoute(x1, y1, z1, x2, y2, z2, opts)
end

-- async variant of the above (time-sliced): kind = "vehicle" | "ped" | "boat" | "gps"; returns a job id, the answer
-- comes as onNavmeshRouteReady(id, result|false, reason) on the calling resource's root element
function requestRoute(kind, x1, y1, z1, x2, y2, z2, opts)
    local fn = kind == "ped" and Nav.pedRoute or kind == "boat" and Nav.boatRoute or Nav.vehicleRoute
    if kind == "gps" then
        opts = opts or {}
        opts.profile = opts.profile or "gps"
        opts.gpsNodes = true
    end
    local target = sourceResourceRoot or resourceRoot
    return Nav.startJob(target, fn, x1, y1, z1, x2, y2, z2, opts)
end

------------------------------------------------------------------------ queries: roads

local function laneInfo(id)
    if not Roads.alink[id] then return false end
    local R = Roads
    local k = R.alink[id]
    local nxt = {}
    for _, c in ipairs(R.anext[id]) do
        nxt[#nxt + 1] = { lane = R.cto[c], connection = c, turn = R.cturn[c], signal = R.csig[c], vmax = R.cvmax[c],
            length = R.clen[c], node = R.cnode[c] }
    end
    return {
        id = id, link = k, class = NAV_CLASS_NAME[R.kclass[k]], from = R.afrom[id], to = R.ato[id],
        index = R.aidx[id], count = R.acount[id], left = R.aleft[id] or false, right = R.aright[id] or false,
        oneway = R.kab[k] == 0 or R.kba[k] == 0, unpaved = bitAnd(R.kfl[k], NAV_KF.UNPAVED) ~= 0,
        emergencyOnly = bitAnd(R.kfl[k], NAV_KF.EMERGENCY) ~= 0, trap = bitAnd(R.afl[id], NAV_LF.TRAP) ~= 0,
        speed = Roads.laneSpeed(id), length = R.alen[id], heading = Roads.laneHeading(id),
        start = { R.ax1[id], R.ay1[id], R.az1[id] }, finish = { R.ax2[id], R.ay2[id], R.az2[id] }, next = nxt,
    }
end

function getLaneInfo(id) return laneInfo(tonumber(id)) end

-- nearest lane(s) to a point. opts: radius, heading, headingTolerance, maxZ, skipTrap, count (1)
function getNearestLanes(x, y, z, opts)
    if not Roads.ready then return false end
    opts = opts or {}
    local res = Roads.nearestLanes(x, y, z, opts)
    local out = {}
    for i = 1, math.min(#res, opts.count or 1) do
        local info = laneInfo(res[i][1])
        info.distance = res[i][2]
        info.u = res[i][3]
        info.x, info.y, info.z = Roads.lanePoint(res[i][1], res[i][3])
        out[#out + 1] = info
    end
    return out
end

function getNearestLane(x, y, z, opts)
    local r = getNearestLanes(x, y, z, opts)
    return r and r[1] or false
end

function getLanePoint(id, u)
    if not Roads.alink[id] then return false end
    return Roads.lanePoint(id, math.max(0, math.min(1, u or 0)))
end

function getConnectionPoints(c)
    if not Roads.cfrom[c] then return false end
    return Roads.connPoints(c)
end

function getSignalGroup(id)
    local R = Roads
    if not R.sx[id] then return false end
    return { id = id, x = R.sx[id], y = R.sy[id], z = R.sz[id], phases = R.sphases[id], nodes = R.snodes[id] }
end

------------------------------------------------------------------------ queries: peds / terrain

-- walkable floor near (x, y, z): z, info {surface, road, crossing, pedPath, edge, steep, layer} or false
function getWalkableGround(x, y, z, maxDz)
    local gz, f, l = Walk.ground(x, y, z, maxDz)
    if not gz then return false end
    return gz, {
        surface = NAV_WALK_CLASS_NAME[bitAnd(f, 7)], road = bitAnd(f, NAV_WF.ROAD) ~= 0, crossing = bitAnd(f, NAV_WF.CROSS) ~= 0,
        pedPath = bitAnd(f, NAV_WF.PED) ~= 0, edge = bitAnd(f, NAV_WF.EDGE) ~= 0, steep = bitAnd(f, NAV_WF.STEEP) ~= 0, layer = l,
    }
end

function isWalkable(x, y, z, maxDz)
    return Walk.ground(x, y, z, maxDz or 1.5) ~= nil
end

-- nearest ped path point: x, y, z, info {edge, kind, width} or false
function getNearestPedPath(x, y, z, radius)
    if not Peds.ready then return false end
    local e, d, u, px, py, pz = Peds.nearestEdge(x, y, z, radius)
    if not e then return false end
    return px, py, pz, { edge = e, kind = NAV_PED_KIND_NAME[Peds.ekind[e]], distance = d,
        width = math.min(Peds.nw[Peds.ea[e]], Peds.nw[Peds.eb[e]]), group = Peds.egroup[e], phase = Peds.ephase[e] }
end

-- wandering: points of a random walk of about `length` metres from the nearest ped node
function getPedRandomWalk(x, y, z, length, role)
    if not Peds.ready then return false end
    local near = Peds.nearestNodes(x, y, z, 60, 1, 6)
    if not near[1] then return false end
    local nodes, edges, dist = Peds.randomWalk(near[1][1], length or 100, NAV.PED[role or "civilian"])
    local pts, crossings = {}, {}
    for i, n in ipairs(nodes) do
        pts[#pts + 1] = { Peds.nx[n], Peds.ny[n], Peds.nz[n] }
        local e = edges[i - 1]
        if e and Peds.ekind[e] >= NAV_PED_KIND.CROSSING then
            crossings[#crossings + 1] = { index = i - 1, light = Peds.ekind[e] == NAV_PED_KIND.LIT, group = Peds.egroup[e], phase = Peds.ephase[e] }
        end
    end
    return { points = pts, crossings = crossings, length = dist }
end

function isCrossingOpen(phase)
    return Nav.isCrossingOpen(tonumber(phase))
end

function getNavmeshStats()
    return {
        roads = { ready = Roads.ready, signature = Roads.signature, nodes = Roads.nodeCount, links = Roads.linkCount, lanes = Roads.laneCount,
                  connections = Roads.connCount, signalGroups = Roads.groupCount },
        peds = { ready = Peds.ready, nodes = Peds.nodeCount, edges = Peds.edgeCount },
        boats = { ready = Boats.ready, nodes = Boats.nodeCount, edges = #Boats.edges },
        walk = { ready = Walk.ready, cachedTiles = Walk.cached, tileReads = Walk.reads },
        jobs = (function() local n = 0 for _ in pairs(Nav.jobs) do n = n + 1 end return n end)(),
    }
end
