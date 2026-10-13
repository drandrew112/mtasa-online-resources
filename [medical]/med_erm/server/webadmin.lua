-- Web "ERM Admin" mode: everything /ermadmin offers in game (shift + task history, details,
-- auto dispatch switch), in the browser. Login with the v_accounts account
-- (exports.v_accounts:httpLogin); the admin level (Config.ADMIN_LEVEL or higher) is re-checked
-- on every call. The queries are the ones of server/admin.lua (AdminHandlers). English only.

WebAdmin = {
    sessions = {},   -- [token] = { account, lastSeen, level, levelAt }
}

local SESSION_TIMEOUT = 10 * 60
local LEVEL_CACHE = 10          -- seconds an admin level lookup is reused
local MAX_FAILS, FAIL_WINDOW = 5, 60
local fails = {}                -- [client] = { timestamps }

local DENIED = { ok = false, error = "unauthorized" }

local function accountsRunning()
    local res = getResourceFromName("v_accounts")
    return res and getResourceState(res) == "running"
end

-- admin_level of an account: the online player's account data (may not be saved yet),
-- otherwise the accounts table.
local function adminLevelOf(account)
    if accountsRunning() then
        for _, p in ipairs(getElementsByType("player")) do
            if exports.v_accounts:getName(p) == account then
                return tonumber(exports.v_mysql:getAccData(p, "admin_level")) or 0
            end
        end
    end
    local rows = exports.v_mysql:mysqlQuerySync("SELECT admin_level FROM `accounts` WHERE account_name = ? LIMIT 1", account)
    return rows and rows[1] and tonumber(rows[1].admin_level) or 0
end

local function tooManyFails(id)
    local t, keep = now(), {}
    for _, ts in ipairs(fails[id] or {}) do
        if t - ts < FAIL_WINDOW then keep[#keep + 1] = ts end
    end
    fails[id] = keep
    return #keep >= MAX_FAILS
end

local function newToken(account)
    return hash("sha256", table.concat({
        tostring(getTickCount()), tostring(now()), account,
        tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)),
    }, ":"))
end

-- session of a token when it is valid AND the account is still an admin
local function check(token)
    local s = type(token) == "string" and WebAdmin.sessions[token]
    if not s then return nil end
    local t = now()
    if t - s.lastSeen > SESSION_TIMEOUT then
        WebAdmin.sessions[token] = nil
        return nil
    end
    s.lastSeen = t
    if t - s.levelAt > LEVEL_CACHE then
        s.level, s.levelAt = adminLevelOf(s.account), t
    end
    if s.level < Config.ADMIN_LEVEL then
        WebAdmin.sessions[token] = nil
        return nil
    end
    return s
end

setTimer(function()
    local t = now()
    for token, s in pairs(WebAdmin.sessions) do
        if t - s.lastSeen > SESSION_TIMEOUT then WebAdmin.sessions[token] = nil end
    end
end, 60000, 0)

---------------------------------------------------------------- http exports

function ermAdminLogin(_, username, password)
    local id = exports.web_api:getCallerId(hostname)
    if tooManyFails(id) then return { ok = false, error = "Too many failed attempts. Try again in a minute." } end
    if not accountsRunning() then return { ok = false, error = "Account system is not available." } end

    local ok, account = exports.v_accounts:httpLogin(username, password)
    local level = ok and adminLevelOf(account) or 0
    if not ok or level < Config.ADMIN_LEVEL then
        table.insert(fails[id], now())
        outputServerLog("[erm] failed web admin login from " .. id)
        return { ok = false, error = ok and ("You need admin level " .. Config.ADMIN_LEVEL .. " or higher.") or account }
    end

    local token = newToken(account)
    WebAdmin.sessions[token] = { account = account, lastSeen = now(), level = level, levelAt = now() }
    outputServerLog("[erm] web admin login: " .. account .. " (" .. id .. ")")
    return { ok = true, token = token, account = account, level = level }
end

function ermAdminLogout(token)
    WebAdmin.sessions[token] = nil
    return { ok = true }
end

-- kind: shifts | shift | tasks | task, params as the in-game panel sends them
function ermAdminQuery(token, kind, params)
    if not check(token) then return DENIED end
    local handler = type(kind) == "string" and AdminHandlers[kind]
    if not handler then return { ok = false, error = "Unknown query." } end
    local ok, data = pcall(handler, type(params) == "table" and params or {})
    if not ok then
        outputDebugString("[erm] web admin query " .. kind .. ": " .. tostring(data), 1)
        return { ok = false, error = "Query failed." }
    end
    return { ok = true, kind = kind, data = data }
end

function ermAdminAuto(token)
    if not check(token) then return DENIED end
    local state = AutoDispatch.state()
    return { ok = true, available = state.available, enabled = state.enabled }
end

function ermAdminAutoSet(token, on)
    local s = check(token)
    if not s then return DENIED end
    local ok, err = AutoDispatch.set(on == true, "admin " .. s.account)
    if not ok then return { ok = false, error = tostring(err or "Failed") } end
    local state = AutoDispatch.state()
    return { ok = true, available = state.available, enabled = state.enabled }
end
