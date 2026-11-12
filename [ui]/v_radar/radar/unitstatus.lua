-- Unit indicator: above the microphone icon, e.g. "L-100 ELÉRHETŐ" / "ALS-301 HELYSZÍNEN" for players that are
-- members of a police or EMS unit. Data: element data "radar.unit" (radar/unitstatus_server.lua).
-- Icon is white tinted to the microphone's idle grey. Colours and texts come from police_system
-- (UNIT_STATUS in shared/radio.lua, keys police_system.status.*) and med_erm (Config.STATUS, keys
-- med_erm.config.*). Called from renderMinimap right after renderVoiceIcon.

local ICONS = { pd = "radar/files/unit_pd.png", ems = "radar/files/unit_ems.png" }
local ICON_TINT = { 150, 150, 150 }       -- same grey as the idle microphone (radar/voiceicon.lua)
local CALLSIGN_COLOR = { 220, 220, 220 }

-- police_system shared/radio.lua UNIT_STATUS
local PD_STATUS = {
	pursuit    = { 235, 64, 64 },
	available  = { 64, 200, 110 },
	responding = { 240, 200, 60 },
	busy       = { 245, 140, 50 },
}
-- med_erm shared/config.lua Config.STATUS (+ its locale key)
local EMS_STATUS = {
	available = { { 46, 160, 67 },   "med_erm.config.available" },
	assigned  = { { 255, 128, 122 }, "med_erm.config.assigned" },
	enroute   = { { 218, 54, 51 },   "med_erm.config.en_route" },
	onscene   = { { 56, 132, 244 },  "med_erm.config.on_scene" },
	handover  = { { 230, 190, 40 },  "med_erm.config.handover" },
	["break"] = { { 245, 140, 30 },  "med_erm.config.break" },
}

local font, fontSize = nil, 0

local function shadowText(text, x, y, color, f)
	dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 180), 1, f, "left", "center")
	dxDrawText(text, x, y, x, y, color, 1, f, "left", "center")
end

local function describe(u)
	if u.a == "pd" then
		local col = PD_STATUS[u.s]
		if not col then return end
		return col, L.upper(L("police_system.status." .. u.s))
	end
	local def = EMS_STATUS[u.s]
	if not def then return end
	return def[1], L.upper(L(def[2]))
end

function renderUnitStatus(mx, my, mw, mh)
	local u = getElementData(localPlayer, "radar.unit")
	if type(u) ~= "table" or not ICONS[u.a] then return end
	local col, status = describe(u)
	if not col then return end

	-- same geometry as the microphone slot (radar/voiceicon.lua); this row is one slot above it
	local speedoSize = math.floor(math.min(mw * 0.375, mh * 0.5333))
	local box = math.floor(speedoSize * 0.4)
	local x = mx + mw
	local y = my + mh - speedoSize - box - 2 - math.floor(box * 0.75)

	local size = math.max(8, math.floor(box * 0.3))
	if size ~= fontSize then
		if isElement(font) then destroyElement(font) end
		font = dxCreateFont("files/RobotoB.ttf", size, false, "antialiased") or "default-bold"
		fontSize = size
	end

	local pad = math.floor(box * 0.22)
	dxDrawImage(x + pad, y + pad, box - pad * 2, box - pad * 2, ICONS[u.a], 0, 0, 0,
		tocolor(ICON_TINT[1], ICON_TINT[2], ICON_TINT[3], 255))

	local cy = y + box / 2
	local tx = x + box + 2
	shadowText(u.c, tx, cy, tocolor(CALLSIGN_COLOR[1], CALLSIGN_COLOR[2], CALLSIGN_COLOR[3], 255), font)
	tx = tx + dxGetTextWidth(u.c, 1, font) + math.floor(box * 0.3)
	shadowText(status, tx, cy, tocolor(col[1], col[2], col[3], 255), font)
end

addEventHandler("onClientResourceStop", resourceRoot, function()
	if isElement(font) then destroyElement(font) end
end)
