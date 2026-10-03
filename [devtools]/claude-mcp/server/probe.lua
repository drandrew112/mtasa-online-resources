-- The probe client: one connected player whose game client answers geometry
-- queries the server cannot (raycasts, ground, model bounds, world models,
-- screenshots). The server has no GTA collision data, so every world-geometry
-- feature needs a probe.
--
-- Selection: the "probePlayer" setting, else the player who typed /mcp probe,
-- else the first ready client. The probe sends a heartbeat every 5 s.

Probe = { clients = {}, preferred = nil, pending = {}, seq = 0 }

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
        if type(info) == "table" then c.info = info end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Probe.clients[source] = nil
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

function Probe.get()
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

function Probe.require()
    local p = Probe.get()
    if not p then
        fail("NO_PROBE_CLIENT", "No probe client is connected. World geometry (raycasts, ground, model bounds, screenshots) needs a player in the game.",
            { retryable = true, suggestion = "Join the MTA server with a game client (optionally type /mcp probe). Entity spawning and road-graph queries still work without one." })
    end
    return p
end

function Probe.info(player)
    player = player or Probe.get()
    if not player then return { connected = false } end
    local c = Probe.clients[player]
    local x, y, z = getElementPosition(player)
    return {
        connected = true,
        player = getPlayerName(player),
        ref = Refs.of(player),
        position = M.vec(x, y, z),
        dimension = getElementDimension(player),
        interior = getElementInterior(player),
        lastHeartbeatMs = now() - c.last,
        client = c.info,
    }
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

---------------------------------------------------------------- focus

-- The client only has collision near its camera. When a query point is far from
-- the probe, the camera is moved above it for the duration of the job.
-- -> focused (bool), distance (m)
function Probe.focus(x, y, z, allowFocus)
    local player = Probe.require()
    local px, py, pz = getElementPosition(player)
    local d = M.dist2D(px, py, x, y)
    -- already focused near this point within the running job
    if Probe.focused == player and Probe.focusPos and M.dist2D(Probe.focusPos[1], Probe.focusPos[2], x, y) <= CMCP.PROBE_RANGE * 0.6 then
        return true, d
    end
    if d <= CMCP.PROBE_RANGE or allowFocus == false then return false, d end
    setCameraMatrix(player, x - 30, y - 30, (z or pz) + 60, x, y, z or pz)
    local first = Probe.focused ~= player
    Probe.focused = player
    Probe.focusPos = { x, y }
    if first then
        Async.defer(function()
            if isElement(player) then setCameraTarget(player, player) end
            Probe.focused = nil
            Probe.focusPos = nil
        end)
    end
    Async.sleep(CMCP.FOCUS_SETTLE)
    return true, d
end
