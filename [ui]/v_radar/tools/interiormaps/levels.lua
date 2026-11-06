-- params X0,Y0,X1,Y1,STEP,ZTOP,ZBOT ; returns rows of space-separated per-point indoor floor z lists "z1/z2"
local rows = {}
for y = Y1, Y0, -STEP do
	local row = {}
	for x = X0, X1, STEP do
		local z, n, list = ZTOP, 0, {}
		while z > ZBOT and n < 30 do
			n = n + 1
			local hit, hx, hy, hz, el, nx, ny, nz = processLineOfSight(x, y, z, x, y, ZBOT, true, false, false, true, false, true, false, false)
			if not hit then break end
			if nz and nz > 0.7 and processLineOfSight(x, y, hz + 0.5, x, y, hz + 6, true, false, false, true, false, true, false, false) then
				list[#list + 1] = string.format("%.1f", hz)
			end
			z = hz - 0.05
		end
		row[#row + 1] = table.concat(list, "/")
	end
	rows[#rows + 1] = table.concat(row, " ")
end
return rows
