-- Open-terrain walk grid (data/runtime/walk.nav, tools/walkgrid.js): 1 m cells, up to 4 floor levels per cell,
-- read per 32x32 m tile on demand (zlib, LRU cache). Grid A* with the ped role costs of NAV.PED.

Walk = { ready = false, tiles = {}, lru = {}, cached = 0, reads = 0 }
local W = Walk
local floor, sqrt, abs, huge = math.floor, math.sqrt, math.abs, math.huge
local NONE = -32768
local bitAnd = bitAnd

function Walk.load()
    local f = fileOpen(NAV.WALK_FILE, true)
    if not f then
        outputDebugString("[navmesh] missing " .. NAV.WALK_FILE .. ", run tools/walkgrid.js", 1)
        return false
    end
    local h = fileRead(f, 24)
    if h:sub(1, 4) ~= "NAVW" then
        fileClose(f)
        outputDebugString("[navmesh] " .. NAV.WALK_FILE .. " is not a walk grid", 1)
        return false
    end
    local b = { h:byte(1, 24) }
    local function u16(i) return b[i] + b[i + 1] * 256 end
    local function i32(i)
        local v = b[i] + b[i + 1] * 256 + b[i + 2] * 65536 + b[i + 3] * 16777216
        if v >= 2147483648 then v = v - 4294967296 end
        return v
    end
    W.version = u16(5)
    if W.version ~= 2 then
        fileClose(f)
        outputDebugString("[navmesh] walk.nav version " .. W.version .. " not supported (need 2)", 1)
        return false
    end
    W.TILE = u16(7)
    W.CS = 1.0
    W.OX, W.OY = i32(13), i32(17)
    W.TX, W.TY = u16(21), u16(23)
    W.CELLS_X = W.TX * W.TILE
    W.index = fileRead(f, W.TX * W.TY * 8)
    W.file = f
    -- zlib support check (MTA 1.6.1 r23219+)
    local ok = pcall(decodeString, "zlib", encodeString("zlib", "navmesh", { format = "zlib" }), { format = "zlib" })
    if not ok then
        outputDebugString("[navmesh] decodeString zlib is not available (needs MTA 1.6.1 r23219+): walk grid disabled", 1)
        fileClose(f); W.file = nil
        return false
    end
    W.ready = true
    outputDebugString(("[navmesh] walk grid: %dx%d tiles of %d m"):format(W.TX, W.TY, W.TILE))
    return true
end

local function u32at(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

-- decoded tile { L = layers, z = {dm...} (1-based, layer * 1024 + cell + 1), f = {flags...} } or false
local function decode(tx, ty)
    local k = ty * W.TX + tx
    local off = u32at(W.index, k * 8 + 1)
    if off == 0 then return false end
    local len = u32at(W.index, k * 8 + 5)
    fileSetPos(W.file, off)
    local raw = decodeString("zlib", fileRead(W.file, len), { format = "zlib" })
    if not raw then return false end
    W.reads = W.reads + 1
    local L = raw:byte(1)
    local n = L * 1024
    local lo, hi = { raw:byte(2, 1 + n) }, { raw:byte(2 + n, 1 + 2 * n) }
    local fl = { raw:byte(2 + 2 * n, 1 + 3 * n) }
    local z = {}
    for l = 0, L - 1 do
        local prev = NONE
        for c = 1, 1024 do
            local i = l * 1024 + c
            local v = lo[i] + hi[i] * 256
            if v >= 32768 then v = v - 65536 end
            local zz
            if prev == NONE then zz = v elseif v == NONE then zz = NONE else zz = prev + v end
            z[i] = zz
            prev = zz
        end
    end
    return { L = L, z = z, f = fl }
end

local tick = 0
function Walk.tile(tx, ty)
    if tx < 0 or ty < 0 or tx >= W.TX or ty >= W.TY then return false end
    local k = ty * W.TX + tx
    local t = W.tiles[k]
    tick = tick + 1
    if t ~= nil then
        W.lru[k] = tick
        return t
    end
    t = decode(tx, ty)
    W.tiles[k] = t
    W.lru[k] = tick
    W.cached = W.cached + 1
    if W.cached > NAV.WALK_CACHE_TILES then
        -- drop the oldest quarter
        local ages = {}
        for key, age in pairs(W.lru) do ages[#ages + 1] = { key, age } end
        table.sort(ages, function(a, b) return a[2] < b[2] end)
        for i = 1, floor(#ages / 4) do
            W.tiles[ages[i][1]] = nil
            W.lru[ages[i][1]] = nil
        end
        W.cached = #ages - floor(#ages / 4)
    end
    return t
end

function Walk.cellOf(x, y)
    return floor(x - W.OX), floor(y - W.OY)
end

function Walk.cellCenter(gx, gy)
    return W.OX + gx + 0.5, W.OY + gy + 0.5
end

-- tile + 1-based cell index of a global cell
local function at(gx, gy)
    local TILE = W.TILE
    local t = Walk.tile(floor(gx / TILE), floor(gy / TILE))
    if not t then return nil end
    return t, (gy % TILE) * TILE + (gx % TILE) + 1
end
Walk.at = at

-- floors of a cell: { {z (m), flags, layer}, ... }
function Walk.floors(gx, gy)
    local t, c = at(gx, gy)
    local res = {}
    if not t then return res end
    for l = 0, t.L - 1 do
        local z = t.z[l * 1024 + c]
        if z ~= NONE then res[#res + 1] = { z / 10, t.f[l * 1024 + c], l } end
    end
    return res
end

-- layer of the cell nearest to zdm (decimetres) within tol (dm); returns layer, z dm, flags
local function layerNear(t, c, zdm, tol)
    local best, bd, bz, bf = nil, tol, nil, nil
    for l = 0, t.L - 1 do
        local z = t.z[l * 1024 + c]
        if z ~= NONE then
            local d = abs(z - zdm)
            if d <= bd then best, bd, bz, bf = l, d, z, t.f[l * 1024 + c] end
        end
    end
    return best, bz, bf
end

-- walkable floor at a world point: z (m), flags, layer; prefers the floor nearest to z (within maxDz, default 3)
function Walk.ground(x, y, z, maxDz)
    if not W.ready then return nil end
    local gx, gy = Walk.cellOf(x, y)
    local t, c = at(gx, gy)
    if not t then return nil end
    if not z then
        local top, tf, tl = nil, nil, nil
        for l = 0, t.L - 1 do
            local zz = t.z[l * 1024 + c]
            if zz ~= NONE and (not top or zz > top) then top, tf, tl = zz, t.f[l * 1024 + c], l end
        end
        if not top then return nil end
        return top / 10, tf, tl
    end
    local l, zz, f = layerNear(t, c, z * 10, (maxDz or 3) * 10)
    if not l then return nil end
    return zz / 10, f, l
end

-- nearest walkable cell (spiral up to r cells) to a point: gx, gy, layer, zdm
function Walk.nearestCell(x, y, z, r, maxDz)
    if not z then z = Walk.ground(x, y) or 0; maxDz = maxDz or 3 end
    local gx0, gy0 = Walk.cellOf(x, y)
    local zdm, tol = z * 10, (maxDz or 3) * 10
    for ring = 0, r or 6 do
        local best, bd
        for dy = -ring, ring do
            for dx = -ring, ring do
                if math.max(abs(dx), abs(dy)) == ring then
                    local t, c = at(gx0 + dx, gy0 + dy)
                    if t then
                        local l, zz = layerNear(t, c, zdm, tol)
                        if l then
                            local d = dx * dx + dy * dy + ((zz - zdm) / 10) ^ 2
                            if not bd or d < bd then best, bd = { gx0 + dx, gy0 + dy, l, zz }, d end
                        end
                    end
                end
            end
        end
        if best then return best[1], best[2], best[3], best[4] end
    end
    return nil
end

------------------------------------------------------------------------ costs

-- cost per metre of a cell for a role (NAV.PED entry)
local function cellWeightRaw(f, role)
    local w
    if bitAnd(f, NAV_WF.CROSS) ~= 0 then w = role.cross
    elseif bitAnd(f, NAV_WF.ROAD) ~= 0 then w = role.road
    else w = role.class[bitAnd(f, 7) + 1] or role.class[1] end
    if bitAnd(f, NAV_WF.PED) ~= 0 then w = w * role.ped end
    if bitAnd(f, NAV_WF.EDGE) ~= 0 then w = w * role.edge end
    if bitAnd(f, NAV_WF.STEEP) ~= 0 then w = w * role.steep end
    return w
end

-- 256-entry weight table per role (flags byte -> cost per metre), built once
local weightTables = setmetatable({}, { __mode = "k" })
local function weights(role)
    local t = weightTables[role]
    if not t then
        t = {}
        for f = 0, 255 do t[f] = cellWeightRaw(f, role) end
        weightTables[role] = t
    end
    return t
end
local function cellWeight(f, role) return weights(role)[f] end
Walk.cellWeight = cellWeight

local function minWeight(role)
    local m = huge
    for _, v in pairs(weights(role)) do if v < m then m = v end end
    return m
end

------------------------------------------------------------------------ A*

local STEP_DM
local function stepTo(nx, ny, zdm)
    local t, c = at(nx, ny)
    if not t then return nil end
    return layerNear(t, c, zdm, STEP_DM)
end

local DX = { 1, -1, 0, 0, 1, 1, -1, -1 }
local DY = { 0, 0, 1, -1, 1, -1, 1, -1 }
local DL = { 1, 1, 1, 1, 1.41421, 1.41421, 1.41421, 1.41421 }

-- Grid A*. from = {gx, gy, layer, zdm}, goals = { [key] = true } or goal = {gx, gy, layer, zdm}
-- key = (gy * CELLS_X + gx) * 4 + layer
-- opts: role (NAV.PED entry), box = {gx0, gy0, gx1, gy1}, maxNodes, goalPoints = {{gx, gy}, ...} for the heuristic,
--       allGoals (Dijkstra to every key of goals: returns { [key] = {cells, cost} }, expanded)
-- returns cells { {gx, gy, layer, zdm, flags}, ... }, cost, expanded  or nil, reason, expanded
function Walk.search(from, goal, goals, opts)
    if not W.ready then return nil, "no_walk_grid" end
    local XC, TILE, TX = W.CELLS_X, W.TILE, W.TX
    STEP_DM = NAV.WALK_STEP * 10 + 0.01
    local STEP = STEP_DM
    local role = opts.role
    local wt = weights(role)
    local wmin = minWeight(role)
    local box = opts.box or { -huge, -huge, huge, huge }
    local bx0, by0, bx1, by1 = box[1], box[2], box[3], box[4]
    local hp = opts.goalPoints or (goal and { { goal[1], goal[2] } }) or {}
    local nhp = #hp
    local hx, hy = hp[1] and hp[1][1], hp[1] and hp[1][2]
    local allGoals = opts.allGoals
    local remaining = 0
    if allGoals then for _ in pairs(goals) do remaining = remaining + 1 end end
    local found = allGoals and {} or nil
    local goalKey = goal and ((goal[2] * XC + goal[1]) * 4 + goal[3])

    -- tiles of this search (no LRU bookkeeping per cell)
    local tcache = {}
    local function tileOf(tx, ty)
        local k = ty * TX + tx
        local t = tcache[k]
        if t == nil then
            t = Walk.tile(tx, ty) or false
            tcache[k] = t
        end
        return t
    end

    local heap = Heap.new()
    local g, came, closed = {}, {}, {}
    local cz, cf = {}, {}
    local sk = (from[2] * XC + from[1]) * 4 + from[3]
    g[sk] = 0
    cz[sk] = from[4]
    do
        local t = tileOf(floor(from[1] / TILE), floor(from[2] / TILE))
        cf[sk] = t and t.f[from[3] * 1024 + (from[2] % TILE) * TILE + (from[1] % TILE) + 1] or 0
    end
    heap:push(sk, 0)
    local n, maxN = 0, opts.maxNodes or NAV.WALK_MAX_NODES
    local open1, open2, open3, open4
    while heap.n > 0 do
        local k = heap:pop()
        if not closed[k] then
            closed[k] = true
            if allGoals then
                if goals[k] then
                    found[k] = true
                    remaining = remaining - 1
                    if remaining == 0 then break end
                end
            elseif k == goalKey or (goals and goals[k]) then found = k; break end
            n = n + 1
            if n > maxN then
                if allGoals then break end
                return nil, "search_limit", n
            end
            if n % 500 == 0 then Nav.budget() end
            local cell = (k - k % 4) / 4
            local gx = cell % XC
            local gy = (cell - gx) / XC
            local zdm, gk = cz[k], g[k]
            local wHere = wt[cf[k]]
            open1, open2, open3, open4 = false, false, false, false
            for d = 1, 8 do
                local nx, ny = gx + DX[d], gy + DY[d]
                local ok = nx >= bx0 and nx <= bx1 and ny >= by0 and ny <= by1
                if ok and d > 4 then
                    if d == 5 then ok = open1 and open3
                    elseif d == 6 then ok = open1 and open4
                    elseif d == 7 then ok = open2 and open3
                    else ok = open2 and open4 end
                end
                if ok then
                    local t = tileOf((nx - nx % TILE) / TILE, (ny - ny % TILE) / TILE)
                    if t then
                        local c = (ny % TILE) * TILE + (nx % TILE) + 1
                        local tz = t.z
                        local bl, bz, bd = nil, nil, STEP
                        if t.L == 1 then
                            local z = tz[c]
                            if z ~= NONE then
                                local dz = z - zdm
                                if dz < 0 then dz = -dz end
                                if dz <= STEP then bl, bz = 0, z end
                            end
                        else
                            for l = 0, t.L - 1 do
                                local z = tz[l * 1024 + c]
                                if z ~= NONE then
                                    local dz = z - zdm
                                    if dz < 0 then dz = -dz end
                                    if dz <= bd then bl, bz, bd = l, z, dz end
                                end
                            end
                        end
                        if bl then
                            if d == 1 then open1 = true elseif d == 2 then open2 = true
                            elseif d == 3 then open3 = true elseif d == 4 then open4 = true end
                            local nk = (ny * XC + nx) * 4 + bl
                            if not closed[nk] then
                                local nf = t.f[bl * 1024 + c]
                                local dz = (bz - zdm) / 10
                                local len = DL[d]
                                if dz > 0.05 or dz < -0.05 then len = sqrt(len * len + dz * dz) end
                                local ng = gk + len * (wHere + wt[nf]) * 0.5
                                local og = g[nk]
                                if not og or ng < og then
                                    g[nk], came[nk], cz[nk], cf[nk] = ng, k, bz, nf
                                    local hh = 0
                                    if not allGoals then
                                        if nhp == 1 then
                                            local ex, ey = nx - hx, ny - hy
                                            hh = sqrt(ex * ex + ey * ey) * wmin
                                        else
                                            hh = huge
                                            for i = 1, nhp do
                                                local ex, ey = nx - hp[i][1], ny - hp[i][2]
                                                local dd = sqrt(ex * ex + ey * ey)
                                                if dd < hh then hh = dd end
                                            end
                                            hh = hh * wmin
                                        end
                                    end
                                    heap:push(nk, ng + hh)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local function unwind(k)
        local cells = {}
        while k do
            local l = k % 4
            local cell = (k - l) / 4
            local gx = cell % XC
            table.insert(cells, 1, { gx, (cell - gx) / XC, l, cz[k], cf[k] })
            k = came[k]
        end
        return cells
    end
    if allGoals then
        local res = {}
        for k in pairs(found) do res[k] = { unwind(k), g[k] } end
        return res, n
    end
    if not found then return nil, "no_path", n end
    return unwind(found), g[found], n
end

-- line of sight between two cells over walkable floors (Bresenham-like sampling, steps checked),
-- every cell no more expensive than maxW
local function los(a, b, role, maxW)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local steps = math.max(abs(dx), abs(dy)) * 2
    if steps == 0 then return true end
    local zdm = a[4]
    local px, py = a[1], a[2]
    for s = 1, steps do
        local fx, fy = a[1] + 0.5 + dx * s / steps, a[2] + 0.5 + dy * s / steps
        local nx, ny = floor(fx), floor(fy)
        if nx ~= px or ny ~= py then
            -- diagonal move between samples: both orthogonal cells must be open
            if nx ~= px and ny ~= py then
                if not stepTo(nx, py, zdm) or not stepTo(px, ny, zdm) then return false end
            end
            local l, nz, nf = stepTo(nx, ny, zdm)
            if not l or cellWeight(nf, role) > maxW then return false end
            zdm, px, py = nz, nx, ny
        end
    end
    return abs(zdm - b[4]) <= STEP_DM
end

-- string pulling: drop cells that a straight walk can skip without entering more expensive cells
function Walk.smooth(cells, role)
    STEP_DM = NAV.WALK_STEP * 10 + 0.01
    if #cells <= 2 then return cells end
    local out = { cells[1] }
    local i = 1
    while i < #cells do
        local j = math.min(#cells, i + 48)
        local maxW = 0
        for q = i, j do
            local w = cellWeight(cells[q][5] or 0, role)
            if w > maxW then maxW = w end
        end
        while j > i + 1 do
            -- the max weight of the replaced stretch only
            local mw = 0
            for q = i, j do
                local w = cellWeight(cells[q][5] or 0, role)
                if w > mw then mw = w end
            end
            if los(cells[i], cells[j], role, mw * 1.02) then break end
            j = j - 1
        end
        out[#out + 1] = cells[j]
        i = j
    end
    return out
end

-- cells -> world points { {x, y, z}, ... }
function Walk.cellsToPoints(cells, out, kindOut)
    out = out or {}
    for _, c in ipairs(cells) do
        local x, y = Walk.cellCenter(c[1], c[2])
        out[#out + 1] = { x, y, c[4] / 10 }
        if kindOut then kindOut[#kindOut + 1] = "walk" end
    end
    return out
end
