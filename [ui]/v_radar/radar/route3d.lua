-- 3D navigation: the GPS routes drawn on the road surface as a see-through ribbon with moving arrows
-- (waypoint purple, objective yellow).
--
-- The ribbon follows the navmesh route points (lane geometry, radar/gps/sourceC.lua trackers): resampled every
-- STEP metres from the segment the player is on, each sample set onto the ground (line of sight down from the lane
-- height, cached), and drawn with dxDrawMaterialPrimitive3D from just ahead of the player up to DRAW_AHEAD.
-- The texture (radar/files/route_ribbon.png) is white: the vertex colour tints it.
-- Switched on / off with setEnable3DNavigation (radar/sourceC.lua, pause menu setting).

local ROUTE3D = {
	WIDTH = 2.4,          -- ribbon width (m)
	TEX_LENGTH = 4.8,     -- metres per texture tile (one arrow)
	SCROLL_SPEED = 0.45,  -- texture tiles per second, moving forward
	STEP = 2,             -- resample distance (m)
	COVER = 600,          -- metres of route resampled ahead of the player
	DRAW_AHEAD = 220,     -- drawn up to this far along the route...
	START_AHEAD = 1.5,    -- ...starting this far ahead of the player
	FADE_IN = 8,          -- alpha ramp right in front of the player (m)
	FADE_OUT = 60,        -- alpha ramp at the far end (m)
	Z_OFFSET = 0.09,      -- above the ground, against z-fighting
	GROUND_UP = 2.5,      -- ground ray from lane height + this...
	GROUND_DOWN = 4,      -- ...down to lane height - this
	GROUND_RANGE = 250,   -- ground is looked up only this close to the camera (streamed in)
	GROUND_PER_FRAME = 60,-- ground rays per frame at most
	BATCH = 120,          -- samples per draw call
	ALPHA = 230,
}

local sqrt, floor, ceil = math.sqrt, math.floor, math.ceil
local ribbonTexture = false

-- one entry per route channel: { tracker, color {r, g, b}, zBias, built = {...} }
local layers = {}

local function getRibbonTexture()
	if not ribbonTexture then
		ribbonTexture = dxCreateTexture("radar/files/route_ribbon.png", "argb", true, "wrap")
	end
	return ribbonTexture
end

-- samples of the route around the player: { x, y, lz (lane height), s (metres from pts[index]), key (segment, step) }
-- from a bit behind startS (player's distance from pts[index]) to COVER metres ahead of it
local function build(layer, startS, first)
	local t = layer.tracker
	local pts = t.points
	first = first or t.index
	local built = {points = pts, first = first, samples = {}, reachedEnd = false}
	startS = startS or 0

	-- ground heights stay valid for the same route
	if layer.groundFor ~= pts then
		layer.groundFor = pts
		layer.ground = {}
	end

	local samples = built.samples
	local s = 0
	local k = first
	local limit = startS + ROUTE3D.COVER
	while k < #pts and s < limit do
		local a, b = pts[k], pts[k + 1]
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local len = sqrt(dx * dx + dy * dy)
		local n = max(1, ceil(len / ROUTE3D.STEP))
		local cut = false
		for j = 0, n - 1 do
			local f = j / n
			local ss = s + len * f
			if ss > limit then
				cut = true
				break
			end
			if ss >= startS - 10 then
				samples[#samples + 1] = {x = a.x + dx * f, y = a.y + dy * f, lz = a.z + dz * f, s = ss, key = k * 100000 + j}
			end
		end
		if cut then
			break
		end
		s = s + len
		k = k + 1
	end
	if k >= #pts then
		local last = pts[#pts]
		samples[#samples + 1] = {x = last.x, y = last.y, lz = last.z, s = s, key = #pts * 100000}
		built.reachedEnd = true
	end
	built.endS = samples[#samples] and samples[#samples].s or 0

	-- sides: perpendicular to the averaged direction, two vertices per sample (reused every frame)
	local half = ROUTE3D.WIDTH / 2
	for i, p in ipairs(samples) do
		local a = samples[i - 1] or p
		local b = samples[i + 1] or p
		local dx, dy = b.x - a.x, b.y - a.y
		local len = sqrt(dx * dx + dy * dy)
		if len < 0.001 then dx, dy, len = 0, 1, 1 end
		local nx, ny = -dy / len * half, dx / len * half
		p.lx, p.ly, p.rx, p.ry = p.x + nx, p.y + ny, p.x - nx, p.y - ny
		p.vl = {p.lx, p.ly, p.lz, 0, 0, 0}
		p.vr = {p.rx, p.ry, p.lz, 0, 1, 0}
	end

	built.cursor = 1
	layer.built = built
end

-- ground under (x, y) near lane height z, false when nothing is there (not streamed in, bridge gap)
local function groundAt(x, y, z)
	local hit, _, _, hz = processLineOfSight(x, y, z + ROUTE3D.GROUND_UP, x, y, z - ROUTE3D.GROUND_DOWN,
		true, false, false, false, false, true, false, false)
	return hit and hz or false
end

-- distance along the built route of the player's position (searched around the last one)
local function playerDistance(built, x, y, full)
	local samples = built.samples
	local best, bestD, bestS = built.cursor, math.huge, 0
	local i0, i1 = max(1, built.cursor - 4), min(#samples - 1, built.cursor + 40)
	if full then
		i0, i1 = 1, #samples - 1
	end
	for i = i0, i1 do
		local a, b = samples[i], samples[i + 1]
		local dx, dy = b.x - a.x, b.y - a.y
		local l2 = dx * dx + dy * dy
		local f = l2 > 0 and ((x - a.x) * dx + (y - a.y) * dy) / l2 or 0
		if f < 0 then f = 0 elseif f > 1 then f = 1 end
		local qx, qy = x - (a.x + dx * f), y - (a.y + dy * f)
		local d = qx * qx + qy * qy
		if d < bestD then
			best, bestD, bestS = i, d, a.s + (b.s - a.s) * f
		end
	end
	-- far from the window (teleport, respawn): search the whole built part once
	if not full and bestD > 900 then
		return playerDistance(built, x, y, true)
	end
	built.cursor = best
	return bestS
end

local function drawLayer(layer, px, py, camX, camY, now, groundBudget)
	local t = layer.tracker
	if not t.active or not t.points then
		layer.built = false
		return groundBudget
	end

	local built = layer.built
	-- a new route: built from the segment the player is on; after that the samples follow the player themselves
	if not built or built.points ~= t.points then
		-- the player's distance along the current segment (tracker.projT)
		local a, b = t.points[t.index], t.points[t.index + 1]
		local startS = 0
		if a and b and t.projT then
			startS = getDistanceBetweenPoints2D(a.x, a.y, b.x, b.y) * t.projT
		end
		build(layer, startS)
		built = layer.built
	end

	local samples = built.samples
	if #samples < 2 then
		return groundBudget
	end

	local ps = playerDistance(built, px, py)
	-- driving along a long segment: resample before the covered part runs out
	if not built.reachedEnd and ps > built.endS - ROUTE3D.DRAW_AHEAD - 20 then
		build(layer, ps, built.first)
		built = layer.built
		samples = built.samples
		if #samples < 2 then
			return groundBudget
		end
		ps = playerDistance(built, px, py)
	end

	local from, to = ps + ROUTE3D.START_AHEAD, ps + ROUTE3D.DRAW_AHEAD
	local r, g, b = layer.color[1], layer.color[2], layer.color[3]
	local scroll = (now / 1000) * ROUTE3D.SCROLL_SPEED
	local ground = layer.ground
	local zOff = ROUTE3D.Z_OFFSET + layer.zBias
	local rangeSq = ROUTE3D.GROUND_RANGE * ROUTE3D.GROUND_RANGE

	local verts, count = {}, 0
	local tex = getRibbonTexture()

	local function flush()
		if count >= 4 then
			dxDrawMaterialPrimitive3D("trianglestrip", tex, false, unpack(verts, 1, count))
		end
		verts, count = {}, 0
	end

	local started = false
	for i = max(1, built.cursor - 1), #samples do
		local p = samples[i]
		if p.s > to then
			break
		end
		if p.s >= from or (samples[i + 1] and samples[i + 1].s >= from) then
			-- ground heights of both sides, once per route (cached by segment / step)
			local gz = ground[p.key]
			if gz == nil and groundBudget > 0 and (p.x - camX) ^ 2 + (p.y - camY) ^ 2 < rangeSq then
				groundBudget = groundBudget - 2
				local zl = groundAt(p.lx, p.ly, p.lz)
				local zr = groundAt(p.rx, p.ry, p.lz)
				if zl or zr then
					gz = {zl or zr, zr or zl}
					ground[p.key] = gz
				end
			end
			local zl = gz and gz[1] or p.lz
			local zr = gz and gz[2] or p.lz

			-- alpha: fade in right ahead of the player, fade out at the far end
			local d = p.s - ps
			local a = ROUTE3D.ALPHA
			if d < ROUTE3D.START_AHEAD + ROUTE3D.FADE_IN then
				a = a * min(1, max(0, (d - ROUTE3D.START_AHEAD) / ROUTE3D.FADE_IN))
			elseif d > ROUTE3D.DRAW_AHEAD - ROUTE3D.FADE_OUT then
				a = a * max(0, (ROUTE3D.DRAW_AHEAD - d) / ROUTE3D.FADE_OUT)
			end
			local color = tocolor(r, g, b, a)
			local v = p.s / ROUTE3D.TEX_LENGTH - scroll

			local vl, vr = p.vl, p.vr
			vl[3], vl[4], vl[6] = zl + zOff, color, v
			vr[3], vr[4], vr[6] = zr + zOff, color, v

			verts[count + 1] = vl
			verts[count + 2] = vr
			count = count + 2
			started = true

			-- next batch starts with this pair again, so the strip has no gap
			if count >= ROUTE3D.BATCH * 2 then
				flush()
				verts[1], verts[2], count = vl, vr, 2
			end
		end
	end
	if started then
		flush()
	end
	return groundBudget
end

-- called by radar/sourceC.lua for each route channel, in drawing order (later = on top)
function addRoute3DLayer(tracker, r, g, b, zBias)
	layers[#layers + 1] = {tracker = tracker, color = {r, g, b}, zBias = zBias or 0, built = false, ground = {}}
end

-- onClientPreRender (attached by applyEnable3DNavigation in radar/sourceC.lua)
function renderRoutes3D()
	if #layers == 0 then
		return
	end
	local px, py = getElementPosition(getPedOccupiedVehicle(localPlayer) or localPlayer)
	local camX, camY = getCameraMatrix()
	local now = getTickCount()
	local budget = ROUTE3D.GROUND_PER_FRAME
	for _, layer in ipairs(layers) do
		budget = drawLayer(layer, px, py, camX, camY, now, budget)
	end
end

-- objective (yellow) under the waypoint (purple, a bit higher where both share the road)
addRoute3DLayer(getRouteTracker("objective"), 255, 205, 40, 0)
addRoute3DLayer(getRouteTracker("waypoint"), 180, 30, 230, 0.03)

addEventHandler("onClientResourceStop", resourceRoot,
	function ()
		if isElement(ribbonTexture) then
			destroyElement(ribbonTexture)
		end
	end
)
