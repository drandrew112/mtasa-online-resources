-- GPS navigation on the navmesh road network.
--
-- The routes come from the navmesh resource ([core]/navmesh, server side, lane-level roads): a route tracker asks
-- the v_radar server (radar/gps/server.lua), which runs navmesh's async route search and sends the points back.
-- A tracker follows the player along its route: passed points are dropped from the drawing, and when the player
-- leaves the route (drove off, missed a turn) or drives against it, a new route is requested from the current
-- position and heading.
--
-- Two trackers use it: the waypoint (purple, vehicle element data gpsDestination, only in a vehicle; this file)
-- and the objective route (yellow, on foot or in a vehicle; radar/objectives.lua).

GPS = {
	UPDATE_INTERVAL = 250,
	OFF_ROUTE_VEHICLE = 30,  -- metres from the route line...
	OFF_ROUTE_FOOT = 50,
	OFF_ROUTE_TIME = 1200,   -- ...for this long (ms): new route
	WRONG_WAY_SPEED = 6,     -- m/s: driving against the route above this speed...
	WRONG_WAY_ANGLE = 115,   -- ...at this angle or more to the route...
	WRONG_WAY_TIME = 2500,   -- ...for this long: new route from the current heading
	REROUTE_COOLDOWN = 3000, -- no new route sooner than this after the last answer
	RETRY_INTERVAL = 5000,   -- no route found (off the roads, navmesh down): try again this often
	REQUEST_TIMEOUT = 15000,
	ARRIVE_DISTANCE = 25,    -- waypoint reached
	IMAGE_REFRESH = 800,     -- map route image rebuilt at most this often while driving along
	LOOKAHEAD = 40,          -- route segments searched ahead of the current one
}

-- the waypoint route points {x, y, z} and the segment the player is on
gpsRoute = false
currentNode = 1

local trackers = {}
local nextRequestId = 0
local sqrt, cosAngle = math.sqrt, math.cos(math.rad(GPS.WRONG_WAY_ANGLE))

local Tracker = {}
Tracker.__index = Tracker

function getRouteTracker(channel)
	return trackers[channel]
end

-- callbacks: changed(tracker) when the points / current segment changed, arrived(tracker) at the route end (optional)
function createRouteTracker(channel, callbacks)
	local t = setmetatable({
		channel = channel, cb = callbacks or {},
		active = false, points = false, index = 1,
		reqId = false, pendingSince = false, lastRequest = 0, lastAnswer = 0,
		offSince = false, wrongSince = false, dirty = false, imageTick = 0,
	}, Tracker)
	trackers[channel] = t
	return t
end

local function routeOrigin()
	local veh = getPedOccupiedVehicle(localPlayer)
	local x, y, z = getElementPosition(veh or localPlayer)
	return x, y, z, veh
end

-- distance of (x, y) to segment a-b, and the 0..1 position of the closest point on it
local function segmentDistance(x, y, a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	local l2 = dx * dx + dy * dy
	local t = l2 > 0 and ((x - a.x) * dx + (y - a.y) * dy) / l2 or 0
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local qx, qy = x - (a.x + dx * t), y - (a.y + dy * t)
	return sqrt(qx * qx + qy * qy), t
end

function Tracker:changed()
	self.dirty = false
	self.imageTick = getTickCount()
	if self.cb.changed then self.cb.changed(self) end
end

-- new route from the player's position (vehicle: in its driving direction). force: even while one is searched
function Tracker:request(force)
	local now = getTickCount()
	if self.pendingSince and not force and now - self.pendingSince < GPS.REQUEST_TIMEOUT then
		return
	end

	local x, y, z, veh = routeOrigin()
	local heading = false
	if veh then
		local _, _, rz = getElementRotation(veh)
		heading = rz
	end

	nextRequestId = nextRequestId + 1
	self.reqId = nextRequestId
	self.pendingSince = now
	self.lastRequest = now
	triggerServerEvent("v_radar:requestRoute", resourceRoot, self.channel, self.reqId, x, y, z,
		self.destX, self.destY, self.destZ or false, heading)
end

function Tracker:setDestination(x, y, z)
	self.destX, self.destY, self.destZ = x, y, z or false
	self.active = true
	self.points = false
	self.index = 1
	self.offSince, self.wrongSince = false, false
	self:request(true)
	self:changed()
end

function Tracker:stop()
	if not self.active and not self.points then return end
	self.active = false
	self.points = false
	self.index = 1
	self.reqId = false
	self.pendingSince = false
	self.offSince, self.wrongSince = false, false
	self:changed()
end

function Tracker:answer(reqId, flat, length)
	if not self.active or reqId ~= self.reqId then return end
	self.pendingSince = false
	self.lastAnswer = getTickCount()

	if type(flat) == "table" and #flat >= 6 then
		local pts = {}
		for i = 1, #flat - 2, 3 do
			pts[#pts + 1] = {x = flat[i], y = flat[i + 1], z = flat[i + 2]}
		end
		self.points = pts
		self.index = 1
		self.length = length
		self.offSince, self.wrongSince = false, false
		self:changed()
	end
	-- no route: an old one stays drawn, update() asks again after RETRY_INTERVAL
end

-- map-space polyline from the player's spot on the route to its end (radar/sourceC.lua addGPSLine format)
function Tracker:getMapLines()
	local lines = {}
	local pts = self.points
	if not pts then return lines end

	local a, b = pts[self.index], pts[self.index + 1]
	if a and b and self.projT then
		lines[1] = {remapTheFirstWay(a.x + (b.x - a.x) * self.projT), remapTheFirstWay(a.y + (b.y - a.y) * self.projT)}
	elseif a then
		lines[1] = {remapTheFirstWay(a.x), remapTheFirstWay(a.y)}
	end
	for i = self.index + 1, #pts do
		lines[#lines + 1] = {remapTheFirstWay(pts[i].x), remapTheFirstWay(pts[i].y)}
	end
	return lines
end

function Tracker:update(now)
	if not self.active then return end

	if self.pendingSince and now - self.pendingSince > GPS.REQUEST_TIMEOUT then
		self.pendingSince = false
	end

	local pts = self.points
	if not pts then
		if not self.pendingSince and now - self.lastRequest > GPS.RETRY_INTERVAL then
			self:request()
		end
		return
	end

	local x, y, _, veh = routeOrigin()

	-- the segment the player is on, searched around the current one
	local best, bestDist, bestT = self.index, math.huge, 0
	for i = math.max(1, self.index - 1), math.min(#pts - 1, self.index + GPS.LOOKAHEAD) do
		local d, t = segmentDistance(x, y, pts[i], pts[i + 1])
		if d < bestDist then
			best, bestDist, bestT = i, d, t
		end
	end
	if best ~= self.index then
		self.index = best
		self.dirty = true
	elseif self.projT and abs(bestT - self.projT) > 0.2 then
		self.dirty = true
	end
	self.projT = bestT
	self.distance = bestDist

	local last = pts[#pts]
	local endDist = getDistanceBetweenPoints2D(x, y, last.x, last.y)
	if best >= #pts - 1 and endDist < GPS.ARRIVE_DISTANCE and self.cb.arrived then
		self.cb.arrived(self)
		return
	end

	-- near the destination off the road (the route ends on the nearest lane): nothing to reroute
	local destDist = getDistanceBetweenPoints2D(x, y, self.destX, self.destY)
	local endToDest = getDistanceBetweenPoints2D(last.x, last.y, self.destX, self.destY)
	local nearDestination = destDist < endToDest + GPS.ARRIVE_DISTANCE

	local limit = veh and GPS.OFF_ROUTE_VEHICLE or GPS.OFF_ROUTE_FOOT
	if bestDist > limit and not nearDestination then
		self.offSince = self.offSince or now
	else
		self.offSince = false
	end

	local wrong = false
	if veh and bestDist <= limit then
		local vx, vy = getElementVelocity(veh)
		local speed = sqrt(vx * vx + vy * vy)
		if speed * 50 > GPS.WRONG_WAY_SPEED then
			local a, b = pts[best], pts[best + 1]
			local dx, dy = b.x - a.x, b.y - a.y
			local len = sqrt(dx * dx + dy * dy)
			wrong = len > 0.5 and (vx * dx + vy * dy) / (speed * len) < cosAngle
		end
	end
	self.wrongSince = wrong and (self.wrongSince or now) or false

	if not self.pendingSince and now - self.lastAnswer > GPS.REROUTE_COOLDOWN then
		if (self.offSince and now - self.offSince > GPS.OFF_ROUTE_TIME)
			or (self.wrongSince and now - self.wrongSince > GPS.WRONG_WAY_TIME) then
			self.offSince, self.wrongSince = false, false
			self:request()
		end
	end

	if self.dirty and now - self.imageTick > GPS.IMAGE_REFRESH then
		self:changed()
	end
end

addEvent("v_radar:routeResult", true)
addEventHandler("v_radar:routeResult", resourceRoot,
	function (channel, reqId, flat, length)
		local t = trackers[channel]
		if t then
			t:answer(reqId, flat, length)
		end
	end
)

------------------------------------------------------------------------ waypoint (gpsDestination)

local waypoint = createRouteTracker("waypoint", {
	changed = function (t)
		gpsRoute = t.points
		currentNode = t.index
		setGPSMapLines(t:getMapLines())
		processGPSLines()
	end,
	arrived = function (t)
		t:stop()
		if occupiedVehicle and isElement(occupiedVehicle) then
			setElementData(occupiedVehicle, "gpsDestination", false)
		end
	end,
})

function makeRoute(destinationX, destinationY)
	if not occupiedVehicle or not tonumber(destinationX) or not tonumber(destinationY) then
		return false
	end
	waypoint:setDestination(tonumber(destinationX), tonumber(destinationY), false)
	return true
end

function endRoute()
	waypoint:stop()
end

addEventHandler("onClientResourceStart", resourceRoot,
	function ()
		setTimer(function ()
			local now = getTickCount()
			-- the waypoint lives on the vehicle: left it / it was destroyed
			if waypoint.active and not getPedOccupiedVehicle(localPlayer) then
				endRoute()
			end
			for _, t in pairs(trackers) do
				t:update(now)
			end
		end, GPS.UPDATE_INTERVAL, 0)

		if occupiedVehicle then
			local destination = getElementData(occupiedVehicle, "gpsDestination")
			if type(destination) == "table" then
				makeRoute(destination[1], destination[2])
			end
		end
	end
)

addEventHandler("onClientVehicleEnter", root,
	function (player)
		if player == localPlayer then
			local destination = getElementData(source, "gpsDestination")
			if type(destination) == "table" then
				makeRoute(destination[1], destination[2])
			end
		end
	end
)

addEventHandler("onClientVehicleExit", root,
	function (player)
		if player == localPlayer then
			endRoute()
		end
	end
)
