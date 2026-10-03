-- status: bridge identity, health, live capabilities.

Api = Api or { handlers = {} }

-- Registers an action. info: { mutates = bool, async = bool, desc = string }
function Api.register(category, action, fn, info)
    Api.handlers[category] = Api.handlers[category] or {}
    Api.handlers[category][action] = { fn = fn, info = info or {} }
end

local INSTANCE = string.format("%08x%04x", getRealTime().timestamp, math.random(0, 0xffff))
local STARTED = getRealTime().timestamp
local startTick = getTickCount()
Api.stats = { requests = 0, errors = 0, lastRequestAt = nil, lastError = nil }

function Api.instance() return INSTANCE end

local function integrations()
    local out = {}
    for _, name in ipairs(CMCP.INTEGRATIONS) do
        local res = getResourceFromName(name)
        out[name] = res and getResourceState(res) or "missing"
    end
    return out
end

local function bridgeStatus()
    local workspaces = {}
    for _, name in ipairs(Registry.order) do
        local ws = Registry.workspaces[name]
        if ws then workspaces[#workspaces + 1] = { name = name, kind = ws.kind, entities = #ws.entities } end
    end
    local players = {}
    for _, p in ipairs(getElementsByType("player")) do
        local c = Probe.clients[p]
        players[#players + 1] = { name = getPlayerName(p), ref = Refs.of(p), probeReady = c and c.ready or false }
    end
    return {
        bridge = {
            name = "claude-mcp", version = CMCP.VERSION, apiVersion = CMCP.API_VERSION,
            instanceId = INSTANCE, startedAt = STARTED, uptimeSec = math.floor((getTickCount() - startTick) / 1000),
        },
        server = {
            name = getServerName(), mtaVersion = getVersion().sortable, httpPort = getServerHttpPort(),
            players = #players, maxPlayers = getMaxPlayers(), gameType = getGameType(), mapName = getMapName(),
        },
        probe = Probe.info(),
        players = players,
        workspaces = workspaces,
        entityCount = Registry.count(),
        jobs = Async.stats(),
        requests = Api.stats,
        integrations = integrations(),
        settings = {
            allowRemote = get("allowRemote") == true or get("allowRemote") == "true",
            allowExec = get("allowExec") == true or get("allowExec") == "true",
            probePlayer = get("probePlayer"),
        },
    }
end

Api.register("status", "get", function()
    return bridgeStatus()
end, { desc = "Bridge identity, probe client, workspaces, integrations, request counters." })

Api.register("status", "health", function()
    local s = bridgeStatus()
    local problems = {}
    if not s.probe.connected then
        problems[#problems + 1] = { code = "NO_PROBE_CLIENT", severity = "degraded",
            message = "No probe client: raycasts, ground, model bounds, area scans and screenshots are unavailable." }
    end
    local missing = 0
    for _, e in pairs(Registry.entities) do if not isElement(e.element) then missing = missing + 1 end end
    if missing > 0 then
        problems[#problems + 1] = { code = "MISSING_ENTITIES", severity = "warning", message = missing .. " registered entities lost their MTA element." }
    end
    if s.integrations.veh_manager ~= "running" then
        problems[#problems + 1] = { code = "VEH_MANAGER_DOWN", severity = "info", message = "veh_manager is not running: vehicle names fall back to GTA names." }
    end
    return {
        healthy = #problems == 0 or (s.probe.connected and missing == 0),
        instanceId = INSTANCE,
        probe = s.probe,
        problems = problems,
        entityCount = s.entityCount,
        missingEntities = missing,
        jobs = s.jobs,
        requests = Api.stats,
        integrations = s.integrations,
    }
end, { desc = "Health checks with structured problems." })

Api.register("status", "actions", function()
    local out = {}
    for category, actions in pairs(Api.handlers) do
        out[category] = {}
        for action, h in pairs(actions) do
            out[category][action] = h.info
        end
    end
    return { instanceId = INSTANCE, actions = out }
end, { desc = "Every HTTP category/action the bridge implements." })

Api.register("status", "ping", function()
    return { pong = true, instanceId = INSTANCE, tick = getTickCount() }
end)
