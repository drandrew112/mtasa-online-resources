-- Unit indicator (server watcher): police / EMS players that are members of a unit get the element data
-- "radar.unit" = { a = "pd" | "ems", c = callsign, s = status key }. The client (radar/unitstatus.lua) draws it
-- above the microphone icon. Data comes from the unit systems themselves:
--   EMS    -> med_erm getUnitData(player)            (callsign, status)
--   police -> police_system getOfficerUnitInfo(player) (callsign, status)
-- Polled once a second, element data is only written when something changed.

local DATA_KEY = "radar.unit"
local POLL_MS = 1000

local function running(name)
	local res = getResourceFromName(name)
	return res and getResourceState(res) == "running"
end

local function lookup(player)
	local emsOk = running("med_erm")
	if emsOk then
		local ok, u = pcall(function() return exports.med_erm:getUnitData(player) end)
		if ok and type(u) == "table" and u.callsign and u.status then
			return { a = "ems", c = tostring(u.callsign), s = u.status }
		end
	end
	if running("police_system") then
		local ok, u = pcall(function() return exports.police_system:getOfficerUnitInfo(player) end)
		if ok and type(u) == "table" and u.callsign and u.status then
			return { a = "pd", c = tostring(u.callsign), s = u.status }
		end
	end
	return nil
end

local function same(a, b)
	if a == nil or b == nil then return a == b end
	return a.a == b.a and a.c == b.c and a.s == b.s
end

local function update(player)
	local work = getElementData(player, "work.id")
	local new = (work == "ems" or work == "police") and lookup(player) or nil
	local cur = getElementData(player, DATA_KEY)
	if same(cur or nil, new) then return end
	if new then
		setElementData(player, DATA_KEY, new)
	else
		removeElementData(player, DATA_KEY)
	end
end

local function updateAll()
	for _, p in ipairs(getElementsByType("player")) do update(p) end
end

addEventHandler("onResourceStart", resourceRoot, function()
	updateAll()
	setTimer(updateAll, POLL_MS, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
	for _, p in ipairs(getElementsByType("player")) do
		if getElementData(p, DATA_KEY) ~= nil then removeElementData(p, DATA_KEY) end
	end
end)
