uicore = exports.ui_core
ui = function(v) return uicore:ui(v) end

local x,y = uicore:getScreenWH()
local rel = ((x/1920)+(y/1080))/2
local movingOffsetX, movingOffsetY = 0, 0;
local movingOffsetX2, movingOffsetY2 = 0, 0;
local mozgat = false
local mySavedConfig = {}
local actionwwidgets = ""
local startingcursorpos = 0
local startingcursorpos2 = 0

local cansizeRadar = false
local cansizeHud = false
local cansizeStamina = false
local cansizeChat = false

local atvisszukx = 0
local atvisszuky = 0
local atvisszukHudx = 0
local atvisszukHudy = 0
local atvisszukStaminaX = 0
local atvisszukStaminaY = 0
local atvisszukChatX = 0
local atvisszukChatY = 0

local moneyLosing = false
local getMoney = false
local moneyLoss = 0

local selectorOffSetX = {}
local selectorOffSetY = {}
local movingWithSelector = false
local selectedWithSelector = {}
local plusTable = {}

local selectorActivated = false
local plus = 1

local fixTable = {
	{ -- Élet HUD
		["xplus"] = -30,
		["yplus"] = -50,
		["width"] = 40,
		["height"] = 0,
	},
	{ -- Body
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- Phone
		["xplus"] = 200,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- SPRINT
		["xplus"] = -30,
		["yplus"] = -6,
		["width"] = 40,
		["height"] = 15,
	},
	{ -- Money
		["xplus"] = -13,
		["yplus"] = 4,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- FPS
		["xplus"] = -10,
		["yplus"] = 3,
		["width"] = 20,
		["height"] = 10,
	},
	{ -- Minimap
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- Óra
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 10,
		["height"] = 5,
	},
	{ -- ActionBar
		["xplus"] = -5,
		["yplus"] = -5,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- Videókártya
		["xplus"] = -5,
		["yplus"] = -5,
		["width"] = 35,
		["height"] = 20,
	},
	{ -- OOC --11
		["xplus"] = -10,
		["yplus"] = 20,
		["width"] = 0,
		["height"] = -10,
	},
	{ -- speedo
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- benzin
		["xplus"] = 73,
		["yplus"] = 73,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- kijelzo
		["xplus"] = 75,
		["yplus"] = 120,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- kickban
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- jarmunev
		["xplus"] = -40,
		["yplus"] = 5,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- guns
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- name
		["xplus"] = -115,
		["yplus"] = -5,
		["width"] = 20,
		["height"] = 5,
	},
	{ -- ping
		["xplus"] = -5,
		["yplus"] = -5,
		["width"] = 20,
		["height"] = 5,
	},
	{ -- nitro
		["xplus"] = -5,
		["yplus"] = -5,
		["width"] = -220,
		["height"] = -185,
	},
	{ -- traffiradar
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
	{ -- customchat
		["xplus"] = 0,
		["yplus"] = 0,
		["width"] = 0,
		["height"] = 0,
	},
}

local boundingBoxes = {
	{ -- Élet HUD
		["name"] = "Életerő",
		["showing"] = true,
		["width"] = 226,
		["height"] = 60,
		["x"] = x - 246,
		["y"] = 70,
	},
	{ -- Body
		["name"] = "Body",
		["showing"] = true,
		["width"] = 18,
		["height"] = 46,
		["x"] = x - 295,
		["y"] = 35,
	},
	{ -- Phone
		["name"] = "TELEFON",
		["showing"] = true,
		["width"] = 300,
		["height"] = 512,
		["x"] = x - 512,
		["y"] = y/2-512/2,
	},
	{ -- SPRINT
		["name"] = "Stamina",
		["showing"] = true,
		["width"] = 226,
		["height"] = 8,
		["x"] = x-246,
		["y"] = 81,
	},
	{ -- Pénz
		["name"] = "Készpénz",
		["showing"] = true,
		["width"] = 220,
		["height"] = 30,
		["x"] = x - 220,
		["y"] = 95,
	},
	{ -- FPS
		["name"] = "FPS",
		["showing"] = false,
		["width"] = 80,
		["height"] = 22,
		["x"] = 50,
		["y"] = 125,
	},
	{ -- Minimap
		["name"] = "Radar",
		["showing"] = true,
		["width"] = 320,
		["height"] = 225,
		["x"] = 12,
		["y"] = y - 235,
	},
	{ -- Óra
		["name"] = "Óra",
		["showing"] = false,
		["width"] = 70,
		["height"] = 30,
		["x"] = 50,
		["y"] = 125,
	},
	{ -- ActionBar
		["name"] = "Action Bar",
		["showing"] = true,
		["width"] = 255+3,
		["height"] = 55+2,
		["x"] = x/2 - 269/2+20,
		["y"] = y - 54 - 10,
	},
	{ -- Videókártya
		["name"] = "Videókártya",
		["showing"] = false,
		["width"] = 256,
		["height"] = 80,
		["x"] = 50,
		["y"] = 125,
	},
	{ -- OOC --11
		["name"] = "OOC Chat",
		["showing"] = true,
		["width"] = 256,
		["height"] = 170,
		["x"] = 0.015625*x,
		["y"] = 16+15+25+100,
	},
	{ -- speedometer --12
		["name"] = "KILÓMÉTERÓRA",
		["showing"] = true,
		["width"] = 256,
		["height"] = 256,
		["x"] = x-256-5,
		["y"] = y-256-5,
	},
	{ -- benzinmeter 13
		["name"] = "ÜZEMANYAG",
		["showing"] = true,
		["width"] = 110,
		["height"] = 110,
		["x"] = x-440,
		["y"] = y-195,
	},
	{ -- speedometerkijelzo 14
		["name"] = "JÁRMŰIKONOK",
		["showing"] = true,
		["width"] = 110,
		["height"] = 70,
		["x"] = x-256,
		["y"] = y-256-5,
	},
	{ -- kickban notification
		["name"] = "Kick/Ban",
		["showing"] = true,
		["width"] = 324,
		["height"] = 120,
		["x"] = 12,
		["y"] = y - 235-80-70,
	},
	{ -- Járműnév
		["name"] = "JÁRMŰNÉV",
		["showing"] = true,
		["width"] = 300,
		["height"] = 45,
		["x"] = x-252,
		["y"] = y - 315,
	},
	{ -- guns
		["name"] = "Guns",
		["showing"] = true,
		["width"] = 256,
		["height"] = 128,
		["x"] = x-280,
		["y"] = 125,
	},
	{ -- name
		["name"] = "Name",
		["showing"] = false,
		["width"] = 300,
		["height"] = 30,
		["x"] = 50,
		["y"] = 125,
	},
	{ -- Ping
		["name"] = "Ping",
		["showing"] = false,
		["width"] = 80,
		["height"] = 30,
		["x"] = 50,
		["y"] = 125,
	},
	{ -- Nitro
		["name"] = "N2O",
		["showing"] = true,
		["width"] = 256,
		["height"] = 256,
		["x"] = x-256+226,
		["y"] = y-256-5,
	},
	{ -- TraffiRadar
		["name"] = "Traffipax radar",
		["showing"] = false,
		["width"] = 274,
		["height"] = 45,
		["x"] = 50,
		["y"] = 125,
	},
	{ -- customchat
		["name"] = "CustomChat",
		["showing"] = false,
		["width"] = 600,
		["height"] = 350,
		["x"] = 12,
		["y"] = 12,
	},
}


local hudhely = {(x/2*1.60), (y/2*0.111)}
local flickerStrength = 0
local myScreenSource = dxCreateScreenSource(x, y)
local Roboto2 = dxCreateFont("files/Roboto.ttf", 22)
local handfont = dxCreateFont("files/hand.ttf", 16)
local gtaFont = dxCreateFont("files/gtaFont.ttf", 20)
local Roboto = dxCreateFont("files/Roboto.ttf", 13)
local RobotoB = dxCreateFont("files/RobotoB.ttf", 24)
local ikonFont = dxCreateFont("files/fontawesome-webfont.ttf", 20)
local ikonFont2 = dxCreateFont("files/fontawesome2.otf", 27)

local szerkesztesmod = false
local kukaforgas = 0
local hudmozgatasba = false
local valaszto = false
local jobbra = false
local balra = false

local egeretnyomunk = false
local currentMoving = false
local resetColorRGB = {255,255,255}
local deleteColorRGB = {255,255,255}

local kijelolesR = false
local kijeloles = {(x/2), (y/2), 200, 200}


local stat = dxGetStatus()
local bit = nil

fontawesomeSheet = createBrowser(128, 256, true, true)
iconPOTSizes = {32, 32, 32, 32, 32, 32}
iconSizes = {14, 14, 14, 14, 14, 20}
iconList = {"heart", "shield", "cutlery", "bolt", "life-ring", "arrows-alt"}

local traf1 = nil
local detectedTraffipax = false

addEventHandler("onClientBrowserCreated", fontawesomeSheet,
	function ()
		loadBrowserURL(source, "http://mta/local/files/html/font-awesome/index.html?fa=" .. table.concat(iconList, ",") .. "&ps=" .. table.concat(iconPOTSizes, ",") .. "&s=" .. table.concat(iconSizes, ","))
	end
)

addEventHandler("onClientResourceStart", getResourceRootElement(),
    function()
        checkJSON_File()
		addEventHandler("onClientBrowserCreated", fontawesomeSheet, processFontAwesomeSheet)
		addEventHandler("onClientBrowserLoadingFailed", fontawesomeSheet, sheetLoadFail)
		setPlayerHudComponentVisible("all", false)
		setPlayerHudComponentVisible("crosshair", true)
    end
)

local plusX = 0

addEventHandler ( "onClientElementDataChange", localPlayer, function(dataName, oldValue, newValue)
	--if not getElementData(localPlayer, "loggedin") then return end
	if dataName == "char.money" then
		local newValue = newValue or 0
		moneyLoss = newValue - (oldValue or 0)
		playSound("files/moneychange.mp3")
		if moneyLoss < 0 then
			moneyLosing = true
			setTimer ( function()
				moneyLosing = false
			end, 3500, 1 )
		elseif moneyLoss > 0 then
			getMoney = true
			setTimer ( function()
				getMoney = false
			end, 3500, 1 )
		end
	elseif dataName == "valaszto" then
		myDisabledWidgets = {}
		for k, v in pairs(mySavedConfig) do
			if not v["showing"] then
				myDisabledWidgets[#myDisabledWidgets+1] = k
			end
		end
		ordnenInSelector()
	end
end)

local counter = 0
local starttick
local currenttick

function convertToBool(string)
	if tostring(string) == "true" then
		return true
	else
		return false
	end
end

local plusYforUZI = 0
local plusX = 0
function hudrajzol ()
	if not getElementData(localPlayer, "enableall") then return end

	setElementData(localPlayer, "valaszto", valaszto)
	setPlayerHudComponentVisible("crosshair", true)

	if szerkesztesmod then
		if not isCursorShowing() then
			mozgat = false
			szerkesztesmod = false
			valaszto = false
			cansizeRadar = false
			cansizeHud = false
			canSizeStamina = false
			canSizeChat = false
			selectorActivated = false
			movingWithSelector = false
			kijelolesR = false
			egeretnyomunk = false
			if isElement(urmasound) then
				stopSound(urmasound)
			end
		end
		dxDrawRectangle(x/1920, y/1080, 1920, 1080 , tocolor(255,255,255,30))
	end

	if mozgat then  -- mozgatás ellenőrzése
		local egerW = {getCursorPosition()}
		local egerP = {egerW[1]*x, egerW[2]*y}
		mySavedConfig[currentMoving]["x"] = egerP[1] - movingOffsetX
		mySavedConfig[currentMoving]["y"] = egerP[2] - movingOffsetY
		hudmozgatasba = true
	else
		hudmozgatasba = false
	end

	if movingWithSelector then
		if selectorActivated then
			for i=1, plus-1 do
				local egerW = {getCursorPosition()}
				local egerP = {egerW[1]*x, egerW[2]*y}
				mySavedConfig[selectedWithSelector[i]]["x"] = egerP[1] - selectorOffSetX[i]
				mySavedConfig[selectedWithSelector[i]]["y"] = egerP[2] - selectorOffSetY[i]
			end
		end
	end
	-- Radar méretezés
	if cansizeRadar then
		egeretnyomunk = false
		local egerW2 = {getCursorPosition()}
		local egerP2 = {egerW2[1]*x, egerW2[2]*y}
		local egerszelesseg = {egerW2[1]*x, egerW2[2]*y}
		local proba = startingcursorposszor[1]-egerszelesseg[1]
		local proba2 = startingcursorposszor[2]-egerszelesseg[2]
		--outputDebugString(proba)
		mySavedConfig[7]["width"] = atvisszukx - proba
		mySavedConfig[7]["height"] = atvisszuky - proba2
	end
	-- Radar méretezés

	-- Hud méretezés
	if cansizeHud then
		egeretnyomunk = false
		local egerW3 = {getCursorPosition()}
		local egerP3 = {egerW3[1]*x, egerW3[2]*y}
		local egerszelesseg = {egerW3[1]*x, egerW3[2]*y}
		local proba = startingcursorposszor3[1]-egerszelesseg[1]
		local proba2 = startingcursorposszor3[2]-egerszelesseg[2]
		--outputDebugString(proba)
		mySavedConfig[1]["width"] = atvisszukHudx - proba
	end
	if canSizeStamina then
		egeretnyomunk = false
		local egerW3 = {getCursorPosition()}
		local egerP3 = {egerW3[1]*x, egerW3[2]*y}
		local egerszelesseg = {egerW3[1]*x, egerW3[2]*y}
		local proba = startingcursorposszor2[1]-egerszelesseg[1]
		local proba2 = startingcursorposszor2[2]-egerszelesseg[2]
		--outputDebugString(proba)
		mySavedConfig[4]["width"] = atvisszukStaminaX - proba
	end

	if canSizeChat then
		egeretnyomunk = false
		local egerW3 = {getCursorPosition()}
		local egerP3 = {egerW3[1]*x, egerW3[2]*y}
		local egerszelesseg = {egerW3[1]*x, egerW3[2]*y}
		local proba = startingcursorposszor2[1]-egerszelesseg[1]
		local proba2 = startingcursorposszor2[2]-egerszelesseg[2]
		--outputDebugString(proba)
		mySavedConfig[22]["width"] = atvisszukChatX - proba
		mySavedConfig[22]["height"] = atvisszukChatY - proba2
	end
	-- Hud méretezés
	if mySavedConfig[1]["width"] <= 80 then
		mySavedConfig[1]["width"] = 80
	elseif mySavedConfig[1]["width"] >= 330 then
		mySavedConfig[1]["width"] = 330
	end
	--radar stop
	if mySavedConfig[7]["width"] <= 204 then
		mySavedConfig[7]["width"] = 204
	elseif mySavedConfig[7]["width"] >= 629 then
		mySavedConfig[7]["width"] = 629
	end
	if mySavedConfig[7]["height"] <= 114 then
		mySavedConfig[7]["height"] = 114
	elseif mySavedConfig[7]["height"] >= 500 then
		mySavedConfig[7]["height"] = 500
	end

	if szerkesztesmod then
		if selectorActivated then
			for i=1, plus-1 do
				--outputDebugString("kiválasztottak "..selectedWithSelector[i])
				roundedRectangle(mySavedConfig[selectedWithSelector[i]]["x"]+fixTable[selectedWithSelector[i]]["xplus"], mySavedConfig[selectedWithSelector[i]]["y"]+fixTable[selectedWithSelector[i]]["yplus"], mySavedConfig[selectedWithSelector[i]]["width"]+fixTable[selectedWithSelector[i]]["width"], mySavedConfig[selectedWithSelector[i]]["height"]+fixTable[selectedWithSelector[i]]["height"], tocolor(153, 204, 153,100))
			end
		end
	end



	if kijelolesR and szerkesztesmod then
		roundedRectangle(kijeloles[1]+fixTable[currentMoving]["xplus"], kijeloles[2]+fixTable[currentMoving]["yplus"], kijeloles[3]+fixTable[currentMoving]["width"], kijeloles[4]+fixTable[currentMoving]["height"], tocolor(153, 204, 153,100))
		if currentMoving == 1 or currentMoving == 7 or currentMoving == 4 or currentMoving == 22 then
			drawTextWithBorder("", 1, mySavedConfig[currentMoving]["x"]+fixTable[currentMoving]["xplus"]+mySavedConfig[currentMoving]["width"]+fixTable[currentMoving]["width"]+15, mySavedConfig[currentMoving]["y"]+fixTable[currentMoving]["yplus"]+mySavedConfig[currentMoving]["height"]+15+fixTable[currentMoving]["height"], mySavedConfig[currentMoving]["x"]+fixTable[currentMoving]["xplus"]+mySavedConfig[currentMoving]["width"]+fixTable[currentMoving]["width"], mySavedConfig[currentMoving]["y"]+fixTable[currentMoving]["yplus"]+mySavedConfig[currentMoving]["height"]+fixTable[currentMoving]["height"], tocolor(0, 0, 0, 255), tocolor(200, 195, 191, 255), 0.6, 0.6, ikonFont, "center", "center", false, false,false, true)

		--	dxDrawRectangle(mySavedConfig[currentMoving]["x"]+fixTable[currentMoving]["xplus"]+mySavedConfig[currentMoving]["width"]+fixTable[1]["width"], mySavedConfig[currentMoving]["y"]+fixTable[currentMoving]["yplus"]+mySavedConfig[currentMoving]["height"], 20, 20)
		end
	elseif not szerkesztesmod then
		kijelolesR = false
	end
	if szerkesztesmod then
		for k, v in pairs(mySavedConfig) do
			if v["showing"] or valaszto then
				if k == 15 or k == 3 then
					drawTextWithBorder(v["name"], 1, v["x"]+fixTable[k]["xplus"], v["y"]+fixTable[k]["yplus"], v["x"]+v["width"]+fixTable[k]["xplus"], v["y"]+v["height"]+fixTable[k]["yplus"], tocolor(0, 0, 0, 255), tocolor(255, 255, 255, 255), 0.5, 0.5, Roboto2, "center", "center", false, false,false, true)
				end
				if not isPedInVehicle(localPlayer) then
					if k == 12 or k == 13 or k == 14 or k == 16 or k == 20 then
						drawTextWithBorder(v["name"], 1, v["x"]+fixTable[k]["xplus"]+fixTable[k]["width"], v["y"]+fixTable[k]["yplus"]+fixTable[k]["height"], v["x"]+v["width"]+fixTable[k]["xplus"], v["y"]+v["height"]+fixTable[k]["yplus"], tocolor(0, 0, 0, 255), tocolor(255, 255, 255, 255), 0.5, 0.5, Roboto2, "center", "center", false, false,false, true)
					end
				end
			end
		end
	end
	if mozgat == true then
		kijeloles[1] = mySavedConfig[currentMoving]["x"]
		kijeloles[2] = mySavedConfig[currentMoving]["y"]
		kijeloles[3] = mySavedConfig[currentMoving]["width"]
		kijeloles[4] = mySavedConfig[currentMoving]["height"]
	end
	if currentMoving == 7 then
		kijeloles[3] = mySavedConfig[7]["width"]
		kijeloles[4] = mySavedConfig[7]["height"]
	end
	if currentMoving == 1 then
		kijeloles[3] = mySavedConfig[1]["width"]
		kijeloles[4] = mySavedConfig[1]["height"]
	end
	if currentMoving == 4 then
		kijeloles[3] = mySavedConfig[4]["width"]
		kijeloles[4] = mySavedConfig[4]["height"]
	end
	if currentMoving == 22 then
		kijeloles[3] = mySavedConfig[22]["width"]
		kijeloles[4] = mySavedConfig[22]["height"]
	end


	if jobbra then -- widget választóba jobbra mozgás
		hudhely[1] = hudhely[1] + 2
	end
	if balra then -- widget választóba balra mozgás
		hudhely[1] = hudhely[1] - 2
	end

	if szerkesztesmod == true then
		if valaszto == true then
			dxDrawRectangle(0, 0, 1920, 225, tocolor(0,0,0,160)) -- külön rajzoljuk ki
		end
	end

	if mySavedConfig[1]["showing"] or valaszto then
	end
	if mySavedConfig[4]["showing"] or valaszto then
	end
	if mySavedConfig[5]["showing"] or valaszto then
	end
	if mySavedConfig[2]["showing"] or valaszto then
	end
    if mySavedConfig[6]["showing"] or valaszto then
	end
	if mySavedConfig[8]["showing"] or valaszto then
	end
	if mySavedConfig[18]["showing"] or valaszto then
    end
    if mySavedConfig[10]["showing"] or valaszto then
    end
	if mySavedConfig[19]["showing"] or valaszto then
	end
	if mySavedConfig[20]["showing"] or valaszto then
	end
end
addEventHandler("onClientRender", getRootElement(), hudrajzol)

function ordnenInSelector()
	local rechner = 1
	for k, v in pairs(mySavedConfig) do
		if not v["showing"] then
			if rechner < 2 then
				mySavedConfig[myDisabledWidgets[1]]["x"] = 50
			else
				mySavedConfig[myDisabledWidgets[rechner]]["x"] = mySavedConfig[myDisabledWidgets[rechner-1]]["x"] + mySavedConfig[myDisabledWidgets[rechner-1]]["width"] + fixTable[myDisabledWidgets[rechner-1]]["xplus"] + 150
			end
			mySavedConfig[myDisabledWidgets[rechner]]["y"] = 225/2-mySavedConfig[myDisabledWidgets[rechner]]["height"]/2-fixTable[myDisabledWidgets[rechner]]["yplus"]
			rechner = rechner + 1
		end
	end
end
addEventHandler("onClientResourceStart", getRootElement(),ordnenInSelector )

function checkJSON_File()
	myDisabledWidgets = {}
	mySavedConfig = {}
	if not fileExists("hud.json") then
		local file = fileCreate("hud.json")
		fileWrite(file, toJSON(boundingBoxes))
		fileClose(file)
		mySavedConfig = boundingBoxes
	else
		local file = fileOpen("hud.json")
		local config = fromJSON(fileRead(file, 9999))

		for k, v in ipairs(config) do
			mySavedConfig[tonumber(k)] = {
				["name"] = tostring(v["name"]),
				["showing"] = convertToBool(v["showing"]),
				["width"] = tonumber(v["width"]),
				["height"] = tonumber(v["height"]),
				["x"] = tonumber(v["x"]),
				["y"] = tonumber(v["y"]),
			}
			if not convertToBool(v["showing"]) then
				myDisabledWidgets[#myDisabledWidgets + 1] = k
			end
		end

		fileClose(file)
	end
end


function processFontAwesomeSheet()
	loadBrowserURL(source, "http://mta/local/files/html/font-awesome/index.html?fa=" .. table.concat(iconList, ",") .. "&ps=" .. table.concat(iconPOTSizes, ",") .. "&s=" .. table.concat(iconSizes, ","))
end

function sheetLoadFail(url, errorCode, errorDescription)
	if not isElement(fontawesomeSheet) then
		fontawesomeSheet = createBrowser(128, 256, true, true)
	end

	setTimer(
		function()
			loadBrowserURL(fontawesomeSheet, "http://mta/local/files/html/font-awesome/index.html?fa=" .. table.concat(iconList, ",") .. "&ps=" .. table.concat(iconPOTSizes, ",") .. "&s=" .. table.concat(iconSizes, ","))
		end,
	1000, 1)
end

function getNode(id, node)
	if mySavedConfig[id] and mySavedConfig[id][node] then
		return mySavedConfig[id][node]
	end
end


function getCursorPositionAdded()
    return cursorX, cursorY
end

local cursorState = isCursorShowing()
local cursorX, cursorY = x/2, y/2
if cursorState then
    local cursorX, cursorY = getCursorPosition()
    cursorX, cursorY = cursorX * x, cursorY * y
end

addEventHandler("onClientCursorMove", root,
    function(_, _, xadd, yadd)
        cursorX, cursorY = xadd, yadd
    end
)


function boxesIntersect(x1, y1, w1, h1, x2, y2, w2, h2)
	local horizontal = (x1 < x2) ~= (x1 < x2 + w2) or (x1 + w1 < x2) ~= (x1 + w1 < x2 + w2) or (x1 < x2) ~= (x1 + w1 < x2) or (x1 < x2 + w2) ~= (x1 + w1 < x2 + w2)
	local vertical = (y1 < y2) ~= (y1 < y2 + h2) or (y1 + h1 < y2) ~= (y1 + h1 < y2 + h2) or (y1 < y2) ~= (y1 + h1 < y2) or (y1 < y2 + h2) ~= (y1 + h1 < y2 + h2)

	return (horizontal and vertical)
end

function radarKeret(x, y, sz, m, vastagsag, alpha, nofront)
	dxDrawRectangle ( x, y-vastagsag, sz, vastagsag, tocolor(0,0,0,alpha) ) -- Felso
	if not nofront then
		dxDrawRectangle ( x-vastagsag, y-vastagsag, vastagsag, m+(vastagsag*2), tocolor(0,0,0,alpha) ) -- Bal
	end
	dxDrawRectangle ( x+sz, y-vastagsag, vastagsag, m+(vastagsag*2), tocolor(0,0,0,alpha) ) -- Jobb
	dxDrawRectangle ( x, y+m, sz, vastagsag, tocolor(0,0,0,alpha) ) -- Also
end

function dxDrawBorderedImageSection(x, y, w, h, ux, uy, uw, uh, path, rx, ry, rz, color, postGUI)
	dxDrawImageSection(x - 1, y - 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x - 1, y + 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x + 1, y - 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x + 1, y + 1, w, h, ux, uy, uw, uh, path, rx, ry, rz, tocolor(0, 0, 0, 200), postGUI)
	dxDrawImageSection(x, y, w, h, ux, uy, uw, uh, path, rx, ry, rz, color, postGUI)
end



function roundedRectangle(x, y, w, h, borderColor, bgColor, postGUI)
	if (x and y and w and h) then
		if (not borderColor) then
			borderColor = tocolor(0, 0, 0, 200);
		end

		if (not bgColor) then
			bgColor = borderColor;
		end

		--> Background
		dxDrawRectangle(x, y, w, h, bgColor, postGUI);

		--> Border
		dxDrawRectangle(x + 2, y - 1, w - 4, 1, borderColor, postGUI); -- top
		dxDrawRectangle(x + 2, y + h, w - 4, 1, borderColor, postGUI); -- bottom
		dxDrawRectangle(x - 1, y + 2, 1, h - 4, borderColor, postGUI); -- left
		dxDrawRectangle(x + w, y + 2, 1, h - 4, borderColor, postGUI); -- right
	end
end


function dobozbaVan(dX, dY, dSZ, dM, eX, eY)
	if(eX >= dX and eX <= dX+dSZ and eY >= dY and eY <= dY+dM) then
		return true
	else
		return false
	end
end

function isInSlot(xS,yS,wS,hS)
	if(isCursorShowing()) then
		XY = {guiGetScreenSize()}
		local cursorX, cursorY = getCursorPosition()
		cursorX, cursorY = cursorX*XY[1], cursorY*XY[2]
		if(dobozbaVan(xS,yS,wS,hS, cursorX, cursorY)) then
			return true
		else
			return false
		end
	end
end

function dxDrawBorderedText(text, x, y, w, h, color, ...)
	local textWithoutHEX = gsub(text, "#%x%x%x%x%x%x", "")
	dxDrawText(textWithoutHEX, x - 1, y - 1, w - 1, h - 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(textWithoutHEX, x - 1, y + 1, w - 1, h + 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(textWithoutHEX, x + 1, y - 1, w + 1, h - 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(textWithoutHEX, x + 1, y + 1, w + 1, h + 1, tocolor(0, 0, 0, 255), ...)
	dxDrawText(text, x, y, w, h, color, ...)
end

function drawTextWithBorder(text, offset, x, y, w, h, borderColor, color, scale, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	for offsetX = -offset, offset do
		for offsetY = -offset, offset do
			dxDrawText(text:gsub("#%x%x%x%x%x%x", ""), x + offsetX, y + offsetY, w + offsetX, h + offsetY, borderColor, scale, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
		end
	end

	dxDrawText(text, x, y, w, h, color, scale, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
end
