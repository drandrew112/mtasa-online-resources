-- Speedometer: square gauge panel attached to the right of the minimap, land vehicles only, km/h.
-- renderSpeedo() is called from renderMinimap (radar/sourceC.lua), so it follows the minimap's
-- position, visibility (bigmap, hideHUD) and size.

local SPEEDO_MAX = 240          -- km/h at a full arc
local SPEEDO_SEG_DEG = 3        -- fill arc is a triangle strip, one segment per this many degrees
local SPEEDO_CORNER = 0.226      -- top right corner radius, fraction of the panel size
local SPEEDO_ARC_START = 135    -- deg, svg angles run clockwise from +x
local SPEEDO_ARC_SPAN = 270
local SPEEDO_SMOOTHING = 0.25   -- 0..1 per frame, lower = lazier needle

local LAND_VEHICLE_TYPES = {
	["Automobile"] = true,
	["Bike"] = true,
	["BMX"] = true,
	["Quad"] = true,
	["Monster Truck"] = true,
}

local speedoSize = 0
local speedoBase
local speedoFont
local shownSpeed = 0

local function arcPath(size, a0, a1)
	local c, r = size / 2, size * 50 / 120
	local sx, sy = c + cos(rad(a0)) * r, c + sin(rad(a0)) * r
	local ex, ey = c + cos(rad(a1)) * r, c + sin(rad(a1)) * r
	local large = (a1 - a0) > 180 and 1 or 0
	return string.format('<path d="M%.2f %.2f A%.2f %.2f 0 %d 1 %.2f %.2f" fill="none" stroke="%%s" stroke-opacity="%%s" stroke-width="%.2f" stroke-linecap="round"/>', sx, sy, r, r, large, ex, ey, size * 7 / 120)
end

local function svgDoc(size, body)
	return string.format('<svg width="%d" height="%d" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">%s</svg>', size * 2, size * 2, size, size, body)
end

local function destroySpeedo()
	if isElement(speedoBase) then destroyElement(speedoBase) end
	if isElement(speedoFont) then destroyElement(speedoFont) end
	speedoBase, speedoFont = nil, nil
end

local function buildSpeedo(size)
	destroySpeedo()
	speedoSize = size
	if not svgCreate then return end
	local track = arcPath(size, SPEEDO_ARC_START, SPEEDO_ARC_START + SPEEDO_ARC_SPAN):format("#ffffff", "0.15")
	-- square panel, flat on the minimap side, only the top right corner rounded
	local cr = size * SPEEDO_CORNER
	local panel = string.format('<path d="M0 0 H%.2f A%.2f %.2f 0 0 1 %.2f %.2f V%.2f H0 Z" fill="#000000" fill-opacity="0.65"/>', size - cr, cr, cr, size, cr, size)
	speedoBase = svgCreate(size * 2, size * 2, svgDoc(size, panel .. track))
	speedoFont = dxCreateFont("files/RobotoB.ttf", math.max(8, floor(size * 0.3)), false, "antialiased")
end

-- Fill arc drawn as geometry every frame: no texture is rebuilt, so it cannot flicker.
local function drawFillArc(cx, cy, size, fraction)
	if fraction <= 0 then return end
	local rMid, half = size * 50 / 120, size * 3.5 / 120
	local color = tocolor(255, 255, 255, 255)
	local span = SPEEDO_ARC_SPAN * fraction
	local segs = max(1, ceil(span / SPEEDO_SEG_DEG))
	local strip = {}
	for i = 0, segs do
		local a = rad(SPEEDO_ARC_START + span * i / segs)
		local ca, sa = cos(a), sin(a)
		strip[#strip + 1] = {cx + ca * (rMid + half), cy + sa * (rMid + half), color}
		strip[#strip + 1] = {cx + ca * (rMid - half), cy + sa * (rMid - half), color}
	end
	dxDrawPrimitive("trianglestrip", false, unpack(strip))

	-- round caps
	for _, deg in ipairs({SPEEDO_ARC_START, SPEEDO_ARC_START + span}) do
		local a = rad(deg)
		local px, py = cx + cos(a) * rMid, cy + sin(a) * rMid
		local fan = {{px, py, color}}
		for k = 0, 16 do
			local t = rad(k * 360 / 16)
			fan[#fan + 1] = {px + cos(t) * half, py + sin(t) * half, color}
		end
		dxDrawPrimitive("trianglefan", false, unpack(fan))
	end
end

local function getLandVehicle()
	local veh = getPedOccupiedVehicle(localPlayer)
	if veh and LAND_VEHICLE_TYPES[getVehicleType(veh)] then
		return veh
	end
end

function renderSpeedo(mx, my, mw, mh)
	local veh = getLandVehicle()
	if not veh then
		shownSpeed = 0
		return
	end

	local size = floor(min(mw * 0.375, mh * 0.5333))
	if size ~= speedoSize then
		buildSpeedo(size)
	end

	local vx, vy, vz = getElementVelocity(veh)
	local speed = sqrt(vx * vx + vy * vy + vz * vz) * 180
	shownSpeed = shownSpeed + (speed - shownSpeed) * SPEEDO_SMOOTHING
	if abs(speed - shownSpeed) < 0.5 then shownSpeed = speed end

	local x = mx + mw
	local y = my + mh - size

	if speedoBase then
		dxDrawImage(x, y, size, size, speedoBase)
		drawFillArc(x + size / 2, y + size / 2, size, min(1, shownSpeed / SPEEDO_MAX))
	end

	local font = speedoFont or "default-bold"
	local numberTop = y + size * 0.27
	local numberBottom = y + size * 0.65
	local text = tostring(floor(shownSpeed + 0.5))
	dxDrawText(text, x + 1, numberTop + 1, x + size + 1, numberBottom + 1, tocolor(0, 0, 0, 200), 1, font, "center", "center")
	dxDrawText(text, x, numberTop, x + size, numberBottom, tocolor(255, 255, 255, 255), 1, font, "center", "center")
	dxDrawText("km/h", x, y + size * 0.62, x + size, y + size * 0.78, tocolor(184, 188, 194, 255), 0.9, "default", "center", "center")
end

addEventHandler("onClientResourceStop", resourceRoot, destroySpeedo)
