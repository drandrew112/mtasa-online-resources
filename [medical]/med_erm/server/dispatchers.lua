-- Dispatcher login for the web console.
--
-- Codes live in data/dispatchers.json (re-read on every login attempt, so
-- edits apply without a restart):
--   { "dispatchers": [ { "code": "DRA112", "name": "DrAndres" }, ... ] }
--
-- A successful login returns a random session token that the page keeps in
-- memory only (a reload asks for the code again). Every API call carries it.

Dispatchers = {
    sessions = {},   -- [token] = { name, display, code, lastSeen }
}

local FILE = "data/dispatchers.json"
local SESSION_TIMEOUT = 10 * 60      -- seconds without any request
local MAX_FAILS, FAIL_WINDOW = 5, 60  -- failed logins per client per window

local fails = {}                      -- [client] = { timestamps }

math.randomseed(getTickCount() + now())

local function loadCodes()
    local f = fileExists(FILE) and fileOpen(FILE, true)
    if not f then
        outputDebugString("[erm] " .. FILE .. " not found - nobody can log in to the dispatcher console", 2)
        return {}
    end
    local content = fileRead(f, fileGetSize(f))
    fileClose(f)

    local parsed = { fromJSON(content) }
    local list = (type(parsed[1]) == "table" and parsed[1].dispatchers) or parsed
    local codes = {}
    for _, d in pairs(type(list) == "table" and list or {}) do
        if type(d) == "table" and d.code and d.name then
            codes[tostring(d.code):upper()] = tostring(d.name)
        end
    end
    return codes
end

local function clientId()
    -- web_api: "player:<serial>" for the in-game console, otherwise the fallback - MTA exposes
    -- the caller's address to HTTP handlers as "hostname"
    return exports.web_api:getCallerId(hostname)
end

local function tooManyFails(id)
    local list, t, keep = fails[id] or {}, now(), {}
    for _, ts in ipairs(list) do
        if t - ts < FAIL_WINDOW then keep[#keep + 1] = ts end
    end
    fails[id] = keep
    return #keep >= MAX_FAILS
end

local function newToken(code)
    return hash("sha256", table.concat({
        tostring(getTickCount()), tostring(now()), code,
        tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)),
    }, ":"))
end

-- -> session | nil, error
function Dispatchers.login(code)
    local id = clientId()
    if tooManyFails(id) then
        return nil, "Too many failed attempts. Try again in a minute."
    end

    code = trim(code):upper()
    local name = code ~= "" and loadCodes()[code]
    if not name then
        table.insert(fails[id], now())
        outputServerLog("[erm] failed dispatcher login from " .. id)
        return nil, "Invalid dispatcher code."
    end

    local token = newToken(code)
    local session = { name = name, display = "Dispatcher " .. name, code = code, lastSeen = now() }
    Dispatchers.sessions[token] = session
    outputServerLog("[erm] " .. session.display .. " logged in (" .. id .. ")")
    return session, token
end

function Dispatchers.logout(token)
    local s = Dispatchers.sessions[token]
    if s then
        outputServerLog("[erm] " .. s.display .. " logged out")
        Dispatchers.sessions[token] = nil
    end
end

-- Session of a token (refreshes its activity), nil when invalid / expired.
function Dispatchers.check(token)
    local s = type(token) == "string" and Dispatchers.sessions[token]
    if not s then return nil end
    if now() - s.lastSeen > SESSION_TIMEOUT then
        Dispatchers.sessions[token] = nil
        return nil
    end
    s.lastSeen = now()
    return s
end

-- Drop expired sessions.
setTimer(function()
    local t = now()
    for token, s in pairs(Dispatchers.sessions) do
        if t - s.lastSeen > SESSION_TIMEOUT then Dispatchers.sessions[token] = nil end
    end
end, 60000, 0)
