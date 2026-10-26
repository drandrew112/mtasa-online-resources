-- Speedometer: round gauge right of the minimap, land vehicles only, km/h.
-- renderSpeedo() is called from renderMinimap (radar/sourceC.lua), so it follows the minimap's
-- position, visibility (bigmap, hideHUD) and size.

local SPEEDO_MAX = 240          -- km/h at a full arc
local SPEEDO_STEPS = 120        -- fill arc is rebuilt every SPEEDO_MAX / SPEEDO_STEPS km/h
local SPEEDO_GAP = 6            -- px between the minimap and the gauge (ui scaled)
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
local speedoFill
local speedoFillStep = -1
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
	if isElement(speedoFill) then destroyElement(speedoFill) end
	if isElement(speedoFont) then destroyElement(speedoFont) end
	speedoBase, speedoFill, speedoFont = nil, nil, nil
	speedoFillStep = -1
end

local function buildSpeedo(size)
	destroySpeedo()
	speedoSize = size
	if not svgCreate then return end
	local c = size / 2
	local track = arcPath(size, SPEEDO_ARC_START, SPEEDO_ARC_START + SPEEDO_ARC_SPAN):format("#ffffff", "0.15")
	speedoBase = svgCreate(size * 2, size * 2, svgDoc(size, string.format('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="#000000" fill-opacity="0.65"/>%s', c, c, c, track)))
	speedoFont = dxCreateFont("files/RobotoB.ttf", math.max(8, floor(size * 0.3)), false, "antialiased")
end

local function setFill(step)
	if step == speedoFillStep then return end
	speedoFillStep = step
	if isElement(speedoFill) then destroyElement(speedoFill) end
	speedoFill = nil
	if step <= 0 or not svgCreate then return end
	local a1 = SPEEDO_ARC_START + SPEEDO_ARC_SPAN * step / SPEEDO_STEPS
	speedoFill = svgCreate(speedoSize * 2, speedoSize * 2, svgDoc(speedoSize, arcPath(speedoSize, SPEEDO_ARC_START, a1):format("#ffffff", "1")))
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

	local x = mx + mw + respc(SPEEDO_GAP)
	local y = my + mh - size

	if speedoBase then
		dxDrawImage(x, y, size, size, speedoBase)
		setFill(floor(min(1, shownSpeed / SPEEDO_MAX) * SPEEDO_STEPS + 0.5))
		if speedoFill then
			dxDrawImage(x, y, size, size, speedoFill)
		end
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
