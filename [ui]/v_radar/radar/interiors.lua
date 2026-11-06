-- Interior maps on the minimap (interiors/index.json + one image per map).
--
-- index.json "maps": { id, name, image, x, y (world position of the image's top-left = north-west corner),
--   width, height (metres the image covers), interior (game interior id, 0 = free-roam building in int 0),
--   zones = { {min = {x, y, z}, max = {x, y, z}}, ... } (player position), zoom (multiplier of BASE_ZOOM:
--   1 = default, 2 = twice as close, 0.5 = half), optional dimension }.
--
-- Exterior maps (interior 0): entering a zone the minimap zooms in while the world map fades out and the
-- building plan fades in; inside only the plan is shown (no roads). Leaving zooms + fades back out.
-- Interior maps (interior ~= 0): the plan fades in alone (no world map, blips or routes) instead of the
-- hidden minimap. The bigmap is not affected.

local INDEX_FILE = "interiors/index.json"
local BASE_ZOOM = 7            -- minimap zoom for "zoom": 1 (rt pixels per map pixel; outside 0.2 .. 0.6), ~80 m wide
local ANIM_TIME = 700          -- ms, zoom in / out
local BG_R, BG_G, BG_B = 40, 42, 46   -- behind the plan (outside the rooms)

local interiorMaps = {}
local textures = {}

local current = nil            -- map being shown (also while fading out)
local blend = 0                -- 0 = world minimap, 1 = interior map
local blendFrom, blendTo, blendStart = 0, 0, 0
local zoomFrom, zoomStart = nil, 0 -- map-to-map swap with different zoom levels: animate between them

local function loadIndex()
	interiorMaps = {}
	if not fileExists(INDEX_FILE) then
		return
	end
	local f = fileOpen(INDEX_FILE, true)
	if not f then
		return
	end
	local raw = fileRead(f, fileGetSize(f))
	fileClose(f)
	local data = raw and fromJSON(raw)
	if type(data) ~= "table" or type(data.maps) ~= "table" then
		outputDebugString("v_radar: interiors/index.json could not be read", 2)
		return
	end
	for _, m in ipairs(data.maps) do
		if type(m) == "table" and m.id and m.image and tonumber(m.x) and tonumber(m.y) and tonumber(m.width) and tonumber(m.height) and type(m.zones) == "table" then
			local zones = {}
			for _, z in ipairs(m.zones) do
				if type(z) == "table" and type(z.min) == "table" and type(z.max) == "table" then
					zones[#zones + 1] = {
						tonumber(z.min[1]), tonumber(z.min[2]), tonumber(z.min[3]) or -10000,
						tonumber(z.max[1]), tonumber(z.max[2]), tonumber(z.max[3]) or 10000,
					}
				end
			end
			interiorMaps[#interiorMaps + 1] = {
				id = m.id,
				name = m.name,
				image = "interiors/" .. m.image,
				x = tonumber(m.x), y = tonumber(m.y),
				width = tonumber(m.width), height = tonumber(m.height),
				interior = tonumber(m.interior) or 0,
				dimension = tonumber(m.dimension),
				zoom = BASE_ZOOM * math.max(0.1, math.min(10, tonumber(m.zoom) or 1)),
				zones = zones,
			}
		end
	end
end

local function getTextureOf(map)
	local tex = textures[map.image]
	if tex == nil then
		tex = dxCreateTexture(map.image, "argb", true, "clamp") or false
		if tex then
			dxSetTextureEdge(tex, "border", tocolor(0, 0, 0, 0))
		end
		textures[map.image] = tex
	end
	return tex
end

local function findMapAt(x, y, z, int, dim)
	for _, m in ipairs(interiorMaps) do
		if m.interior == int and (not m.dimension or m.dimension == dim) then
			for _, b in ipairs(m.zones) do
				if x >= b[1] and x <= b[4] and y >= b[2] and y <= b[5] and z >= b[3] and z <= b[6] then
					return m
				end
			end
		end
	end
	return nil
end

-- Exported: the interior map the local player is in (id, name) or false.
function getCurrentInteriorMap()
	if current and blendTo == 1 then
		return current.id, current.name
	end
	return false
end

local function easeInOut(t)
	return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
end

local function logLerp(a, b, t)
	return math.exp(math.log(a) + (math.log(b) - math.log(a)) * t)
end

-- The zoom of the current map, mid-animation after a map-to-map swap.
local function currentMapZoom(now)
	if not current then
		return BASE_ZOOM
	end
	if zoomFrom then
		local t = ((now or getTickCount()) - zoomStart) / ANIM_TIME
		if t < 1 then
			return logLerp(zoomFrom, current.zoom, easeInOut(t))
		end
		zoomFrom = nil
	end
	return current.zoom
end

-- Called once per minimap frame. -> map (or nil), blend 0..1 (eased), isInteriorMode
function updateInteriorMap()
	local x, y, z = getElementPosition(localPlayer)
	local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
	local now = getTickCount()
	local found = findMapAt(x, y, z, int, dim)

	if found and found ~= current then
		if int ~= 0 or not current then
			-- fade in (exterior: with the zoom); a game interior starts from nothing
			current, zoomFrom = found, nil
			if int ~= 0 then blend = 0 end
			blendFrom, blendTo, blendStart = blend, 1, now
		else
			-- walked from one building zone straight into another: swap without zooming out, but move
			-- smoothly to the new map's zoom level
			if found.zoom ~= current.zoom then
				zoomFrom, zoomStart = currentMapZoom(now), now
			end
			current = found
			blendFrom, blendTo, blendStart = blend, 1, now
		end
	elseif found and found == current and blendTo == 0 then
		blendFrom, blendTo, blendStart = blend, 1, now           -- turned back while zooming out
	elseif not found and current and blendTo ~= 0 then
		if int ~= 0 or current.interior ~= int then
			current, blend, blendFrom, blendTo = nil, 0, 0, 0   -- teleported away: no animation
		else
			blendFrom, blendTo, blendStart = blend, 0, now
		end
	end

	if current then
		local t = math.min(1, (now - blendStart) / ANIM_TIME)
		blend = blendFrom + (blendTo - blendFrom) * t
		if blendTo == 0 and t >= 1 then
			current, blend = nil, 0
		end
	end

	if not current then
		return nil, 0, false
	end
	return current, easeInOut(blend), current.interior ~= 0
end

-- Minimap zoom with the building zoom blended in (log scale, so the zoom speed feels even).
function blendInteriorZoom(baseZoom, map, b)
	if not map then
		return baseZoom
	end
	local mapZoom = map == current and currentMapZoom() or map.zoom
	if map.interior ~= 0 then
		return mapZoom                                -- game interior: no world map to zoom from
	end
	if b <= 0 then
		return baseZoom
	end
	return logLerp(baseZoom, mapZoom, b)
end

-- Draws the plan into the minimap render target. half = render target centre, zoom = rt pixels per map pixel,
-- ratio = metres per map pixel, px / py = player world position.
-- The background covers the world map with the same blend, so inside a zone no roads show; only the
-- transition is a cross-fade. In a game interior the background is always solid, only the plan fades.
function drawInteriorMap(map, b, half, zoom, ratio, px, py, interiorMode)
	local alpha = math.floor(255 * b)
	dxDrawRectangle(0, 0, half * 2, half * 2, tocolor(BG_R, BG_G, BG_B, interiorMode and 255 or alpha))
	local tex = getTextureOf(map)
	if not tex then
		return
	end
	local s = zoom / ratio
	dxDrawImage(half + (map.x - px) * s, half - (map.y - py) * s, map.width * s, map.height * s, tex, 0, 0, 0, tocolor(255, 255, 255, alpha))
end

addEventHandler("onClientResourceStart", resourceRoot, loadIndex)
