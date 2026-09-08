-- Account System - server side

local SAVE_INTERVAL = 120000 -- periodic autosave interval, in ms
local BANS_FILE = "bans.xml"

-- Players currently being logged out by this script. Used to break the
-- onPlayerLogout -> logOut() -> onPlayerLogout recursion.
local loggingOut = {}
-- Players currently being renamed by the script on purpose, so the
-- onPlayerChangeNick handler can allow those while still blocking manual ones.
local scriptedRename = {}

--------------------------------------------------------------------------------
-- Bans
--------------------------------------------------------------------------------

-- Bans are keyed by ACCOUNT NAME (you cannot join without an account). When the
-- banned player is online at ban time their SERIAL is stored too, so a fresh
-- account on the same machine is caught on join as well. There are no temporary
-- bans: "felold" is "Never" while active and "1" once lifted.

local function currentDateString()
    local t = getRealTime()
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

-- Loads bans.xml, creating it if it does not exist yet.
local function loadBansXml(createIfMissing)
    local xml = xmlLoadFile(BANS_FILE)
    if not xml and createIfMissing then
        xml = xmlCreateFile(BANS_FILE, "bans")
    end
    return xml
end

-- Returns {date, admin, reason, account} for the active ban matching this
-- serial or account name, or nil when neither is banned.
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
-- so all they can do is look at the ban panel. Non-GTA controls (chatbox,
-- console) are left enabled on purpose.
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

    local acc = getPlayerAccount(player)
    if acc and not isGuestAccount(acc) then
        triggerClientEvent(player, "acc:setPanel", player, nil)
    else
        triggerClientEvent(player, "acc:setPanel", player, "login")
    end
end

-- Checked on join (serial only – the account is not known yet).
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
-- NOTE: not "banPlayer"/"unbanPlayer" – those are built-in MTA functions and
-- cannot be re-exported under the same name.
--------------------------------------------------------------------------------

-- Bans an account. If the account holder is online their serial is stored too
-- and they are frozen behind the ban panel immediately.
-- Returns true, or false + an error string.
function banAccount(accountName, reason, adminName)
    if type(accountName) ~= "string" or accountName == "" then
        return false, "Invalid account name"
    end

    local acc = getAccount(accountName)
    if not acc then
        return false, "Account not found: " .. accountName
    end
    accountName = getAccountName(acc)

    reason    = (type(reason) == "string"    and reason    ~= "") and reason    or "No reason given"
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local target = getAccountPlayer(acc)
    local serial = isElement(target) and getPlayerSerial(target) or nil

    local xml = loadBansXml(true)
    if not xml then return false, "Could not open the ban file" end

    -- Reuse an existing active ban node for this account, otherwise add one.
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

-- Lifts every active ban for an account. Returns true, or false + an error.
function unbanAccount(accountName)
    if type(accountName) ~= "string" or accountName == "" then
        return false, "Invalid account name"
    end

    local acc = getAccount(accountName)
    if acc then accountName = getAccountName(acc) end

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

    -- Free an online player sitting behind the ban panel on that account.
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
-- Panel routing
--------------------------------------------------------------------------------

-- The client asks which panel to show once its UI has been built.
addEvent("acc:requestPanel", true)
addEventHandler("acc:requestPanel", root, function()
    local player = client
    if not isElement(player) then return end

    if getElementData(player, "banned") == true then
        triggerClientEvent(player, "acc:setPanel", player, "banned")
    elseif getElementData(player, "isLogged") == true
    and not isGuestAccount(getPlayerAccount(player)) then
        -- Already logged in (e.g. after a resource restart): no panel needed.
        triggerClientEvent(player, "acc:setPanel", player, nil)
    else
        triggerClientEvent(player, "acc:setPanel", player, "login")
    end
end)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Renames a player without the onPlayerChangeNick guard blocking it.
local function setAccountName(player, name)
    scriptedRename[player] = true
    setPlayerName(player, name)
    scriptedRename[player] = nil
end

-- Loading steps to wait for after login before spawning. v_mysql pulls the
-- account data from the shared database and reports "accountdata" when done.
local function pendingLoadTypes()
    local types = {}
    local mysqlRes = getResourceFromName("v_mysql")
    if mysqlRes and getResourceState(mysqlRes) == "running" then
        types[#types + 1] = "accountdata"
    end
    return types
end

-- Restores the player's saved state and drops the black loading screen. Runs
-- only once every data provider has reported in (see server/loading.lua).
local function spawnLoggedInPlayer(player)
    loadPosition(player)
    loadHealth(player)
    loadArmor(player)
    loadMoney(player)
    loadStats(player)
    loadWeapons(player)

    triggerClientEvent(player, "acc:loadingScreen", player, false)
    triggerClientEvent(player, "acc:setPanel", player, nil)

    -- The player is fully loaded (account data synced, saved state restored,
    -- spawned). Other resources hook this instead of onPlayerLogin.
    triggerEvent("onPlayerLoaded", player, getPlayerAccount(player))
end

local function finishLogin(player, acc, username)
    setElementData(player, "accName", username)
    setElementData(player, "accID", getAccountID(acc) or 0)
    setElementData(player, "isLogged", true)
    setAccountName(player, username)

    -- Hide the login panel, show the loading screen, wait for the data
    -- providers, then spawn.
    triggerClientEvent(player, "acc:setPanel", player, nil)
    triggerClientEvent(player, "acc:loadingScreen", player, true)
    beginLoading(player, pendingLoadTypes(), spawnLoggedInPlayer)
end

--------------------------------------------------------------------------------
-- Login / Register
--------------------------------------------------------------------------------

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

    local acc = getAccount(username, password)
    if not acc then
        triggerClientEvent(player, "acc:error", player, "Wrong username or password")
        return
    end

    if isElement(getAccountPlayer(acc)) then
        triggerClientEvent(player, "acc:error", player, "This account is already in use")
        return
    end

    local ban = getActiveBan(getPlayerSerial(player), getAccountName(acc))
    if ban then
        applyBanState(player, ban)
        triggerClientEvent(player, "acc:setPanel", player, "banned")
        triggerClientEvent(player, "acc:error", player, "This account is banned")
        return
    end

    if not logIn(player, acc, password) then
        triggerClientEvent(player, "acc:error", player, "Login failed")
        return
    end

    finishLogin(player, acc, username)
end
addEvent("login_player", true)
addEventHandler("login_player", root, login_player)

function register_player(username, password)
    local player = client
    if not isElement(player) then return end
    if getElementData(player, "banned") == true then return end
    if getElementData(player, "isLogged") == true then return end

    if type(username) ~= "string" or type(password) ~= "string" then return end
    if username == "" then
        triggerClientEvent(player, "acc:error", player, "Username missing")
        return
    end
    if #password < 5 then
        triggerClientEvent(player, "acc:error", player, "Password too short")
        return
    end
    if getAccount(username) then
        triggerClientEvent(player, "acc:error", player, "Account already exists")
        return
    end

    local acc = addAccount(username, password)
    if not acc then
        triggerClientEvent(player, "acc:error", player, "Registration failed")
        return
    end

    if not logIn(player, acc, password) then
        triggerClientEvent(player, "acc:error", player, "Login failed")
        return
    end

    setElementData(player, "accName", username)
    setElementData(player, "accID", getAccountID(acc) or 0)
    setElementData(player, "isLogged", true)
    setAccountName(player, username)

    -- Fresh account: go through the same loading gate (v_mysql simply finds no
    -- stored data), then spawn at the default location and store a baseline -
    -- which save_all() also mirrors into the shared database.
    triggerClientEvent(player, "acc:setPanel", player, nil)
    triggerClientEvent(player, "acc:loadingScreen", player, true)
    beginLoading(player, pendingLoadTypes(), function(p)
        loadPosition(p)
        save_all(p)
        triggerClientEvent(p, "acc:loadingScreen", p, false)
        triggerClientEvent(p, "acc:setPanel", p, nil)
        triggerEvent("onPlayerLoaded", p, getPlayerAccount(p))
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
    loggingOut[source] = nil
    scriptedRename[source] = nil
end)

addEventHandler("onPlayerLogout", root, function()
    local player = source
    if loggingOut[player] then return end -- re-entrant call from logOut() below
    loggingOut[player] = true

    cancelEvent() -- keep the account attached so the save still works
    save_all(player)
    logOut(player)
    loggingOut[player] = nil

    setElementData(player, "isLogged", false)
    setElementData(player, "accName", false)
    setElementData(player, "accID", false)
    triggerClientEvent(player, "acc:setPanel", player, "login")
end)

-- Block manual nick changes, but let the script's own renames through.
addEventHandler("onPlayerChangeNick", root, function()
    if scriptedRename[source] then return end
    cancelEvent()
end)
