-- rw_trainhorn (server) – DrAndrew112
-- A kürt állapota a vonaton van (element data "rw_horn"), minden kliens ebből szól.

local DATA_KEY   = "rw_horn"
local MIN_TOGGLE = 80      -- ms, toggle spam védelem
local MAX_HOLD   = 20000   -- ms, ennyi után automatikusan elengedi

local lastToggle = {}   -- [player] = tick
local holdTimers = {}   -- [train] = timer
local autoTimers = {}   -- [train] = timer (soundTrainHorn)

local function isTrain(v)
	return isElement(v) and getElementType(v) == "vehicle" and getVehicleType(v) == "Train"
end

local function stopTimer(t)
	if t and isTimer(t) then killTimer(t) end
end

function isTrainHornOn(train)
	return isTrain(train) and getElementData(train, DATA_KEY) == true
end

function setTrainHorn(train, state)
	if not isTrain(train) then return false end
	state = state and true or false
	stopTimer(holdTimers[train]); holdTimers[train] = nil
	if state then
		holdTimers[train] = setTimer(function()
			holdTimers[train] = nil
			setTrainHorn(train, false)
		end, MAX_HOLD, 1)
	else
		stopTimer(autoTimers[train]); autoTimers[train] = nil
	end
	if (getElementData(train, DATA_KEY) == true) ~= state then
		if state then
			setElementData(train, DATA_KEY, true)
		else
			removeElementData(train, DATA_KEY)
		end
	end
	return true
end

-- Adott hosszú dudálás (pl. rw_auto NPC vonatokhoz)
function soundTrainHorn(train, duration)
	if not isTrain(train) then return false end
	duration = math.max(50, tonumber(duration) or 1500)
	setTrainHorn(train, true)
	stopTimer(autoTimers[train])
	autoTimers[train] = setTimer(function()
		autoTimers[train] = nil
		setTrainHorn(train, false)
	end, duration, 1)
	return true
end

addEvent("rw_trainhorn:set", true)
addEventHandler("rw_trainhorn:set", resourceRoot, function(state)
	if not client then return end
	local train = getPedOccupiedVehicle(client)
	if not isTrain(train) or getVehicleController(train) ~= client then return end
	local now = getTickCount()
	if state and lastToggle[client] and now - lastToggle[client] < MIN_TOGGLE then return end
	lastToggle[client] = now
	setTrainHorn(train, state)
end)

local function releaseDriverHorn(player)
	local train = getPedOccupiedVehicle(player)
	if isTrain(train) and getVehicleController(train) == player then
		setTrainHorn(train, false)
	end
end

addEventHandler("onVehicleExit", root, function(_, seat)
	if seat == 0 and isTrain(source) then setTrainHorn(source, false) end
end)
addEventHandler("onPlayerWasted", root, function() releaseDriverHorn(source) end)
addEventHandler("onPlayerQuit", root, function()
	releaseDriverHorn(source)
	lastToggle[source] = nil
end)
addEventHandler("onElementDestroy", root, function()
	if holdTimers[source] or autoTimers[source] then
		stopTimer(holdTimers[source]); holdTimers[source] = nil
		stopTimer(autoTimers[source]); autoTimers[source] = nil
	end
end)

addEventHandler("onResourceStop", resourceRoot, function()
	for _, v in ipairs(getElementsByType("vehicle")) do
		if getElementData(v, DATA_KEY) then removeElementData(v, DATA_KEY) end
	end
end)
