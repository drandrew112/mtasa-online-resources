-- HTTP entry points. One exported function per category:
--   POST /claude-mcp/call/<category>   body: [ "<action>", { params }, { meta } ]
-- Response: [ envelope ]
--   { ok = true, result = ..., job, ms }                         finished
--   { ok = true, pending = true, job = "j12" }                   still running (poll jobs / callback)
--   { ok = false, error = { code, message, retryable, suggestion, ... } }

local LOCAL_HOSTS = { ["127.0.0.1"] = true, ["::1"] = true, ["localhost"] = true, ["::ffff:127.0.0.1"] = true }

local function allowedCaller()
    -- `hostname` is set by MTA for HTTP calls only; in-process calls have none
    if type(hostname) ~= "string" then return true end
    if LOCAL_HOSTS[hostname] then return true end
    local remote = get("allowRemote")
    return remote == true or remote == "true"
end

local function dispatch(category, action, params, meta)
    Api.stats.requests = Api.stats.requests + 1
    Api.stats.lastRequestAt = getRealTime().timestamp
    if not allowedCaller() then
        return { ok = false, error = { code = "REMOTE_NOT_ALLOWED", message = "Only localhost may call the bridge (" .. tostring(hostname) .. ").",
            suggestion = "Run the MCP server on the MTA host, or set claude-mcp.allowRemote = true." } }
    end
    local actions = Api.handlers[category]
    if type(action) ~= "string" or not actions or not actions[action] then
        local known = {}
        for a in pairs(actions or {}) do known[#known + 1] = a end
        table.sort(known)
        return { ok = false, error = { code = "UNKNOWN_ACTION", message = "Unknown action '" .. tostring(action) .. "' in category '" .. category .. "'.",
            known = known } }
    end
    if params ~= nil and type(params) ~= "table" then
        return { ok = false, error = { code = "INVALID_PARAMS", message = "params must be a JSON object." } }
    end
    local env = Async.run(category, action, actions[action].fn, params or {}, meta)
    if not env.ok then
        Api.stats.errors = Api.stats.errors + 1
        Api.stats.lastError = { at = getRealTime().timestamp, category = category, action = action, code = env.error and env.error.code }
    end
    env.instanceId = Api.instance()
    return env
end

local function entry(category)
    return function(action, params, meta)
        local ok, env = pcall(dispatch, category, action, params, meta)
        if not ok then
            return { ok = false, error = Util.toError(env), instanceId = Api.instance() }
        end
        return env
    end
end

status     = entry("status")
player     = entry("player")
camera     = entry("camera")
world      = entry("world")
roads      = entry("roads")
models     = entry("models")
entities   = entry("entities")
placement  = entry("placement")
workspace  = entry("workspace")
scene      = entry("scene")
validation = entry("validation")
screenshot = entry("screenshot")
medical    = entry("medical")
dev        = entry("debug") -- not "debug": that would shadow the Lua debug library

-- jobs("poll", { ids = { ... } })
function jobs(action, params)
    if not allowedCaller() then
        return { ok = false, error = { code = "REMOTE_NOT_ALLOWED", message = "Only localhost may call the bridge." } }
    end
    if action == "poll" then
        return { ok = true, result = Async.poll(type(params) == "table" and params.ids or {}), instanceId = Api.instance() }
    end
    return { ok = false, error = { code = "UNKNOWN_ACTION", message = "jobs supports 'poll'." }, instanceId = Api.instance() }
end

-- in-process API for other resources (same envelope). Async actions return the pending envelope.
function callBridge(category, action, params)
    return entry(tostring(category))(action, params, nil)
end

addEventHandler("onResourceStart", resourceRoot, function()
    cmcpLog("bridge %s started (instance %s); HTTP: /%s/call/<category>", CMCP.VERSION, Api.instance(), getResourceName(resource))
end)
