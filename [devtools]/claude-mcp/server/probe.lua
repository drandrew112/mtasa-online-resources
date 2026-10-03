-- The probe clients: connected players whose game clients answer geometry
-- queries the server cannot (raycasts, ground, model bounds, world models,
-- screenshots). The server has no GTA collision data, so every world-geometry
-- feature needs a probe.
--
-- Primary probe: the "probePlayer" setting, else the player who typed /mcp probe
-- (or select_probe), else the first ready client. "player" / "probe" / "camera"
-- targets, the player/camera API and plain screenshots of the current view
-- always mean the primary.
--
-- Work distribution: every job is bound to one probe the first time it needs
-- one (Probe.require / Probe.focus), and keeps it until it ends. With several
-- probes connected the least loaded one is picked (fewest running jobs, free
-- camera, closest to the query point), so parallel requests run on different
-- game clients. Every ready client in the primary's dimension / interior is a
-- worker. A job that moves a probe camera owns it until it ends; other jobs
-- that need the same camera wait for it.
--
-- The probe sends a heartbeat every 5 s.

Probe = { clients = {}, preferred = nil, pending = {}, seq = 0, load = {}, camOwner = {} }

addEvent("cmcp:clientReady", true)
addEvent("cmcp:heartbeat", true)
addEvent("cmcp:probeReply", true)

local function now() return getTickCount() end

addEventHandler("cmcp:clientReady", resourceRoot, function(info)
    if not isElement(client) then return end
    Probe.clients[client] = { ready = true, since = now(), last = now(), info = type(info) == "table" and info or {} }
    cmcpLog("probe client ready: %s", getPlayerName(client))
end)

addEventHandler("cmcp:heartbeat", resourceRoot, function(info)
    local c = Probe.clients[client]
    if c then
        c.last = now()
        if type(info) == "table" then
            -- sticky: also set by a failed screenshot, cleared only by a restore of the window
            if info.minimized then c.minimized = true elseif info.restored then c.minimized = false end
            info.restored = nil
            c.info = info
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Probe.clients[source] = nil
    Probe.load[source] = nil
    Probe.camOwner[source] = nil
    if Probe.preferred == source then Probe.preferred = nil end
    for rid, req in pairs(Probe.pending) do
        if req.player == source then
            Probe.pending[rid] = nil
            req.wake(false, { code = "PROBE_DISCONNECTED", message = "The probe client left the server during the request.", retryable = true })
        end
    end
end)

local function alive(player)
    local c = Probe.clients[player]
    return isElement(player) and c and c.ready and now() - c.last < CMCP.PROBE_STALE
end
Probe.alive = alive

-- the primary probe (the developer's own client)
function Probe.primary()
    local wanted = get("probePlayer")
    if type(wanted) == "string" and wanted ~= "" then
        local p = getPlayerFromName(wanted)
        if p and alive(p) then return p end
    end
    if Probe.preferred and alive(Probe.preferred) then return Probe.preferred end
    local best, bestSince
    for player, c in pairs(Probe.clients) do
        if alive(player) and (not bestSince or c.since < bestSince) then best, bestSince = player, c.since end
    end
    return best
end

-- every probe that can take work: the primary first, then the other ready
-- clients in the primary's dimension / interior (element collision differs per dimension)
function Probe.workers()
    local primary = Probe.primary()
    if not primary then return {} end
    local list = { primary }
    local dim, int = getElementDimension(primary), getElementInterior(primary)
    for player in pairs(Probe.clients) do
        if player ~= primary and alive(player) and getElementDimension(player) == dim and getElementInterior(player) == int then
            list[#list + 1] = player
        end
    end
    return list
end

local function jobProbe(job)
    return job and job.probe and alive(job.probe) and job.probe or nil
end

-- binds the running job to a probe (once) -> player | nil
-- opts: primary (must be the primary), screen (needs a non-minimized window), near {x, y}
function Probe.acquire(opts)
    opts = opts or {}
    local job = Async.self()
    local bound = jobProbe(job)
    if bound then return bound end
    local pick
    if opts.primary then
        pick = Probe.primary()
    else
        local list = Probe.workers()
        if opts.screen then
            local visible = {}
            for _, pl in ipairs(list) do
                if not Probe.clients[pl].minimized then visible[#visible + 1] = pl end
            end
            if #visible > 0 then list = visible end
        end
        local bestScore
        for i, pl in ipairs(list) do
            local owner = Probe.camOwner[pl]
            local score = (Probe.load[pl] or 0) * 1000 + ((owner and not owner.done) and 500 or 0) + (i == 1 and 0 or 1)
            if opts.near then
                local x, y = getElementPosition(pl)
                score = score + math.min(M.dist2D(x, y, opts.near[1], opts.near[2]), CMCP.PROBE_RANGE * 2) / 10
            end
            if not bestScore or score < bestScore then pick, bestScore = pl, score end
        end
    end
    if pick and job then
        job.probe = pick
        Probe.load[pick] = (Probe.load[pick] or 0) + 1
        Async.defer(function()
            if Probe.load[pick] then Probe.load[pick] = math.max(0, Probe.load[pick] - 1) end
        end)
    end
    return pick
end

-- the running job's probe, else the primary (never binds; use it to check whether a probe exists)
function Probe.get()
    return jobProbe(Async.self()) or Probe.primary()
end

function Probe.require(opts)
    local p = Probe.acquire(opts)
    if not p then
        fail("NO_PROBE_CLIENT", "No probe client is connected. World geometry (raycasts, ground, model bounds, screenshots) needs a player in the game.",
            { retryable = true, suggestion = "Join the MTA server with a game client (optionally type /mcp probe). Entity spawning and road-graph queries still work without one." })
    end
    return p
end

function Probe.info(player)
    player = player or Probe.primary()
    if not player then return { connected = false } end
    local c = Probe.clients[player]
    local x, y, z = getElementPosition(player)
    return {
        connected = true,
        player = getPlayerName(player),
        ref = Refs.of(player),
        primary = player == Probe.primary(),
        runningJobs = Probe.load[player] or 0,
        cameraBusy = Probe.camOwner[player] ~= nil,
        minimized = c.minimized == true,
        position = M.vec(x, y, z),
        dimension = getElementDimension(player),
        interior = getElementInterior(player),
        lastHeartbeatMs = now() - c.last,
        client = c.info,
    }
end

-- every worker probe (status)
function Probe.list()
    local out = {}
    for _, pl in ipairs(Probe.workers()) do out[#out + 1] = Probe.info(pl) end
    return out
end

-- Calls a probe op on the client and waits for the reply (inside a job).
-- -> result table; throws a structured error on failure / timeout
function Probe.call(op, args, timeout, player)
    player = player or Probe.require()
    Probe.seq = Probe.seq + 1
    local rid = Probe.seq
    local wake = Async.waker()
    local req = { player = player, op = op, wake = wake, started = now() }
    Probe.pending[rid] = req
    req.timer = setTimer(function()
        if Probe.pending[rid] then
            Probe.pending[rid] = nil
            wake(false, { code = "PROBE_TIMEOUT", message = "The probe client did not answer '" .. op .. "' in time.", retryable = true,
                suggestion = "The game client may be minimized, loading or lagging. Retry, or check get_status." })
        end
    end, timeout or CMCP.PROBE_TIMEOUT, 1)
    triggerClientEvent(player, "cmcp:probe", resourceRoot, rid, op, args or {})
    local ok, result = Async.wait()
    if not ok then
        local e = type(result) == "table" and result or { code = "PROBE_ERROR", message = tostring(result) }
        fail(e.code or "PROBE_ERROR", e.message or "Probe operation failed.", e)
    end
    return result
end

addEventHandler("cmcp:probeReply", resourceRoot, function(rid, ok, result)
    local req = Probe.pending[rid]
    if not req or req.player ~= client then return end
    Probe.pending[rid] = nil
    if isTimer(req.timer) then killTimer(req.timer) end
    req.wake(ok == true, result)
end)

---------------------------------------------------------------- camera ownership

-- Gives the running job exclusive use of the probe's camera until it ends (waits
-- while another job holds it). The camera is handed back to the player afterwards
-- unless keepCamera is set (the job only needs the camera to stay where it is).
function Probe.lockCamera(player, keepCamera)
    local job = Async.self()
    if not job then return end
    job.cameraMoved = job.cameraMoved or not keepCamera
    local deadline = now() + CMCP.CAMERA_WAIT
    while true do
        local owner = Probe.camOwner[player]
        if owner == job then return end
        if not owner or owner.done then break end
        if not alive(player) then fail("PROBE_DISCONNECTED", "The probe client left the server during the request.", { retryable = true }) end
        if now() > deadline then
            fail("PROBE_BUSY", "The probe camera stayed busy with job " .. tostring(owner.id) .. ".", { retryable = true })
        end
        Async.sleep(150)
    end
    Probe.camOwner[player] = job
    Async.defer(function()
        if Probe.camOwner[player] ~= job then return end
        Probe.camOwner[player] = nil
        if not job.cameraMoved then return end
        if isElement(player) then setCameraTarget(player, player) end
    end)
end

---------------------------------------------------------------- focus

-- The client only has collision near its camera. When a query point is far from
-- the job's probe, its camera is moved above the point for the rest of the job.
-- -> focused (bool), distance (m)
function Probe.focus(x, y, z, allowFocus)
    local job = Async.self()
    local player = Probe.require({ near = { x, y } })
    local px, py, pz = getElementPosition(player)
    local d = M.dist2D(px, py, x, y)
    -- already focused near this point within the running job
    if job and job.focusPos and Probe.camOwner[player] == job and M.dist2D(job.focusPos[1], job.focusPos[2], x, y) <= CMCP.PROBE_RANGE * 0.6 then
        return true, d
    end
    if d <= CMCP.PROBE_RANGE or allowFocus == false then return false, d end
    Probe.lockCamera(player)
    setCameraMatrix(player, x - 30, y - 30, (z or pz) + 60, x, y, z or pz)
    if job then job.focusPos = { x, y } end
    Async.sleep(CMCP.FOCUS_SETTLE)
    return true, d
end
