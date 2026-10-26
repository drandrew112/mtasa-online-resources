--[[
    ui_phone / server/apps/settings.lua
    Persists the chosen wallpaper per account.
]]

local KEY = "phone.wallpaper"

local function accountOf(player)
    if not isElement(player) or not exports.v_accounts:isLoggedIn(player) then return nil end
    return player
end

local function currentKey(player)
    local acc = accountOf(player)
    local stored = acc and exports.v_mysql:getAccData(acc, KEY) or nil
    return PHONE_CONFIG.wallpaperByKey(stored or PHONE_CONFIG.defaultWallpaper).key
end

PhoneServer.onPull(function(player)
    PhoneServer.push(player, "settings:wallpaper", currentKey(player))
end)

PhoneServer.on("settings:setWallpaper", function(player, key)
    if type(key) ~= "string" then return end
    local w = PHONE_CONFIG.wallpaperByKey(key)
    local acc = accountOf(player)
    if acc then exports.v_mysql:setAccData(acc, KEY, w.key) end
    PhoneServer.push(player, "settings:wallpaper", w.key)
end)
