-- pt_web :: server/util.lua - helpers shared by the server scripts

Util = {}

function Util.running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- exports[res][fn](...) when the resource runs and the call does not fail -> result | nil
-- (looked up per call: a reloaded resource is a new object, a cached exports table goes stale)
function Util.call(res, fn, ...)
    if not Util.running(res) then return nil end
    local ok, a = pcall(function(...) return exports[res][fn](exports[res], ...) end, ...)
    if ok then return a end
    outputDebugString(("pt_web: %s:%s failed: %s"):format(res, fn, tostring(a)), 2)
    return nil
end

local function isMsg(x)
    return type(x) == "table" and rawget(x, "__loc") == true and type(rawget(x, "t")) == "string"
end

-- v_locals message objects (they lose their metatable across exports) -> plain text, deep.
-- Texts without parameters are cached (station / line names repeat in every answer).
local textCache = {}
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "v_locals" then textCache = {} end
end)

local function resolveMsg(m)
    local cacheable = rawget(m, "p") == nil
    if cacheable and textCache[m.t] then return textCache[m.t] end
    local s = Util.call("v_locals", "resolve", PT.LANG, { t = m.t, p = rawget(m, "p"), __loc = true })
    if type(s) ~= "string" or s == "" then s = m.t end
    if cacheable then textCache[m.t] = s end
    return s
end

function Util.text(x, depth)
    depth = depth or 0
    if isMsg(x) then return resolveMsg(x) end
    if type(x) ~= "table" or depth > 10 then return x end
    local out = {}
    for k, v in pairs(x) do out[k] = Util.text(v, depth + 1) end
    return out
end

function Util.now() return getRealTime().timestamp end

function Util.secOfDay(ts)
    local t = getRealTime(ts)
    return t.hour * 3600 + t.minute * 60 + t.second
end

function Util.dayStart(ts)
    return ts - Util.secOfDay(ts)
end

function Util.clean(s) return (tostring(s or ""):gsub("#%x%x%x%x%x%x", "")) end
