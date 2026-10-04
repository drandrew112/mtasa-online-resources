-- rw_trainhorn (client) – DrAndrew112
-- Nyomva tartott kürt: horn_start -> horn_loop (amíg nyomod) -> horn_end.

local DATA_KEY     = "rw_horn"
local MAX_DISTANCE = 300
local MIN_DISTANCE = 25
local VOLUME       = 1.0

local SND_START = "horn_start.wav"
local SND_LOOP  = "horn_loop.wav"
local SND_END   = "horn_end.wav"

-- [train] = { on = bool, phase = "start"|"loop"|"end", sound = element }
local horns = {}
local soundOwner = {}   -- [sound] = train

local function isTrain(v)
	return isElement(v) and getElementType(v) == "vehicle" and getVehicleType(v) == "Train"
end

local function playOn(train, file, looped)
	local x, y, z = getElementPosition(train)
	local snd = playSound3D(file, x, y, z, looped)
	if not snd then return nil end
	attachElements(snd, train)
	setElementDimension(snd, getElementDimension(train))
	setElementInterior(snd, getElementInterior(train))
	setSoundMaxDistance(snd, MAX_DISTANCE)
	setSoundMinDistance(snd, MIN_DISTANCE)
	setSoundVolume(snd, VOLUME)
	soundOwner[snd] = train
	return snd
end

local function stopCurrent(h)
	if h.sound and isElement(h.sound) then
		soundOwner[h.sound] = nil
		stopSound(h.sound)
	end
	h.sound = nil
end

local function setPhase(train, h, phase)
	stopCurrent(h)
	h.phase = phase
	if phase == "start" then
		h.sound = playOn(train, SND_START, false)
	elseif phase == "loop" then
		h.sound = playOn(train, SND_LOOP, true)
	elseif phase == "end" then
		h.sound = playOn(train, SND_END, false)
	end
	if not h.sound then horns[train] = nil end
end

-- Idempotens: többszöri hívás ugyanazzal az állapottal nem csinál semmit.
local function setHorn(train, on)
	if not isTrain(train) then return end
	local h = horns[train]
	if on then
		if h and h.on then return end
		if not h then
			h = { on = true }
			horns[train] = h
			setPhase(train, h, "start")
		else
			h.on = true
			-- lecsengés közben újra megnyomva: rögtön vissza a loopba
			if h.phase == "end" then setPhase(train, h, "loop") end
		end
	else
		if not h or not h.on then return end
		h.on = false
		-- start közben elengedve: a start lejátszódik, utána jön az end
		if h.phase == "loop" then setPhase(train, h, "end") end
	end
end

addEventHandler("onClientSoundStopped", resourceRoot, function(reason)
	local train = soundOwner[source]
	soundOwner[source] = nil
	if reason ~= "finished" or not train then return end
	local h = horns[train]
	if not h or h.sound ~= source then return end
	h.sound = nil
	if not isElement(train) then horns[train] = nil return end
	if h.phase == "start" then
		setPhase(train, h, h.on and "loop" or "end")
	elseif h.phase == "end" then
		horns[train] = nil
	end
end)

addEventHandler("onClientElementDataChange", root, function(key, _, new)
	if key == DATA_KEY and isTrain(source) then
		setHorn(source, new == true)
	end
end)

addEventHandler("onClientElementDestroy", root, function()
	local h = horns[source]
	if h then
		stopCurrent(h)
		horns[source] = nil
	end
end)

-- Ha a vonat már dudál, amikor bejön a látótávba / csatlakozáskor
addEventHandler("onClientElementStreamIn", root, function()
	if isTrain(source) and getElementData(source, DATA_KEY) == true and not horns[source] then
		local h = { on = true }
		horns[source] = h
		setPhase(source, h, "loop")
	end
end)

-- ===== Saját vezetés: horn gomb =====

local holding = false

local function myTrain()
	local v = getPedOccupiedVehicle(localPlayer)
	if isTrain(v) and getVehicleController(v) == localPlayer then return v end
end

local function hornDown()
	local train = myTrain()
	if not train or holding then return end
	holding = true
	setHorn(train, true)   -- azonnal szól nálunk, nem várunk a szerverre
	triggerServerEvent("rw_trainhorn:set", resourceRoot, true)
end

local function hornUp()
	if not holding then return end
	holding = false
	local train = myTrain()
	if train then setHorn(train, false) end
	triggerServerEvent("rw_trainhorn:set", resourceRoot, false)
end

bindKey("horn", "down", hornDown)
bindKey("horn", "up", hornUp)

addEventHandler("onClientPlayerVehicleExit", localPlayer, function(veh)
	if holding then
		holding = false
		if isTrain(veh) then setHorn(veh, false) end
	end
end)
addEventHandler("onClientPlayerWasted", localPlayer, function()
	if holding then hornUp() end
end)
