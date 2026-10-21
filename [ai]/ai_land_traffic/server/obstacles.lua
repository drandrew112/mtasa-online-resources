-- Non-traffic obstacles (server): players, their vehicles, other vehicles and peds near players.
-- Rebuilt a few times a second into a spatial hash the simulation queries.
--
-- obstacle = { el, x, y, z, vx, vy (m/s), hw, hl (half width / length), fx, fy (heading, vehicles), player (bool), els (bool) }

Obstacles = { hash = {}, CELL = 40 }

local O = Obstacles
local floor = math.floor
local sin, cos, rad = math.sin, math.cos, math.rad
local GROUP = 30                            -- players this close share one scan...
local RANGE = TRAFFIC.DESPAWN_RADIUS + GROUP   -- ...so the radius covers the traffic of every member
local sizeByModel = {}

-- half width / half length from the model's bounding box (default when the server cannot tell)
local function vehicleSize(veh)
    local model = getElementModel(veh)
    local sz = sizeByModel[model]
    if not sz then
        sz = { 1.25, 2.7 }
        local ok, x1, y1, _, x2, y2 = pcall(getElementBoundingBox, veh)
        if ok and x1 then sz = { math.max(1, (x2 - x1) / 2), math.max(2, (y2 - y1) / 2) } end
        sizeByModel[model] = sz
    end
    return sz[1], sz[2]
end

local function add(hash, seen, el, isPlayerish)
    if seen[el] then return end
    seen[el] = true
    local x, y, z = getElementPosition(el)
    local vx, vy = getElementVelocity(el)
    local o = { el = el, x = x, y = y, z = z, vx = (vx or 0) * 50, vy = (vy or 0) * 50, player = isPlayerish }
    if getElementType(el) == "vehicle" then
        o.hw, o.hl = vehicleSize(el)
        local _, _, rz = getElementRotation(el)
        o.fx, o.fy = -sin(rad(rz)), cos(rad(rz))
        o.els = Els.active[el] == true   -- kept up to date from onElementDataChange (els.lua)
    else
        o.hw, o.hl = 0.45, 0.45
    end
    local key = floor(x / O.CELL) * 10000 + floor(y / O.CELL)
    local b = hash[key]
    if not b then b = {}; hash[key] = b end
    b[#b + 1] = o
end

-- everything non-traffic within RANGE of a point
local function scan(hash, seen, x, y, z)
    for _, v in ipairs(getElementsWithinRange(x, y, z, RANGE, "vehicle", 0, 0)) do
        if not Agents.byVeh[v] and not seen[v] then
            local driver = getVehicleOccupant(v, 0)
            add(hash, seen, v, driver and getElementType(driver) == "player")
        end
    end
    for _, ped in ipairs(getElementsWithinRange(x, y, z, RANGE, "ped", 0, 0)) do
        if not Agents.byPed[ped] and not seen[ped] and not getPedOccupiedVehicle(ped) then
            add(hash, seen, ped, false)
        end
    end
    for _, pl in ipairs(getElementsWithinRange(x, y, z, RANGE, "player", 0, 0)) do
        if not seen[pl] and not getPedOccupiedVehicle(pl) then add(hash, seen, pl, true) end
    end
end

-- players: { { el, x, y, z }, ... } (active players from Traffic.activePlayers)
-- A player within GROUP of one already scanned shares its area queries (RANGE covers the margin).
function Obstacles.rebuild(players)
    local hash, seen, scanned = {}, {}, {}
    for _, p in ipairs(players) do
        local veh = getPedOccupiedVehicle(p.el)
        if veh then
            if not Agents.byVeh[veh] then add(hash, seen, veh, true) end
        else
            add(hash, seen, p.el, true)
        end
        local covered = false
        for i = 1, #scanned do
            local q = scanned[i]
            if (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 + (q.z - p.z) ^ 2 <= GROUP * GROUP then covered = true; break end
        end
        if not covered then
            scanned[#scanned + 1] = p
            scan(hash, seen, p.x, p.y, p.z)
        end
    end
    O.hash = hash
end

function Obstacles.near(x, y, r, out)
    out = out or {}
    local cell = O.CELL
    for cx = floor((x - r) / cell), floor((x + r) / cell) do
        for cy = floor((y - r) / cell), floor((y + r) / cell) do
            local b = O.hash[cx * 10000 + cy]
            if b then
                for i = 1, #b do out[#out + 1] = b[i] end
            end
        end
    end
    return out
end
