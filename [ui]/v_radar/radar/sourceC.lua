uicore = exports.ui_core
safe_x, safe_y = uicore:getSafeZone()

min, max, cos, sin, rad, deg, atan2 = math.min, math.max, math.cos, math.sin, math.rad, math.deg, math.atan2
sqrt, abs, floor, ceil, random = math.sqrt, math.abs, math.floor, math.ceil, math.random
gsub = string.gsub

screenW, screenH = guiGetScreenSize()

reMap = function(value, low1, high1, low2, high2)
	return low2 + (value - low1) * (high2 - low2) / (high1 - low1)
end

responsiveMultiplier = math.min(1, reMap(screenW, 1024, 1920, 0.75, 1))

resp = function(value)
	return value * responsiveMultiplier
end

respc = function(value)
	--return ceil(value * responsiveMultiplier)
	return uicore:ui(value)
end

deepcopy = function(original)
	local copy

	if type(original) == "table" then
		copy = {}

		for k, v in next, original, nil do
			copy[deepcopy(k)] = deepcopy(v)
		end

		setmetatable(copy, deepcopy(getmetatable(original)))
	else
		copy = original
	end

	return copy
end

local function rotateAround(angle, x, y)
	angle = math.rad(angle)
	local cosinus, sinus = math.cos(angle), math.sin(angle)
	return x * cosinus - y * sinus, x * sinus + y * cosinus
end



local mapTextureSize = 3072
local mapRatio = 6000 / mapTextureSize

local minimapPosX = 0
local minimapPosY = 0
local minimapWidth = respc(320)
local minimapHeight = respc(225)
local minimapCenterX = minimapPosX + minimapWidth / 2
local minimapCenterY = minimapPosY + minimapHeight / 2
local minimapRenderSize = 400
local minimapRenderHalfSize = minimapRenderSize * 0.5
local minimapRender = dxCreateRenderTarget(minimapRenderSize, minimapRenderSize)
local playerMinimapZoom = 0.5
local minimapZoom = playerMinimapZoom
local minimapIsVisible = true

-- The bigmap is a full-screen part of the pause menu (ui_pause).
local bigmapPosX = 0
local bigmapPosY = 0
local bigmapWidth = screenW
local bigmapHeight = screenH
local bigmapCenterX = bigmapPosX + bigmapWidth / 2
local bigmapCenterY = bigmapPosY + bigmapHeight / 2
local bigmapZoom = 0.5
local bigmapIsVisible = false
local bigmapOpenedFromPause = false
local ignoreNextBigmapEnter = false

local lastCursorPos = false
local mapDifferencePos = false
local mapMovedPos = false
local lastDifferencePos = false
local mapIsMoving = false
local lastMapPosX, lastMapPosY = 0, 0
local mapPlayerPosX, mapPlayerPosY = 0, 0

local zoneLineHeight = 20
local screenSource = dxCreateScreenSource(screenW, screenH)
local bigmapBackgroundSource = dxCreateScreenSource(screenW, screenH)
local bigmapBlurShader = dxCreateShader("radar/files/bigmap_blur.fx")

local gps_color = tocolor(180, 30, 230)
local gpsLineWidth = respc(60)
local gpsLineIconSize = respc(40)
local gpsLineIconHalfSize = gpsLineIconSize / 2
local createdTextures = {}

settingsStorage = {
	show3DBlips = false,
	enable3DNavigation = true,
}

local RADAR_SETTINGS_FILE = "radar_settings.json"
local render3DBlipsAttached = false
local render3DNavigationAttached = false

function loadRadarSettings()
	if not fileExists(RADAR_SETTINGS_FILE) then return end
	local f = fileOpen(RADAR_SETTINGS_FILE, true)
	if not f then return end
	local raw = fileRead(f, fileGetSize(f)) or ""
	fileClose(f)
	local data = fromJSON(raw)
	if type(data) == "table" then
		if type(data.show3DBlips) == "boolean" then
			settingsStorage.show3DBlips = data.show3DBlips
		end
		if type(data.enable3DNavigation) == "boolean" then
			settingsStorage.enable3DNavigation = data.enable3DNavigation
		end
	end
end

function saveRadarSettings()
	if fileExists(RADAR_SETTINGS_FILE) then
		fileDelete(RADAR_SETTINGS_FILE)
	end
	local f = fileCreate(RADAR_SETTINGS_FILE)
	if not f then return end
	fileWrite(f, toJSON({
		show3DBlips = settingsStorage.show3DBlips and true or false,
		enable3DNavigation = settingsStorage.enable3DNavigation and true or false,
	}))
	fileClose(f)
end

function applyShow3DBlips(state, skipSave)
	state = state and true or false
	settingsStorage.show3DBlips = state
	state3DBlip = state

	if render3DBlipsAttached then
		removeEventHandler("onClientHUDRender", getRootElement(), render3DBlips)
		render3DBlipsAttached = false
	end
	if state then
		addEventHandler("onClientHUDRender", getRootElement(), render3DBlips, true, "low-99999999")
		render3DBlipsAttached = true
	end

	if not skipSave then
		saveRadarSettings()
	end
end

-- Exported: toggled from the pause menu (ui_pause) Settings > Display page.
function setShow3DBlips(state)
	applyShow3DBlips(state and true or false)
	return true
end

function getShow3DBlips()
	return settingsStorage.show3DBlips and true or false
end

-- 3D navigation: a floating line above the road, following the GPS route nodes
-- (each raised by +6 on Z) and joined with dxDrawLine3D segments. Only visible
-- while a GPS route is active. gpsRoute / currentNode are globals from
-- radar/gps/sourceC.lua.
local navigation3DColor = gps_color
local navigation3DShadow = tocolor(0, 0, 0, 160)
local NAVIGATION_3D_Z_OFFSET = 6

function render3DNavigation()
	if not gpsRoute then return end
	if getElementDimension(localPlayer) ~= 0 then return end

	local startIndex = tonumber(currentNode) or 1
	if startIndex < 1 then startIndex = 1 end

	for i = startIndex, #gpsRoute - 1 do
		local a = gpsRoute[i]
		local b = gpsRoute[i + 1]

		if a and b then
			local ax, ay, az = a.x, a.y, a.z + NAVIGATION_3D_Z_OFFSET
			local bx, by, bz = b.x, b.y, b.z + NAVIGATION_3D_Z_OFFSET

			dxDrawLine3D(ax, ay, az - 0.12, bx, by, bz - 0.12, navigation3DShadow, 6)
			dxDrawLine3D(ax, ay, az, bx, by, bz, navigation3DColor, 4)
		end
	end
end

function applyEnable3DNavigation(state, skipSave)
	state = state and true or false
	settingsStorage.enable3DNavigation = state

	if render3DNavigationAttached then
		removeEventHandler("onClientPreRender", getRootElement(), render3DNavigation)
		render3DNavigationAttached = false
	end
	if state then
		addEventHandler("onClientPreRender", getRootElement(), render3DNavigation)
		render3DNavigationAttached = true
	end

	if not skipSave then
		saveRadarSettings()
	end
end

-- Exported: managed by the pause menu (ui_pause). Default is on.
function setEnable3DNavigation(state)
	applyEnable3DNavigation(state and true or false)
	return true
end

function getEnable3DNavigation()
	return settingsStorage.enable3DNavigation and true or false
end

createdFonts = {}

occupiedVehicle = false

addCommandHandler("pos3", function()
	local x,y,z = getElementPosition(localPlayer)
	local text = x..","..y..","..z
	outputChatBox(text)
	setClipboard(text)
end)

createdBlips = {}
local mainBlips = {
	-- Train stations
	{1719.1861572266,-1883.5534667969,13.565537452698, "blips/47.png", false, 300}, -- Train station: Ls Main
	{825.43377685547,-1360.1910400391,-0.5078125, "blips/47.png", false, 300}, -- Train station: Ls West
	{-1968.9625244141,137.92936706543,27.6875, "blips/47.png", false, 300}, -- Train station:  SF
	{1432.8743896484,2634.1186523438,17.486980438232, "blips/47.png", false, 300}, -- Train station: LV North
	{2853.9965820312,1290.9426269531,11.390625, "blips/47.png", false, 300}, -- Train station: LV East
	
	-- Airports
	{1627.2409667969,-2286.3374023438,94.1328125, "blips/5.png", false, 500}, -- Airport: LS
	{1678.9660644531,1447.7465820312,47.7780418396, "blips/5.png", false, 500}, -- Airport: LV
	{365.31829833984,2537.0776367188,16.664966583252, "blips/5.png", false, 500}, -- Airport: Desert (near LV)
	{-1275.8029785156,53.749702453613,89.233612060547, "blips/5.png", false, 500}, -- Airport: SF
	
	-- Hospitals
	{-2649.4216308594,608.18615722656,14.453125, "blips/22.png", false, 300}, -- Hospital: SF Med center
	{1607.0931396484,1824.5986328125,24.153646469116, "blips/22.png", false, 300}, -- Hospital: LV
	{1178.3270263672,-1323.6711425781,14.114587783813, "blips/22.png", false, 300}, -- Hospital: LS General
	{2029.8089599609,-1419.0695800781,16.9921875, "blips/22.png", false, 300}, -- Hospital: LS East
	
	-- Police stations
	{1553.3978271484,-1675.6483154297,16.1953125, "blips/30.png", false, 300}, -- Police: LSPD
	{2314.8203125,2450.4797363281,10.8203125, "blips/30.png", false, 300}, -- Police: LVPD
	{-1605.3837890625,711.50561523438,13.8671875, "blips/30.png", false, 300}, -- Police: SFPD
	--{, "blips/30.png"}, -- Police:
	
	-- Stunt parks
	{1913.8464355469,-1407.0209960938,16.359375, "blips/8.png", false, 200, 1.5}, -- LS (near East hospital)
	{1946.7679443359,-1812.8077392578,13.546875, "blips/8.png", false, 200, 1.5}, -- LS (behind South Fuel Station)

	-- Cabble car
	{-2130.6020507812,-2551.0700683594,42.5234375, "blips/7.png", false, 1000, 2}, -- Bottom station
	{-2260.3950195312,-1780.0151367188,457.5234375, "blips/7.png", false, 500, 2}, -- Top station

	--{115.1590423584, 2959.9367675781, 72.15119934082, "blips/4.png", true, 9999, 16.5},
}
-- createCustomBlip(x, y, z, icon, farShow, visibleDistance, size, color)

local blipTooltips = {
	["blips/1.png"] = "Player",
	["blips/2.png"] = "",
	["blips/3.png"] = "",
	["blips/4.png"] = "",
	["blips/5.png"] = "Airport",
	["blips/6.png"] = "Weaponshop",
	["blips/7.png"] = "Cablecar",
	["blips/8.png"] = "Stunt park",
	["blips/9.png"] = "Job",
	["blips/10.png"] = "Fire Department",
	["blips/11.png"] = "",
	["blips/12.png"] = "",
	["blips/13.png"] = "",
	["blips/14.png"] = "",
	["blips/15.png"] = "",
	["blips/16.png"] = "",
	["blips/17.png"] = "",
	["blips/18.png"] = "",
	["blips/19.png"] = "",
	["blips/20.png"] = "",
	["blips/21.png"] = "",
	["blips/22.png"] = "Hospital",
	["blips/23.png"] = "",
	["blips/24.png"] = "",
	["blips/25.png"] = "",
	["blips/26.png"] = "",
	["blips/27.png"] = "",
	["blips/28.png"] = "",
	["blips/29.png"] = "",
	["blips/30.png"] = "Police",
	["blips/31.png"] = "Property for sale",
	["blips/32.png"] = "Property",
	["blips/33.png"] = "",
	["blips/34.png"] = "",
	["blips/35.png"] = "",
	["blips/36.png"] = "",
	["blips/37.png"] = "",
	["blips/38.png"] = "",
	["blips/39.png"] = "",
	["blips/40.png"] = "",
	["blips/41.png"] = "",
	["blips/42.png"] = "",
	["blips/43.png"] = "",
	["blips/44.png"] = "",
	["blips/45.png"] = "",
	["blips/46.png"] = "Ferriswheel",
	["blips/47.png"] = "Train station",
	["blips/48.png"] = "",
	["blips/49.png"] = "",
	["blips/50.png"] = "",
	["blips/51.png"] = "Fuel station",
	["blips/52.png"] = "Bank",
	["blips/53.png"] = "Arena War",
	["blips/54.png"] = "Shop",
	["blips/55.png"] = "",
	["blips/56.png"] = "",
	["blips/57.png"] = "",
	["blips/58.png"] = "",
	["blips/59.png"] = "",
	["blips/60.png"] = "",
	["blips/61.png"] = "Time Trial",
	["blips/62.png"] = "",
	["blips/63.png"] = "",
	["blips/64.png"] = "",
	["blips/markblip.png"] = "Waypoint",
	["blips/north.png"] = "North",
}

local blipTooltip_fontsize = 1
local visibleBlipTooltip = false
local hoveredWaypointBlip = false

local farshowBlipsData = {}
-- Off-minimap blips with farShow / isFarVisibility set are shown on the minimap
-- frame. This keeps the smoothed marker state between frames, keyed by blipTableId.
local farshowBlipSmooth = {}
local EDGE_INDICATOR_TAU = 90 -- ms; lower = snappier edge marker, higher = smoother

carCanGPSVal = false
local gpsHello = false
local gpsLines = {}
local gpsRouteImage = false
local gpsRouteImageData = {}

state3DBlip = true -- global: also written by applyShow3DBlips() defined above

-- Bigmap blip-type menu (top-right). Arrow keys pick a type and step between the
-- individual blips of that type; the mouse still drives the map itself.
local bigmapBlipMenu = {}
local blipMenuSel = 1
local blipMenuIndex = 1
blipMenuFocus = false -- global to keep renderTheBigmap's upvalue count down

local playerCanSeePlayers = true

local getZoneNameEx = getZoneName
function getZoneName(x, y, z, citiesonly)
	local zoneName = getZoneNameEx(x, y, z, citiesonly)
	if zoneName == "Greenglass College" then
		return "Las Venturas City Hall"
	else
		return zoneName
	end
end

function getTexture(name)
	if createdTextures[name] then
		return createdTextures[name]
	end

	return false
end

addCommandHandler("showplayers",
	function ()
	    playerCanSeePlayers = not playerCanSeePlayers
	end
)

local textura_mini = dxCreateTexture("radar/files/radar.jpg")
local textura = dxCreateTexture("radar/files/radar.png")

addEventHandler("onClientResourceStart", getResourceRootElement(),
	function ()
    createdTextures = {
			minimapMap = textura_mini,
			bigmapMap = textura,
		}
		initFont("Roboto", "Roboto.ttf", 12)
		initFont("RobotoB", "Roboto.ttf", 24)
		initFont("pricedown", "Roboto.ttf", 40)
		initFont("BrushScriptStd", "Roboto.ttf", 30)
		occupiedVehicle = getPedOccupiedVehicle(localPlayer)

		-- Disable the built-in GTA world map: the bigmap is only reachable from
		-- the pause menu now, and F11 must do nothing.
		toggleControl("radar", false)

		if getTexture("minimapMap") then
			dxSetTextureEdge(getTexture("minimapMap"), "border", tocolor(84, 112, 126)) -- water
		end

		if getTexture("bigmapMap") then
			-- The big map PNG has transparency. Keep pixels outside the texture transparent
			-- so they fade into the dark wash drawn behind the bigmap instead of showing a
			-- solid black patch when scrolling (zooming) out past the texture bounds.
			dxSetTextureEdge(getTexture("bigmapMap"), "border", tocolor(0, 0, 0, 0))
		end

		for k,v in ipairs(getElementsByType("blip")) do
			blipTooltips[v] = getElementData(v, "tooltipText")
		end

		for k,v in ipairs(mainBlips) do
			createCustomBlip(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8])
		end

		if occupiedVehicle then
			carCanGPS()
		end

		loadRadarSettings()
		applyShow3DBlips(settingsStorage.show3DBlips, true)
		applyEnable3DNavigation(settingsStorage.enable3DNavigation, true)
	end
)

addEventHandler("onClientElementDataChange", getRootElement(),
	function (dataName, oldValue)
		if source == occupiedVehicle then
			if dataName == "vehicle.tuning.seeGO" then
				local dataValue = getElementData(source, dataName) or false

				if dataValue then
					carCanGPSVal = dataValue
				else
					if oldValue then
						carCanGPSVal = false
					end
				end

				if not carCanGPSVal then
					if getElementData(source, "gpsDestination") then
						endRoute()
					end
				end
			elseif dataName == "gpsDestination" then
				local dataValue = getElementData(source, dataName) or false

				if dataValue then
					gpsThread = coroutine.create(makeRoute)
					coroutine.resume(gpsThread, unpack(dataValue))
				else
					endRoute()
				end
			end
		end

		if getElementType(source) == "blip" and dataName == "tooltipText" then
			blipTooltips[source] = getElementData(source, dataName)
		end
	end
)

addEventHandler("onClientPlayerDamage", getLocalPlayer(),
	function ()
		damageEffectStart = getTickCount()
	end
)

addEventHandler("onClientRender", getRootElement(),
	function ()
		renderTheBigmap()
		--mapWidth = exports.r8_radar:getNode(7, "width");
		--mapHeight = exports.r8_radar:getNode(7, "height");
		--mapX = exports.r8_radar:getNode(7, "x");
		--mapY = exports.r8_radar:getNode(7, "y");
		--if (exports["r8_radar"]:getNode(7, "showing") or getElementData(localPlayer, "valaszto")) then
		mapWidth = uicore:ui(300)
		mapHeight = uicore:ui(200)
		mapX = safe_x
		mapY = screenH-safe_y-mapHeight

		local hideHUD = getElementData(localPlayer, "hideHUD")
		if not hideHUD then
			renderMinimap(mapX, mapY, mapWidth, mapHeight)
		end
	end
)

function renderMinimap(x, y, w, h)
	local playerDimension = getElementDimension(localPlayer)
	local int = getElementInterior(localPlayer)
	if int == 0 then

		if bigmapIsVisible or not minimapIsVisible then
			return
		end

		minimapWidth = w
		minimapHeight = h

		if (minimapWidth > respc(445) or minimapHeight > respc(400)) and minimapRenderSize < 800 then
			minimapRenderSize = 800
			minimapRenderHalfSize = minimapRenderSize * 0.5
			destroyElement(minimapRender)
			minimapRender = dxCreateRenderTarget(minimapRenderSize, minimapRenderSize)
		end
		if minimapWidth <= respc(445) and minimapHeight <= respc(400) and minimapRenderSize > 600 then
			minimapRenderSize = 600
			minimapRenderHalfSize = minimapRenderSize * 0.5
			destroyElement(minimapRender)
			minimapRender = dxCreateRenderTarget(minimapRenderSize, minimapRenderSize)
		end
		if (minimapWidth > respc(325) or minimapHeight > respc(235)) and minimapRenderSize < 600 then
			minimapRenderSize = 600
			minimapRenderHalfSize = minimapRenderSize * 0.5
			destroyElement(minimapRender)
			minimapRender = dxCreateRenderTarget(minimapRenderSize, minimapRenderSize)
		end
		if minimapWidth <= respc(325) and minimapHeight <= respc(235) and minimapRenderSize > 400 then
			minimapRenderSize = 400
			minimapRenderHalfSize = minimapRenderSize * 0.5
			destroyElement(minimapRender)
			minimapRender = dxCreateRenderTarget(minimapRenderSize, minimapRenderSize)
		end

		if minimapPosX ~= x or minimapPosY ~= y then
			minimapPosX = x
			minimapPosY = y
		end

		minimapCenterX = minimapPosX + minimapWidth / 2
		minimapCenterY = minimapPosY + minimapHeight / 2

		dxUpdateScreenSource(screenSource, true)
--
		--if getKeyState("num_add") and playerMinimapZoom < 1.2 then
		--	playerMinimapZoom = playerMinimapZoom + 0.01
		--elseif getKeyState("num_sub") and playerMinimapZoom > 0.31 then
		--	playerMinimapZoom = playerMinimapZoom - 0.01
		--end

		minimapZoom = 0.6

		if occupiedVehicle then
			local vehicleZoom = getVehicleSpeed(occupiedVehicle) / 1300
			if vehicleZoom >= 0.4 then
				vehicleZoom = 0.4
			end
			minimapZoom = minimapZoom - vehicleZoom
		end

		local playerPosX, playerPosY, playerPosZ = getElementPosition(localPlayer)
		local cameraX, cameraY, _, faceTowardX, faceTowardY = getCameraMatrix()
		local cameraRotation = deg(atan2(faceTowardY - cameraY, faceTowardX - cameraX)) + 360 + 90

		local minimapRenderSizeOffset = respc(minimapRenderSize * 0.75)

		farshowBlipsData = {}

		if playerDimension == 0 then
			local remapPlayerPosX, remapPlayerPosY = remapTheFirstWay(playerPosX), remapTheFirstWay(playerPosY)
			-- Unique-key base for blipTableId (createdBlips use their own index 1..n).
			local farBlipsCount = 10000
			local manualBlipsCount = 1
			local defaultBlipsCount = 1

			dxSetRenderTarget(minimapRender, true)
			-- Opaque base fill: the render target is cleared to transparent black, so
			-- without this any pixel the map image does not fully cover would let the
			-- game world bleed through and make the minimap map look washed out / faint.
			dxDrawRectangle(0, 0, minimapRenderSize, minimapRenderSize, tocolor(84, 112, 126, 255))
			dxDrawImageSection(0, 0, minimapRenderSize, minimapRenderSize, remapTheSecondWay(playerPosX) - minimapRenderSize / minimapZoom / 2, remapTheFirstWay(playerPosY) - minimapRenderSize / minimapZoom / 2, minimapRenderSize / minimapZoom, minimapRenderSize / minimapZoom, getTexture("minimapMap"), 0, 0, 0, tocolor(255, 255, 255, 255))

			if gpsRouteImage then
				dxDrawImage(minimapRenderSize / 2 + (remapTheFirstWay(playerPosX) - (gpsRouteImageData[1] + gpsRouteImageData[3] / 2)) * minimapZoom - gpsRouteImageData[3] * minimapZoom / 2, minimapRenderSize / 2 - (remapTheFirstWay(playerPosY) - (gpsRouteImageData[2] + gpsRouteImageData[4] / 2)) * minimapZoom + gpsRouteImageData[4] * minimapZoom / 2, gpsRouteImageData[3] * minimapZoom, -(gpsRouteImageData[4] * minimapZoom), gpsRouteImage, 180, 0, 0, gps_color)
			end

			for i = 1, #createdBlips do
				if createdBlips[i] then
					renderBlip(createdBlips[i].icon, createdBlips[i].posX, createdBlips[i].posY, remapPlayerPosX, remapPlayerPosY, createdBlips[i].iconSize*12, createdBlips[i].iconSize*12, createdBlips[i].color, cameraRotation, createdBlips[i].farShow, i)

					manualBlipsCount = manualBlipsCount + 1
				end
			end

			local defaultBlips = getElementsByType("blip")
			for i = 1, #defaultBlips do
				if defaultBlips[i] then
					local tableId = farBlipsCount + manualBlipsCount + defaultBlipsCount

					local blipPosX, blipPosY = getElementPosition(defaultBlips[i])

					local blipIco = getBlipIcon(defaultBlips[i])
					local blipDist = getBlipVisibleDistance(defaultBlips[i])
					local blipSize = getBlipSize(defaultBlips[i])*12

					--local px,py = getElementPosition(localPlayer)
					--if getDistanceBetweenPoints2D(px,py, blipPosX,blipPosY) <= blipDist then
						renderBlip("blips/"..blipIco..".png", blipPosX, blipPosY, remapPlayerPosX, remapPlayerPosY, blipSize, blipSize, 0xFFFFFFFF, cameraRotation, getElementData(defaultBlips[i], "isFarVisibility") and true or false, tableId)
					--end

					defaultBlipsCount = defaultBlipsCount + 1
				end
			end

			dxSetRenderTarget()
			dxDrawImage(minimapPosX - minimapRenderSize / 2 + minimapWidth / 2, minimapPosY - minimapRenderSize / 2 + minimapHeight / 2, minimapRenderSize, minimapRenderSize, minimapRender, cameraRotation - 180, 0, 0, tocolor(255, 255, 255, 255))
		end

		dxDrawImageSection(minimapPosX - minimapRenderSizeOffset, minimapPosY - minimapRenderSizeOffset, minimapWidth + minimapRenderSizeOffset * 2, minimapRenderSizeOffset, minimapPosX - minimapRenderSizeOffset, minimapPosY - minimapRenderSizeOffset, minimapWidth + minimapRenderSizeOffset * 2, minimapRenderSizeOffset, screenSource)
		dxDrawImageSection(minimapPosX - minimapRenderSizeOffset, minimapPosY + minimapHeight, minimapWidth + minimapRenderSizeOffset * 2, minimapRenderSizeOffset, minimapPosX - minimapRenderSizeOffset, minimapPosY + minimapHeight, minimapWidth + minimapRenderSizeOffset * 2, minimapRenderSizeOffset, screenSource)
		dxDrawImageSection(minimapPosX - minimapRenderSizeOffset, minimapPosY, minimapRenderSizeOffset, minimapHeight, minimapPosX - minimapRenderSizeOffset, minimapPosY, minimapRenderSizeOffset, minimapHeight, screenSource)
		dxDrawImageSection(minimapPosX + minimapWidth, minimapPosY, minimapRenderSizeOffset, minimapHeight, minimapPosX + minimapWidth, minimapPosY, minimapRenderSizeOffset, minimapHeight, screenSource)
		dxDrawOuterBorder(minimapPosX, minimapPosY, minimapWidth, minimapHeight+10, 2, tocolor(0, 0, 0, 200))

		-- Frame-edge direction markers for far blips, on top of the finished frame.
		for _, data in pairs(farshowBlipsData) do
			drawEdgeIndicator(data)
		end

		local px,py,pz = getElementPosition(localPlayer)
		local isSignal = true
		local gpsPolar = 12
		local gpsHeight = 500
		if ( isLineOfSightClear(px,py,pz+2, px,py,pz+gpsHeight, true, false, false) or isLineOfSightClear(px+gpsPolar,py,pz+2, px+gpsPolar,py,pz+gpsHeight, true, false, false) or isLineOfSightClear(px-gpsPolar,py,pz+2, px-gpsPolar,py,pz+gpsHeight, true, false, false) or isLineOfSightClear(px,py+gpsPolar,pz+2, px,py+gpsPolar,pz+gpsHeight, true, false, false) or isLineOfSightClear(px,py-gpsPolar,pz+2, px,py-gpsPolar,pz+gpsHeight, true, false, false) ) then
			isSignal = true
		end

		if int == 0 then
			local playerArrowSize = 60 / (4 - minimapZoom) + 3
			local playerArrowHalfSize = playerArrowSize / 2
			local _, _, playerRotation = getElementRotation(localPlayer)

			dxDrawImage(minimapCenterX - playerArrowHalfSize, minimapCenterY - playerArrowHalfSize, playerArrowSize, playerArrowSize, "radar/files/arrow.png", abs(360 - playerRotation) + (cameraRotation - 180))
			
			--dxDrawRectangle(minimapPosX, minimapPosY + minimapHeight - zoneLineHeight, minimapWidth, zoneLineHeight, tocolor(0, 0, 0, 150))
			--dxDrawText(getZoneName(playerPosX, playerPosY, playerPosZ), minimapPosX+5, minimapPosY + minimapHeight - zoneLineHeight , minimapPosX + minimapWidth - resp(10), minimapPosY + minimapHeight, tocolor(200, 200, 200, 255), 1.2, "default-small", "left", "center")
			--dxDrawText("3.2 km", minimapPosX+5, minimapPosY + minimapHeight - zoneLineHeight , minimapPosX + minimapWidth - resp(10), minimapPosY + minimapHeight, tocolor(255, 255, 255, 255), 1.5, "default", "left", "bottom", false) -- total left
		else
			dxDrawRectangle(minimapPosX, minimapPosY, minimapWidth, minimapHeight, tocolor(0, 0, 0))

			if not lostSignalStartTick then
				lostSignalStartTick = getTickCount()
			end

			local fadeAlpha = 255
			if not lostSignalFadeIn then
				fadeAlpha = 255
			else
				fadeAlpha = 0
			end

			local lostSignalTick = (getTickCount() - lostSignalStartTick) / 1500
			if lostSignalTick > 1 then
				lostSignalStartTick = getTickCount()
				lostSignalFadeIn = not lostSignalFadeIn
			end

			dxDrawImage(minimapCenterX - 32, minimapCenterY - 32, 64, 64, "radar/files/gpslosticon.png", 0, 0, 0, tocolor(255, 255, 255, interpolateBetween(fadeAlpha, 0, 0, 255 - fadeAlpha, 0, 0, lostSignalTick, "Linear")))
			--dxDrawText("NO SIGNAL", minimapPosX + minimapRenderSize / 2, minimapPosY + minimapRenderSize + 160, _,_, tocolor(255,255,255,255), 1	, "arial", "center", "center")
		end

		if damageEffectStart then
			if tonumber(damageEffectStart) then
				if getTickCount() - damageEffectStart >= 1000 then
					damageEffectStart = false
					return
				end
			else
				damageEffectStart = false
				return
			end

			local effectProgress = (getTickCount() - damageEffectStart) / 500
			if effectProgress > 1 then
				damageEffectStart = false
				return
			end

			dxDrawRectangle(minimapPosX, minimapPosY, minimapWidth, minimapHeight, tocolor(255, 0, 0, interpolateBetween(150, 0, 0, 0, 0, 0, effectProgress, "Linear")))
		end

		-- health & armor
		local elet = getElementHealth(localPlayer)
		local panel = getPedArmor(localPlayer)

		dxDrawLine(minimapPosX, minimapPosY+minimapHeight, minimapPosX+minimapWidth, minimapPosY+minimapHeight, tocolor(0,0,0,255), 1)
		dxDrawRectangle(minimapPosX, minimapPosY+minimapHeight+1, minimapWidth, 10, tocolor(0,0,0,255))

		dxDrawRectangle(minimapPosX, minimapPosY+minimapHeight+1, minimapWidth/2-1, 10, tocolor(30,160,30,100))
		dxDrawRectangle(minimapPosX+(minimapWidth/2+2), minimapPosY+minimapHeight+1, minimapWidth/2-1, 10, tocolor(80,120,220,100))

		dxDrawRectangle(minimapPosX, minimapPosY+minimapHeight+1, 					 elet*((minimapWidth/2-1)/100), 10, tocolor(30,160,30,255))
		dxDrawRectangle(minimapPosX+(minimapWidth/2+2), minimapPosY+minimapHeight+1, panel*((minimapWidth/2-1)/100), 10, tocolor(80,120,255,255))
	end
end

function renderTheBigmap()
	if not bigmapIsVisible then
		return
	end

	-- Faint dark wash behind the whole bigmap, needed to darken the pause menu
	-- behind it. The map texture's own out-of-bounds edges stay transparent
	-- (see dxSetTextureEdge below) so they fade into this wash instead of
	-- showing a solid black patch.
	dxDrawRectangle(0, 0, screenW, screenH, tocolor(4, 7, 11, 150))
	dxDrawRectangle(0, 0, screenW, screenH, tocolor(12, 16, 23, 150))

	if hoveredWaypointBlip then
		hoveredWaypointBlip = false
	end

	dxDrawOuterBorder(bigmapPosX, bigmapPosY, bigmapWidth, bigmapHeight, 5, tocolor(0, 0, 0, 60))

	if getElementDimension(localPlayer) == 0 then
		local playerPosX, playerPosY, playerPosZ = getElementPosition(localPlayer)

		cursorX, cursorY = getHudCursorPos()
		if cursorX and cursorY then
			cursorX, cursorY = cursorX * screenW, cursorY * screenH

			if getKeyState("mouse1") then
				blipMenuFocus = false

				if not lastCursorPos then
					lastCursorPos = {cursorX, cursorY}
				end

				if not mapDifferencePos then
					mapDifferencePos = {0, 0}
				end

				if not lastDifferencePos then
					if not mapMovedPos then
						lastDifferencePos = {0, 0}
					else
						lastDifferencePos = {mapMovedPos[1], mapMovedPos[2]}
					end
				end

				mapDifferencePos = {mapDifferencePos[1] + cursorX - lastCursorPos[1], mapDifferencePos[2] + cursorY - lastCursorPos[2]}

				if not mapMovedPos then
					if abs(mapDifferencePos[1]) >= 3 or abs(mapDifferencePos[2]) >= 3 then
						mapMovedPos = {lastDifferencePos[1] - mapDifferencePos[1] / bigmapZoom, lastDifferencePos[2] + mapDifferencePos[2] / bigmapZoom}
						mapIsMoving = true
					end
				elseif mapDifferencePos[1] ~= 0 or mapDifferencePos[2] ~= 0 then
					mapMovedPos = {lastDifferencePos[1] - mapDifferencePos[1] / bigmapZoom, lastDifferencePos[2] + mapDifferencePos[2] / bigmapZoom}
					mapIsMoving = true
				end

				lastCursorPos = {cursorX, cursorY}
			else
				local moveSpeed = 5
				if getKeyState("w") then
					if not mapDifferencePos then
						mapDifferencePos = {0, 0}
					end
					if not lastDifferencePos then
						if not mapMovedPos then
							lastDifferencePos = {0, 0}
						else
							lastDifferencePos = {mapMovedPos[1], mapMovedPos[2]}
						end
					end
					mapDifferencePos = {mapDifferencePos[1], mapDifferencePos[2]+moveSpeed}
					mapMovedPos = {lastDifferencePos[1] - mapDifferencePos[1] / bigmapZoom, lastDifferencePos[2] + mapDifferencePos[2] / bigmapZoom}
					mapIsMoving = true
				end
				if getKeyState("s") then
					if not mapDifferencePos then
						mapDifferencePos = {0, 0}
					end
					if not lastDifferencePos then
						if not mapMovedPos then
							lastDifferencePos = {0, 0}
						else
							lastDifferencePos = {mapMovedPos[1], mapMovedPos[2]}
						end
					end
					mapDifferencePos = {mapDifferencePos[1], mapDifferencePos[2]-moveSpeed}
					mapMovedPos = {lastDifferencePos[1] - mapDifferencePos[1] / bigmapZoom, lastDifferencePos[2] + mapDifferencePos[2] / bigmapZoom}
					mapIsMoving = true
				end
				if getKeyState("a") then
					if not mapDifferencePos then
						mapDifferencePos = {0, 0}
					end
					if not lastDifferencePos then
						if not mapMovedPos then
							lastDifferencePos = {0, 0}
						else
							lastDifferencePos = {mapMovedPos[1], mapMovedPos[2]}
						end
					end
					mapDifferencePos = {mapDifferencePos[1]+moveSpeed, mapDifferencePos[2]}
					mapMovedPos = {lastDifferencePos[1] - mapDifferencePos[1] / bigmapZoom, lastDifferencePos[2] + mapDifferencePos[2] / bigmapZoom}
					mapIsMoving = true
				end
				if getKeyState("d") then
					if not mapDifferencePos then
						mapDifferencePos = {0, 0}
					end
					if not lastDifferencePos then
						if not mapMovedPos then
							lastDifferencePos = {0, 0}
						else
							lastDifferencePos = {mapMovedPos[1], mapMovedPos[2]}
						end
					end
					mapDifferencePos = {mapDifferencePos[1]-moveSpeed, mapDifferencePos[2]}
					mapMovedPos = {lastDifferencePos[1] - mapDifferencePos[1] / bigmapZoom, lastDifferencePos[2] + mapDifferencePos[2] / bigmapZoom}
					mapIsMoving = true
				end

				if mapMovedPos then
					lastDifferencePos = {mapMovedPos[1], mapMovedPos[2]}
				end

				lastCursorPos = false
				mapDifferencePos = false
			end
		end

		mapPlayerPosX, mapPlayerPosY = lastMapPosX, lastMapPosY

		if mapMovedPos then
			mapPlayerPosX = mapPlayerPosX + mapMovedPos[1]
			mapPlayerPosY = mapPlayerPosY + mapMovedPos[2]
		else
			mapPlayerPosX, mapPlayerPosY = playerPosX, playerPosY
			lastMapPosX, lastMapPosY = mapPlayerPosX, mapPlayerPosY
		end

		-- When a blip type is picked from the top-right menu, centre the map on it.
		if blipMenuFocus then
			mapPlayerPosX, mapPlayerPosY = blipMenuFocus[1], blipMenuFocus[2]
		end

		dxDrawImageSection(bigmapPosX, bigmapPosY, bigmapWidth, bigmapHeight, remapTheSecondWay(mapPlayerPosX) - bigmapWidth / bigmapZoom / 2, remapTheFirstWay(mapPlayerPosY) - bigmapHeight / bigmapZoom / 2, bigmapWidth / bigmapZoom, bigmapHeight / bigmapZoom, getTexture("bigmapMap"))

		if gpsRouteImage then
			dxUpdateScreenSource(screenSource, true)
			--dxSetBlendMode("add")
			dxDrawImage(bigmapCenterX + (remapTheFirstWay(mapPlayerPosX) - (gpsRouteImageData[1] + gpsRouteImageData[3] / 2)) * bigmapZoom - gpsRouteImageData[3] * bigmapZoom / 2, bigmapCenterY - (remapTheFirstWay(mapPlayerPosY) - (gpsRouteImageData[2] + gpsRouteImageData[4] / 2)) * bigmapZoom + gpsRouteImageData[4] * bigmapZoom / 2, gpsRouteImageData[3] * bigmapZoom, -(gpsRouteImageData[4] * bigmapZoom), gpsRouteImage, 180, 0, 0, gps_color)
			--dxSetBlendMode("blend")
			dxDrawImageSection(0, 0, bigmapPosX, screenH, 0, 0, bigmapPosX, screenH, screenSource)
			dxDrawImageSection(screenW - bigmapPosX, 0, bigmapPosX, screenH, screenW - bigmapPosX, 0, bigmapPosX, screenH, screenSource)
			dxDrawImageSection(bigmapPosX, 0, screenW - 2 * bigmapPosX, bigmapPosY, bigmapPosX, 0, screenW - 2 * bigmapPosX, bigmapPosY, screenSource)
			dxDrawImageSection(bigmapPosX, screenH - bigmapPosY, screenW - 2 * bigmapPosX, bigmapPosY, bigmapPosX, screenH - bigmapPosY, screenW - 2 * bigmapPosX, bigmapPosY, screenSource)
		end

		for i = 1, #createdBlips do
			if createdBlips[i] then
				renderBigBlip(createdBlips[i].icon, createdBlips[i].posX, createdBlips[i].posY, mapPlayerPosX, mapPlayerPosY, createdBlips[i].renderDistance, createdBlips[i].iconSize*16, createdBlips[i].iconSize*16, createdBlips[i].color, false, i, playerRotation)
			end
		end

		for k,v in ipairs(getElementsByType("blip")) do
			if getElementAttachedTo(v) ~= localPlayer then
				local blipPosX, blipPosY = getElementPosition(v)
				local blipSize = getBlipSize(v)*16

				renderBigBlip("blips/"..getBlipIcon(v)..".png", blipPosX, blipPosY, mapPlayerPosX, mapPlayerPosY, 9999, blipSize, blipSize, 0xFFFFFFFF, v, k)
			end
		end

		if playerCanSeePlayers then
			for k,v in ipairs(getElementsByType("player")) do
				if v ~= localPlayer then
					local playerPosX, playerPosY = getElementPosition(v)
					renderBigBlip("blips/1.png", playerPosX, playerPosY, mapPlayerPosX, mapPlayerPosY, 9999, 24, 24, tocolor(160, 200, 255), v, k)
				end
			end
		end

		renderBigBlip("arrow.png", playerPosX, playerPosY, mapPlayerPosX, mapPlayerPosY, false, 20, 20)

		if mapMovedPos then
			renderBigBlip("cross.png", mapPlayerPosX, mapPlayerPosY, mapPlayerPosX, mapPlayerPosY, false, 128, 128)
		end

		dxDrawRectangle(bigmapPosX, bigmapPosY + bigmapHeight - zoneLineHeight, bigmapWidth, zoneLineHeight, tocolor(0, 0, 0, 200))

		if cursorX and cursorY then
			local zoneX = reMap((cursorX - bigmapPosX) / bigmapZoom + (remapTheSecondWay(mapPlayerPosX) - bigmapWidth / bigmapZoom / 2), 0, mapTextureSize, -3000, 3000)
			local zoneY = reMap((cursorY - bigmapPosY) / bigmapZoom + (remapTheFirstWay(mapPlayerPosY) - bigmapHeight / bigmapZoom / 2), 0, mapTextureSize, 3000, -3000)

			dxDrawText(getZoneName(zoneX, zoneY, 0), bigmapPosX + 10, bigmapPosY + bigmapHeight - zoneLineHeight, bigmapPosX + bigmapWidth, bigmapPosY + bigmapHeight, 0xFFFFFFFF, 0.5, getFont("BrushScriptStd"), "left", "center")

			if visibleBlipTooltip then
				dxDrawRectangle(cursorX + respc(12.5), cursorY, dxGetTextWidth(visibleBlipTooltip, blipTooltip_fontsize, getFont("Roboto")) + respc(10), respc(25), tocolor(0, 0, 0, 150))
				dxDrawText(visibleBlipTooltip, cursorX + respc(12.5), cursorY, cursorX + (dxGetTextWidth(visibleBlipTooltip, blipTooltip_fontsize, getFont("Roboto")) + respc(10)) + respc(12.5), cursorY + respc(25), 0xFFFFFFFF, blipTooltip_fontsize, getFont("Roboto"), "center", "center")
			end
		else
			dxDrawText(getZoneName(playerPosX, playerPosY, playerPosZ), bigmapPosX + 10, bigmapPosY + bigmapHeight - zoneLineHeight, bigmapPosX + bigmapWidth, bigmapPosY + bigmapHeight, 0xFFFFFFFF, 0.5, getFont("BrushScriptStd"), "left", "center")
		end

		drawBigmapBlipMenu()

		if visibleBlipTooltip then
			visibleBlipTooltip = false
		end

		if mapMovedPos then
			if getKeyState("space") then
				mapMovedPos = false
				lastDifferencePos = false
			end
		end
	else
		dxDrawRectangle(bigmapPosX, bigmapPosY, bigmapWidth, bigmapHeight, tocolor(0, 0, 0))
		dxDrawImage(bigmapCenterX - 32, bigmapCenterY - 32 - 16, 64, 64, "radar/files/gpslosticon.png")
		dxDrawImage(bigmapCenterX - 128, bigmapCenterY + 16 + 8, 256, 16, "radar/files/gpslosttext.png")
		dxDrawImage(bigmapPosX + bigmapWidth - 64, bigmapPosY, 64, 16, "radar/files/nosignaltext.png")
	end
end

local function setBigmapVisible(visible, openedFromPause)
	if bigmapIsVisible == visible then
		return
	end

	bigmapIsVisible = visible
	setElementData(localPlayer, "bigmapIsVisible", visible, false)
	if visible then
		bigmapOpenedFromPause = openedFromPause == true
		setElementData(localPlayer, "enableall", false)
		showCursor(true)
		setCursorPosition(screenW / 2, screenH / 2)
		setElementData(localPlayer, "hideHUD", true)
		blipMenuFocus = false
		buildBigmapBlipMenu()
	else
		blipMenuFocus = false
		setElementData(localPlayer, "enableall", true)
		if gpsHello and isElement(gpsHello) then
			destroyElement(gpsHello)
		end
		gpsHello = false
		showCursor(false)
		setElementData(localPlayer, "hideHUD", bigmapOpenedFromPause)
		bigmapOpenedFromPause = false
	end
end

function openPauseBigmap()
	ignoreNextBigmapEnter = true
	setTimer(function()
		ignoreNextBigmapEnter = false
	end, 50, 1)
	setBigmapVisible(true, true)
end

function closePauseBigmap()
	if bigmapOpenedFromPause then
		setBigmapVisible(false, false)
	end
end

function isPauseBigmapOpen()
	return bigmapIsVisible and bigmapOpenedFromPause
end

addEventHandler("onClientKey", getRootElement(),
	function (key, pressDown)
		-- F11 does nothing: the bigmap only opens from the pause menu. The event is
		-- still cancelled so the built-in MTA world map cannot open either.
		if key == "F11" then
			if pressDown then
				cancelEvent()
			end
			return
		elseif key == "mouse_wheel_up" or key == "num_add" then
			if pressDown then
				if bigmapIsVisible and bigmapZoom + 0.1 <= 2.1 then
					bigmapZoom = bigmapZoom + 0.1
				end
			end
		elseif key == "mouse_wheel_down" or key == "num_sub" then
			if pressDown then
				if bigmapIsVisible and bigmapZoom - 0.1 >= 0.1 then
					bigmapZoom = bigmapZoom - 0.1
				end
			end
		elseif bigmapIsVisible and pressDown and (key == "arrow_u" or key == "arrow_d" or key == "arrow_l" or key == "arrow_r") then
			cancelEvent()
			if #bigmapBlipMenu > 0 then
				if key == "arrow_u" then
					blipMenuSel = blipMenuSel > 1 and blipMenuSel - 1 or #bigmapBlipMenu
					blipMenuIndex = 1
				elseif key == "arrow_d" then
					blipMenuSel = blipMenuSel < #bigmapBlipMenu and blipMenuSel + 1 or 1
					blipMenuIndex = 1
				elseif key == "arrow_l" then
					blipMenuIndex = blipMenuIndex - 1
				elseif key == "arrow_r" then
					blipMenuIndex = blipMenuIndex + 1
				end
				focusBlipMenuTarget()
			end
		end
	end
)

addEventHandler("onClientClick", getRootElement(),
	function (button, state, cursorX, cursorY)
		if not bigmapIsVisible then
			return
		end

		if state == "up" and mapIsMoving then
			mapIsMoving = false
			return
		end

		local gpsRouteProcess = false

		if button == "left" and state == "up" then
			if occupiedVehicle and carCanGPS() then
				if getElementData(occupiedVehicle, "gpsDestination") then
					setElementData(occupiedVehicle, "gpsDestination", false)
				else
					setElementData(occupiedVehicle, "gpsDestination", {
						reMap((cursorX - bigmapPosX) / bigmapZoom + (remapTheSecondWay(mapPlayerPosX) - bigmapWidth / bigmapZoom / 2), 0, mapTextureSize, -3000, 3000),
						reMap((cursorY - bigmapPosY) / bigmapZoom + (remapTheFirstWay(mapPlayerPosY) - bigmapHeight / bigmapZoom / 2), 0, mapTextureSize, 3000, -3000)
					})
				end
				gpsRouteProcess = true
			end
		end

		--[[
		if not gpsRouteProcess then
			if state == "up" then
				if hoveredWaypointBlip then
					table.remove(createdBlips, hoveredWaypointBlip)
				else
					local blipPosX = reMap((cursorX - bigmapPosX) / bigmapZoom + (remapTheSecondWay(mapPlayerPosX) - bigmapWidth / bigmapZoom / 2), 0, mapTextureSize, -3000, 3000)
					local blipPosY = reMap((cursorY - bigmapPosY) / bigmapZoom + (remapTheFirstWay(mapPlayerPosY) - bigmapHeight / bigmapZoom / 2), 0, mapTextureSize, 3000, -3000)
					local blipPosZ = getGroundPosition(blipPosX, blipPosY, 400) + 3

					createCustomBlip(blipPosX, blipPosY, blipPosZ, "blips/markblip.png", true, 9999, 18, 0xFFFFFFFF)
				end
			end
		end
		]]--
	end
)

bindKey("enter", "down", function()
	if ignoreNextBigmapEnter then
		ignoreNextBigmapEnter = false
		return
	end

	if not bigmapIsVisible then
		return
	end
	
	local gpsRouteProcess = false

	local cursorX,cursorY = screenW/2,screenH/2

	if occupiedVehicle and carCanGPS() then
		if getElementData(occupiedVehicle, "gpsDestination") then
			setElementData(occupiedVehicle, "gpsDestination", false)
		else
			setElementData(occupiedVehicle, "gpsDestination", {
				reMap((cursorX - bigmapPosX) / bigmapZoom + (remapTheSecondWay(mapPlayerPosX) - bigmapWidth / bigmapZoom / 2), 0, mapTextureSize, -3000, 3000),
				reMap((cursorY - bigmapPosY) / bigmapZoom + (remapTheFirstWay(mapPlayerPosY) - bigmapHeight / bigmapZoom / 2), 0, mapTextureSize, 3000, -3000)
			})
		end
		gpsRouteProcess = true
	end

	if not gpsRouteProcess then
		if state == "up" then
			if hoveredWaypointBlip then
				table.remove(createdBlips, hoveredWaypointBlip)
			else
				local blipPosX = reMap((cursorX - bigmapPosX) / bigmapZoom + (remapTheSecondWay(mapPlayerPosX) - bigmapWidth / bigmapZoom / 2), 0, mapTextureSize, -3000, 3000)
				local blipPosY = reMap((cursorY - bigmapPosY) / bigmapZoom + (remapTheFirstWay(mapPlayerPosY) - bigmapHeight / bigmapZoom / 2), 0, mapTextureSize, 3000, -3000)
				local blipPosZ = getGroundPosition(blipPosX, blipPosY, 400) + 3

				createCustomBlip(blipPosX, blipPosY, blipPosZ, "blips/markblip.png", true, 9999, 3, 0xFFFFFFFF)
			end
		end
	end
end)

addEventHandler("onClientRestore", getRootElement(),
	function ()
		if gpsRoute then
			processGPSLines()
		end
	end
)

function renderBlip(icon, blipX, blipY, playerPosX, playerPosY, blipWidth, blipHeight, blipColor, cameraRotation, farShow, blipTableId)
	local blipPosX = minimapRenderHalfSize + (playerPosX - remapTheFirstWay(blipX)) * minimapZoom
	local blipPosY = minimapRenderHalfSize - (playerPosY - remapTheFirstWay(blipY)) * minimapZoom

	if not farShow and (blipPosX > minimapRenderSize or 0 > blipPosX or blipPosY > minimapRenderSize or 0 > blipPosY) then
		return
	end

	local blipIsVisible = true
	if farShow then
		-- Real on-screen position of the blip after the minimap's rotation, with no
		-- render-target clamp, so a far-away blip yields an honest direction.
		local angle = rad((cameraRotation - 270) + 90)
		local cosinus, sinus = cos(angle), sin(angle)

		local relX = blipPosX - minimapRenderHalfSize
		local relY = blipPosY - minimapRenderHalfSize
		local blipScreenPosX = minimapCenterX + cosinus * relX - sinus * relY
		local blipScreenPosY = minimapCenterY + sinus * relX + cosinus * relY

		if blipScreenPosX >= minimapPosX and blipScreenPosX <= minimapPosX + minimapWidth
			and blipScreenPosY >= minimapPosY and blipScreenPosY <= minimapPosY + minimapHeight then
			-- Blip is on the visible minimap: let the normal path draw it, forget any
			-- edge state so re-entering the frame later starts from a fresh position.
			farshowBlipSmooth[blipTableId] = nil
		else
			blipIsVisible = false

			-- Cast the centre -> blip direction onto the minimap frame rectangle.
			local dirX = blipScreenPosX - minimapCenterX
			local dirY = blipScreenPosY - minimapCenterY
			if dirX * dirX + dirY * dirY < 1 then
				dirY = -1
			end

			local pad = max(blipWidth, blipHeight) / 2 + 3
			local halfW = max(1, minimapWidth / 2 - pad)
			local halfH = max(1, minimapHeight / 2 - pad)
			local scale = min(halfW / max(abs(dirX), 0.0001), halfH / max(abs(dirY), 0.0001))

			local targetX = minimapCenterX + dirX * scale
			local targetY = minimapCenterY + dirY * scale
			local targetAngle = atan2(dirY, dirX)

			-- Ease the marker towards its target position/angle, frame-rate independent.
			local now = getTickCount()
			local s = farshowBlipSmooth[blipTableId]
			if not s then
				s = {x = targetX, y = targetY, angle = targetAngle, tick = now}
				farshowBlipSmooth[blipTableId] = s
			end

			local dt = min(now - (s.tick or now), 250)
			s.tick = now
			local t = 1 - math.exp(-dt / EDGE_INDICATOR_TAU)

			local da = targetAngle - s.angle
			if da > math.pi then da = da - 2 * math.pi end
			if da < -math.pi then da = da + 2 * math.pi end

			s.x = s.x + (targetX - s.x) * t
			s.y = s.y + (targetY - s.y) * t
			s.angle = s.angle + da * t

			farshowBlipsData[blipTableId] = {
				posX = s.x - blipWidth / 2,
				posY = s.y - blipHeight / 2,
				centerX = s.x,
				centerY = s.y,
				angle = s.angle,
				icon = icon,
				iconWidth = blipWidth,
				iconHeight = blipHeight,
				color = blipColor,
			}
		end
	end

	if blipIsVisible then
		local path = "radar/files/"..icon
		if fileExists(path) then
			dxDrawImage(blipPosX - blipWidth / 2, blipPosY - blipHeight / 2, blipWidth, blipHeight, path, 180 - cameraRotation, 0, 0, blipColor)
			--outputDebugString("renderBlip: "..path)
		else
			--outputDebugString("File does not exists: "..path)
		end
	end
end

-- Draws one off-minimap blip on the minimap frame: the blip icon pinned to the
-- border, plus a small chevron pointing outward towards the real blip. Position
-- and angle are already smoothed by renderBlip (farshowBlipSmooth).
function drawEdgeIndicator(data)
	local path = "radar/files/" .. data.icon
	if fileExists(path) then
		dxDrawImage(data.posX, data.posY, data.iconWidth, data.iconHeight, path, 0, 0, 0, data.color)
	end

	local a = data.angle
	local reach = max(data.iconWidth, data.iconHeight) / 2 + 3
	local tipX = data.centerX + cos(a) * (reach + 5)
	local tipY = data.centerY + sin(a) * (reach + 5)
	local lX = data.centerX + cos(a + 0.6) * reach
	local lY = data.centerY + sin(a + 0.6) * reach
	local rX = data.centerX + cos(a - 0.6) * reach
	local rY = data.centerY + sin(a - 0.6) * reach

	dxDrawLine(lX + 1, lY + 1, tipX + 1, tipY + 1, tocolor(0, 0, 0, 170), 2)
	dxDrawLine(rX + 1, rY + 1, tipX + 1, tipY + 1, tocolor(0, 0, 0, 170), 2)
	dxDrawLine(lX, lY, tipX, tipY, data.color, 2)
	dxDrawLine(rX, rY, tipX, tipY, data.color, 2)
end

function renderBigBlip(icon, blipX, blipY, playerPosX, playerPosY, renderDistance, blipWidth, blipHeight, blipColor, blipElement, blipId)
	--if renderDistance and getDistanceBetweenPoints2D(playerPosX, playerPosY, blipX, blipY) > renderDistance then return end

	blipWidth = (blipWidth / (4 - bigmapZoom) + 3) * 2.25
	blipHeight = (blipHeight / (4 - bigmapZoom) + 3) * 2.25

	local blipHalfWidth = blipWidth / 2
	local blipHalfHeight = blipHeight / 2

	blipX = max(bigmapPosX + blipHalfWidth, min(bigmapPosX + bigmapWidth - blipHalfWidth, bigmapCenterX + (remapTheFirstWay(playerPosX) - remapTheFirstWay(blipX)) * bigmapZoom))
	blipY = max(bigmapPosY + blipHalfHeight, min(bigmapPosY + bigmapHeight - blipHalfHeight - zoneLineHeight, bigmapCenterY - (remapTheFirstWay(playerPosY) - remapTheFirstWay(blipY)) * bigmapZoom))

	if icon == "arrow.png" then
		local _, _, playerRotation = getElementRotation(localPlayer)
		dxDrawImage(blipX - blipHalfWidth, blipY - blipHalfHeight, blipWidth, blipHeight, "radar/files/" .. icon, abs(360 - playerRotation))
	else
		dxDrawImage(blipX - blipHalfWidth, blipY - blipHalfHeight, blipWidth, blipHeight, "radar/files/" .. icon, 0, 0, 0, blipColor)
	end

	if cursorX and cursorY then
		if isElement(blipElement) then
			if isCursorWithinArea(cursorX, cursorY, blipX - blipHalfWidth, blipY - blipHalfHeight, blipWidth, blipHeight) then
				if getElementType(blipElement) == "player" and playerCanSeePlayers then
					visibleBlipTooltip = getPlayerName(blipElement)
				elseif blipTooltips[icon] then
					visibleBlipTooltip = blipTooltips[icon]
				end
			end
		else
			if blipTooltips[icon] and isCursorWithinArea(cursorX, cursorY, blipX - blipHalfWidth, blipY - blipHalfHeight, blipWidth, blipHeight) then
				visibleBlipTooltip = blipTooltips[icon]

				if icon == "blips/markblip.png" then
					hoveredWaypointBlip = blipId
				end
			end
		end
	end
end

function render3DBlips()
	if getElementDimension(localPlayer) == 0 then
		local playerPosX, playerPosY, playerPosZ = getElementPosition(localPlayer)

		local blipTable = getElementsByType("blip")
		for i = 1, #blipTable do
			if blipTable[i] then
				if getElementAttachedTo(blipTable[i]) ~= localPlayer then
					local blipPosX, blipPosY, blipPosZ = getElementPosition(blipTable[i])
					local screenX, screenY = getScreenFromWorldPosition(blipPosX, blipPosY, blipPosZ)

					local blipDist = getBlipVisibleDistance(blipTable[i])
					if getDistanceBetweenPoints3D(playerPosX,playerPosY,playerPosZ, blipPosX,blipPosY,blipPosZ) <= blipDist then
						if screenX and screenY then
							local distanceBetweenBlip = getDistanceBetweenPoints3D(playerPosX, playerPosY, playerPosZ, blipPosX, blipPosY, blipPosZ)
							local blipIcon = getBlipIcon(blipTable[i])

							dxDrawText(floor(distanceBetweenBlip) .. " m\n" .. (blipTooltips[blipTable[i]] or ""), screenX + 1, screenY + 1 + 7.5 + respc(4), screenX, 0, tocolor(0, 0, 0, 255), 0.75, getFont("Roboto"), "center", "top")
							dxDrawText(floor(distanceBetweenBlip) .. " m#e0e0e0\n" .. (blipTooltips[blipTable[i]] or ""), screenX, screenY + 7.5 + respc(4), screenX, 0, 0xFFFFFFFF, 0.75, getFont("Roboto"), "center", "top", false, false, false, true)
							dxDrawImage(screenX - 9*1.5, screenY - 7.5*1.5, 18*1.5, 15*1.5, "radar/files/blips/" .. blipIcon .. ".png", 0, 0, 0, tocolor(255, 255, 255, 200))
						end
					end
				end
			end
		end
		for i = 1, #createdBlips do
			local blipPosX, blipPosY, blipPosZ = createdBlips[i].posX, createdBlips[i].posY, createdBlips[i].posZ
			local screenX, screenY = getScreenFromWorldPosition(blipPosX, blipPosY, blipPosZ)

			local blipDist = createdBlips[i].renderDistance
			if getDistanceBetweenPoints3D(playerPosX,playerPosY,playerPosZ, blipPosX,blipPosY,blipPosZ) <= blipDist then
				if screenX and screenY then
					local distanceBetweenBlip = getDistanceBetweenPoints3D(playerPosX, playerPosY, playerPosZ, blipPosX, blipPosY, blipPosZ)
					local blipIcon = createdBlips[i].icon

					dxDrawText(floor(distanceBetweenBlip) .. " m\n" .. (blipTooltips[createdBlips[i]] or ""), screenX + 1, screenY + 1 + 7.5 + respc(4), screenX, 0, tocolor(0, 0, 0, 255), 0.75, getFont("Roboto"), "center", "top")
					dxDrawText(floor(distanceBetweenBlip) .. " m#e0e0e0\n" .. (blipTooltips[createdBlips[i]] or ""), screenX, screenY + 7.5 + respc(4), screenX, 0, 0xFFFFFFFF, 0.75, getFont("Roboto"), "center", "top", false, false, false, true)
					dxDrawImage(screenX - 9*1.5, screenY - 7.5*1.5, 18*1.5, 15*1.5, "radar/files/" .. blipIcon, 0, 0, 0, tocolor(255, 255, 255, 200))
				end
			end
		end
	end
end

function createCustomBlip(x, y, z, icon, farShow, visibleDistance, size, color)
	table.insert(createdBlips, {
		posX = x,
		posY = y,
		posZ = z,
		icon = icon,
		farShow = farShow,
		renderDistance = visibleDistance or 9999,
		iconSize = size or 2,
		color = color or tocolor(255, 255, 255)
	})
end

function deleteCustomBlip(count)
	table.remove(createdBlips, count)
end

function remapTheFirstWay(coord)
	return (-coord + 3000) / mapRatio
end

function remapTheSecondWay(coord)
	return (coord + 3000) / mapRatio
end

function carCanGPS()
	if getElementData(occupiedVehicle, "dbid") then
		carCanGPSVal = getElementData(occupiedVehicle, "vehicle.tuning.seeGO") or false
	else
		carCanGPSVal = 1
	end

	return carCanGPSVal
end

function addGPSLine(x, y)
	table.insert(gpsLines, {remapTheFirstWay(x), remapTheFirstWay(y)})
end

function processGPSLines()
	local routeStartPosX, routeStartPosY = 99999, 99999
	local routeEndPosX, routeEndPosY = -99999, -99999

	for i = 1, #gpsLines do
		if gpsLines[i][1] < routeStartPosX then
			routeStartPosX = gpsLines[i][1]
		end

		if gpsLines[i][2] < routeStartPosY then
			routeStartPosY = gpsLines[i][2]
		end

		if gpsLines[i][1] > routeEndPosX then
			routeEndPosX = gpsLines[i][1]
		end

		if gpsLines[i][2] > routeEndPosY then
			routeEndPosY = gpsLines[i][2]
		end
	end

	local routeWidth = (routeEndPosX - routeStartPosX) + 16
	local routeHeight = (routeEndPosY - routeStartPosY) + 16

	if isElement(gpsRouteImage) then
		destroyElement(gpsRouteImage)
	end

	gpsRouteImage = dxCreateRenderTarget(routeWidth, routeHeight, true)
	gpsRouteImageData = {routeStartPosX - 8, routeStartPosY - 8, routeWidth, routeHeight}

	dxSetRenderTarget(gpsRouteImage)
	dxSetBlendMode("modulate_add")

	dxDrawImage(gpsLines[1][1] - routeStartPosX + 8 - 4, gpsLines[1][2] - routeStartPosY + 8 - 4, 8, 8, "radar/gps/images/dot.png")

	for i = 2, #gpsLines do
		if gpsLines[i - 1] then
			local startX = gpsLines[i][1] - routeStartPosX + 8
			local startY = gpsLines[i][2] - routeStartPosY + 8
			local endX = gpsLines[i - 1][1] - routeStartPosX + 8
			local endY = gpsLines[i - 1][2] - routeStartPosY + 8

			dxDrawImage(startX - 4, startY - 4, 8, 8, "radar/gps/images/dot.png")
			dxDrawLine(startX, startY, endX, endY, tocolor(255, 255, 255), 9)
		end
	end

	dxSetBlendMode("blend")
	dxSetRenderTarget()
end

function clearGPSRoute()
	gpsLines = {}

	if isElement(gpsRouteImage) then
		destroyElement(gpsRouteImage)
	end
	gpsRouteImage = false
end


function dxDrawInnerBorder(x, y, w, h, borderSize, borderColor, postGUI)
	borderSize = borderSize or 2
	borderColor = borderColor or tocolor(0, 0, 0, 255)

	dxDrawRectangle(x, y, w, borderSize, borderColor, postGUI)
	dxDrawRectangle(x, y + h - borderSize, w, borderSize, borderColor, postGUI)
	dxDrawRectangle(x, y + borderSize, borderSize, h - (borderSize * 2), borderColor, postGUI)
	dxDrawRectangle(x + w - borderSize, y + borderSize, borderSize, h - (borderSize * 2), borderColor, postGUI)
end

function dxDrawOuterBorder(x, y, w, h, borderSize, borderColor, postGUI)
	borderSize = borderSize or 2
	borderColor = borderColor or tocolor(0, 0, 0, 255)

	dxDrawRectangle(x - borderSize, y - borderSize, w + (borderSize * 2), borderSize, borderColor, postGUI)
	dxDrawRectangle(x, y + h, w, borderSize, borderColor, postGUI)
	dxDrawRectangle(x - borderSize, y, borderSize, h + borderSize, borderColor, postGUI)
	dxDrawRectangle(x + w, y, borderSize, h + borderSize, borderColor, postGUI)
end

function dxDrawBorderedImageSection(x, y, w, h, ux, uy, uw, uh, path, rx, ry, rz, color, postGUI)
	dxDrawImageSection(x - 1, y - 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x - 1, y + 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x + 1, y - 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x + 1, y + 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x, y, w, h, ux, uy, uw, uh, path, rx, ry, rz, color, postGUI)
end

function dxDrawBorderedText(text, x, y, w, h, color, ...)
	local textWithoutHEX = gsub(text, "#%x%x%x%x%x%x", "")
	dxDrawText(textWithoutHEX, x - 1, y - 1, w - 1, h - 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(textWithoutHEX, x - 1, y + 1, w - 1, h + 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(textWithoutHEX, x + 1, y - 1, w + 1, h - 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(textWithoutHEX, x + 1, y + 1, w + 1, h + 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(text, x, y, w, h, color, ...)
end

function dxDrawRoundedRectangle(x, y, w, h, color, postGUI, subPixelPositioning, radius)
	radius = radius or 5

	dxDrawImage(x, y, radius, radius, getTexture("round"), 0, 0, 0, color, postGUI)
	dxDrawRectangle(x, y + radius, radius, h - radius * 2, color, postGUI, subPixelPositioning)
	dxDrawImage(x, y + h - radius, radius, radius, getTexture("round"), 270, 0, 0, color, postGUI)
	dxDrawRectangle(x + radius, y, w - radius * 2, h, color, postGUI, subPixelPositioning)
	dxDrawImage(x + w - radius, y, radius, radius, getTexture("round"), 90, 0, 0, color, postGUI)
	dxDrawRectangle(x + w - radius, y + radius, radius, h - radius * 2, color, postGUI, subPixelPositioning)
	dxDrawImage(x + w - radius, y + h - radius, radius, radius, getTexture("round"), 180, 0, 0, color, postGUI)
end

function getHudCursorPos()
	if isCursorShowing() then
		return getCursorPosition()
	end
	return false
end

function getFont(name)
	if createdFonts[name] then
		return createdFonts[name]
	end

	return "default"
end

function initFont(name, path, size)
	if not createdFonts[name] then
		createdFonts[name] = dxCreateFont("files/" .. path, resp(size), false, "antialiased")
	else
		return createdFonts[name]
	end
end

function isCursorWithinArea(cx, cy, x, y, w, h)
	if isCursorShowing() then
		if cx >= x and cx <= x + w and cy >= y and cy <= y + h then
			return true
		end
	end

	return false
end

addEventHandler("onClientVehicleEnter", getRootElement(),
	function (player)
		if player == localPlayer then
			if occupiedVehicle ~= source then
				occupiedVehicle = source
			end
		end
	end
)

addEventHandler("onClientVehicleExit", getRootElement(),
	function (player)
		if player == localPlayer then
			if occupiedVehicle == source then
				occupiedVehicle = false
			end
		end
	end
)

addEventHandler("onClientElementDestroy", getRootElement(),
	function ()
		if occupiedVehicle == source then
			occupiedVehicle = false
		end
	end
)

addEventHandler("onClientVehicleExplode", getRootElement(),
	function ()
		if occupiedVehicle == source then
			occupiedVehicle = false
		end
	end
)

function getVehicleSpeed(vehicle)
	local velocityX, velocityY, velocityZ = getElementVelocity(vehicle)
	return ((velocityX * velocityX + velocityY * velocityY + velocityZ * velocityZ) ^ 0.5) * 187.5
end

-- Collect every point-of-interest blip on the map, grouped by icon/type, so the
-- player can jump between all hospitals, all train stations, etc.
function buildBigmapBlipMenu()
	local groups, order = {}, {}

	local function add(icon, x, y)
		local label = blipTooltips[icon]
		if not label or label == "" then return end
		local g = groups[icon]
		if not g then
			g = { icon = icon, label = label, positions = {} }
			groups[icon] = g
			order[#order + 1] = icon
		end
		g.positions[#g.positions + 1] = { x, y }
	end

	for i = 1, #createdBlips do
		local b = createdBlips[i]
		if b and b.icon then add(b.icon, b.posX, b.posY) end
	end

	for _, v in ipairs(getElementsByType("blip")) do
		if getElementAttachedTo(v) ~= localPlayer then
			local x, y = getElementPosition(v)
			add("blips/" .. getBlipIcon(v) .. ".png", x, y)
		end
	end

	local list = {}
	for _, icon in ipairs(order) do list[#list + 1] = groups[icon] end
	table.sort(list, function(a, b) return a.label < b.label end)

	bigmapBlipMenu = list
	if blipMenuSel > #list then blipMenuSel = 1 end
	blipMenuIndex = 1
end

function focusBlipMenuTarget()
	local cat = bigmapBlipMenu[blipMenuSel]
	if not cat or #cat.positions == 0 then
		blipMenuFocus = false
		return
	end

	if blipMenuIndex < 1 then blipMenuIndex = #cat.positions end
	if blipMenuIndex > #cat.positions then blipMenuIndex = 1 end

	local p = cat.positions[blipMenuIndex]
	blipMenuFocus = { p[1], p[2] }
end

-- Arrow-navigable blip-type menu, top-right of the bigmap (mouse still moves the map).
function drawBigmapBlipMenu()
	if #bigmapBlipMenu == 0 then return end

	local rowH = respc(26)
	local panelW = respc(236)
	local lx = bigmapPosX + bigmapWidth - panelW - respc(20)
	local ly = bigmapPosY + respc(20)
	local panelH = rowH * #bigmapBlipMenu + respc(16)

	dxDrawRectangle(lx, ly, panelW, panelH, tocolor(0, 0, 0, 175))

	for i, cat in ipairs(bigmapBlipMenu) do
		local ry = ly + respc(8) + (i - 1) * rowH
		local sel = (i == blipMenuSel)

		if sel then
			dxDrawRectangle(lx, ry - respc(2), panelW, rowH, tocolor(240, 243, 247, 235))
			dxDrawRectangle(lx, ry - respc(2), respc(3), rowH, tocolor(70, 180, 240, 255))
		end

		if fileExists("radar/files/" .. cat.icon) then
			dxDrawImage(lx + respc(10), ry, respc(16), respc(16), "radar/files/" .. cat.icon)
		end

		dxDrawText(cat.label, lx + respc(34), ry - respc(2), lx + panelW - respc(46), ry + rowH - respc(2),
			sel and tocolor(12, 16, 22) or 0xFFFFFFFF, 0.85, getFont("Roboto"), "left", "center")

		local countText = sel and (blipMenuIndex .. " / " .. #cat.positions) or tostring(#cat.positions)
		dxDrawText(countText, lx + respc(10), ry - respc(2), lx + panelW - respc(10), ry + rowH - respc(2),
			sel and tocolor(12, 16, 22) or tocolor(150, 162, 176), 0.78, getFont("Roboto"), "right", "center")
	end

	dxDrawText("Up/Down: type     Left/Right: step", lx, ly + panelH + respc(4), lx + panelW, ly + panelH + respc(20),
		tocolor(210, 216, 224), 0.72, getFont("Roboto"), "center", "top")
end

-- Exported: the pause menu (ui_pause) draws this as the map preview on its MAP
-- tab, before the player opens the full-screen bigmap.
function renderPausePreview(px, py, pw, ph)
	if not (px and py and pw and ph) or pw <= 0 or ph <= 0 then
		return
	end

	px, py, pw, ph = floor(px), floor(py), floor(pw), floor(ph)

	dxDrawRectangle(px, py, pw, ph, tocolor(18, 28, 38, 255))

	if getElementDimension(localPlayer) ~= 0 or getElementInterior(localPlayer) ~= 0 then
		dxDrawImage(px + pw / 2 - 32, py + ph / 2 - 40, 64, 64, "radar/files/gpslosticon.png")
		dxDrawText("NO SIGNAL", px, py + ph / 2 + 28, px + pw, py + ph / 2 + 48, 0xFFFFFFFF, 1, "default-bold", "center", "center")
		dxDrawOuterBorder(px, py, pw, ph, 2, tocolor(0, 0, 0, 220))
		return
	end

	local playerPosX, playerPosY = getElementPosition(localPlayer)
	local zoom = 0.5
	local map = getTexture("bigmapMap")
	if map then
		dxDrawImageSection(px, py, pw, ph,
			remapTheSecondWay(playerPosX) - (pw / zoom) / 2,
			remapTheFirstWay(playerPosY) - (ph / zoom) / 2,
			pw / zoom, ph / zoom, map)
	end

	local function toScreen(wx, wy)
		return px + pw / 2 + ((wx - playerPosX) / mapRatio) * zoom,
			py + ph / 2 - ((wy - playerPosY) / mapRatio) * zoom
	end

	for i = 1, #createdBlips do
		local b = createdBlips[i]
		if b then
			local bx, by = toScreen(b.posX, b.posY)
			if bx >= px and bx <= px + pw and by >= py and by <= py + ph then
				local s = (b.iconSize or 2) * 7
				dxDrawImage(bx - s / 2, by - s / 2, s, s, "radar/files/" .. b.icon, 0, 0, 0, b.color)
			end
		end
	end

	for _, v in ipairs(getElementsByType("blip")) do
		if getElementAttachedTo(v) ~= localPlayer then
			local wx, wy = getElementPosition(v)
			local bx, by = toScreen(wx, wy)
			if bx >= px and bx <= px + pw and by >= py and by <= py + ph then
				dxDrawImage(bx - 9, by - 9, 18, 18, "radar/files/blips/" .. getBlipIcon(v) .. ".png")
			end
		end
	end

	local _, _, rot = getElementRotation(localPlayer)
	dxDrawImage(px + pw / 2 - 11, py + ph / 2 - 11, 22, 22, "radar/files/arrow.png", abs(360 - rot))

	dxDrawOuterBorder(px, py, pw, ph, 2, tocolor(0, 0, 0, 220))
end
