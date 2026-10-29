-- Player country for the flags (client/flags.lua): element data "country" = lowercase
-- ISO code ("hu") from the player's IP via the ip2c resource (local database), never
-- from the chosen language. ip2c loads its database in the background after it starts:
-- until then the lookup is retried every RETRY_MS.
-- Local / LAN IPs are not in the database: they get LOCAL_COUNTRY (false = no flag).
local LOCAL_COUNTRY = "hu"
local RETRY_MS, MAX_TRIES = 2000, 60

local function isLocalIP(ip)
    return ip:find("^127%.") or ip:find("^10%.") or ip:find("^192%.168%.")
        or ip:find("^172%.1[6-9]%.") or ip:find("^172%.2%d%.") or ip:find("^172%.3[01]%.")
end

local function apply(player, code)
    if isElement(player) then setElementData(player, "country", code or false) end
end

local function ip2cCountry(player)
    local ip2c = getResourceFromName("ip2c")
    if not (ip2c and getResourceState(ip2c) == "running") then return nil end
    local ok, code = pcall(function() return exports.ip2c:getPlayerCountry(player) end)
    if ok and type(code) == "string" and code:match("^%a%a$") then return code:lower() end
    return nil
end

local function lookup(player, tries)
    if not isElement(player) then return end
    local ip = getPlayerIP(player)
    if not ip then return apply(player, false) end
    if isLocalIP(ip) then return apply(player, LOCAL_COUNTRY) end
    local code = ip2cCountry(player)
    if code then return apply(player, code) end
    -- ip2c not running / database still loading / unknown IP: try again a few times
    tries = (tries or 0) + 1
    if tries < MAX_TRIES then
        setTimer(function() lookup(player, tries) end, RETRY_MS, 1)
    else
        apply(player, false)
    end
end

addEventHandler("onPlayerJoin", root, function() lookup(source) end)
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do lookup(player) end
end)
-- ip2c (re)started later: look up everyone still without a country
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "ip2c" then return end
    for _, player in ipairs(getElementsByType("player")) do
        if not getElementData(player, "country") then lookup(player) end
    end
end)

-- ===== exports =====

-- player's country code ("hu", ...) or false (unknown / lookup still running)
function getPlayerCountry(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    return getElementData(player, "country") or false
end

-- override (tests): code = ISO code string or false to clear
function setPlayerCountry(player, code)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if code ~= false and (type(code) ~= "string" or not code:match("^%a%a[%a%-]*$")) then return false end
    return setElementData(player, "country", code and code:lower() or false)
end
