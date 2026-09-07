uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

local lineTo = false
local adminTitles_forNametag = {
    [1] = "#000000[#00BAFFTRIAL MOD#000000] #FF0000",
    [2] = "#000000[#00BAFFMOD#000000] #FF0000",
    [3] = "#000000[#BAFFBAADMIN#000000] #FF0000",
    [4] = "#000000[#fc1f17SUPERADMIN#000000] #FF0000",
    [5] = "#000000[#FFBB00DEV#000000] #FFFFFF",
    [6] = "#000000[#FF4400OWNER#000000] #FFFFFF",
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


local firstNames = {
    "James", "John", "Robert", "Michael", "William",
    "David", "Richard", "Joseph", "Thomas", "Charles",
    "Christopher", "Daniel", "Matthew", "Anthony", "Mark",
    "Donald", "Steven", "Paul", "Andrew", "Joshua",
    "Kenneth", "Kevin", "Brian", "George", "Timothy",
    "Ryan", "Jason", "Jacob", "Gary", "Nicholas",
    "Eric", "Jonathan", "Stephen", "Justin", "Scott",
    "Brandon", "Benjamin", "Samuel", "Gregory", "Frank",
    "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth",
    "Barbara", "Susan", "Jessica", "Sarah", "Karen",
    "Lisa", "Nancy", "Betty", "Sandra", "Margaret",
    "Ashley", "Kimberly", "Emily", "Donna", "Michelle",
    "Carol", "Amanda", "Melissa", "Deborah", "Stephanie",
    "Rebecca", "Laura", "Sharon", "Cynthia", "Kathleen",
    "Amy", "Angela", "Anna", "Brenda", "Pamela",
    "Emma", "Nicole", "Helen", "Samantha", "Katherine"
}

local lastNames = {
    "Smith", "Johnson", "Williams", "Brown", "Jones",
    "Garcia", "Miller", "Davis", "Rodriguez", "Martinez",
    "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
    "Thomas", "Taylor", "Moore", "Jackson", "Martin",
    "Lee", "Perez", "Thompson", "White", "Harris",
    "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson",
    "Walker", "Young", "Allen", "King", "Wright",
    "Scott", "Torres", "Nguyen", "Hill", "Flores",
    "Green", "Adams", "Nelson", "Baker", "Hall",
    "Rivera", "Campbell", "Mitchell", "Carter", "Roberts",
    "Phillips", "Evans", "Turner", "Parker", "Collins",
    "Edwards", "Stewart", "Morris", "Murphy", "Cook",
    "Rogers", "Morgan", "Peterson", "Cooper", "Reed",
    "Bailey", "Bell", "Gomez", "Kelly", "Howard",
    "Ward", "Cox", "Diaz", "Richardson", "Wood",
    "Watson", "Brooks", "Bennett", "Gray", "James"
}

function getRandomName(ped)
    if not isElement(ped) then
        return "No Name"
    end

    local currentName = getElementData(ped, "name")
    if currentName and currentName ~= "" then
        return currentName
    end

    local name = string.format(
        "%s %s",
        firstNames[math.random(#firstNames)],
        lastNames[math.random(#lastNames)]
    )

    setElementData(ped, "name", name)
    return name
end

setPedTargetingMarkerEnabled(false)

addEventHandler("onClientRender", getRootElement(), function()
	local lX, lY, lZ = getElementPosition(localPlayer)

	-- PLAYERS
	for i, playerInfo in ipairs(getElementsByType("player")) do
		if playerInfo == localPlayer and getElementData(localPlayer, "toggleOwnNametag") then
			--
		else
			local pX, pY, pZ = getElementPosition(playerInfo)
			setPlayerNametagShowing(playerInfo, false)
			if getElementAlpha(playerInfo) ~= 0 then
				if getDistanceBetweenPoints3D(pX, pY, pZ, lX, lY, lZ) <= 50 then
					local veh = getPedOccupiedVehicle(playerInfo)
					if isLineOfSightClear(lX, lY, lZ+1.5, pX, pY, pZ+1.5) or veh then
						if lineTo then
							dxDrawLine3D(lX, lY, lZ+1.5, pX, pY, pZ+1.5)
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

							local level_text = "lvl "..tostring(getElementData(playerInfo, "level"))

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
							local adminW = (admin_plain ~= "") and dxGetTextWidth(admin_plain, fontS, "default-bold") or 0
							local nameW  = dxGetTextWidth(player_text, fontS, "default-bold")

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
		if isElement(ped) and getElementAlpha(ped) ~= 0 then
			if getElementData(ped, "hide_nametag") then
				return
			end
			
			local pX, pY, pZ = getElementPosition(ped)

			if getDistanceBetweenPoints3D(pX, pY, pZ, lX, lY, lZ) <= 50 then
				if isLineOfSightClear(lX, lY, lZ + 1.5, pX, pY, pZ + 1.5) then
					local sX, sY = getScreenFromWorldPosition(pX, pY, pZ + 1.2)

					if sX and sY then
						local pedName = getElementData(ped, "name") or getRandomName(ped)

						local fontS = ui(2)
						local textWidth = dxGetTextWidth(pedName, fontS, "default-bold")

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
end)

addCommandHandler("toggleowntag", function()
	if (getElementData(localPlayer, "toggleOwnNametag") == nil) then
		setElementData(localPlayer, "toggleOwnNametag", true)
	end
	setElementData(localPlayer, "toggleOwnNametag", not getElementData(localPlayer, "toggleOwnNametag"))
end)
