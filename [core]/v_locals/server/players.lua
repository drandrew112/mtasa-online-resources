-- Player languages (server).
--
--   * Account language: accData "locale.language" (v_mysql). Not elementData:
--     nobody else needs it, it would only cost a broadcast.
--   * Before login the client sends the language it remembers (private client
--     file) with "v_locals:clientHello"; that is used for the session and saved
--     to the account if the account has none yet.
--   * On onPlayerLoaded the account value wins and is pushed to the client.
--   * Every change fires  onPlayerLanguageChange(newLang, oldLang)  (source =
--     player); the server libs of other resources keep their cache with it.

local LANG  = {}   -- player -> code (nil = default)
local READY = {}   -- player -> client side of v_locals is running

function locGetPlayerLanguage(player)
    return LANG[player] or LOC.DEFAULT_LANG
end

local function isLogged(player)
    return isElement(player) and getElementData(player, "isLogged") == true
end

local function mysqlRunning()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running"
end

local function storedLanguage(player)
    if not isLogged(player) or not mysqlRunning() then return nil end
    local code = exports.v_mysql:getAccData(player, LOC.ACCDATA_KEY)
    if Catalog.isEnabled(code) then return code end
    return nil
end

local function persist(player, code)
    if not isLogged(player) or not mysqlRunning() then return end
    if exports.v_mysql:getAccData(player, LOC.ACCDATA_KEY) ~= code then
        exports.v_mysql:setAccData(player, LOC.ACCDATA_KEY, code)
    end
end

-- sets the language; push = also tell the client (only once it is ready)
local function apply(player, code, push)
    local old = locGetPlayerLanguage(player)
    LANG[player] = code
    if push and READY[player] then
        triggerClientEvent(player, "v_locals:applyLanguage", resourceRoot, code)
    end
    if old ~= code then
        triggerEvent("onPlayerLanguageChange", player, code, old)
    end
end

-- export logic; returns true on success
function locSetPlayerLanguage(player, code)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if not Catalog.isEnabled(code) then return false end
    apply(player, code, true)
    persist(player, code)
    return true
end

addEvent("onPlayerLanguageChange")

addEvent("v_locals:clientHello", true)
addEventHandler("v_locals:clientHello", resourceRoot, function(clientCode)
    local player = client
    if not isElement(player) then return end
    READY[player] = true

    local account = storedLanguage(player)
    if account then
        apply(player, account, account ~= clientCode)
    elseif Catalog.isEnabled(clientCode) then
        apply(player, clientCode, false)
        persist(player, clientCode)
    else
        apply(player, LOC.DEFAULT_LANG, true)
    end
end)

-- the player picked a language (pause menu -> Display -> Language)
addEvent("v_locals:requestLanguage", true)
addEventHandler("v_locals:requestLanguage", resourceRoot, function(code)
    local player = client
    if not isElement(player) then return end
    if not Catalog.isEnabled(code) then
        -- refused: put the client back to the language the server knows
        triggerClientEvent(player, "v_locals:applyLanguage", resourceRoot, locGetPlayerLanguage(player))
        return
    end
    apply(player, code, false)
    persist(player, code)
end)

-- account data is loaded: the account's language wins (at the login - the
-- account menu comes before onPlayerLoaded - and again when loaded)
local function accountLanguage()
    local player = source
    local account = storedLanguage(player)
    if account then
        apply(player, account, true)
    elseif LANG[player] then
        persist(player, LANG[player])
    end
end
addEvent("onPlayerAccountLogin")
addEventHandler("onPlayerAccountLogin", root, accountLanguage)
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, accountLanguage)

addEventHandler("onPlayerQuit", root, function()
    LANG[source] = nil
    READY[source] = nil
end)

-- resource (re)start with players online: take their account languages; the
-- clients restart too and send their hello
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        local account = storedLanguage(player)
        if account then LANG[player] = account end
    end
end)

LOCALS_INTERNAL.getPlayerLanguage = locGetPlayerLanguage
