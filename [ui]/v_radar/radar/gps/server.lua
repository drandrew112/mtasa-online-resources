-- GPS routes: the clients (radar/gps/sourceC.lua) ask for a route, the navmesh resource (server only) searches it
-- as an async job and the points go back to the asking player. At most one job runs per player and route channel
-- (waypoint / objective); a newer request while one runs waits and only the latest one is searched afterwards.

local CHANNELS = { waypoint = true, objective = true }

-- navmesh findVehicleRoute opts (README of [core]/navmesh)
local ROUTE_OPTS = {
	profile = "gps",
	simplify = 0.5,        -- metres: thins the lane geometry (kept close: the 3D ribbon follows it)
	startRadius = 60,
	startFallback = 300,   -- on foot off the roads, out in the hills
	goalRadius = 60,
	goalFallback = 600,    -- a map click far from the roads
}

local jobs = {}  -- [navmesh job id] = { player, channel, reqId }
local state = {} -- [player][channel] = { job = id | false, queued = args | false }

addEvent("onNavmeshRouteReady")
addEvent("v_radar:requestRoute", true)

local function navmeshRunning()
	local res = getResourceFromName("navmesh")
	return res and getResourceState(res) == "running"
end

local function reply(player, channel, reqId, flat, length)
	if isElement(player) then
		triggerClientEvent(player, "v_radar:routeResult", resourceRoot, channel, reqId, flat or false, length or 0)
	end
end

local function startJob(player, channel, args)
	local st = state[player][channel]
	st.queued = false

	if not navmeshRunning() then
		st.job = false
		reply(player, channel, args.reqId, false)
		return
	end

	local opts = {}
	for k, v in pairs(ROUTE_OPTS) do opts[k] = v end
	opts.heading = args.heading or nil

	local ok, id = pcall(function()
		return exports.navmesh:requestRoute("vehicle", args.x1, args.y1, args.z1, args.x2, args.y2, args.z2, opts)
	end)
	if not ok or not id then
		st.job = false
		reply(player, channel, args.reqId, false)
		return
	end

	st.job = id
	jobs[id] = { player = player, channel = channel, reqId = args.reqId }
end

addEventHandler("v_radar:requestRoute", resourceRoot, function(channel, reqId, x1, y1, z1, x2, y2, z2, heading)
	local player = client
	if not CHANNELS[channel] or not tonumber(reqId) then return end
	x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
	if not (x1 and y1 and x2 and y2) then return end

	local args = { reqId = reqId, x1 = x1, y1 = y1, z1 = tonumber(z1) or false, x2 = x2, y2 = y2,
		z2 = tonumber(z2) or false, heading = tonumber(heading) or false }

	state[player] = state[player] or {}
	state[player][channel] = state[player][channel] or { job = false, queued = false }
	local st = state[player][channel]

	if st.job then
		st.queued = args
		return
	end
	startJob(player, channel, args)
end)

addEventHandler("onNavmeshRouteReady", resourceRoot, function(id, result)
	local job = jobs[id]
	if not job then return end
	jobs[id] = nil

	local player, channel = job.player, job.channel
	local st = state[player] and state[player][channel]
	if not st then return end
	st.job = false

	-- a newer request is waiting: this answer is already out of date
	if st.queued then
		startJob(player, channel, st.queued)
		return
	end

	if type(result) ~= "table" or type(result.points) ~= "table" or #result.points < 2 then
		reply(player, channel, job.reqId, false)
		return
	end

	-- flat x, y, z list in decimetre steps: smaller to send
	local flat = {}
	for _, p in ipairs(result.points) do
		flat[#flat + 1] = math.floor(p[1] * 10 + 0.5) / 10
		flat[#flat + 1] = math.floor(p[2] * 10 + 0.5) / 10
		flat[#flat + 1] = math.floor(p[3] * 10 + 0.5) / 10
	end
	reply(player, channel, job.reqId, flat, result.length)
end)

-- navmesh stopped: its jobs never answer, free the channels (the clients retry)
addEventHandler("onResourceStop", root, function(res)
	if getResourceName(res) ~= "navmesh" then return end
	for id, job in pairs(jobs) do
		local st = state[job.player] and state[job.player][job.channel]
		if st then st.job, st.queued = false, false end
		reply(job.player, job.channel, job.reqId, false)
		jobs[id] = nil
	end
end)

addEventHandler("onPlayerQuit", root, function()
	state[source] = nil
end)
