-- Non-traffic obstacles (server): players, their vehicles, other vehicles and peds near players.
-- Rebuilt a few times a second into a spatial hash the simulation queries.
--
-- obstacle = { el, x, y, z, vx, vy (m/s), hw, hl (half width / length), player (bool), els (bool) }

Obstacles = { hash = {}, CELL = 40 }

local O = Obstacles
local floor = math.floor
local RANGE = 250

local function add(hash, seen, el, isPlayerish)
    if seen[el] then return end
    seen[el] = true
    local x, y, z = getElementPosition(el)
    local vx, vy = getElementVelocity(el)
    local o = { el = el, x = x, y = y, z = z, vx = (vx or 0) * 50, vy = (vy or 0) * 50, player = isPlayerish }
    if getElementType(el) == "vehicle" then
        o.hw, o.hl = 1.25, 2.7
        o.els = getElementData(el, TRAFFIC.ELS_DATA) == true
    else
        o.hw, o.hl = 0.45, 0.45
    end
    local key = floor(x / O.CELL) * 10000 + floor(y / O.CELL)
    local b = hash[key]
    if not b then b = {}; hash[key] = b end
    b[#b + 1] = o
end

-- players: { { el, x, y, z }, ... } (active players from Traffic.activePlayers)
function Obstacles.rebuild(players)
    local hash, seen = {}, {}
    for _, p in ipairs(players) do
        local veh = getPedOccupiedVehicle(p.el)
        if veh then
            if not Agents.byVeh[veh] then add(hash, seen, veh, true) end
        else
            add(hash, seen, p.el, true)
        end
        for _, v in ipairs(getElementsWithinRange(p.x, p.y, p.z, RANGE, "vehicle", 0, 0)) do
            if not Agents.byVeh[v] and not seen[v] then
                local driver = getVehicleOccupant(v, 0)
                add(hash, seen, v, driver and getElementType(driver) == "player")
            end
        end
        for _, ped in ipairs(getElementsWithinRange(p.x, p.y, p.z, RANGE, "ped", 0, 0)) do
            if not Agents.byPed[ped] and not seen[ped] and not getPedOccupiedVehicle(ped) then
                add(hash, seen, ped, false)
            end
        end
        for _, pl in ipairs(getElementsWithinRange(p.x, p.y, p.z, RANGE, "player", 0, 0)) do
            if not seen[pl] and not getPedOccupiedVehicle(pl) then add(hash, seen, pl, true) end
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
