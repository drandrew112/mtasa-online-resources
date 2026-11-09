-- Agency radio channels: players on EMS / police work duty (work_core element data "work.id") get
-- their agency frequency (RADIO.AGENCIES), and the unit they are signed in to becomes their radio
-- unit label (shown next to their name on the listeners' radar):
--   EMS    -> med_erm getUnitData(player).callsign
--   police -> police_system getOfficerUnit(player)
-- Duty end takes them off the frequency (only if it is still the agency's own).
-- Event driven (work duty, med_erm sign-in / sign-out) with a slow poll as a safety net for
-- unit changes that have no event (police units, crew joins).

local byWork = {}
for _, a in ipairs(RADIO.AGENCIES) do byWork[a.work] = a end

local assigned = {}   -- [player] = agency the frequency came from

local function running(name)
	local res = getResourceFromName(name)
	return res and getResourceState(res) == "running"
end

local function unitCallsign(agency, player)
	local ok, cs = false, nil
	if agency.id == "ems" and running("med_erm") then
		ok, cs = pcall(function()
			local u = exports.med_erm:getUnitData(player)
			return u and u.callsign
		end)
	elseif agency.id == "police" and running("police_system") then
		ok, cs = pcall(function() return exports.police_system:getOfficerUnit(player) end)
	end
	if ok and cs and cs ~= "" then return tostring(cs) end
	return nil
end

local function update(player)
	if not isElement(player) then return end
	local agency = byWork[getElementData(player, "work.id")]
	local current = assigned[player]

	if current and current ~= agency then
		-- duty ended (or switched work): off the agency frequency
		if getPlayerRadioFrequency(player) == current.freq then
			setPlayerRadioFrequency(player, false)
		end
		setPlayerRadioUnit(player, false)
		assigned[player] = nil
		current = nil
	end

	if agency then
		if not current then
			assigned[player] = agency
			setPlayerRadioFrequency(player, agency.freq)
		end
		local cs = unitCallsign(agency, player)
		setPlayerRadioUnit(player, cs and (agency.tag .. " " .. cs) or agency.tag)
	end
end

local pending = {}
local function updateSoon(player)
	if pending[player] then return end
	pending[player] = true
	setTimer(function()
		pending[player] = nil
		update(player)
	end, 100, 1)
end

local function updateAll()
	for _, p in ipairs(getElementsByType("player")) do update(p) end
	for p in pairs(assigned) do
		if not isElement(p) then assigned[p] = nil end
	end
end

addEventHandler("onResourceStart", resourceRoot, function()
	updateAll()
	setTimer(updateAll, RADIO.AGENCY_UPDATE_MS, 0)
end)

addEventHandler("onPlayerQuit", root, function()
	assigned[source] = nil
	pending[source] = nil
end)

addEventHandler("onElementDataChange", root, function(key)
	if key == "work.id" and getElementType(source) == "player" then updateSoon(source) end
end)

-- work_core events (also fine when work_core is not running: the handlers just never fire)
addEvent("onPlayerWorkDutyStart")
addEvent("onPlayerWorkDutyEnd")
addEventHandler("onPlayerWorkDutyStart", root, function() updateSoon(source) end)
addEventHandler("onPlayerWorkDutyEnd", root, function() updateSoon(source) end)

-- med_erm unit sign-in / sign-out: refresh everybody on EMS duty (the crew list is in med_erm)
local function refreshAgency(id)
	for _, p in ipairs(getElementsByType("player")) do
		local a = byWork[getElementData(p, "work.id")]
		if a and a.id == id then updateSoon(p) end
	end
end
addEvent("onErmUnitSignIn")
addEvent("onErmUnitSignOut")
addEventHandler("onErmUnitSignIn", root, function() refreshAgency("ems") end)
addEventHandler("onErmUnitSignOut", root, function() refreshAgency("ems") end)
