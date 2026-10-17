if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Account System - server side
--
-- The mod does NOT use MTA's built-in account system. An "account" is a row in
-- the shared `accounts` table (see server/db.lua + [core]/v_mysql). A logged-in
-- player is identified by the "accName" element data set here; every other
-- resource reads/writes their data through exports.v_mysql:getAccData /
-- setAccData. Passwords are bcrypt hashes (passwordHash / passwordVerify).

local SAVE_INTERVAL = 120000 -- periodic autosave interval, in ms
local BANS_FILE = "bans.xml"

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

-- Bans are keyed by ACCOUNT NAME. When the banned player is online at ban time
-- their SERIAL is stored too, so a fresh account on the same machine is caught
-- on join as well. There are no temporary bans: "felold" is "Never" while
-- active and "1" once lifted.

local function currentDateString()
    local t = getRealTime()
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

local function loadBansXml(createIfMissing)
    local xml = xmlLoadFile(BANS_FILE)
    if not xml and createIfMissing then
        xml = xmlCreateFile(BANS_FILE, "bans")
    end
    return xml
end

-- {date, admin, reason, account} for the active ban matching this serial or
-- account name, or nil when neither is banned.
local function getActiveBan(serial, accountName)
    local xml = xmlLoadFile(BANS_FILE)
    if not xml then return nil end

    local result
    for _, ban in ipairs(xmlNodeGetChildren(xml)) do
        if xmlNodeGetAttribute(ban, "felold") ~= "1" then
            local banSerial  = xmlNodeGetAttribute(ban, "serial")
            local banAccount = xmlNodeGetAttribute(ban, "account")
            if (serial and banSerial and banSerial == serial)
            or (accountName and banAccount and banAccount == accountName) then
                result = {
                    date    = xmlNodeGetAttribute(ban, "date")  or "n/a",
                    admin   = xmlNodeGetAttribute(ban, "admin") or "n/a",
                    reason  = xmlNodeGetAttribute(ban, "indok") or "n/a",
                    account = banAccount,
                }
                break
            end
        end
    end

    xmlUnloadFile(xml)
    return result
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

addEventHandler("onPlayerJoin", root, function()
    evaluateBan(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        evaluateBan(player)
    end
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

    local canonical = accountNameExists(accountName)
    if not canonical then
        return false, L.msg("v_accounts.server.account_not_found", { account_name = accountName })
    end
    accountName = canonical

    reason    = (type(reason) == "string"    and reason    ~= "") and reason    or L.msg("v_accounts.server.no_reason_given")
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local target = playerOnAccount(accountName)
    local serial = isElement(target) and getPlayerSerial(target) or nil

    local xml = loadBansXml(true)
    if not xml then return false, L.msg("v_accounts.server.could_not_open_ban_file") end

    local node
    for _, child in ipairs(xmlNodeGetChildren(xml)) do
        if xmlNodeGetAttribute(child, "account") == accountName
        and xmlNodeGetAttribute(child, "felold") ~= "1" then
            node = child
            break
        end
    end
    node = node or xmlCreateChild(xml, "ban")

    xmlNodeSetAttribute(node, "account", accountName)
    if serial then xmlNodeSetAttribute(node, "serial", serial) end
    xmlNodeSetAttribute(node, "admin", adminName)
    xmlNodeSetAttribute(node, "indok", reason)
    xmlNodeSetAttribute(node, "date", currentDateString())
    xmlNodeSetAttribute(node, "felold", "Never")

    xmlSaveFile(xml)
    xmlUnloadFile(xml)

    if isElement(target) then
        applyBanState(target, { date = currentDateString(), admin = adminName, reason = reason, account = accountName })
        triggerClientEvent(target, "acc:setPanel", target, "banned")
    end

    outputServerLog(("[v_accounts] %s banned account '%s' (%s)"):format(adminName, accountName, reason))
    return true
end

function unbanAccount(accountName)
    if type(accountName) ~= "string" or accountName == "" then
        return false, L.msg("v_accounts.server.invalid_account_name")
    end

    local canonical = accountNameExists(accountName)
    if canonical then accountName = canonical end

    local xml = xmlLoadFile(BANS_FILE)
    if not xml then return false, L.msg("v_accounts.server.no_bans_on_record") end

    local found = false
    for _, child in ipairs(xmlNodeGetChildren(xml)) do
        if xmlNodeGetAttribute(child, "account") == accountName
        and xmlNodeGetAttribute(child, "felold") ~= "1" then
            xmlNodeSetAttribute(child, "felold", "1")
            found = true
        end
    end
    if found then xmlSaveFile(xml) end
    xmlUnloadFile(xml)

    if not found then
        return false, L.msg("v_accounts.server.no_active_ban_for_account", { account_name = accountName })
    end

    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, "banned") == true
        and getElementData(player, "banned_account") == accountName then
            clearBanState(player)
        end
    end

    outputServerLog(("[v_accounts] account '%s' unbanned"):format(accountName))
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

local function markLoggedIn(player, username, accId)
    -- always start a session from the DB, not a copy cached on this server earlier
    -- (the other server may have changed the account since)
    exports.v_mysql:flushAccData(username)
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
        if rows ~= false then recordLoginFail(player) end -- a DB error is not the player's fault
        return loginError(player, "v_accounts.server.wrong_username_or_password")
    end
    local canonical, accId = row.account_name, tonumber(row.id) or 0

    passwordVerify(pending.password, row.password, {}, function(matches)
        clearPending(player)
        if not isElement(player) or getElementData(player, "isLogged") == true then return end
        if not matches then
            recordLoginFail(player)
            return loginError(player, "v_accounts.server.wrong_username_or_password")
        end
        clearLoginFails(player)

        if isElement(playerOnAccount(canonical)) then
            return loginError(player, "v_accounts.server.this_account_is_already_in_use")
        end

        local ban = getActiveBan(getPlayerSerial(player), canonical)
        if ban then
            applyBanState(player, ban)
            triggerClientEvent(player, "acc:setPanel", player, "banned")
            return loginError(player, "v_accounts.server.this_account_is_banned")
        end

        markLoggedIn(player, canonical, accId)
        triggerClientEvent(player, "acc:setPanel", player, nil)
        triggerClientEvent(player, "acc:loadingScreen", player, true)
        beginLoading(player, {}, spawnLoggedInPlayer)
    end)
end)

-- Step 1: the client asks to log in.
function login_player(username, password)
    local player = client
    if not isElement(player) then return end
    if getElementData(player, "banned") == true then return end
    if getElementData(player, "isLogged") == true then return end
    if loginPending[player] then return end

    local tick = getTickCount()
    if lastAttempt[player] and tick - lastAttempt[player] < LOGIN_MIN_INTERVAL then return end
    lastAttempt[player] = tick

    local wait = lockRemaining(player)
    if wait > 0 then
        return loginError(player, "v_accounts.server.too_many_login_attempts", { seconds = wait })
    end

    if type(username) ~= "string" or type(password) ~= "string"
    or username == "" or password == "" then
        return loginError(player, "v_accounts.server.username_or_password_missing")
    end
    if #username > 64 or #password > 128 then
        recordLoginFail(player)
        return loginError(player, "v_accounts.server.wrong_username_or_password")
    end

    loginSeq = loginSeq + 1
    local id = loginSeq
    loginPending[player] = {
        id = id, password = password,
        timer = setTimer(function()
            if loginPending[player] and loginPending[player].id == id then clearPending(player) end
        end, LOGIN_TIMEOUT, 1),
    }
    pendingById[id] = player

    if not fetchAccountAuthAsync(username, "acc:loginRow", id) then
        -- without a DB connection acc:loginRow may already have answered
        if loginPending[player] and loginPending[player].id == id then
            clearPending(player)
            loginError(player, "v_accounts.server.wrong_username_or_password")
        end
    end
end
addEvent("login_player", true)
addEventHandler("login_player", root, login_player)

local registerPending = {} -- [player] = true while the bcrypt hash is being made

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
    if accountNameExists(username) then
        triggerClientEvent(player, "acc:error", player, L.msg("v_accounts.server.account_already_exists"))
        return
    end

    registerPending[player] = true
    passwordHash(password, "bcrypt", {}, function(hash)
        registerPending[player] = nil
        if not isElement(player) or getElementData(player, "isLogged") == true then return end
        if type(hash) ~= "string" then
            triggerClientEvent(player, "acc:error", player, L.msg("v_accounts.server.registration_failed"))
            return
        end
        if accountNameExists(username) then
            triggerClientEvent(player, "acc:error", player, L.msg("v_accounts.server.account_already_exists"))
            return
        end

        local id = createAccountRow(username, hash, nil)
        if not id then
            triggerClientEvent(player, "acc:error", player, L.msg("v_accounts.server.registration_failed"))
            return
        end

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
    end)
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
    clearPending(source)
    lastAttempt[source] = nil
    registerPending[source] = nil
end)

-- Block manual nick changes, but let the script's own renames through.
addEventHandler("onPlayerChangeNick", root, function()
    if scriptedRename[source] then return end
    cancelEvent()
end)
