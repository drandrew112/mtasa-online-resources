-- Server helpers: structured errors, parameter parsing, output formatting, logging.

Util = {}

---------------------------------------------------------------- errors

-- Throws a structured error. extra: { retryable, suggestion, entity, cause, details }
function fail(code, message, extra)
    local e = { __cmcp = true, code = code, message = message }
    if type(extra) == "table" then
        for k, v in pairs(extra) do e[k] = v end
    end
    -- inside a job coroutine (and not inside Util.try) the error is yielded out of the
    -- job instead of raised: MTA logs every error that ends a coroutine as a script error.
    local co = coroutine.running()
    if co and Async and Async.FAIL and not (Util.tryDepth[co] and Util.tryDepth[co] > 0) and Async.isJobCoroutine(co) then
        coroutine.yield(Async.FAIL, e)
    end
    error(e, 0)
end

Util.tryDepth = setmetatable({}, { __mode = "k" })

-- pcall for code that may call fail(): fail() raises a normal error inside it
function Util.try(fn, ...)
    local co = coroutine.running() or "main"
    Util.tryDepth[co] = (Util.tryDepth[co] or 0) + 1
    local res = { pcall(fn, ...) }
    Util.tryDepth[co] = Util.tryDepth[co] - 1
    return unpack(res, 1, table.maxn(res))
end

-- normalises anything thrown into an error table
function Util.toError(err)
    if type(err) == "table" and err.__cmcp then
        err.__cmcp = nil
        return err
    end
    local msg = tostring(err)
    return { code = "INTERNAL_ERROR", message = msg, retryable = false,
        suggestion = "This is a bridge bug or an unexpected MTA state; check get_debug_log." }
end

---------------------------------------------------------------- logging

Util.log = {}  -- ring buffer { t, level, source, message }
local logSeq = 0

function Util.addLog(level, source, message, extra)
    logSeq = logSeq + 1
    local entry = { seq = logSeq, time = getRealTime().timestamp, tick = getTickCount(), level = level, source = source, message = tostring(message) }
    if extra then for k, v in pairs(extra) do entry[k] = v end end
    Util.log[#Util.log + 1] = entry
    if #Util.log > CMCP.LOG_SIZE then table.remove(Util.log, 1) end
end

function cmcpLog(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    outputServerLog("[claude-mcp] " .. msg)
    Util.addLog("info", "bridge", msg)
end

---------------------------------------------------------------- params

P = {}

function P.num(p, key, default, min, max)
    local v = p and p[key]
    if v == nil then
        if default == nil then fail("INVALID_PARAMS", "Missing numeric parameter '" .. key .. "'.") end
        return default
    end
    v = tonumber(v)
    if not v or v ~= v then fail("INVALID_PARAMS", "Parameter '" .. key .. "' must be a number.") end
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end

function P.int(p, key, default, min, max)
    local v = P.num(p, key, default, min, max)
    return v and math.floor(v)
end

function P.str(p, key, default, allowed)
    local v = p and p[key]
    if v == nil then
        if default == nil then fail("INVALID_PARAMS", "Missing string parameter '" .. key .. "'.") end
        return default
    end
    v = tostring(v)
    if allowed then
        for _, a in ipairs(allowed) do if a == v then return v end end
        fail("INVALID_PARAMS", "Parameter '" .. key .. "' must be one of: " .. table.concat(allowed, ", ") .. " (got '" .. v .. "').")
    end
    return v
end

function P.bool(p, key, default)
    local v = p and p[key]
    if v == nil then return default end
    return v == true or v == "true" or v == 1
end

-- {x,y,z} | [x,y,z] -> x, y, z (z optional -> nil)
function P.vec(v, name, requireZ)
    if type(v) ~= "table" then
        fail("INVALID_PARAMS", "Parameter '" .. (name or "position") .. "' must be {x, y, z}.")
    end
    local x = tonumber(v.x or v[1])
    local y = tonumber(v.y or v[2])
    local z = tonumber(v.z or v[3])
    if not x or not y or (requireZ and not z) then
        fail("INVALID_PARAMS", "Parameter '" .. (name or "position") .. "' must contain numeric x, y" .. (requireZ and ", z" or "") .. ".")
    end
    if math.abs(x) > 1e5 or math.abs(y) > 1e5 or (z and math.abs(z) > 1e5) then
        fail("INVALID_PARAMS", "Parameter '" .. (name or "position") .. "' is out of range.")
    end
    return x, y, z
end

---------------------------------------------------------------- output

function Util.pos(element)
    local x, y, z = getElementPosition(element)
    return M.vec(x, y, z)
end

function Util.rot(element)
    local rx, ry, rz = getElementRotation(element)
    return M.vec(rx, ry, rz, 2)
end

function Util.copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Util.copy(x) end
    return out
end

function Util.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Util.resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running" or false
end

function Util.zone(x, y, z)
    return {
        zone = getZoneName(x, y, z or 0, false),
        city = getZoneName(x, y, z or 0, true),
    }
end

-- vehicle model display name, preferring veh_manager:getModelName
function Util.vehicleName(model)
    if Util.resourceRunning("veh_manager") then
        local ok, name = pcall(function() return exports.veh_manager:getModelName(model) end)
        if ok and name then return name, "veh_manager" end
    end
    local n = getVehicleNameFromModel(model)
    if n and n ~= "" then return n, "gta" end
    return nil
end

-- makes a value safe for JSON (elements -> refs, functions dropped, NaN -> 0)
function Util.jsonSafe(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return 0 end
        return v
    elseif t == "string" or t == "boolean" or t == "nil" then
        return v
    elseif t == "userdata" then
        if isElement(v) then return { ["$ref"] = Refs.of(v), type = getElementType(v) } end
        return tostring(v)
    elseif t == "table" then
        if depth > 12 then return "<max depth>" end
        local out = {}
        for k, x in pairs(v) do
            local key = type(k) == "number" and k or tostring(k)
            out[key] = Util.jsonSafe(x, depth + 1)
        end
        return out
    end
    return tostring(v)
end
