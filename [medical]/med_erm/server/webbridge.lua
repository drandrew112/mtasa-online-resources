-- In-game dispatcher console (ui_browser site) -> web API.
-- The page cannot use HTTP in game, so client/webpage.lua forwards its calls
-- here; they run the very same http.lua functions (token check included).

local ALLOWED = {
    ermLogin = true, ermLogout = true, ermGetState = true, ermSetPriority = true,
    ermAssign = true, ermUnassign = true, ermCloseTask = true, ermCreateTask = true,
    ermSendMessage = true,
}

-- Identifies the caller for the login rate limit (see Dispatchers.login).
WebCaller = nil

local function pack(...)
    return { n = select("#", ...), ... }
end

addEvent("erm:web:call", true)
addEventHandler("erm:web:call", resourceRoot, function(localId, fn, argsJson)
    local player = client
    if not isElement(player) or not ALLOWED[fn] or type(_G[fn]) ~= "function" then return end
    if type(argsJson) ~= "string" or #argsJson > 8192 then return end

    local args = pack(fromJSON(argsJson))
    WebCaller = "player:" .. getPlayerSerial(player)
    local ok, result = pcall(_G[fn], unpack(args, 1, args.n))
    WebCaller = nil

    if not ok then
        outputDebugString("[erm] web bridge " .. fn .. ": " .. tostring(result), 1)
        result = { ok = false, error = "Server error" }
    end
    triggerClientEvent(player, "erm:web:result", resourceRoot, localId, result)
end)
