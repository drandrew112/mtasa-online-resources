if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Login (password or remember-me token), without blocking the server (PERF-01):
--   1. acc_auth:login / acc_auth:loginToken   throttle, row fetch (async)
--   2. acc_auth:loginRow                      bcrypt / token check, ban check
--   3. acc_auth:loginData                     fresh account data load into the v_mysql cache
--   then markLoggedIn() -> onPlayerAccountLogin (acc_savesys opens the account menu)

--------------------------------------------------------------------------------
-- Login throttle
--------------------------------------------------------------------------------
-- Failed logins are counted per serial and per IP. Too many inside the window
-- locks that key out; every further lockout doubles, up to LOGIN_LOCK_MAX.
-- One player can also have only one attempt in flight, at most one per
-- LOGIN_MIN_INTERVAL. Wrong reset codes and wrong passwords at an email change
-- count here as well (recordLoginFail is global).

local loginFails   = {} -- ["serial:..." | "ip:..."] = { times = {}, lockUntil = ts, locks = n }
lastAttempt        = {} -- [player] = tick (shared with register.lua)
loginPending       = {} -- [player] = { id, username, password | tokenHash, timer, ... }
local pendingById  = {} -- [id] = player
local loginSeq     = 0

local function nowSec() return getRealTime().timestamp end

local function throttleKeys(player)
    return { serial = "serial:" .. tostring(getPlayerSerial(player)), ip = "ip:" .. tostring(getPlayerIP(player)) }
end

-- seconds until the player may try again (0 = now)
function lockRemaining(player)
    local t, wait = nowSec(), 0
    for _, key in pairs(throttleKeys(player)) do
        local f = loginFails[key]
        if f and f.lockUntil and f.lockUntil > t then wait = math.max(wait, f.lockUntil - t) end
    end
    return wait
end

function recordLoginFail(player)
    local t = nowSec()
    for kind, key in pairs(throttleKeys(player)) do
        local f = loginFails[key] or { times = {}, locks = 0 }
        loginFails[key] = f
        local keep = {}
        for _, ts in ipairs(f.times) do
            if t - ts < AUTH.LOGIN_FAIL_WINDOW then keep[#keep + 1] = ts end
        end
        keep[#keep + 1] = t
        f.times = keep
        if #keep >= AUTH.LOGIN_MAX_FAILS[kind] then
            f.locks = f.locks + 1
            f.lockUntil = t + math.min(AUTH.LOGIN_LOCK * 2 ^ (f.locks - 1), AUTH.LOGIN_LOCK_MAX)
            f.times = {}
            outputServerLog(("[acc_auth] login locked for %s (%d s)"):format(key, f.lockUntil - t))
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
        if (not f.lockUntil or f.lockUntil <= t) and t - last > AUTH.LOGIN_LOCK_MAX then loginFails[key] = nil end
    end
end, 10 * 60 * 1000, 0)

-- "Remember me" token, saved by the client as "<account name>=<hash>". The hash
-- is sha256 of the stored bcrypt hash + the player's serial: it never contains
-- the password, it does not work from another machine, and a password change
-- invalidates it.
local function rememberHash(player, passwordHash)
    return hash("sha256", passwordHash .. "|" .. tostring(getPlayerSerial(player))):lower()
end

local function tokenRefused(player)
    triggerClientEvent(player, "acc_auth:onClientTokenInvalid", player)
    authError(player, "acc_auth.server.saved_login_expired")
end

-- Step 2: the account row arrived (server/db.lua fetchAccountAuthAsync).
addEvent("acc_auth:loginRow")
addEventHandler("acc_auth:loginRow", resourceRoot, function(id, rows)
    local player = pendingById[id]
    if not player then return end
    local pending = loginPending[player]
    if not isElement(player) or getElementData(player, "isLogged") == true then return clearPending(player) end

    local row = type(rows) == "table" and rows[1] or nil
    if not row or type(row.password) ~= "string" or type(row.account_name) ~= "string" then
        clearPending(player)
        if rows == false then return authError(player, "acc_auth.server.database_query_error") end -- a DB error is not the player's fault
        recordLoginFail(player)
        if pending.tokenHash then return tokenRefused(player) end
        return authError(player, "acc_auth.server.wrong_username_or_password")
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
            if pending.tokenHash then return tokenRefused(player) end
            return authError(player, "acc_auth.server.wrong_username_or_password")
        end
        clearLoginFails(player)
        rememberAccountName(canonical)

        if pending.remember then
            triggerClientEvent(player, "acc_auth:rememberToken", player, canonical .. "=" .. rememberHash(player, row.password))
        end

        if isElement(playerOnAccount(canonical)) then
            clearPending(player)
            return authError(player, "acc_auth.server.this_account_is_already_in_use")
        end

        local ban = activeBan(getPlayerSerial(player), canonical)
        if ban then
            clearPending(player)
            exports.acc_bans:applyBan(player, ban)
            return authError(player, "acc_auth.server.this_account_is_banned")
        end

        -- Online on another server instance (MySQL online_players, server/online.lua)?
        onlineElsewhere(canonical, function(other)
            if loginPending[player] ~= pending then return end
            if not isElement(player) or getElementData(player, "isLogged") == true then return clearPending(player) end
            if other then
                clearPending(player)
                outputServerLog(("[acc_auth] login of '%s' refused: online on server #%d"):format(canonical, other.server))
                return authError(player, "acc_auth.server.account_online_on_other_server",
                    { server = other.serverName or ("#" .. other.server) })
            end

            -- Step 3: read the account data BEFORE the player counts as logged in. If it
            -- cannot be read the login is refused: a login on empty data would restart
            -- the intro and the autosave would overwrite the real data with defaults.
            pending.canonical, pending.accId = canonical, accId
            pending.dataTries = 0
            requestLoginData(player)
        end)
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
            authError(player, "acc_auth.server.database_query_error")
        end
    end, AUTH.LOGIN_TIMEOUT, 1)
    if not resourceRunning("v_mysql")
    or not exports.v_mysql:loadAccDataAsync("acc_auth:loginData", p.id, p.canonical) then
        -- no answer event is coming unless the DB is down, in which case it already came
        if loginPending[player] and loginPending[player].id == p.id and p.dataTries >= DATA_TRIES then
            clearPending(player)
            authError(player, "acc_auth.server.database_query_error")
        end
    end
end

addEvent("acc_auth:loginData")
addEventHandler("acc_auth:loginData", resourceRoot, function(id, ok)
    local player = pendingById[id]
    if not player then return end
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
        outputServerLog(("[acc_auth] login of '%s' refused: account data could not be loaded"):format(p.canonical))
        return authError(player, "acc_auth.server.database_query_error")
    end
    local canonical, accId = p.canonical, p.accId
    clearPending(player)
    if isElement(playerOnAccount(canonical)) then
        exports.v_mysql:flushAccData(canonical)
        return authError(player, "acc_auth.server.this_account_is_already_in_use")
    end

    markLoggedIn(player, canonical, accId, false, true)
end)

-- Common gate of both step-1 entry points; true if the player may attempt now.
local function loginAllowed(player)
    if not isElement(player) then return false end
    if getElementData(player, "banned") == true then return false end
    if getElementData(player, "isLogged") == true then return false end
    if loginPending[player] then return false end

    local tick = getTickCount()
    if lastAttempt[player] and tick - lastAttempt[player] < AUTH.LOGIN_MIN_INTERVAL then return false end
    lastAttempt[player] = tick

    local wait = lockRemaining(player)
    if wait > 0 then
        authError(player, "acc_auth.server.too_many_login_attempts", { seconds = wait })
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
    end, AUTH.LOGIN_TIMEOUT, 1)
    loginPending[player] = pending
    pendingById[id] = player

    if not fetchAccountAuthAsync(username, "acc_auth:loginRow", id) then
        -- without a DB connection acc_auth:loginRow may already have answered
        if loginPending[player] and loginPending[player].id == id then
            clearPending(player)
            authError(player, "acc_auth.server.database_query_error")
        end
    end
end

-- Step 1: the client asks to log in with a password. remember: answer with a
-- remember-me token (acc_auth:rememberToken) once the password is verified.
addEvent("acc_auth:login", true)
addEventHandler("acc_auth:login", root, function(username, password, remember)
    local player = client
    if not loginAllowed(player) then return end

    if type(username) ~= "string" or type(password) ~= "string"
    or username == "" or password == "" then
        return authError(player, "acc_auth.server.username_or_password_missing")
    end
    if #username > 64 or #password > 128 then
        recordLoginFail(player)
        return authError(player, "acc_auth.server.wrong_username_or_password")
    end

    startLogin(player, username, { password = password, remember = remember == true })
end)

-- Step 1 (Continue as ...): the client logs in with its saved "<name>=<hash>" token.
addEvent("acc_auth:loginToken", true)
addEventHandler("acc_auth:loginToken", root, function(token)
    local player = client
    if not loginAllowed(player) then return end

    local username, tokenHash
    if type(token) == "string" and #token <= 160 then
        username, tokenHash = token:match("^([^=]+)=(%x+)$")
    end
    if not username or #username > 64 or #tokenHash ~= 64 then
        recordLoginFail(player)
        return tokenRefused(player)
    end

    startLogin(player, username, { tokenHash = tokenHash:lower() })
end)

addEventHandler("onPlayerQuit", root, function()
    local pendingLogin = loginPending[source]
    if pendingLogin and pendingLogin.canonical and getElementData(source, "isLogged") ~= true then
        exports.v_mysql:flushAccData(pendingLogin.canonical) -- data was loaded for a login that never finished
    end
    clearPending(source)
    lastAttempt[source] = nil
end)
