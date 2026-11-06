-- params: X0,Y0,X1,Y1,CELL,ZF,HLOW,HHIGH, SKIP (table model->true)
-- returns {nx, ny, chunks...}: one char per cell, row-major from (X0,Y0) going +x then +y.
-- char = string.char(48 + mask): 1 hit at low height, 2 hit at high height, 4 floor below, 8 ceiling above (<4 m)
local nx = math.floor((X1 - X0) / CELL + 0.5)
local ny = math.floor((Y1 - Y0) / CELL + 0.5)
local grid = {}
for i = 0, nx * ny - 1 do grid[i] = 0 end
local function mark(x, y, bit)
	local cx = math.floor((x - X0) / CELL)
	local cy = math.floor((y - Y0) / CELL)
	if cx >= 0 and cx < nx and cy >= 0 and cy < ny then
		local i = cy * nx + cx
		if grid[i] % (bit * 2) < bit then grid[i] = grid[i] + bit end
	end
end
local function skippable(el)
	if el and isElement(el) and getElementType(el) == "object" then
		return SKIP[getElementModel(el)]
	end
	return false
end
local function march(ax, ay, bx, by, z, bit)
	local dx, dy = bx - ax, by - ay
	local len = math.sqrt(dx * dx + dy * dy)
	dx, dy = dx / len, dy / len
	local sx, sy = ax, ay
	local guard = 0
	while guard < 400 do
		guard = guard + 1
		local hit, hx, hy, hz, el = processLineOfSight(sx, sy, z, bx, by, z, true, false, false, true, false, true, false, false)
		if not hit then return end
		if not skippable(el) then mark(hx + dx * 0.02, hy + dy * 0.02, bit) end
		sx, sy = hx + dx * 0.04, hy + dy * 0.04
		if (bx - sx) * dx + (by - sy) * dy <= 0 then return end
	end
end
for _, hb in ipairs({{ZF + HLOW, 1}, {ZF + HHIGH, 2}}) do
	local z, bit = hb[1], hb[2]
	for cy = 0, ny - 1 do
		local y = Y0 + (cy + 0.5) * CELL
		march(X0 - 0.5, y, X1 + 0.5, y, z, bit)
		march(X1 + 0.5, y, X0 - 0.5, y, z, bit)
	end
	for cx = 0, nx - 1 do
		local x = X0 + (cx + 0.5) * CELL
		march(x, Y0 - 0.5, x, Y1 + 0.5, z, bit)
		march(x, Y1 + 0.5, x, Y0 - 0.5, z, bit)
	end
end
for cy = 0, ny - 1 do
	local y = Y0 + (cy + 0.5) * CELL
	for cx = 0, nx - 1 do
		local x = X0 + (cx + 0.5) * CELL
		if processLineOfSight(x, y, ZF + 0.6, x, y, ZF - 0.5, true, false, false, true, false, true, false, false) then mark(x, y, 4) end
		if processLineOfSight(x, y, ZF + 0.8, x, y, ZF + (CEIL or 4.5), true, false, false, true, false, true, false, false) then mark(x, y, 8) end
	end
end
local parts = {}
for i = 0, nx * ny - 1 do parts[#parts + 1] = string.char(48 + grid[i]) end
local s = table.concat(parts)
local out = {nx, ny}
for i = 1, #s, 30000 do out[#out + 1] = s:sub(i, i + 29999) end
return out
