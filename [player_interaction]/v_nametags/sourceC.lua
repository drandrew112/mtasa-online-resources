if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

-- Nametag design (2026-10-25):
--   [crew tag] [munka kártya]
--   (mic) [RANG] Név [lvl] (...)
--   ----- páncél (ha van)
--   ===== health (a név színében, 25% alatt piros)
-- Név színe csak az admin szinttől függ: admin = rang színe, egyébként fehér.
-- Munka (work_core duty): mini kártya a crew tag mellett, a munka színével és nevével.

local adminTitles_forNametag = {}
local function build_adminTitles_forNametag()
	-- a locale string pl. "#000000[#BAFFBAADMIN#000000] #FF0000": a szín a "[" utáni kód, a felirat a sima szöveg
	adminTitles_forNametag = {}
	local keys = { "trial_mod", "mod", "admin", "superadmin", "dev", "owner" }
	for level, key in ipairs(keys) do
		local raw = L("v_nametags.sourcec." .. key)
		local hex = raw:match("%[#(%x%x%x%x%x%x)") or "FFFFFF"
		local text = stripColorCodes(raw):gsub("[%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", "")
		adminTitles_forNametag[level] = {
			text = text,
			r = tonumber(hex:sub(1, 2), 16), g = tonumber(hex:sub(3, 4), 16), b = tonumber(hex:sub(5, 6), 16),
		}
	end
end

function RGBToHex(red, green, blue, alpha)
	if( ( red < 0 or red > 255 or green < 0 or green > 255 or blue < 0 or blue > 255 ) or ( alpha and ( alpha < 0 or alpha > 255 ) ) ) then
		return nil
	end
	if alpha then
		return string.format("#%.2X%.2X%.2X%.2X", red, green, blue, alpha)
	else
		return string.format("#%.2X%.2X%.2X", red, green, blue)
	end
end

setElementData(localPlayer, "toggleOwnNametag", true)

-- MTA színkódok (#RRGGBB) eltávolítása egy stringből
function stripColorCodes(text)
    return (tostring(text or ""):gsub("#%x%x%x%x%x%x", ""))
end


setPedTargetingMarkerEnabled(false)

-- fej pozíció (8-as csont); ha nincs streamelve, a test közepe + 0.6
local function getHeadPosition(ped)
	local x, y, z = getPedBonePosition(ped, 8)
	if not x then
		x, y, z = getElementPosition(ped)
		z = z + 0.6
	end
	return x, y, z
end

-- fejtől fejig, peds/járművek nélkül: alacsony belső plafon ne takarja ki
local function canSee(hX, hY, hZ, target)
	local tX, tY, tZ = getHeadPosition(target)
	return isLineOfSightClear(hX, hY, hZ, tX, tY, tZ, true, false, false, true, false, true), tX, tY, tZ
end

-- Cache: nearby players -> their pre-built display data (PERF-06).
local nearby = {}
local FONT_S = 1.2 -- fix betűméret, nem skálázódik távolsággal/felbontással
local FONT = "default-bold"
local SMALL_S = 1.0
local GAP = 5
local NEARBY_RANGE = 50
local BAR_W, HP_H, ARMOR_H = 70, 4, 2
local ICON = 14
local COLOR_WHITE = { 255, 255, 255 }
local COLOR_LOWHP = { 255, 77, 77 }
local IMG_MIC, IMG_BUBBLE, IMG_DOT = "img/mic.png", "img/bubble.png", "img/dot.png"

-- voice: a kliens maga látja, ki beszél (nincs element data)
local speaking = {}
addEventHandler("onClientPlayerVoiceStart", root, function() speaking[source] = true end)
addEventHandler("onClientPlayerVoiceStop", root, function() speaking[source] = nil end)

-- element data keys that affect what is displayed
local watchedKeys = {
	admin_level = true, accName = true, displayName = true, adminDuty = true, admin_name = true,
	level = true, chatTyping = true, ["work.id"] = true, crewTag = true,
}

-- munka színe + neve a work_core listából (nil, ha még nem szinkronizált)
local function getWorkInfo(workId)
	if not workId then return nil end
	local ok, work = pcall(function() return exports.work_core:getWork(workId) end)
	if not (ok and type(work) == "table") then return nil end
	local c = type(work.color) == "table" and work.color[1] and { work.color[1], work.color[2], work.color[3] } or { 130, 130, 130 }
	return c, tostring(work.name or workId)
end

local function setWork(entry, workId)
	entry.workId = workId or false
	entry.workColor, entry.workName = getWorkInfo(entry.workId)
	entry.workW = entry.workName and (L.width(entry.workName, SMALL_S, FONT) + 10) or 0
end

-- (re)build every displayed value of one player from element data
local function buildEntry(p, entry)
	entry = entry or {}
	local adminlevel = tonumber(getElementData(p, "admin_level")) or 0
	local adminDuty = getElementData(p, "adminDuty") == true

	local name = getElementData(p, "displayName") or getElementData(p, "accName")
	if adminDuty then
		name = getElementData(p, "admin_name") or name
	end
	name = stripColorCodes(name)

	local title = adminTitles_forNametag[adminlevel]
	entry.admin = title
	entry.adminDuty = adminDuty
	entry.adminW = title and (L.width(title.text, SMALL_S, FONT) + 8) or 0

	setWork(entry, getElementData(p, "work.id"))
	entry.crewW = uicore:getCrewTagBoxSize(getElementData(p, "crewTag"), SMALL_S) or 0

	entry.name = name
	entry.nameW = L.width(name, FONT_S, FONT)
	entry.nameH = dxGetFontHeight(FONT_S, FONT)
	entry.level_text = tostring(getElementData(p, "level") or "")
	entry.lvlW = (entry.level_text ~= "") and (L.width(entry.level_text, SMALL_S, FONT) + 8) or 0
	entry.smallH = dxGetFontHeight(SMALL_S, FONT)
	entry.typing = getElementData(p, "chatTyping") == true
	return entry
end

local function rebuildAll()
	for p, entry in pairs(nearby) do
		buildEntry(p, entry)
	end
end

addEventHandler("onClientElementDataChange", root, function(key)
	if watchedKeys[key] and nearby[source] then
		buildEntry(source, nearby[source])
	end
end)

addEventHandler("onClientPlayerQuit", root, function()
	nearby[source] = nil
	speaking[source] = nil
end)

-- 500 ms: ki van a közelben (streamelt, azonos int/dim, látható, <= 50 egység, LOS)
local function refreshNearby()
	if not isElement(localPlayer) then return end
	local lX, lY, lZ = getElementPosition(localPlayer)
	local hX, hY, hZ = getHeadPosition(localPlayer)
	local lInt, lDim = getElementInterior(localPlayer), getElementDimension(localPlayer)
	local seen = {}

	for _, p in ipairs(getElementsByType("player", root, true)) do
		if not (p == localPlayer and getElementData(localPlayer, "toggleOwnNametag")) then
			local pX, pY, pZ = getElementPosition(p)
			if getElementAlpha(p) ~= 0
				and getElementInterior(p) == lInt
				and getElementDimension(p) == lDim
				and getDistanceBetweenPoints3D(pX, pY, pZ, lX, lY, lZ) <= NEARBY_RANGE then
				local visible = getPedOccupiedVehicle(p) or canSee(hX, hY, hZ, p)
				if visible then
					seen[p] = true
					if not nearby[p] then
						setPlayerNametagShowing(p, false)
						nearby[p] = buildEntry(p)
					elseif nearby[p].workId and not nearby[p].workName then
						-- a work_core lista később szinkronizálódhat
						setWork(nearby[p], nearby[p].workId)
					end
				end
			end
		end
	end

	for p in pairs(nearby) do
		if not seen[p] then nearby[p] = nil end
	end
end

local function drawOutline(x, y, w, h, color)
	dxDrawRectangle(x, y, w, 1, color)
	dxDrawRectangle(x, y + h - 1, w, 1, color)
	dxDrawRectangle(x, y, 1, h, color)
	dxDrawRectangle(x + w - 1, y, 1, h, color)
end

-- név színe csak az admin szinttől függ
local function nameColor(e)
	if e.admin then return { e.admin.r, e.admin.g, e.admin.b } end
	return COLOR_WHITE
end

local function renderNametags()
	local now = getTickCount()
	for p, e in pairs(nearby) do
		if isElement(p) then
			local pX, pY, pZ = getElementPosition(p)
			local sX, sY = getScreenFromWorldPosition(pX, pY, pZ + 1.2)
			if sX and sY then
				local col = nameColor(e)
				local cr, cg, cb = col[1], col[2], col[3]

				-- fő sor: [RANG] Név [lvl], sX-re centrálva; a mic balra, a buborék jobbra lóg ki
				local totalW = e.nameW
					+ ((e.adminW > 0) and (e.adminW + GAP) or 0)
					+ ((e.lvlW > 0) and (e.lvlW + GAP) or 0)
				local left = sX - totalW / 2
				local curX = left
				local rowTop = sY - e.nameH
				local smallTop = sY - e.nameH / 2 - e.smallH / 2

				if e.adminW > 0 then
					local a = e.admin
					if e.adminDuty then
						dxDrawRectangle(curX, smallTop, e.adminW, e.smallH, tocolor(a.r, a.g, a.b, 255))
						dxDrawText(a.text, curX, smallTop, curX + e.adminW, smallTop + e.smallH,
							tocolor(a.r * 0.15, a.g * 0.15, a.b * 0.15, 255), SMALL_S, FONT, "center", "center")
					else
						dxDrawRectangle(curX, smallTop, e.adminW, e.smallH, tocolor(0, 0, 0, 120))
						drawOutline(curX, smallTop, e.adminW, e.smallH, tocolor(a.r, a.g, a.b, 255))
						dxDrawText(a.text, curX, smallTop, curX + e.adminW, smallTop + e.smallH,
							tocolor(a.r, a.g, a.b, 255), SMALL_S, FONT, "center", "center")
					end
					curX = curX + e.adminW + GAP
				end

				-- név: 1px árnyék + szín kódolt szöveg
				dxDrawText(e.name, curX + 1, rowTop + 1, curX + e.nameW + 1, sY + 1, tocolor(0, 0, 0, 200), FONT_S, FONT, "left", "bottom")
				dxDrawText(e.name, curX, rowTop, curX + e.nameW, sY, tocolor(cr, cg, cb, 255), FONT_S, FONT, "left", "bottom")
				curX = curX + e.nameW + GAP

				if e.lvlW > 0 then
					dxDrawRectangle(curX, smallTop, e.lvlW, e.smallH, tocolor(0, 0, 0, 115))
					dxDrawText(e.level_text, curX, smallTop, curX + e.lvlW, smallTop + e.smallH,
						tocolor(154, 166, 184, 255), SMALL_S, FONT, "center", "center")
					curX = curX + e.lvlW + GAP
				end

				-- voice: pulzáló zöld mikrofon a sor bal szélén
				if speaking[p] then
					local pulse = 150 + 105 * math.abs(math.sin(now / 250))
					dxDrawImage(left - GAP - ICON, sY - e.nameH / 2 - ICON / 2, ICON, ICON, IMG_MIC, 0, 0, 0, tocolor(111, 220, 140, pulse))
				end

				-- chat typing: "..." buborék a sor jobb szélén
				if e.typing then
					local bw, bh = 30, 18
					local bx, by = curX, rowTop - bh / 2
					dxDrawImage(bx, by, bw, bh, IMG_BUBBLE, 0, 0, 0, tocolor(255, 255, 255, 235))
					for i = 0, 2 do
						local a = 70 + 185 * math.max(0, math.sin((now / 200) - i * 0.9))
						dxDrawImage(bx + 7 + i * 6, by + 5, 4, 4, IMG_DOT, 0, 0, 0, tocolor(27, 34, 48, a))
					end
				end

				-- fő sor felett: crew tag + munka mini kártya egymás mellett, együtt centrálva
				local crewW = e.crewW
				local topW = crewW + ((crewW > 0 and e.workW > 0) and GAP or 0) + e.workW
				local topX = sX - topW / 2
				local topBottom = rowTop - 3
				if crewW > 0 then
					uicore:drawCrewTagBoxForPlayer(p, topX, topBottom, SMALL_S, 255, "left", "bottom")
					topX = topX + crewW + GAP
				end
				if e.workW > 0 then
					local wc = e.workColor
					local cardY = topBottom - e.smallH
					dxDrawRectangle(topX, cardY, e.workW, e.smallH, tocolor(0, 0, 0, 150))
					dxDrawRectangle(topX, cardY, 3, e.smallH, tocolor(wc[1], wc[2], wc[3], 255))
					dxDrawText(e.workName, topX + 3, cardY, topX + e.workW, cardY + e.smallH,
						tocolor(wc[1], wc[2], wc[3], 255), SMALL_S, FONT, "center", "center")
				end

				-- páncél (ha van) + health a sor alatt; minden frame-ben olvassuk
				local barX = sX - BAR_W / 2
				local barY = sY + 4
				local armor = math.max(0, math.min(100, getPedArmor(p)))
				if armor > 0 then
					dxDrawRectangle(barX, barY, BAR_W, ARMOR_H, tocolor(0, 0, 0, 160))
					dxDrawRectangle(barX, barY, BAR_W * (armor / 100), ARMOR_H, tocolor(217, 221, 228, 255))
					barY = barY + ARMOR_H + 2
				end
				local hp = math.max(0, math.min(100, getElementHealth(p)))
				local hc = (hp < 25) and COLOR_LOWHP or col
				dxDrawRectangle(barX, barY, BAR_W, HP_H, tocolor(0, 0, 0, 160))
				dxDrawRectangle(barX, barY, BAR_W * (hp / 100), HP_H, tocolor(hc[1], hc[2], hc[3], 255))
			end
		else
			nearby[p] = nil
		end
	end
end
-- minden más onClientRender előtt fut, így a nametag a többi panel ALATT lesz
addEventHandler("onClientRender", root, renderNametags, true, "high+9999")

-- az alap nametageket csak egyszer, a resource indulásakor kapcsoljuk ki
-- (később érkezők: a cache-be kerüléskor)
addEventHandler("onClientResourceStart", resourceRoot, function()
	for _, p in ipairs(getElementsByType("player")) do
		setPlayerNametagShowing(p, false)
	end
	refreshNearby()
	setTimer(refreshNearby, 500, 0)
end)

addCommandHandler("toggleowntag", function()
	if (getElementData(localPlayer, "toggleOwnNametag") == nil) then
		setElementData(localPlayer, "toggleOwnNametag", true)
	end
	setElementData(localPlayer, "toggleOwnNametag", not getElementData(localPlayer, "toggleOwnNametag"))
end)

-- Texts load only once the player is loaded (v_loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    build_adminTitles_forNametag()
    rebuildAll()
    exports.v_loading:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
-- also when this resource started after the loading screen appeared (v_loading asks again)
addEvent("onClientReadyCheck")
addEventHandler("onClientReadyCheck", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
