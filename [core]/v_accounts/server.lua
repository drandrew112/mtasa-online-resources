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
        return false, "Invalid account name"
    end

    local canonical = accountNameExists(accountName)
    if not canonical then
        return false, "Account not found: " .. accountName
    end
    accountName = canonical

    reason    = (type(reason) == "string"    and reason    ~= "") and reason    or "No reason given"
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local target = playerOnAccount(accountName)
    local serial = isElement(target) and getPlayerSerial(target) or nil

    local xml = loadBansXml(true)
    if not xml then return false, "Could not open the ban file" end

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
        return false, "Invalid account name"
    end

    local canonical = accountNameExists(accountName)
    if canonical then accountName = canonical end

    local xml = xmlLoadFile(BANS_FILE)
    if not xml then return false, "No bans on record" end

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
        return false, "No active ban for account: " .. accountName
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

-- Restores the player's saved state and drops the black loading screen.
local function spawnLoggedInPlayer(player)
    loadPosition(player)
    loadHealth(player)
    loadArmor(player)
    loadMoney(player)
    loadStats(player)
    loadWeapons(player)

    triggerClientEvent(player, "acc:loadingScreen", player, false)
    triggerClientEvent(player, "acc:setPanel", player, nil)

    -- The player is fully loaded. Other resources hook this (arg 1 = account
    -- name string) instead of the old onPlayerLogin.
    triggerEvent("onPlayerLoaded", player, getElementData(player, "accName"))
end

local function markLoggedIn(player, username, accId)
    setElementData(player, "accName", username)
    setElementData(player, "accID", accId or 0)
    setElementData(player, "isLogged", true)
    setAccountName(player, username)
end

function login_player(username, password)
    local player = client
    if not isElement(player) then return end
    if getElementData(player, "banned") == true then return end
    if getElementData(player, "isLogged") == true then return end

    if type(username) ~= "string" or type(password) ~= "string"
    or username == "" or password == "" then
        triggerClientEvent(player, "acc:error", player, "Username or password missing")
        return
    end

    local canonical = accountNameExists(username)
    local auth = canonical and fetchAccountAuth(canonical) or nil
    if not auth or type(auth.password) ~= "string" then
        triggerClientEvent(player, "acc:error", player, "Wrong username or password")
        return
    end

    passwordVerify(password, auth.password, {}, function(matches)
        if not isElement(player) or getElementData(player, "isLogged") == true then return end
        if not matches then
            triggerClientEvent(player, "acc:error", player, "Wrong username or password")
            return
        end

        if isElement(playerOnAccount(canonical)) then
            triggerClientEvent(player, "acc:error", player, "This account is already in use")
            return
        end

        local ban = getActiveBan(getPlayerSerial(player), canonical)
        if ban then
            applyBanState(player, ban)
            triggerClientEvent(player, "acc:setPanel", player, "banned")
            triggerClientEvent(player, "acc:error", player, "This account is banned")
            return
        end

        markLoggedIn(player, canonical, auth.id)
        triggerClientEvent(player, "acc:setPanel", player, nil)
        triggerClientEvent(player, "acc:loadingScreen", player, true)
        beginLoading(player, {}, spawnLoggedInPlayer)
    end)
end
addEvent("login_player", true)
addEventHandler("login_player", root, login_player)

function register_player(username, password)
    local player = client
    if not isElement(player) then return end
    if getElementData(player, "banned") == true then return end
    if getElementData(player, "isLogged") == true then return end

    if type(username) ~= "string" or type(password) ~= "string" then return end
    if not username:find("^[%w_%-%.]+$") or #username < 3 or #username > 30 then
        triggerClientEvent(player, "acc:error", player, "Username must be 3-30 chars (letters, digits, _ - .)")
        return
    end
    if #password < 5 then
        triggerClientEvent(player, "acc:error", player, "Password too short")
        return
    end
    if accountNameExists(username) then
        triggerClientEvent(player, "acc:error", player, "Account already exists")
        return
    end

    passwordHash(password, "bcrypt", {}, function(hash)
        if not isElement(player) or getElementData(player, "isLogged") == true then return end
        if type(hash) ~= "string" then
            triggerClientEvent(player, "acc:error", player, "Registration failed")
            return
        end
        if accountNameExists(username) then
            triggerClientEvent(player, "acc:error", player, "Account already exists")
            return
        end

        local id = createAccountRow(username, hash, nil)
        if not id then
            triggerClientEvent(player, "acc:error", player, "Registration failed")
            return
        end

        markLoggedIn(player, username, id)
        triggerClientEvent(player, "acc:setPanel", player, nil)
        triggerClientEvent(player, "acc:loadingScreen", player, true)
        beginLoading(player, {}, function(p)
            loadPosition(p)
            save_all(p)
            triggerClientEvent(p, "acc:loadingScreen", p, false)
            triggerClientEvent(p, "acc:setPanel", p, nil)
            triggerEvent("onPlayerLoaded", p, getElementData(p, "accName"))
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
end)

-- Block manual nick changes, but let the script's own renames through.
addEventHandler("onPlayerChangeNick", root, function()
    if scriptedRename[source] then return end
    cancelEvent()
end)
