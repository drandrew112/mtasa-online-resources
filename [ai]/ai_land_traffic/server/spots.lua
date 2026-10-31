-- Spots (server): helpers for scripts that bring vehicles into the world unseen and predict where a vehicle goes
-- (police AI, tow trucks, ambulances). Exports:
--   findHiddenRoadSpawn(x, y, z, opts)  -> x, y, z, rot | false   a road point no player camera sees
--   isElementSeenByPlayers(el)          -> bool                   any player camera looks at it (no fresh report = yes)
--   predictRoadPath(x, y, z, rot, len)  -> { {x, y, z}, ... }     the road ahead, straight on where possible
--   getTrafficVehiclePose(veh)          -> x, y, z, speed | false  the simulated pose of a traffic vehicle (the server
--                                                                  element position is only refreshed every few s)
-- Police AI has priority over the random traffic: a spawn with opts.priority makes room in a full area by removing a
-- civilian vehicle nobody sees.

Spots = {}

local T = TRAFFIC
local sqrt, random, deg, atan2, max, min, floor = math.sqrt, math.random, math.deg, math.atan2, math.max, math.min, math.floor

local function nearestPlayer2(x, y)
    local best = math.huge
    for _, p in ipairs(Traffic.players) do
        local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
        if d < best then best = d end
    end
    return best
end

-- room for a priority spawn: in a full area one civilian vehicle that no camera sees goes
function Spots.makeRoom(x, y, now)
    local list = Agents.near(x, y, T.SIM_RADIUS, {})
    if #list < T.MAX_PER_PLAYER * 0.75 then return end
    local cull2 = T.CULL_MIN_DIST * T.CULL_MIN_DIST
    for _, ag in ipairs(list) do
        if not ag.script and not ag.held and nearestPlayer2(ag.x, ag.y) > cull2
            and not Views.anySees(Traffic.players, ag.x, ag.y, ag.z + 1, now) then
            Agents.destroy(ag)
            return
        end
    end
end

-- opts: minDist (180), maxDist (400) from (x, y, z); playerDist (min distance from every player, default 120);
-- toward = element or {x, y}: the lane must lead towards it (default: the given point); priority (make room)
function findHiddenRoadSpawn(x, y, z, opts)
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
    if not x or not y or not Net.ready then return false end
    opts = type(opts) == "table" and opts or {}
    local minD, maxD = tonumber(opts.minDist) or 180, tonumber(opts.maxDist) or 400
    local pmin2 = (tonumber(opts.playerDist) or 120) ^ 2
    local tx, ty = x, y
    if isElement(opts.toward) then tx, ty = getElementPosition(opts.toward)
    elseif type(opts.toward) == "table" then tx, ty = tonumber(opts.toward[1]) or x, tonumber(opts.toward[2]) or y end
    local now = getTickCount()
    local cells = Net.cellsAround(x, y, maxD)
    if #cells == 0 then return false end
    for _ = 1, T.HIDDEN_SPAWN_TRIES do
        local cell = cells[random(#cells)]
        local lanes = cell.lanes
        if lanes and #lanes > 0 then
            local id = lanes[random(#lanes)]
            local len = Geo.length(id)
            if len > 6 then
                local s = 3 + random() * (len - 6)
                local px, py, pz, fx, fy, fz = Geo.pose(id, s, 0)
                if px then
                    local d = sqrt((px - x) ^ 2 + (py - y) ^ 2)
                    if d >= minD and d <= maxD and nearestPlayer2(px, py) >= pmin2
                        and (tx - px) * fx + (ty - py) * fy > 0
                        and not Views.anySees(Traffic.players, px, py, pz + 1, now) then
                        if opts.priority then Spots.makeRoom(px, py, now) end
                        local _, _, rz = Geo.rotation(fx, fy, fz)
                        return px, py, pz, rz
                    end
                end
            end
        end
    end
    return false
end

function getTrafficVehiclePose(veh)
    local ag = isElement(veh) and Agents.byVeh[veh]
    if not ag or not Agents.list[ag.id] then return false end
    return ag.x, ag.y, ag.z, ag.v
end

function isElementSeenByPlayers(el)
    if not isElement(el) then return false end
    local x, y, z = getElementPosition(el)
    return Views.anySees(Traffic.players, x, y, z + 1, getTickCount())
end

-- the road ahead of a vehicle at (x, y, z) facing rot (degrees): points every ~20 m for `len` metres, straight on
-- at junctions where possible (else the first non u-turn exit). false = no lane there.
function predictRoadPath(x, y, z, rot, len)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z or not Navmesh.ok then return false end
    local lane, s = Navmesh.laneAt(x, y, z, tonumber(rot) or 0)
    if not lane then return false end
    len = min(tonumber(len) or 400, 1200)
    local pts, d, code, pos = {}, 0, lane, s or 0
    for _ = 1, 80 do
        local segLen = Geo.length(code)
        while pos < segLen and d < len do
            pos = min(segLen, pos + 20)
            d = d + 20
            local px, py, pz = Geo.pose(code, pos, 0)
            if px then pts[#pts + 1] = { px, py, pz } end
        end
        if d >= len then break end
        pos = 0
        if code < 0 then
            code = Net.cto[-code]
        else
            local nexts, pick = Net.lnext[code], nil
            if not nexts then break end
            for _, c in ipairs(nexts) do if Net.cturn[c] == "S" then pick = c; break end end
            if not pick then for _, c in ipairs(nexts) do if Net.cturn[c] ~= "U" then pick = c; break end end end
            if not pick then break end
            code = Geo.isCurve(pick) and -pick or Net.cto[pick]
        end
        if not code then break end
    end
    return pts
end
