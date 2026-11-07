-- tools/probe_walk/scan.mjs runs this on the probe client per strip of rows. Floors: every surface of a vertical
-- column (|normal z| >= cos 50, both windings: custom models have flipped faces) with 1.75 m clearance and no obstacle
-- above step height 0.3 m around the centre; walls: rays between neighbour centres at 0.6 / 1.3 m over the floors.
-- params prepended: X0, Y0 (world, integer), NX, NY (cells), ZTOP, ZBOT, DOORS (bool: toggle door collisions)
local pLOS = processLineOfSight
local floor = math.floor
local WALK_NZ, STEP, CLEAR = 0.6428, 0.55, 1.75
local function ray(x1, y1, z1, x2, y2, z2)
    return pLOS(x1, y1, z1, x2, y2, z2, true, false, false, true, false, false, false, false, nil, false)
end
if DOORS ~= nil then
    local models = { [1491] = true, [1536] = true, [3051] = true, [2911] = true, [1495] = true, [1504] = true, [1505] = true,
        [1506] = true, [1507] = true, [1522] = true, [1523] = true, [1532] = true, [1535] = true, [1537] = true, [1555] = true, [1556] = true, [1557] = true }
    local n = 0
    for _, o in ipairs(getElementsByType("object")) do
        if models[getElementModel(o)] then setElementCollisionsEnabled(o, not DOORS); n = n + 1 end
    end
    return n
end
-- columns: col[row][i] = { {z, nz, mat}, ... } top first
local cols = {}
local function column(x, y)
    local hits, z = {}, ZTOP
    for _ = 1, 14 do
        local h, hx, hy, hz, el, nx, ny, nz, mat = ray(x, y, z, x, y, ZBOT)
        if not h then break end
        hits[#hits + 1] = { hz, nz, mat or 0 }
        z = hz - 0.03
    end
    return hits
end
for r = 0, NY do
    local row = {}
    for i = 0, NX - 1 do row[i] = column(X0 + i + 0.5, Y0 + r + 0.5) end
    cols[r] = row
end
-- candidate floors per cell (rows 0..NY), after clearance + in-cell checks
local floors = {}
local function cellFloors(r, i)
    local key = r * 10000 + i
    if floors[key] then return floors[key] end
    local res = {}
    local col = cols[r] and cols[r][i]
    if col then
        local cx, cy = X0 + i + 0.5, Y0 + r + 0.5
        local lastZ
        for _, hit in ipairs(col) do
            local fz, nz = hit[1], math.abs(hit[2])
            -- the same surface hit twice (double-sided / stacked faces): keep the top one
            if nz >= WALK_NZ and not (lastZ and lastZ - fz < 0.3) then
                local ok = not ray(cx, cy, fz + 0.05, cx, cy, fz + CLEAR)
                if ok then
                    -- obstacles above step height around the centre (inset 0.3: tables, beds, counters)
                    local C = { { -0.3, -0.3 }, { 0.3, -0.3 }, { 0.3, 0.3 }, { -0.3, 0.3 } }
                    for k = 1, 4 do
                        local px, py = cx + C[k][1], cy + C[k][2]
                        local h, _, _, hz = ray(px, py, fz + 1.6, px, py, fz - 0.6)
                        if h and hz > fz + STEP then ok = false; break end
                    end
                end
                if ok then res[#res + 1] = { fz, hit[3], nz } end
            end
            lastZ = fz
        end
    end
    floors[key] = res
    return res
end
local out, blocks = {}, {}
local function nearFloor(list, z)
    local best, bd
    for _, f in ipairs(list) do
        local d = math.abs(f[1] - z)
        if d <= STEP and (not bd or d < bd) then best, bd = f, d end
    end
    return best
end
for r = 0, NY - 1 do
    local line = {}
    for i = 0, NX - 1 do
        local cx, cy = X0 + i + 0.5, Y0 + r + 0.5
        for _, f in ipairs(cellFloors(r, i)) do
            line[#line + 1] = ("%d:%d:%d:%d"):format(i, floor(f[1] * 10 + 0.5), f[2], floor(math.abs(f[3]) * 100))
            -- links east (i+1) and north (r+1)
            for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
                local ni, nr = i + d[1], r + d[2]
                if ni < NX and nr <= NY then
                    local nf = nearFloor(cellFloors(nr, ni), f[1])
                    if nf then
                        for _, hh in ipairs({ 0.6, 1.3 }) do
                            local h, hx, hy = ray(cx, cy, f[1] + hh, cx + d[1], cy + d[2], nf[1] + hh)
                            if h then
                                local t = d[1] == 1 and (hx - cx) or (hy - cy)
                                blocks[#blocks + 1] = ("%d:%d:%d:%d:%d:%d"):format(i, r, floor(f[1] * 10 + 0.5), d[1] == 1 and 1 or 2,
                                    floor(nf[1] * 10 + 0.5), floor(t * 100 + 0.5))
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    out[#out + 1] = table.concat(line, " ")
end
return table.concat(blocks, " "), unpack(out)
