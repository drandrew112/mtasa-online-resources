if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Identity: who is logged into which account, and the identity exports.
--
-- The mod does NOT use MTA's built-in account system. An "account" is a row in
-- the shared `accounts` table (server/db.lua + [core]/v_mysql). A logged-in
-- player is identified by element data set here: accName, accID, isLogged.
-- Every other resource reads/writes their data through
-- exports.v_mysql:getAccData / setAccData.

addEvent("onPlayerAccountLogin") -- (accountName, isNewAccount), source = player; fired by login.lua / register.lua

-- Players currently being renamed by the script on purpose, so the
-- onPlayerChangeNick handler can allow those while still blocking manual ones.
local scriptedRename = {}

function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- The logged-in account name for a player, or nil.
function nameOf(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return nil end
    local n = getElementData(player, "accName")
    return (type(n) == "string" and n ~= "") and n or nil
end

-- The online player logged into `accountName`, or nil.
function playerOnAccount(accountName)
    if type(accountName) ~= "string" then return nil end
    local needle = accountName:lower()
    for _, player in ipairs(getElementsByType("player")) do
        local n = nameOf(player)
        if n and n:lower() == needle then return player end
    end
    return nil
end

-- active ban of a serial / account (acc_bans), or false
function activeBan(serial, accountName)
    if not resourceRunning("acc_bans") then return false end
    return exports.acc_bans:getActiveBan(serial, accountName)
end

-- Renames a player without the onPlayerChangeNick guard blocking it.
local function setAccountName(player, name)
    scriptedRename[player] = true
    setPlayerName(player, name)
    scriptedRename[player] = nil
end

-- Marks the player logged in and announces it (onPlayerAccountLogin).
-- keepCache: the login already loaded the row fresh - keep that v_mysql cache.
function markLoggedIn(player, username, accId, isNew, keepCache)
    -- always start a session from the DB, not a copy cached on this server earlier
    -- (the other server may have changed the account since)
    if not keepCache then exports.v_mysql:flushAccData(username) end
    setElementData(player, "accName", username)
    setElementData(player, "accID", accId or 0)
    setElementData(player, "isLogged", true)
    setAccountName(player, username)
    if isNew then
        -- server-only: a brand-new account (v_introduce ends its first introduction at the spawn)
        setElementData(player, "acc.registered", true, false)
    end
    -- last login (v_admin Accounts page)
    exports.v_mysql:setAccData(player, {
        last_login  = getRealTime().timestamp,
        last_serial = getPlayerSerial(player),
        last_ip     = getPlayerIP(player),
    })
    triggerClientEvent(player, "acc_auth:onClientLoggedIn", player, username, isNew == true)
    triggerEvent("onPlayerAccountLogin", player, username, isNew == true)
end

function authError(player, key, params)
    if isElement(player) then
        triggerClientEvent(player, "acc_auth:onClientAuthError", player, L.msg(key, params))
    end
end

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

-- The logged-in account name of a player, or false.
function getName(player)
    return nameOf(player) or false
end

function isLoggedIn(player)
    return nameOf(player) ~= nil
end

-- accountNameExists / getAllAccountNames: server/db.lua

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
    if activeBan(nil, canonical) then return false, "This account is banned." end

    httpFails[key] = nil
    return true, canonical
end

--------------------------------------------------------------------------------

-- Block manual nick changes, but let the script's own renames through.
addEventHandler("onPlayerChangeNick", root, function()
    if scriptedRename[source] then return end
    cancelEvent()
end)

addEventHandler("onPlayerQuit", root, function()
    scriptedRename[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    ensureEmailIndex()
end)
