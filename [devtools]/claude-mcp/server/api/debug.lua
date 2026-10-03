-- debug: log capture, Lua execution (server / probe client), resources, exports,
-- element data. Development helpers for testing resource behaviour.

addEventHandler("onDebugMessage", root, function(message, level, file, line)
    if type(message) == "string" and message:find("[claude-mcp]", 1, true) then return end
    local lv = ({ [0] = "custom", [1] = "error", [2] = "warning", [3] = "info" })[level] or tostring(level)
    Util.addLog(lv, "server", message, { file = file, line = line })
end)

addEvent("cmcp:clientLog", true)
addEventHandler("cmcp:clientLog", resourceRoot, function(entries)
    if not Probe.clients[client] or type(entries) ~= "table" then return end
    for i = 1, math.min(#entries, 50) do
        local e = entries[i]
        Util.addLog(tostring(e.level), "client", tostring(e.message), { file = e.file, line = e.line, player = getPlayerName(client) })
    end
end)

-- log: { since (seq), level = error|warning|info|custom, source = server|client|bridge|api, search, limit }
Api.register("debug", "log", function(p)
    local since = P.int(p, "since", 0)
    local limit = P.int(p, "limit", 100, 1, CMCP.LOG_SIZE)
    local q = p.search and tostring(p.search):lower()
    local out = {}
    for i = #Util.log, 1, -1 do
        local e = Util.log[i]
        if e.seq <= since then break end
        if (not p.level or e.level == p.level) and (not p.source or e.source == p.source)
            and (not q or e.message:lower():find(q, 1, true) or (e.file and e.file:lower():find(q, 1, true))) then
            table.insert(out, 1, e)
            if #out >= limit then break end
        end
    end
    local last = Util.log[#Util.log]
    return { entries = out, returned = #out, lastSeq = last and last.seq or since,
        note = "Pass since = lastSeq next time to get only newer entries." }
end, { desc = "Captured server / probe-client debug messages and bridge events." })

local function allowExec()
    local v = get("allowExec")
    if v ~= true and v ~= "true" then
        fail("EXEC_DISABLED", "Lua execution is disabled (setting claude-mcp.allowExec = false).")
    end
end

local function packResults(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do out[i] = Util.jsonSafe((select(i, ...))) end
    return out, n
end

-- exec: { code, side = server|client, timeout }
Api.register("debug", "exec", function(p)
    allowExec()
    local code = P.str(p, "code")
    local side = P.str(p, "side", "server", { "server", "client" })
    Util.addLog("info", "api", "exec on " .. side .. ": " .. code:sub(1, 200))
    if side == "client" then
        return Probe.call("exec", { code = code }, P.int(p, "timeout", 10000, 500, 60000))
    end
    local fn, err = loadstring("return " .. code, "mcp_exec")
    if not fn then fn, err = loadstring(code, "mcp_exec") end
    if not fn and err == nil and not hasObjectPermissionTo(resource, "function.loadstring", false) then
        fail("ACL_DENIED", "The bridge has no ACL right for loadstring (server-side execute_lua).",
            { suggestion = "Give resource.claude-mcp an ACL with function.loadstring (e.g. add it to the runcode group in acl.xml) and run reloadacl (docs/installation.md). side = 'client' works without it." })
    end
    if not fn then fail("LUA_SYNTAX_ERROR", tostring(err)) end
    local printed = {}
    local env = setmetatable({
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
            printed[#printed + 1] = table.concat(parts, "\t")
        end,
        ref = function(id) return (Refs.resolve(id)) end,
        refOf = Refs.of,
    }, { __index = _G })
    setfenv(fn, env)
    local res = { pcall(fn) }
    if not res[1] then
        return { success = false, error = tostring(res[2]), printed = printed }
    end
    local values, n = packResults(unpack(res, 2, table.maxn(res)))
    return { success = true, results = values, count = n, printed = printed }
end, { mutates = true, async = true, desc = "Runs Lua on the server or the probe client (dev only)." })

-- resources: { action = list|info|start|stop|restart, name, filter }
Api.register("debug", "resources", function(p)
    local action = P.str(p, "action", "list", { "list", "info", "start", "stop", "restart" })
    if action == "list" then
        local out = {}
        local q = p.filter and tostring(p.filter):lower()
        for _, res in ipairs(getResources()) do
            local name = getResourceName(res)
            if not q or name:lower():find(q, 1, true) then
                out[#out + 1] = { name = name, state = getResourceState(res) }
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return { count = #out, resources = out }
    end
    local name = P.str(p, "name")
    local res = getResourceFromName(name)
    if not res then fail("RESOURCE_NOT_FOUND", "No resource '" .. name .. "'.") end
    if action == "info" then
        local exportsList = getResourceExportedFunctions(res) or {}
        return {
            name = name, state = getResourceState(res), failureReason = getResourceLoadFailureReason(res),
            info = { author = getResourceInfo(res, "author"), version = getResourceInfo(res, "version"), description = getResourceInfo(res, "description") },
            exports = exportsList, lastStartTime = getResourceLastStartTime(res), loadTime = getResourceLoadTime(res),
        }
    end
    if name == getResourceName(resource) then
        if action ~= "restart" then fail("INVALID_PARAMS", "The bridge can only restart itself, not " .. action .. ".") end
        if not hasObjectPermissionTo(resource, "function.restartResource", false) then
            fail("ACL_DENIED", "The bridge has no ACL right to restart resources.", { suggestion = "Add resource.claude-mcp to the Admin group in acl.xml, then reloadacl." })
        end
        setTimer(function() restartResource(resource) end, 500, 1)
        return { success = true, name = name, action = "restart", state = "restarting",
            note = "The bridge restarts in 0.5 s: all workspaces and entity ids are dropped; the probe client re-registers in a few seconds." }
    end
    local ok
    if action == "start" then ok = startResource(res, true)
    elseif action == "stop" then ok = stopResource(res)
    else ok = restartResource(res) end
    if not ok then
        fail("ACL_DENIED_OR_FAILED", action .. " " .. name .. " failed (state " .. getResourceState(res) .. ", reason: " .. tostring(getResourceLoadFailureReason(res)) .. ").",
            { suggestion = "The bridge needs ACL rights: add <object name=\"resource.claude-mcp\"/> to the Admin group in acl.xml (see docs/troubleshooting.md)." })
    end
    if p.wait ~= false then Async.sleep(1000) end
    return { success = true, name = name, action = action, state = getResourceState(res) }
end, { mutates = true, async = true, desc = "List / inspect / start / stop / restart resources." })

-- callExport: { resource, fn, args } ; args may contain { "$ref": "<entity id>" } element references
Api.register("debug", "callExport", function(p)
    local resName, fnName = P.str(p, "resource"), P.str(p, "fn")
    local res = getResourceFromName(resName)
    if not res or getResourceState(res) ~= "running" then fail("RESOURCE_NOT_RUNNING", "Resource '" .. resName .. "' is not running.") end
    local function decode(v)
        if type(v) == "table" then
            if v["$ref"] then return (Refs.require(v["$ref"])) end
            local out = {}
            for k, x in pairs(v) do out[k] = decode(x) end
            return out
        end
        return v
    end
    local args = {}
    for i, a in ipairs(type(p.args) == "table" and p.args or {}) do args[i] = decode(a) end
    local res2 = { pcall(call, res, fnName, unpack(args)) }
    if not res2[1] then fail("EXPORT_CALL_FAILED", tostring(res2[2])) end
    local values, n = packResults(unpack(res2, 2, table.maxn(res2)))
    return { success = true, results = values, count = n }
end, { mutates = true, desc = "Calls an exported server function of any running resource." })

-- elementData: { id, key, value (set when present), sync }
Api.register("debug", "elementData", function(p)
    local el = Refs.require(P.str(p, "id"))
    if p.key and p.value ~= nil then
        setElementData(el, tostring(p.key), p.value, p.sync ~= false)
        return { success = true, key = p.key, value = Util.jsonSafe(getElementData(el, tostring(p.key))) }
    end
    if p.key then return { key = p.key, value = Util.jsonSafe(getElementData(el, tostring(p.key))) } end
    return { data = Util.jsonSafe(getAllElementData(el)) }
end, { desc = "Reads (or sets) element data." })
