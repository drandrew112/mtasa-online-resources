-- ============================================================
--  v_admin / server/web.lua
--  Web admin panel: everything the in-game panel (O) offers, in the browser
--  (http://<server>:<httpport>/v_admin/). English only.
--
--  Login: the acc_auth account (exports.acc_auth:httpLogin). The admin level is
--  re-read regularly; every action runs through the SAME admin* functions as the
--  commands and the in-game panel, with a "web actor" (see server/core.lua) in place
--  of a player element, so ADMIN.perms / canPunish apply unchanged.
--
--  The functions exported with http="true" are called by the page at
--  POST /v_admin/call/<function>; the first argument is the session token.
-- ============================================================

WebAdmin = {
    sessions = {},   -- [token] = { account, lastSeen, level, levelAt }
}

local SESSION_TIMEOUT = 10 * 60
local LEVEL_CACHE = 10          -- seconds an admin level lookup is reused
local MAX_FAILS, FAIL_WINDOW = 5, 60
local fails = {}                -- [caller id] = { timestamps }

local DENIED = { ok = false, error = "unauthorized" }

local function now() return getRealTime().timestamp end

local function accountsRunning()
    local res = getResourceFromName("acc_auth")
    return res and getResourceState(res) == "running"
end

local function sameAccount(a, b)
    return a and b and tostring(a):lower() == tostring(b):lower()
end

-- the online player logged into `account`, or nil
local function playerOnAccount(account)
    if not accountsRunning() then return nil end
    for _, p in ipairs(getElementsByType("player")) do
        if sameAccount(exports.acc_auth:getName(p), account) then return p end
    end
end

-- admin_level of an account: the online player's account data (may not be saved yet),
-- otherwise the accounts table.
local function adminLevelOf(account)
    local p = playerOnAccount(account)
    if p then return tonumber(exports.v_mysql:getAccData(p, "admin_level")) or 0 end
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
    if s.level < ADMIN.perms.panel then
        WebAdmin.sessions[token] = nil
        return nil
    end
    return s
end

--- A web session of this account is alive (used by the report claim logic).
function WebAdmin.accountActive(account)
    local t = now()
    for _, s in pairs(WebAdmin.sessions) do
        if sameAccount(s.account, account) and t - s.lastSeen <= SESSION_TIMEOUT then return true end
    end
    return false
end

setTimer(function()
    local t = now()
    for token, s in pairs(WebAdmin.sessions) do
        if t - s.lastSeen > SESSION_TIMEOUT then WebAdmin.sessions[token] = nil end
    end
end, 60000, 0)

-- The admin* functions' view of a session.
local function actorOf(s)
    local player = playerOnAccount(s.account)
    return {
        web     = true,
        account = s.account,
        name    = player and getPlayerName(player):gsub("#%x%x%x%x%x%x", "") or s.account,
        level   = s.level,
        player  = player,
        out     = {},
    }
end

local function english(x) return L.resolveFor("en", x) end

---------------------------------------------------------------- http exports

function adminWebLogin(_, username, password)
    local id = exports.web_api:getCallerId(hostname)
    if tooManyFails(id) then return { ok = false, error = "Too many failed attempts. Try again in a minute." } end
    if not accountsRunning() then return { ok = false, error = "Account system is not available." } end

    local ok, account = exports.acc_auth:httpLogin(username, password)
    local level = ok and adminLevelOf(account) or 0
    if not ok or level < ADMIN.perms.panel then
        table.insert(fails[id], now())
        outputServerLog("[v_admin] failed web login from " .. id)
        return { ok = false, error = ok and ("You need admin level " .. ADMIN.perms.panel .. " or higher.") or account }
    end

    local token = newToken(account)
    WebAdmin.sessions[token] = { account = account, lastSeen = now(), level = level, levelAt = now() }
    outputServerLog("[v_admin] web login: " .. account .. " (lvl " .. level .. ", " .. id .. ")")
    return { ok = true, token = token, account = account }
end

function adminWebLogout(token)
    WebAdmin.sessions[token] = nil
    return { ok = true }
end

-- Static data of the page: permission levels, rank names, command list.
local function staticInfo()
    local ranks = {}
    for lvl = 0, ADMIN.maxLevel do ranks[#ranks + 1] = { level = lvl, name = english(ADMIN.rankNames[lvl]) } end

    local commands = {}
    for _, c in ipairs(ADMIN.commands) do
        commands[#commands + 1] = {
            cmd = c.cmd,
            desc = english(c.desc),
            level = c.perm and ADMIN.perms[c.perm] or 0,
        }
    end
    local ok, languages = pcall(function() return exports.v_locals:getLanguages() end)
    return { perms = ADMIN.perms, ranks = ranks, commands = commands, maxLevel = ADMIN.maxLevel,
             instance = { id = INSTANCE.id(), name = INSTANCE.name() },
             languages = ok and type(languages) == "table" and languages or {} }
end

-- Everything the page shows, in one poll: players + reports + the caller.
function adminWebState(token, withStatic)
    local s = check(token)
    if not s then return DENIED end

    local players = adminPlayerList(true)
    local data = {
        ok      = true,
        time    = now(),
        account = s.account,
        level   = s.level,
        inGame  = playerOnAccount(s.account) and true or false,
        players = players,
        reports = (s.level >= ADMIN.perms.reports) and adminReportListEnglish() or {},
    }
    if withStatic then data.info = staticInfo() end
    return data
end

-- action: the in-game panel's actions (goto, mute, jail, ban, setlevel, announce, ...)
function adminWebAction(token, action, targetId, a, b)
    local s = check(token)
    if not s then return DENIED end
    if type(action) ~= "string" then return { ok = false, error = "Unknown action." } end

    local actor = actorOf(s)
    local ok, known = pcall(adminRunAction, actor, action, targetId, a, b)
    if not ok then
        outputDebugString("[v_admin] web action " .. action .. ": " .. tostring(known), 1)
        return { ok = false, error = "Action failed." }
    end
    if not known then return { ok = false, error = "Unknown action." } end
    return { ok = true, messages = actor.out }
end

-- op: claim | message | close | tp
function adminWebReport(token, op, id, text)
    local s = check(token)
    if not s then return DENIED end
    if s.level < ADMIN.perms.reports then
        return { ok = false, error = "You need admin level " .. ADMIN.perms.reports .. " or higher." }
    end

    local actor = actorOf(s)
    local ok, done
    if op == "claim" then ok, done = pcall(adminReportClaim, actor, id)
    elseif op == "message" then ok, done = pcall(adminReportMessage, actor, id, text)
    elseif op == "close" then ok, done = pcall(adminReportClose, actor, id)
    elseif op == "tp" then ok, done = pcall(adminReportTP, actor, id)
    else return { ok = false, error = "Unknown operation." } end

    if not ok then
        outputDebugString("[v_admin] web report " .. tostring(op) .. ": " .. tostring(done), 1)
        return { ok = false, error = "Action failed." }
    end
    if op == "close" and done then adminLog(actor, "closed report " .. tostring(id)) end
    return { ok = done and true or false, messages = actor.out, error = (not done and #actor.out == 0) and "That report no longer exists." or nil }
end

-- Saved logs: no file name = the list, otherwise one log.
function adminWebLogs(token, file)
    local s = check(token)
    if not s then return DENIED end
    if s.level < ADMIN.perms.reports then
        return { ok = false, error = "You need admin level " .. ADMIN.perms.reports .. " or higher." }
    end
    if file == nil or file == "" then
        return { ok = true, list = adminReportLogList() }
    end
    local data = adminReportLogRead(file)
    if not data then return { ok = false, error = "Could not read that log file." } end
    for _, m in ipairs(data.messages or {}) do
        m.sender, m.text = english(m.sender), english(m.text)
    end
    return { ok = true, file = file, log = data }
end

---------------------------------------------------------------- pages (v_admin 3.0)

-- Page requests (server/pages.lua) that answer later wait here until the page asks again.
local jobs, jobSeq = {}, 0       -- [id] = { account, t, done, result, message, out }

local function jobAnswer(job)
    return {
        ok = job.result ~= false,
        result = job.result,
        message = job.message,
        messages = job.out,
        error = (job.result == false and not job.message) and "Request failed." or nil,
    }
end

-- One page request: { ok, result, message, messages } or { ok, pending = id } (ask adminWebResult).
function adminWebCall(token, page, action, args)
    local s = check(token)
    if not s then return DENIED end
    local actor = actorOf(s)
    local job = { account = s.account, t = now(), out = actor.out }
    PAGES.run(actor, tostring(page), tostring(action), type(args) == "table" and args or {}, function(result, message)
        job.done = true
        job.result = L.resolveDeep(result, "en")
        job.message = message and (tostring(L.resolveFor("en", message)):gsub("#%x%x%x%x%x%x", "")) or nil
    end)
    if job.done then return jobAnswer(job) end
    jobSeq = jobSeq + 1
    jobs[jobSeq] = job
    return { ok = true, pending = jobSeq }
end

function adminWebResult(token, id)
    local s = check(token)
    if not s then return DENIED end
    id = tonumber(id)
    local job = id and jobs[id]
    if not job or not sameAccount(job.account, s.account) then return { ok = false, error = "Unknown request." } end
    if not job.done then return { ok = true, pending = id } end
    jobs[id] = nil
    return jobAnswer(job)
end

setTimer(function()
    local t = now()
    for id, job in pairs(jobs) do
        if t - job.t > 120 then jobs[id] = nil end
    end
end, 60000, 0)
