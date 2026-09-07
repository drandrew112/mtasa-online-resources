--[[
    v_phone / server/apps/settings.lua
    Persists the chosen wallpaper per account.
]]

local KEY = "phone.wallpaper"

local function accountOf(player)
    local acc = player and getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return nil end
    return acc
end

local function currentKey(player)
    local acc = accountOf(player)
    local stored = acc and getAccountData(acc, KEY) or nil
    return PHONE_CONFIG.wallpaperByKey(stored or PHONE_CONFIG.defaultWallpaper).key
end

PhoneServer.onPull(function(player)
    PhoneServer.push(player, "settings:wallpaper", currentKey(player))
end)

PhoneServer.on("settings:setWallpaper", function(player, key)
    if type(key) ~= "string" then return end
    local w = PHONE_CONFIG.wallpaperByKey(key)
    local acc = accountOf(player)
    if acc then setAccountData(acc, KEY, w.key) end
    PhoneServer.push(player, "settings:wallpaper", w.key)
end)
