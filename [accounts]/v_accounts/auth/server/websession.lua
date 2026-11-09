-- Web sessions: login of external software (voice client, tools) with the account's username + password.
-- Over HTTP (http="true" exports, POST /v_accounts/call/<fn>, body = JSON array):
--   webLogin(username, password [, clientName]) -> { ok, token, account, displayName, expiresIn } | { ok = false, error }
--   webLogout(token)                            -> { ok = true }
--   webCheck(token)                             -> { ok, account, displayName, online, expiresIn } | { ok = false, error }
-- For other resources (server exports):
--   getWebSession(token)     -> account name | false   (also extends the session)
--   getWebSessionInfo(token) -> { account, client, created, lastSeen, host } | false
--   endWebSessions(account)  -> number of sessions ended (password change, ban, admin)
-- Sessions live in memory: a v_accounts restart logs every web client out.
-- Guests need HTTP in the Default ACL (general.http), like the med_web pages.

WebSessions = { byToken = {} }

local SESSION_IDLE = 12 * 3600       -- seconds without a call before the session ends
local SESSION_MAX = 7 * 24 * 3600    -- absolute lifetime
local MAX_PER_ACCOUNT = 5            -- oldest session goes when a 6th logs in
local BAN_RECHECK = 300              -- seconds between two ban checks of a session
local HOST_MAX_FAILS, HOST_FAIL_WINDOW = 10, 60

local hostFails = {}   -- [address] = { timestamps }

local function now() return getRealTime().timestamp end

local function caller()
    return type(hostname) == "string" and hostname ~= "" and hostname or "script"
end

local function newToken(account)
    return hash("sha256", table.concat({
        tostring(getTickCount()), tostring(now()), account, caller(),
        tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)),
    }, ":"))
end

local function displayNameOf(account)
    local p = playerOnAccount(account)
    if p then return getDisplayName(p) end
    return account
end

local function hostBlocked(host)
    local t, keep = now(), {}
    for _, ts in ipairs(hostFails[host] or {}) do
        if t - ts < HOST_FAIL_WINDOW then keep[#keep + 1] = ts end
    end
    hostFails[host] = keep
    return #keep >= HOST_MAX_FAILS
end

-- valid session of a token (expired / banned ones are removed) | nil
local function session(token)
    if type(token) ~= "string" or #token ~= 64 then return nil end
    local s = WebSessions.byToken[token]
    if not s then return nil end
    local t = now()
    if t - s.lastSeen > SESSION_IDLE or t - s.created > SESSION_MAX then
        WebSessions.byToken[token] = nil
        return nil
    end
    if t - (s.banChecked or 0) > BAN_RECHECK then
        s.banChecked = t
        if activeBan and activeBan(nil, s.account) then
            WebSessions.byToken[token] = nil
            return nil
        end
    end
    s.lastSeen = t
    return s
end

local function expiresIn(s)
    local t = now()
    return math.max(0, math.min(SESSION_IDLE - (t - s.lastSeen), SESSION_MAX - (t - s.created)))
end

---------------------------------------------------------------- HTTP

function webLogin(username, password, clientName)
    local host = caller()
    if hostBlocked(host) then return { ok = false, error = "Too many failed attempts. Try again in a minute." } end
    local ok, account = httpLogin(username, password)
    if not ok then
        table.insert(hostFails[host], now())
        outputServerLog("[v_accounts] failed web login (" .. tostring(username):sub(1, 32) .. ") from " .. host)
        return { ok = false, error = account }
    end

    -- keep at most MAX_PER_ACCOUNT sessions per account
    local mine = {}
    for token, s in pairs(WebSessions.byToken) do
        if s.account == account then mine[#mine + 1] = { token = token, created = s.created } end
    end
    table.sort(mine, function(a, b) return a.created < b.created end)
    for i = 1, #mine - MAX_PER_ACCOUNT + 1 do WebSessions.byToken[mine[i].token] = nil end

    local token = newToken(account)
    local t = now()
    WebSessions.byToken[token] = {
        account = account, client = tostring(clientName or "web"):sub(1, 40), created = t, lastSeen = t,
        host = host, banChecked = t,
    }
    outputServerLog("[v_accounts] web login: " .. account .. " (" .. tostring(clientName or "web"):sub(1, 40) .. ", " .. host .. ")")
    return { ok = true, token = token, account = account, displayName = displayNameOf(account), expiresIn = SESSION_IDLE }
end

function webLogout(token)
    if type(token) == "string" then WebSessions.byToken[token] = nil end
    return { ok = true }
end

function webCheck(token)
    local s = session(token)
    if not s then return { ok = false, error = "unauthorized" } end
    return { ok = true, account = s.account, displayName = displayNameOf(s.account),
        online = playerOnAccount(s.account) ~= nil, expiresIn = expiresIn(s) }
end

---------------------------------------------------------------- server exports

function getWebSession(token)
    local s = session(token)
    return s and s.account or false
end

function getWebSessionInfo(token)
    local s = session(token)
    if not s then return false end
    return { account = s.account, client = s.client, created = s.created, lastSeen = s.lastSeen, host = s.host }
end

function endWebSessions(account)
    if type(account) ~= "string" then return 0 end
    local n, needle = 0, account:lower()
    for token, s in pairs(WebSessions.byToken) do
        if s.account:lower() == needle then
            WebSessions.byToken[token] = nil
            n = n + 1
        end
    end
    return n
end

setTimer(function()
    local t = now()
    for token, s in pairs(WebSessions.byToken) do
        if t - s.lastSeen > SESSION_IDLE or t - s.created > SESSION_MAX then WebSessions.byToken[token] = nil end
    end
    for host in pairs(hostFails) do hostBlocked(host) if #hostFails[host] == 0 then hostFails[host] = nil end end
end, 600000, 0)
