if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

local lineTo = false
local adminTitles_forNametag = {}
local function build_adminTitles_forNametag()
adminTitles_forNametag = {
    [1] = L("v_nametags.sourcec.trial_mod"),
    [2] = L("v_nametags.sourcec.mod"),
    [3] = L("v_nametags.sourcec.admin"),
    [4] = L("v_nametags.sourcec.superadmin"),
    [5] = L("v_nametags.sourcec.dev"),
    [6] = L("v_nametags.sourcec.owner"),
}
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
-- nearby[player] = { name, level_text, admin_draw, adminW, nameW, nameH, voice }
local nearby = {}
local FONT_S = 1.2 -- fix betűméret, nem skálázódik távolsággal/felbontással
local FONT = "default-bold"
local GAP = 6
local NEARBY_RANGE = 50

-- element data keys that affect what is displayed
local watchedKeys = {
	admin_level = true, accName = true, adminDuty = true, admin_name = true,
	level = true, isChat = true, voice = true,
}

-- (re)build every displayed value of one player from element data
local function buildEntry(p, entry)
	entry = entry or {}
	local adminlevel = tonumber(getElementData(p, "admin_level")) or 0

	local name = getElementData(p, "accName")
	if getElementData(p, "adminDuty") == true then
		name = getElementData(p, "admin_name")
	end
	name = tostring(name or "")
	-- chat jelző a név elé
	if getElementData(p, "isChat") then
		name = "[/] " .. name
	end

	-- admin cím: A prefix MEGTARTJA a saját színezését; a lezáró színkódot levágjuk,
	-- hogy ne szivárogjon át a névre.
	local admin_draw, admin_plain = "", ""
	if adminlevel > 0 and adminTitles_forNametag[adminlevel] then
		admin_draw = adminTitles_forNametag[adminlevel]
			:gsub("%s*#%x%x%x%x%x%x%s*$", "")
			:gsub("^%s+", ""):gsub("%s+$", "")
		admin_plain = stripColorCodes(admin_draw)
	end

	entry.name = name
	entry.level_text = L("v_nametags.sourcec.lvl", { player_info = tostring(getElementData(p, "level")) })
	entry.admin_draw = admin_draw
	entry.adminW = (admin_plain ~= "") and L.width(admin_plain, FONT_S, FONT) or 0
	entry.nameW = L.width(name, FONT_S, FONT)
	entry.nameH = dxGetFontHeight(FONT_S, FONT)
	-- a név színe a voice alapján dől el: fehér, ha nincs aktív voice
	entry.voice = getElementData(p, "voice") and true or false
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
					end
				end
			end
		end
	end

	for p in pairs(nearby) do
		if not seen[p] then nearby[p] = nil end
	end
end

local function renderNametags()
	for p, e in pairs(nearby) do
		if isElement(p) then
			local pX, pY, pZ = getElementPosition(p)
			local sX, sY = getScreenFromWorldPosition(pX, pY, pZ + 1.2)
			if sX and sY then
				local totalW = e.nameW + ((e.adminW > 0) and (e.adminW + GAP) or 0)
				local curX = sX - totalW / 2

				-- 1. sor: admin prefix + név egy vízszintes sorban, sX-re centrálva
				if e.adminW > 0 then
					-- admin prefix: saját színezéssel (colorCoded = true)
					dxDrawText(e.admin_draw, curX, sY, curX + e.adminW, sY, tocolor(255,255,255, 255), FONT_S, FONT, "left", "bottom", false, false, false, true)
					curX = curX + e.adminW + GAP
				end

				-- playername: mindig fehér, csak aktív voice színezi
				local nr, ng, nb = 255, 255, 255
				if e.voice then nr, ng, nb = 80, 142, 230 end
				dxDrawText(e.name, curX, sY, curX + e.nameW, sY, tocolor(nr, ng, nb, 255), FONT_S, FONT, "left", "bottom", false, false, false, false)

				-- crew tag a NÉV FELETT
				uicore:drawCrewTagBoxForPlayer(p, sX, sY - e.nameH - 4, FONT_S, 255, "center", "bottom")

				-- 2. sor: szint
				dxDrawText(e.level_text, sX, sY, nil, nil, tocolor(150,200,255, 255), FONT_S, FONT, "center", "top", false, false, false, true)

				-- kis health bar a SZINT ALATT; a health gyorsan változik, ezért minden frame-ben olvassuk
				local hpW, hpH = 60, 4
				local hpX = sX - hpW / 2
				local hpY = sY + e.nameH + 3
				local hp  = math.max(0, math.min(100, getElementHealth(p)))
				dxDrawRectangle(hpX, hpY, hpW, hpH, tocolor(0, 0, 0, 180))
				dxDrawRectangle(hpX, hpY, hpW * (hp / 100), hpH, tocolor(140, 205, 255, 255))
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

-- Texts load only once the player is loaded (acc_loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    build_adminTitles_forNametag()
    rebuildAll()
    exports.acc_loading:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
