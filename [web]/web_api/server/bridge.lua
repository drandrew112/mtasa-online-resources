-- web_api :: server/bridge.lua
-- In-game transport. A page inside ui_browser has no HTTP access, so its calls arrive here
-- (page -> client/bridge.lua -> "osa:web:call") and run the very same exported functions that
-- MTA exposes over HTTP as  /<resource>/call/<function>.  Only exports marked http="true" in
-- the app's meta.xml can be reached, exactly like over HTTP.

local MAX_ARGS_LEN   = 16384    -- bytes of the JSON argument array
local LATENT_OVER    = 24000    -- answers longer than this go out as a latent event
local LATENT_BPS     = 300000
local FLOOD_MAX      = 100      -- calls per player ...
local FLOOD_WINDOW   = 5000     -- ... per this many ms

local current = nil             -- { player, id } while an app function runs

-- Which functions of an app can be called: the server exports with http="true".
local exportCache = {}          -- [app] = { [function] = true }

local function httpExports(app)
    if exportCache[app] then return exportCache[app] end
    local xml = xmlLoadFile(":" .. app .. "/meta.xml", true)
    if not xml then return nil end
    local set = {}
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        if xmlNodeGetName(node) == "export" and xmlNodeGetAttribute(node, "http") == "true" then
            local kind = xmlNodeGetAttribute(node, "type")
            local fn = xmlNodeGetAttribute(node, "function")
            if fn and (kind == "server" or kind == "shared") then set[fn] = true end
        end
    end
    xmlUnloadFile(xml)
    exportCache[app] = set
    return set
end

addEventHandler("onResourceStart", root, function(res) exportCache[getResourceName(res)] = nil end)
addEventHandler("onResourceStop", root, function(res) exportCache[getResourceName(res)] = nil end)

-- Identifies who is behind the current http="true" call: "player:<serial>" for the in-game
-- page, otherwise the fallback (pass the HTTP global `hostname`) or "web". Used for rate
-- limits and logs.
function getCallerId(fallback)
    if current then return current.id end
    return type(fallback) == "string" and fallback ~= "" and fallback or "web"
end

-- The player behind the current call, false over HTTP.
function getCallerPlayer()
    return current and current.player or false
end

local flood = {}   -- [player] = { windowStart, count }

local function flooded(player)
    local t = getTickCount()
    local f = flood[player]
    if not f or t - f[1] > FLOOD_WINDOW then
        flood[player] = { t, 1 }
        return false
    end
    f[2] = f[2] + 1
    return f[2] > FLOOD_MAX
end

addEventHandler("onPlayerQuit", root, function() flood[source] = nil end)

local function pack(...)
    return { n = select("#", ...), ... }
end

local function answer(player, localId, result)
    local json
    if result == nil then
        json = "[null]"
    else
        json = toJSON(result, true) or '[{"ok":false,"error":"Encoding failed"}]'
    end
    if #json > LATENT_OVER then
        triggerLatentClientEvent(player, "osa:web:result", LATENT_BPS, false, resourceRoot, localId, json)
    else
        triggerClientEvent(player, "osa:web:result", resourceRoot, localId, json)
    end
end

local function fail(msg)
    return { ok = false, error = msg }
end

local function invoke(player, app, fn, argsJson)
    local res = getResourceFromName(app)
    if not res or getResourceState(res) ~= "running" then return fail("Service unavailable") end

    local allowed = httpExports(app)
    if not allowed or not allowed[fn] then return fail("Unknown function") end

    local args = pack(fromJSON(argsJson))
    current = { player = player, id = "player:" .. tostring(getPlayerSerial(player)) }
    local ok, result = pcall(call, res, fn, unpack(args, 1, args.n))
    current = nil

    if not ok then
        outputDebugString("[web_api] " .. app .. "." .. fn .. ": " .. tostring(result), 1)
        return fail("Server error")
    end
    return result
end

addEvent("osa:web:call", true)
addEventHandler("osa:web:call", resourceRoot, function(localId, app, fn, argsJson)
    local player = client
    if not isElement(player) or getElementType(player) ~= "player" then return end
    if type(localId) ~= "number" or type(app) ~= "string" or type(fn) ~= "string" or type(argsJson) ~= "string" then return end
    if #argsJson > MAX_ARGS_LEN or not app:find("^[%w_%-]+$") or not fn:find("^[%w_]+$") then return end

    if flooded(player) then
        return answer(player, localId, fail("Too many requests"))
    end
    answer(player, localId, invoke(player, app, fn, argsJson))
end)
