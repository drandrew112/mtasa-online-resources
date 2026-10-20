if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Account System - server side
--
-- The mod does NOT use MTA's built-in account system. An "account" is a row in
-- the shared `accounts` table (see server/db.lua + [core]/v_mysql). A logged-in
-- player is identified by the "accName" element data set here; every other
-- resource reads/writes their data through exports.v_mysql:getAccData /
-- setAccData. Passwords are bcrypt hashes (passwordHash / passwordVerify).

local SAVE_INTERVAL = 120000 -- periodic autosave interval, in ms

-- Players currently being renamed by the script on purpose, so the
-- onPlayerChangeNick handler can allow those while still blocking manual ones.
local scriptedRename = {}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- The logged-in account name for a player, or nil.
local function nameOf(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return nil end
    local n = getElementData(player, "accName")
    return (type(n) == "string" and n ~= "") and n or nil
end

-- The online player logged into `accountName`, or nil.
local function playerOnAccount(accountName)
    if type(accountName) ~= "string" then return nil end
    local needle = accountName:lower()
    for _, player in ipairs(getElementsByType("player")) do
        local n = nameOf(player)
        if n and n:lower() == needle then return player end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Bans
--------------------------------------------------------------------------------

-- Bans live in the shared MySQL `bans` table (through v_mysql), so a ban made
-- on one server applies on every server using the same database. They are
-- keyed by ACCOUNT NAME. When the banned player is online at ban time their
-- SERIAL (and IP, for the record) is stored too, so a fresh account on the same
-- machine is caught on join as well. There are no temporary bans: a row is
-- active while lifted_at = 0.
--
-- The active rows are cached here and re-read every BAN_REFRESH ms (async), so
-- join/login checks never wait on the database. After each refresh the online
-- players are re-checked, which picks up bans / unbans made on another server.

local BAN_TABLE   = "bans"
local BAN_REFRESH = 30000

local activeBans = {}   -- { { id, account, serial, date, admin, reason }, ... }

local function banDbReady()
    local res = getResourceFromName("v_mysql")
    if not res or getResourceState(res) ~= "running" then return false end
    return exports.v_mysql:mysqlIsConnected() == true
end

local function dateString(timestamp)
    local ts = tonumber(timestamp)
    local t = ts and getRealTime(ts) or getRealTime()
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

local function nonEmpty(v)
    return (type(v) == "string" and v ~= "") and v or nil
end

local function rowToBan(row)
    return {
        id      = tonumber(row.id),
        account = nonEmpty(row.account_name),
        serial  = nonEmpty(row.serial),
        date    = dateString(row.created_at),
        admin   = nonEmpty(row.admin)  or "n/a",
        reason  = nonEmpty(row.reason) or "n/a",
    }
end

local BAN_SELECT = "SELECT id, account_name, serial, admin, reason, created_at FROM `"
    .. BAN_TABLE .. "` WHERE lifted_at = 0"

local function setActiveBans(rows)
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = rowToBan(row) end
    activeBans = list
end

-- {date, admin, reason, account} for the active ban matching this serial or
-- account name, or nil when neither is banned.
local function getActiveBan(serial, accountName)
    local needle = type(accountName) == "string" and accountName:lower() or nil
    for _, ban in ipairs(activeBans) do
        if (serial and ban.serial == serial)
        or (needle and ban.account and ban.account:lower() == needle) then
            return ban
        end
    end
    return nil
end

-- A banned player stays connected but is frozen and stripped of GTA controls,
-- so all they can do is look at the ban panel.
local function applyBanState(player, ban)
    setElementData(player, "banned", true)
    setElementData(player, "banned_date", ban.date)
    setElementData(player, "banned_admin", ban.admin)
    setElementData(player, "banned_reason", ban.reason)
    setElementData(player, "banned_account", ban.account or false)

    setElementFrozen(player, true)
    toggleAllControls(player, false, true, false)
end

local function clearBanState(player)
    setElementFrozen(player, false)
    toggleAllControls(player, true, true, true)
    for _, key in ipairs({ "banned_date", "banned_admin", "banned_reason", "banned_account" }) do
        setElementData(player, key, false)
    end
    setElementData(player, "banned", false)

    if nameOf(player) then
        triggerClientEvent(player, "acc:setPanel", player, nil)
    else
        triggerClientEvent(player, "acc:setPanel", player, "login")
    end
end

-- Checked on join (serial only - the account is not known yet).
local function evaluateBan(player)
    local ban = getActiveBan(getPlayerSerial(player), nil)
    if ban then
        applyBanState(player, ban)
        return true
    end

    if getElementData(player, "banned") == true then
        clearBanState(player) -- ban was lifted since the last check
    end
    setElementData(player, "banned", false)
    return false
end

-- Re-checks every online player against the cache (after a refresh). The
-- account is the logged-in one, or the one a rejected login was banned on.
local function syncBanStates()
    for _, player in ipairs(getElementsByType("player")) do
        local wasBanned = getElementData(player, "banned") == true
        local account = nameOf(player) or (wasBanned and getElementData(player, "banned_account")) or nil
        local ban = getActiveBan(getPlayerSerial(player), account)
        if ban and not wasBanned then
            applyBanState(player, ban)
            triggerClientEvent(player, "acc:setPanel", player, "banned")
        elseif not ban and wasBanned then
            clearBanState(player)
        end
    end
end

addEvent("acc:banRows")
addEventHandler("acc:banRows", resourceRoot, function(_, rows)
    if type(rows) ~= "table" then return end -- DB error: keep the last known list
    setActiveBans(rows)
    syncBanStates()
end)

local function refreshBans()
    if not banDbReady() then return end
    exports.v_mysql:mysqlQueryAsync("acc:banRows", 0, BAN_SELECT)
end

addEventHandler("onPlayerJoin", root, function()
    evaluateBan(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if banDbReady() then
        exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. BAN_TABLE .. [[` (
            `id`           INT AUTO_INCREMENT PRIMARY KEY,
            `account_name` VARCHAR(50)  DEFAULT NULL,
            `serial`       VARCHAR(32)  DEFAULT NULL,
            `ip`           VARCHAR(45)  DEFAULT NULL,
            `reason`       TEXT         NOT NULL,
            `admin`        VARCHAR(64)  NOT NULL DEFAULT '',
            `created_at`   INT          NOT NULL DEFAULT 0,
            `lifted_at`    INT          NOT NULL DEFAULT 0,
            `lifted_by`    VARCHAR(64)  DEFAULT NULL,
            KEY `idx_account` (`account_name`),
            KEY `idx_serial`  (`serial`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        local rows = exports.v_mysql:mysqlQuerySync(BAN_SELECT)
        if type(rows) == "table" then setActiveBans(rows) end
    end
    for _, player in ipairs(getElementsByType("player")) do
        evaluateBan(player)
    end
    setTimer(refreshBans, BAN_REFRESH, 0)
end)

--------------------------------------------------------------------------------
-- Ban / unban API (exported as banAccount / unbanAccount)
-- NOTE: not "banPlayer"/"unbanPlayer" - those are built-in MTA functions and
-- cannot be re-exported under the same name.
--------------------------------------------------------------------------------

function banAccount(accountName, reason, adminName)
    if type(accountName) ~= "string" or accountName == "" then
        return false, L.msg("v_accounts.server.invalid_account_name")
    end
    if not banDbReady() then
        return false, L.msg("v_accounts.server.ban_database_unavailable")
    end

    local canonical = accountNameExists(accountName)
    if not canonical then
        return false, L.msg("v_accounts.server.account_not_found", { account_name = accountName })
    end
    accountName = canonical

    reason    = (type(reason) == "string"    and reason    ~= "") and reason    or L.msg("v_accounts.server.no_reason_given")
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local target = playerOnAccount(accountName)
    local serial = isElement(target) and getPlayerSerial(target) or nil
    local ip     = isElement(target) and getPlayerIP(target) or nil
    local now    = getRealTime().timestamp

    -- Re-banning an already banned account updates its active row.
    local existing = exports.v_mysql:mysqlQuerySync(
        "SELECT id, serial FROM `" .. BAN_TABLE .. "` WHERE account_name = ? AND lifted_at = 0 ORDER BY id DESC LIMIT 1",
        accountName)
    if existing == false then
        return false, L.msg("v_accounts.server.ban_database_unavailable")
    end

    local id
    if existing[1] then
        id = tonumber(existing[1].id)
        serial = serial or nonEmpty(existing[1].serial)
        if not exports.v_mysql:mysqlExec(
            "UPDATE `" .. BAN_TABLE .. "` SET serial = ?, ip = COALESCE(?, ip), reason = ?, admin = ?, created_at = ? WHERE id = ?",
            serial, ip, reason, adminName, now, id) then
            return false, L.msg("v_accounts.server.ban_database_unavailable")
        end
    else
        id = exports.v_mysql:mysqlInsert(
            "INSERT INTO `" .. BAN_TABLE .. "` (account_name, serial, ip, reason, admin, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            accountName, serial, ip, reason, adminName, now)
        if type(id) ~= "number" then
            return false, L.msg("v_accounts.server.ban_database_unavailable")
        end
    end

    local ban = { id = id, account = accountName, serial = serial, date = dateString(now), admin = adminName, reason = reason }
    for i = #activeBans, 1, -1 do
        if activeBans[i].id == id then table.remove(activeBans, i) end
    end
    activeBans[#activeBans + 1] = ban

    if isElement(target) then
        applyBanState(target, ban)
        triggerClientEvent(target, "acc:setPanel", target, "banned")
    end

    outputServerLog(("[v_accounts] %s banned account '%s' (%s)"):format(adminName, accountName, reason))
    return true
end

function unbanAccount(accountName, adminName)
    if type(accountName) ~= "string" or accountName == "" then
        return false, L.msg("v_accounts.server.invalid_account_name")
    end
    if not banDbReady() then
        return false, L.msg("v_accounts.server.ban_database_unavailable")
    end

    local canonical = accountNameExists(accountName)
    if canonical then accountName = canonical end
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local rows = exports.v_mysql:mysqlQuerySync(
        "SELECT id FROM `" .. BAN_TABLE .. "` WHERE account_name = ? AND lifted_at = 0", accountName)
    if rows == false then
        return false, L.msg("v_accounts.server.ban_database_unavailable")
    end
    if not rows[1] then
        return false, L.msg("v_accounts.server.no_active_ban_for_account", { account_name = accountName })
    end

    if not exports.v_mysql:mysqlExec(
        "UPDATE `" .. BAN_TABLE .. "` SET lifted_at = ?, lifted_by = ? WHERE account_name = ? AND lifted_at = 0",
        getRealTime().timestamp, adminName, accountName) then
        return false, L.msg("v_accounts.server.ban_database_unavailable")
    end

    local needle = accountName:lower()
    for i = #activeBans, 1, -1 do
        local acc = activeBans[i].account
        if acc and acc:lower() == needle then table.remove(activeBans, i) end
    end

    -- Lift the panel for anyone held by this ban (by account, or by the serial
    -- it carried) unless another active ban still matches them.
    syncBanStates()

    outputServerLog(("[v_accounts] %s unbanned account '%s'"):format(adminName, accountName))
    return true
end

--------------------------------------------------------------------------------
-- Exports for other resources (identity lookups)
--------------------------------------------------------------------------------

-- The logged-in account name of a player, or false.
function getName(player)
    return nameOf(player) or false
end

function isLoggedIn(player)
    return nameOf(player) ~= nil
end

-- Credential check without a player, for logins over HTTP (web consoles such as med_erm's
-- web tablet). Verifies the bcrypt password and the account ban, but does NOT log anyone
-- in on the server. Returns true, <canonical account name> | false, <english error>.
-- Failed attempts are throttled per account (the caller should throttle per client too).
local httpFails = {}   -- [lower account name] = { timestamps }
local HTTP_MAX_FAILS, HTTP_FAIL_WINDOW = 5, 60

function httpLogin(username, password)
    if type(username) ~= "string" or type(password) ~= "string"
    or username == "" or password == "" or #username > 64 or #password > 128 then
        return false, "Username or password missing."
    end

    local key, t, keep = username:lower(), getRealTime().timestamp, {}
    for _, ts in ipairs(httpFails[key] or {}) do
        if t - ts < HTTP_FAIL_WINDOW then keep[#keep + 1] = ts end
    end
    httpFails[key] = keep
    if #keep >= HTTP_MAX_FAILS then return false, "Too many failed attempts. Try again in a minute." end

    local canonical = accountNameExists(username)
    local auth = canonical and fetchAccountAuth(canonical) or nil
    if not auth or type(auth.password) ~= "string" or not passwordVerify(password, auth.password) then
        keep[#keep + 1] = t
        return false, "Wrong username or password."
    end
    if getActiveBan(nil, canonical) then return false, "This account is banned." end

    httpFails[key] = nil
    return true, canonical
end

--------------------------------------------------------------------------------
-- Panel routing
--------------------------------------------------------------------------------

-- Weekly updates shown next to the login/register panels (v_weekly is optional:
-- no include, it is only queried while running).
local function sendWeekly(player)
    local res = getResourceFromName("v_weekly")
    if not (res and getResourceState(res) == "running") then return end
    local ok, info = pcall(function() return exports.v_weekly:getWeeklyInfo(0) end)
    if ok and type(info) == "table" then
        triggerClientEvent(player, "acc:weekly", player, info)
    end
end

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "v_weekly" then return end
    for _, p in ipairs(getElementsByType("player")) do
        if not nameOf(p) and getElementData(p, "banned") ~= true then sendWeekly(p) end
    end
end)

addEvent("acc:requestPanel", true)
addEventHandler("acc:requestPanel", root, function()
    local player = client
    if not isElement(player) then return end

    if getElementData(player, "banned") == true then
        triggerClientEvent(player, "acc:setPanel", player, "banned")
    elseif nameOf(player) then
        triggerClientEvent(player, "acc:setPanel", player, nil)
    else
        triggerClientEvent(player, "acc:setPanel", player, "login")
        sendWeekly(player)
    end
end)

--------------------------------------------------------------------------------
-- Login / register flow
--------------------------------------------------------------------------------

-- Renames a player without the onPlayerChangeNick guard blocking it.
local function setAccountName(player, name)
    scriptedRename[player] = true
    setPlayerName(player, name)
    scriptedRename[player] = nil
end

addEvent("v_mapcam:onFinish", true)
local spawnPending = {} -- [player] = true while the spawn camera of the login runs
addEvent("acc:clientWorldLoaded", true)
-- Restores the player's saved state and drops the black loading screen.
addEventHandler("acc:clientWorldLoaded", root, function()
    -- client az a játékos, aki küldte az eseményt
    local player = client 
    if not isElement(player) then return end
    -- only once per login: a repeated event must not replay the spawn / onPlayerLoaded
    if getElementData(player, "isLogged") ~= true or getElementData(player, "loaded") == true then return end
    if spawnPending[player] then return end
    spawnPending[player] = true

    -- Itt fut le a spawn animáció és a betöltőképernyő levétele
    triggerClientEvent(player, "acc:loadingScreen", player, false)
    triggerClientEvent(player, "acc:setPanel", player, nil)

    exports.v_mapcam:playSpawn(player)

    -- Ezt levesszük a root-ról, és közvetlenül a playerhez kötjük, ahogy az eredetiben is volt
    -- one-shot: the handler must not stay on the player, else every later
    -- v_mapcam teleport would fire onPlayerLoaded again
    local function onFinish()
        removeEventHandler("v_mapcam:onFinish", player, onFinish)
        spawnPending[player] = nil
        if not isElement(player) then return end

        setElementData(player, "loaded", true)
        local accName = getElementData(player, "accName")
        
        triggerEvent("onPlayerLoaded", player, accName)
        triggerClientEvent(player, "acc:playerLoaded", player, accName)
    end
    addEventHandler("v_mapcam:onFinish", player, onFinish)
end)

local function spawnLoggedInPlayer(player)
    loadPosition(player)
    loadHealth(player)
    loadArmor(player)
    loadMoney(player)
    loadStats(player)
    loadWeapons(player)

    exports.v_mapcam:preSpawn(player)

    -- A fix Timer HELYETT értesítjük a klienst, hogy kezdje el ellenőrizni a világot
    triggerClientEvent(player, "acc:startWorldCheck", player)
end

-- keepCache: the login already loaded the row fresh (acc:loginData) - keep that cache
local function markLoggedIn(player, username, accId, keepCache)
    -- always start a session from the DB, not a copy cached on this server earlier
    -- (the other server may have changed the account since)
    if not keepCache then exports.v_mysql:flushAccData(username) end
    setElementData(player, "accName", username)
    setElementData(player, "accID", accId or 0)
    setElementData(player, "isLogged", true)
    setAccountName(player, username)
end

--------------------------------------------------------------------------------
-- Login throttle
--------------------------------------------------------------------------------
-- Failed logins are counted per serial and per IP. Too many inside the window
-- locks that key out; every further lockout doubles, up to LOGIN_LOCK_MAX.
-- One player can also have only one attempt in flight, at most one per
-- LOGIN_MIN_INTERVAL.

local LOGIN_MIN_INTERVAL = 1000     -- ms between two attempts of one player
local LOGIN_FAIL_WINDOW  = 60       -- s
local LOGIN_MAX_FAILS    = { serial = 5, ip = 15 } -- ip is higher: shared/NAT addresses
local LOGIN_LOCK         = 60       -- s, first lockout
local LOGIN_LOCK_MAX     = 15 * 60  -- s
local LOGIN_TIMEOUT      = 15000    -- ms, give up on a lost DB answer
local REGISTER_MIN_INTERVAL = 3000  -- ms between two registration attempts of one player

local loginFails   = {} -- ["serial:..." | "ip:..."] = { times = {}, lockUntil = ts, locks = n }
local lastAttempt  = {} -- [player] = tick
local loginPending = {} -- [player] = { id, username, password, timer }
local pendingById  = {} -- [id] = player
local loginSeq     = 0

local function nowSec() return getRealTime().timestamp end

local function throttleKeys(player)
    return { serial = "serial:" .. tostring(getPlayerSerial(player)), ip = "ip:" .. tostring(getPlayerIP(player)) }
end

-- seconds until the player may try again (0 = now)
local function lockRemaining(player)
    local t, wait = nowSec(), 0
    for _, key in pairs(throttleKeys(player)) do
        local f = loginFails[key]
        if f and f.lockUntil and f.lockUntil > t then wait = math.max(wait, f.lockUntil - t) end
    end
    return wait
end

local function recordLoginFail(player)
    local t = nowSec()
    for kind, key in pairs(throttleKeys(player)) do
        local f = loginFails[key] or { times = {}, locks = 0 }
        loginFails[key] = f
        local keep = {}
        for _, ts in ipairs(f.times) do
            if t - ts < LOGIN_FAIL_WINDOW then keep[#keep + 1] = ts end
        end
        keep[#keep + 1] = t
        f.times = keep
        if #keep >= LOGIN_MAX_FAILS[kind] then
            f.locks = f.locks + 1
            f.lockUntil = t + math.min(LOGIN_LOCK * 2 ^ (f.locks - 1), LOGIN_LOCK_MAX)
            f.times = {}
            outputServerLog(("[v_accounts] login locked for %s (%d s)"):format(key, f.lockUntil - t))
        end
    end
end

local function clearLoginFails(player)
    loginFails[throttleKeys(player).serial] = nil
end

local function clearPending(player)
    local p = loginPending[player]
    if not p then return end
    loginPending[player] = nil
    pendingById[p.id] = nil
    if isTimer(p.timer) then killTimer(p.timer) end
end

-- forget old, unlocked entries now and then
setTimer(function()
    local t = nowSec()
    for key, f in pairs(loginFails) do
        local last = f.times[#f.times] or 0
        if (not f.lockUntil or f.lockUntil <= t) and t - last > LOGIN_LOCK_MAX then loginFails[key] = nil end
    end
end, 10 * 60 * 1000, 0)

local function loginError(player, key, params)
    triggerClientEvent(player, "acc:error", player, L.msg(key, params))
end

-- "Remember me" token, saved by the client as "<account name>=<hash>". The hash
-- is sha256 of the stored bcrypt hash + the player's serial: it never contains
-- the password, it does not work from another machine, and a password change
-- invalidates it.
local function rememberHash(player, passwordHash)
    return hash("sha256", passwordHash .. "|" .. tostring(getPlayerSerial(player)))
end

-- Step 2: the account row arrived (server/db.lua fetchAccountAuthAsync).
addEvent("acc:loginRow")
addEventHandler("acc:loginRow", resourceRoot, function(id, rows)
    local player = pendingById[id]
    if not player then return end
    local pending = loginPending[player]
    if not isElement(player) or getElementData(player, "isLogged") == true then return clearPending(player) end

    local row = type(rows) == "table" and rows[1] or nil
    if not row or type(row.password) ~= "string" or type(row.account_name) ~= "string" then
        clearPending(player)
        if rows == false then return loginError(player, "v_accounts.server.database_query_error") end -- a DB error is not the player's fault
        recordLoginFail(player)
        if pending.tokenHash then
            triggerClientEvent(player, "acc:tokenInvalid", player)
            return loginError(player, "v_accounts.server.saved_login_expired")
        end
        return loginError(player, "v_accounts.server.wrong_username_or_password")
    end
    local canonical, accId = row.account_name, tonumber(row.id) or 0

    local function onVerified(matches)
        -- the pending login stays registered (until the data load answers, step 3)
        if loginPending[player] ~= pending then return end
        if not isElement(player) or getElementData(player, "isLogged") == true then return clearPending(player) end
        pending.password = nil
        if not matches then
            clearPending(player)
            recordLoginFail(player)
            if pending.tokenHash then
                triggerClientEvent(player, "acc:tokenInvalid", player)
                return loginError(player, "v_accounts.server.saved_login_expired")
            end
            return loginError(player, "v_accounts.server.wrong_username_or_password")
        end
        clearLoginFails(player)
        rememberAccountName(canonical)

        if pending.remember then
            triggerClientEvent(player, "acc:rememberToken", player, canonical .. "=" .. rememberHash(player, row.password))
        end

        if isElement(playerOnAccount(canonical)) then
            clearPending(player)
            return loginError(player, "v_accounts.server.this_account_is_already_in_use")
        end

        local ban = getActiveBan(getPlayerSerial(player), canonical)
        if ban then
            clearPending(player)
            applyBanState(player, ban)
            triggerClientEvent(player, "acc:setPanel", player, "banned")
            return loginError(player, "v_accounts.server.this_account_is_banned")
        end

        -- Step 3: read the account data BEFORE the player counts as logged in. If it
        -- cannot be read the login is refused: a login on empty data would restart
        -- the intro and the autosave would overwrite the real data with defaults.
        pending.canonical, pending.accId = canonical, accId
        pending.dataTries = 0
        requestLoginData(player)
    end

    if pending.tokenHash then
        onVerified(rememberHash(player, row.password) == pending.tokenHash)
    else
        passwordVerify(pending.password, row.password, {}, onVerified)
    end
end)

local DATA_TRIES = 3

-- Step 3 (also the retry): fresh load of the account row into the v_mysql cache.
function requestLoginData(player)
    local p = loginPending[player]
    if not p then return end
    p.dataTries = (p.dataTries or 0) + 1
    p.timer = isTimer(p.timer) and p.timer or setTimer(function()
        if loginPending[player] and loginPending[player].id == p.id then
            exports.v_mysql:flushAccData(p.canonical)
            clearPending(player)
            if isElement(player) then loginError(player, "v_accounts.server.database_query_error") end
        end
    end, LOGIN_TIMEOUT, 1)
    local mysql = getResourceFromName("v_mysql")
    if not mysql or getResourceState(mysql) ~= "running"
    or not exports.v_mysql:loadAccDataAsync("acc:loginData", p.id, p.canonical) then
        -- no answer event is coming unless the DB is down, in which case it already came
        if loginPending[player] and loginPending[player].id == p.id and p.dataTries >= DATA_TRIES then
            clearPending(player)
            loginError(player, "v_accounts.server.database_query_error")
        end
    end
end

addEvent("acc:loginData")
addEventHandler("acc:loginData", resourceRoot, function(id, ok)
    local player = pendingById[id]
    if not player then
        return
    end
    local p = loginPending[player]
    if not p or not p.canonical then return end
    if not isElement(player) or getElementData(player, "isLogged") == true then
        exports.v_mysql:flushAccData(p.canonical)
        return clearPending(player)
    end
    if not ok then
        if p.dataTries < DATA_TRIES then
            return setTimer(requestLoginData, 1000, 1, player)
        end
        exports.v_mysql:flushAccData(p.canonical)
        clearPending(player)
        outputServerLog(("[v_accounts] login of '%s' refused: account data could not be loaded"):format(p.canonical))
        return loginError(player, "v_accounts.server.database_query_error")
    end
    local canonical, accId = p.canonical, p.accId
    clearPending(player)
    if isElement(playerOnAccount(canonical)) then
        exports.v_mysql:flushAccData(canonical)
        return loginError(player, "v_accounts.server.this_account_is_already_in_use")
    end

    markLoggedIn(player, canonical, accId, true)
    triggerClientEvent(player, "acc:setPanel", player, nil)
    triggerClientEvent(player, "acc:loadingScreen", player, true)
    beginLoading(player, {}, spawnLoggedInPlayer)
end)

-- Common gate of both step-1 entry points; true if the player may attempt now.
local function loginAllowed(player)
    if not isElement(player) then return false end
    if getElementData(player, "banned") == true then return false end
    if getElementData(player, "isLogged") == true then return false end
    if loginPending[player] then return false end

    local tick = getTickCount()
    if lastAttempt[player] and tick - lastAttempt[player] < LOGIN_MIN_INTERVAL then return false end
    lastAttempt[player] = tick

    local wait = lockRemaining(player)
    if wait > 0 then
        loginError(player, "v_accounts.server.too_many_login_attempts", { seconds = wait })
        return false
    end
    return true
end

-- Registers the pending login (password or tokenHash set) and fetches the row (step 2).
local function startLogin(player, username, pending)
    loginSeq = loginSeq + 1
    local id = loginSeq
    pending.id = id
    pending.timer = setTimer(function()
        local p = loginPending[player]
        if p and p.id == id then
            if p.canonical then exports.v_mysql:flushAccData(p.canonical) end
            clearPending(player)
        end
    end, LOGIN_TIMEOUT, 1)
    loginPending[player] = pending
    pendingById[id] = player

    if not fetchAccountAuthAsync(username, "acc:loginRow", id) then
        -- without a DB connection acc:loginRow may already have answered
        if loginPending[player] and loginPending[player].id == id then
            clearPending(player)
            loginError(player, "v_accounts.server.database_query_error")
        end
    end
end

-- Step 1: the client asks to log in with a password. remember: answer with a
-- remember-me token (acc:rememberToken) once the password is verified.
function login_player(username, password, remember)
    local player = client
    if not loginAllowed(player) then return end

    if type(username) ~= "string" or type(password) ~= "string"
    or username == "" or password == "" then
        return loginError(player, "v_accounts.server.username_or_password_missing")
    end
    if #username > 64 or #password > 128 then
        recordLoginFail(player)
        return loginError(player, "v_accounts.server.wrong_username_or_password")
    end

    startLogin(player, username, { password = password, remember = remember == true })
end
addEvent("login_player", true)
addEventHandler("login_player", root, login_player)

-- Step 1 (Continue as ...): the client logs in with its saved "<name>=<hash>" token.
addEvent("login_token", true)
addEventHandler("login_token", root, function(token)
    local player = client
    if not loginAllowed(player) then return end

    local username, tokenHash
    if type(token) == "string" and #token <= 160 then
        username, tokenHash = token:match("^([^=]+)=(%x+)$")
    end
    if not username or #username > 64 or #tokenHash ~= 64 then
        recordLoginFail(player)
        triggerClientEvent(player, "acc:tokenInvalid", player)
        return loginError(player, "v_accounts.server.saved_login_expired")
    end

    startLogin(player, username, { tokenHash = tokenHash:upper() })
end)

-- Registration runs without blocking the server (PERF-01):
--   1. register_player       name check (async query)
--   2. acc:registerName      bcrypt hash (async)
--   3. createAccountRowAsync insert; the UNIQUE account_name decides a name
--                            race, so no second check is needed
--   4. acc:registerRow       log in as the new account
local REGISTER_TIMEOUT = 15000 -- ms, give up on a lost DB answer
local registerPending = {} -- [player] = { id, username, password, timer } until step 4 or an error
local registerById    = {} -- [id] = player
local registerSeq     = 0

local function clearRegister(player)
    local p = registerPending[player]
    if not p then return end
    registerPending[player] = nil
    registerById[p.id] = nil
    if isTimer(p.timer) then killTimer(p.timer) end
end

local function registerError(player, key)
    clearRegister(player)
    if isElement(player) then
        triggerClientEvent(player, "acc:error", player, L.msg(key))
    end
end

-- the pending registration of a request id, if the player can still use it
local function registerOf(id)
    local player = registerById[id]
    if not player then return nil end
    local p = registerPending[player]
    if not p or p.id ~= id then return nil end
    if not isElement(player) or getElementData(player, "isLogged") == true then
        clearRegister(player)
        return nil
    end
    return player, p
end

local function finishRegister(player, username, id)
    clearRegister(player)
    markLoggedIn(player, username, id)
    triggerClientEvent(player, "acc:setPanel", player, nil)
    triggerClientEvent(player, "acc:loadingScreen", player, true)
    beginLoading(player, {}, function(p)
        -- server-only: a brand-new account (v_introduce ends its first introduction at the spawn)
        setElementData(p, "acc.registered", true, false)
        loadPosition(p)
        setElementData(p, "loaded", true)
        save_all(p)
        triggerClientEvent(p, "acc:loadingScreen", p, false)
        triggerClientEvent(p, "acc:setPanel", p, nil)
        triggerEvent("onPlayerLoaded", p, getElementData(p, "accName"))
        triggerClientEvent(p, "acc:playerLoaded", p, getElementData(p, "accName"))
    end)
end

-- Step 4: the row was inserted (or not).
addEvent("acc:registerRow")
addEventHandler("acc:registerRow", resourceRoot, function(id, newId, err)
    local player, p = registerOf(id)
    if not player then return end
    if type(newId) ~= "number" then
        if tostring(err):lower():find("duplicate", 1, true) then
            return registerError(player, "v_accounts.server.account_already_exists")
        end
        return registerError(player, "v_accounts.server.registration_failed")
    end
    accountRowCreated(p.username)
    finishRegister(player, p.username, newId)
end)

-- Step 2: the name check answered -> hash the password -> step 3.
addEvent("acc:registerName")
addEventHandler("acc:registerName", resourceRoot, function(id, rows)
    local player, p = registerOf(id)
    if not player then return end
    if type(rows) ~= "table" then
        return registerError(player, "v_accounts.server.registration_failed")
    end
    if rows[1] then
        rememberAccountName(rows[1].account_name)
        return registerError(player, "v_accounts.server.account_already_exists")
    end

    local password = p.password
    p.password = nil
    passwordHash(password, "bcrypt", {}, function(hash)
        if registerOf(id) ~= player then return end -- timed out, quit or logged in meanwhile
        if type(hash) ~= "string" then
            return registerError(player, "v_accounts.server.registration_failed")
        end
        if not createAccountRowAsync(p.username, hash, nil, "acc:registerRow", id) then
            -- No answer is coming (v_mysql stopped, or an older v_mysql without
            -- mysqlInsertAsync): the blocking insert. Without a database
            -- connection the answer already came and cleared the request.
            if registerOf(id) ~= player then return end
            local newId = createAccountRow(p.username, hash, nil)
            if not newId then
                return registerError(player, "v_accounts.server.registration_failed")
            end
            finishRegister(player, p.username, newId)
        end
    end)
end)

-- Step 1: the client asks to register.
function register_player(username, password)
    local player = client
    if not isElement(player) then return end
    if getElementData(player, "banned") == true then return end
    if getElementData(player, "isLogged") == true then return end
    if registerPending[player] or loginPending[player] then return end

    local tick = getTickCount()
    if lastAttempt[player] and tick - lastAttempt[player] < REGISTER_MIN_INTERVAL then return end
    lastAttempt[player] = tick

    if type(username) ~= "string" or type(password) ~= "string" then return end
    if not username:find("^[%w_%-%.]+$") or #username < 3 or #username > 30 then
        triggerClientEvent(player, "acc:error", player, L.msg("v_accounts.server.username_must_be_3_30_chars"))
        return
    end
    if #password > 128 then return end
    if #password < 5 then
        triggerClientEvent(player, "acc:error", player, L.msg("v_accounts.register.password_too_short"))
        return
    end
    if knownAccountName(username) then
        triggerClientEvent(player, "acc:error", player, L.msg("v_accounts.server.account_already_exists"))
        return
    end

    registerSeq = registerSeq + 1
    local id = registerSeq
    registerPending[player] = {
        id = id, username = username, password = password,
        timer = setTimer(function()
            if registerOf(id) == player then
                registerError(player, "v_accounts.server.registration_failed")
            end
        end, REGISTER_TIMEOUT, 1),
    }
    registerById[id] = player

    if not fetchAccountNameAsync(username, "acc:registerName", id) then
        -- without a DB connection acc:registerName may already have answered
        if registerOf(id) == player then
            registerError(player, "v_accounts.server.registration_failed")
        end
    end
end
addEvent("register_player", true)
addEventHandler("register_player", root, register_player)

--------------------------------------------------------------------------------
-- Saving
--------------------------------------------------------------------------------

setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, "isLogged") == true then
            save_all(player)
        end
    end
end, SAVE_INTERVAL, 0)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, "isLogged") == true then
            local veh = getPedOccupiedVehicle(player)
            if veh then
                removePedFromVehicle(player)
                setElementVelocity(veh, 0, 0, 0)
                local x, y, z = getElementPosition(player)
                setElementPosition(player, x, y, z + 2)
            end
            save_all(player)
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    if getElementData(source, "isLogged") == true then
        save_all(source)
    end
    scriptedRename[source] = nil
    spawnPending[source] = nil
    local pendingLogin = loginPending[source]
    if pendingLogin and pendingLogin.canonical and getElementData(source, "isLogged") ~= true then
        exports.v_mysql:flushAccData(pendingLogin.canonical) -- data was loaded for a login that never finished
    end
    clearPending(source)
    lastAttempt[source] = nil
    clearRegister(source)
end)

-- Block manual nick changes, but let the script's own renames through.
addEventHandler("onPlayerChangeNick", root, function()
    if scriptedRename[source] then return end
    cancelEvent()
end)
