if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

local lineTo = false
local adminTitles_forNametag = {
    [1] = L("v_nametags.sourcec.trial_mod"),
    [2] = L("v_nametags.sourcec.mod"),
    [3] = L("v_nametags.sourcec.admin"),
    [4] = L("v_nametags.sourcec.superadmin"),
    [5] = L("v_nametags.sourcec.dev"),
    [6] = L("v_nametags.sourcec.owner"),
}

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

local function renderNametags()
	local lX, lY, lZ = getElementPosition(localPlayer)
	local hX, hY, hZ = getHeadPosition(localPlayer)
	local lInt, lDim = getElementInterior(localPlayer), getElementDimension(localPlayer)

	-- PLAYERS
	for i, playerInfo in ipairs(getElementsByType("player")) do
		if playerInfo == localPlayer and getElementData(localPlayer, "toggleOwnNametag") then
			--
		else
			local pX, pY, pZ = getElementPosition(playerInfo)
			setPlayerNametagShowing(playerInfo, false)
			if getElementAlpha(playerInfo) ~= 0
				and getElementInterior(playerInfo) == lInt
				and getElementDimension(playerInfo) == lDim then
				if getDistanceBetweenPoints3D(pX, pY, pZ, lX, lY, lZ) <= 50 then
					local veh = getPedOccupiedVehicle(playerInfo)
					local visible, tX, tY, tZ = canSee(hX, hY, hZ, playerInfo)
					if visible or veh then
						if lineTo then
							dxDrawLine3D(hX, hY, hZ, tX, tY, tZ)
						end

						local sX, sY = getScreenFromWorldPosition(pX, pY, pZ+1.2)

						local fontS = 1.2 -- fix betűméret, nem skálázódik távolsággal/felbontással
						if sX and sY then
							local adminlevel = tonumber(getElementData(playerInfo, "admin_level")) or 0

							local player_text = getElementData(playerInfo, "accName")
							if getElementData(playerInfo, "adminDuty") == true then
								player_text = getElementData(playerInfo, "admin_name")
							end
							player_text = tostring(player_text or "")

							local level_text = L("v_nametags.sourcec.lvl", { player_info = tostring(getElementData(playerInfo, "level")) })

							-- admin cím: admin_level element data + adminTitles_forNametag alapján.
							-- A prefix MEGTARTJA a saját színezését; a lezáró színkódot levágjuk,
							-- hogy ne szivárogjon át a névre.
							local admin_draw, admin_plain = "", ""
							if adminlevel > 0 and adminTitles_forNametag[adminlevel] then
								admin_draw = adminTitles_forNametag[adminlevel]
									:gsub("%s*#%x%x%x%x%x%x%s*$", "")
									:gsub("^%s+", ""):gsub("%s+$", "")
								admin_plain = stripColorCodes(admin_draw)
							end

							-- chat jelző a név elé
							if getElementData(playerInfo, "isChat") then
								player_text = "[/] "..player_text
							end

							-- a név színe a voice alapján dől el: fehér, ha nincs aktív voice
							local nr, ng, nb = 255, 255, 255
							if getElementData(playerInfo, "voice") then
								nr, ng, nb = 80, 142, 230
							end

							local nameH = dxGetFontHeight(fontS, "default-bold")

							-- 1. sor: admin prefix + név egy vízszintes sorban, sX-re centrálva
							local gap = 6
							local adminW = (admin_plain ~= "") and L.width(admin_plain, fontS, "default-bold") or 0
							local nameW  = L.width(player_text, fontS, "default-bold")

							local totalW = nameW + ((adminW > 0) and (adminW + gap) or 0)
							local curX = sX - totalW / 2

							if adminW > 0 then
								-- admin prefix: saját színezéssel (colorCoded = true)
								dxDrawText(admin_draw, curX, sY, curX + adminW, sY, tocolor(255,255,255, 255), fontS, "default-bold", "left", "bottom", false, false, false, true)
								curX = curX + adminW + gap
							end

							-- playername: mindig fehér, csak aktív voice színezi
							dxDrawText(player_text, curX, sY, curX + nameW, sY, tocolor(nr, ng, nb, 255), fontS, "default-bold", "left", "bottom", false, false, false, false)

							-- crew tag a NÉV FELETT
							uicore:drawCrewTagBoxForPlayer(playerInfo, sX, sY - nameH - 4, fontS, 255, "center", "bottom")

							-- 2. sor: szint
							dxDrawText(level_text, sX, sY, nil, nil, tocolor(150,200,255, 255), fontS, "default-bold", "center", "top", false, false, false, true)

							-- kis health bar a SZINT ALATT (kis szélesség, világoskék csík)
							local hpW, hpH = 60, 4
							local hpX = sX - hpW / 2
							local hpY = sY + nameH + 3
							local hp  = math.max(0, math.min(100, getElementHealth(playerInfo)))
							dxDrawRectangle(hpX, hpY, hpW, hpH, tocolor(0, 0, 0, 180))
							dxDrawRectangle(hpX, hpY, hpW * (hp / 100), hpH, tocolor(140, 205, 255, 255))
						end
					end
				end
			end
		end
	end

	-- PEDS
	for i, ped in ipairs(getElementsByType("ped")) do
		local pedName = isElement(ped) and getElementData(ped, "name")
		if pedName and pedName ~= ""
			and getElementAlpha(ped) ~= 0
			and not getElementData(ped, "hide_nametag")
			and getElementInterior(ped) == lInt
			and getElementDimension(ped) == lDim then
			pedName = tostring(pedName)
			local pX, pY, pZ = getElementPosition(ped)

			if getDistanceBetweenPoints3D(pX, pY, pZ, lX, lY, lZ) <= 50 then
				if canSee(hX, hY, hZ, ped) then
					local sX, sY = getScreenFromWorldPosition(pX, pY, pZ + 1.2)

					if sX and sY then
						local fontS = ui(2)
						local textWidth = L.width(pedName, fontS, "default-bold")

						local bgWidth = textWidth + ui(10)
						local bgHeight = ui(42)

						-- Nametag háttér
						dxDrawRectangle(
							sX - bgWidth / 2,
							sY - ui(40),
							bgWidth,
							bgHeight,
							tocolor(0, 0, 0, 160)
						)

						-- Név
						dxDrawText(
							pedName,
							sX, sY,
							nil, nil,
							tocolor(255,255,255,255),
							fontS,
							"default-bold",
							"center",
							"bottom",
							false, false, false, true
						)

						-- HP
						local health = math.max(0, math.min(100, getElementHealth(ped)))
						local hpWidth = bgWidth - ui(10)
						local hpHeight = ui(5)

						local hpX = sX - hpWidth / 2
						local hpY = sY + ui(3)

						-- HP háttér
						dxDrawRectangle(
							hpX,
							hpY,
							hpWidth,
							hpHeight,
							tocolor(50, 50, 50, 220)
						)

						-- HP szín
						local r, g, b

						if health >= 50 then
							-- Zöld -> Sárga
							local progress = (health - 50) / 50
							r = 255 * (1 - progress)
							g = 200
							b = 0
						else
							-- Sárga -> Piros
							local progress = health / 50
							r = 255
							g = 200 * progress
							b = 0
						end

						-- HP töltött rész
						dxDrawRectangle(
							hpX,
							hpY,
							hpWidth * (health / 100),
							hpHeight,
							tocolor(r, g, b, 255)
						)
					end
				end
			end
		end
	end
end
-- minden más onClientRender előtt fut, így a nametag a többi panel ALATT lesz
addEventHandler("onClientRender", root, renderNametags, true, "high+9999")

addCommandHandler("toggleowntag", function()
	if (getElementData(localPlayer, "toggleOwnNametag") == nil) then
		setElementData(localPlayer, "toggleOwnNametag", true)
	end
	setElementData(localPlayer, "toggleOwnNametag", not getElementData(localPlayer, "toggleOwnNametag"))
end)
