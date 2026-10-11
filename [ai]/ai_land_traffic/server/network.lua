-- Road topology for the simulation (server): data/runtime/sim.dat + the shared geometry.

Net = {
    -- lanes
    llink = {}, lflags = {}, lcount = {}, lindex = {}, lnext = {}, lspeed = {},
    -- connections
    cfrom = {}, cto = {}, cnode = {}, cturn = {}, cvmax = {}, cphase = {}, cgroup = {}, cconf = {}, cyield = {},
    -- spawn grid: [cell] = { lanes = {id...}, length = total }
    grid = {}, CELL = 100,
    ready = false,
}

local N = Net
local tonumber, floor = tonumber, math.floor

local function list(s)
    if s == "-" then return nil end
    local t = {}
    for v in s:gmatch("%d+") do t[#t + 1] = tonumber(v) end
    return t
end

local function laneSpeed(fl)
    if bitAnd(fl, LF_PARKING) ~= 0 then return TRAFFIC.SPEED_PARKING end
    if bitAnd(fl, LF_HIGHWAY) ~= 0 then return TRAFFIC.SPEED_HIGHWAY end
    if bitAnd(fl, LF_UNPAVED) ~= 0 or bitAnd(fl, LF_EMERGENCY) ~= 0 then return TRAFFIC.SPEED_UNPAVED end
    return TRAFFIC.SPEED_ROAD
end

function Net.cellOf(x, y)
    return floor(x / N.CELL) * 10000 + floor(y / N.CELL)
end

local function buildGrid()
    local cell = N.CELL
    for id, len in pairs(Geo.llen) do
        local fl = N.lflags[id] or 0
        local spawnable = len >= 6 and bitAnd(fl, LF_PARKING + LF_ROADBLOCK + LF_TRAP) == 0
            and bitAnd(fl, LF_EMERGENCY) == 0
        if spawnable then
            local mx, my = (Geo.lx1[id] + Geo.lx2[id]) / 2, (Geo.ly1[id] + Geo.ly2[id]) / 2
            local key = floor(mx / cell) * 10000 + floor(my / cell)
            local c = N.grid[key]
            if not c then c = { lanes = {}, length = 0 }; N.grid[key] = c end
            c.lanes[#c.lanes + 1] = id
            c.length = c.length + len * (bitAnd(fl, LF_UNPAVED) ~= 0 and TRAFFIC.WEIGHT_UNPAVED or 1)
        end
    end
end

function Net.load()
    local t0 = getTickCount()
    local geo = Geo.readFile(TRAFFIC.GEO_FILE)
    local sim = Geo.readFile(TRAFFIC.SIM_FILE)
    if not geo or not sim then
        outputDebugString("[ai_land_traffic] missing runtime data, run tools/build_runtime.py", 1)
        return false
    end
    Geo.parse(geo)
    for line in sim:gmatch("[^\n]+") do
        local kind = line:sub(1, 1)
        if kind == "L" then
            local id, link, fl, count, index, nxt = line:match("^L (%d+) (%d+) (%d+) (%d+) (%d+) (%S+)")
            id = tonumber(id)
            if id then
                fl = tonumber(fl)
                N.llink[id], N.lflags[id] = tonumber(link), fl
                N.lcount[id], N.lindex[id] = tonumber(count), tonumber(index)
                N.lnext[id] = list(nxt)
                N.lspeed[id] = laneSpeed(fl)
            end
        elseif kind == "C" then
            local id, f, e, node, turn, _, vmax, phase, group, conf, yld =
                line:match("^C (%d+) (%d+) (%d+) (%d+) (%a) (%S+) (%S+) (%d+) (%d+) (%S+) (%S+)")
            id = tonumber(id)
            if id then
                N.cfrom[id], N.cto[id], N.cnode[id], N.cturn[id] = tonumber(f), tonumber(e), tonumber(node), turn
                local v = tonumber(vmax)
                N.cvmax[id] = (v and v > 0) and v or nil
                N.cphase[id], N.cgroup[id] = tonumber(phase), tonumber(group)
                N.cconf[id], N.cyield[id] = list(conf), list(yld)
            end
        end
    end
    buildGrid()
    N.ready = true
    outputDebugString(string.format("[ai_land_traffic] network loaded: %d lanes, %d curves (%d ms)",
        Geo.lanes, Geo.curves, getTickCount() - t0))
    return true
end

-- spawn candidates: cells overlapping the circle
function Net.cellsAround(x, y, r)
    local out = {}
    local cell = N.CELL
    local cx0, cx1 = floor((x - r) / cell), floor((x + r) / cell)
    local cy0, cy1 = floor((y - r) / cell), floor((y + r) / cell)
    for cx = cx0, cx1 do
        for cy = cy0, cy1 do
            local c = N.grid[cx * 10000 + cy]
            if c then
                local mx, my = (cx + 0.5) * cell, (cy + 0.5) * cell
                if (mx - x) ^ 2 + (my - y) ^ 2 <= (r + cell * 0.71) ^ 2 then out[#out + 1] = c end
            end
        end
    end
    return out
end
