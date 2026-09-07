--[[
    ui_phone / server/core/phone.lua
    Transport + dispatch for the server-side app modules (server/apps/*.lua).

      PhoneServer.on(name, fn)      handle an RPC from a client, fn(player, ...)
      PhoneServer.onPull(fn)        fn(player) - (re)send this player everything
      PhoneServer.push(pl, n, ...)  push an event to a client's app
      PhoneServer.toast(pl, text)   notification
      PhoneServer.close(pl)         close that player's phone
]]

PhoneServer = {}

local rpc   = {}
local pulls = {}

function PhoneServer.on(name, fn)
    rpc[name] = fn
end

function PhoneServer.onPull(fn)
    pulls[#pulls + 1] = fn
end

function PhoneServer.push(player, name, ...)
    if isElement(player) then
        triggerClientEvent(player, "phone:event", player, name, ...)
    end
end

function PhoneServer.toast(player, text)
    if isElement(player) then
        triggerClientEvent(player, "phone:toast", player, tostring(text))
    end
end

function PhoneServer.close(player)
    if isElement(player) then
        triggerClientEvent(player, "phone:close", player)
    end
end

local function runPulls(player)
    if not isElement(player) then return end
    for _, fn in ipairs(pulls) do
        local ok, err = pcall(fn, player)
        if not ok then outputDebugString("[phone] pull handler failed: " .. tostring(err), 2) end
    end
end

addEvent("phone:rpc", true)
addEventHandler("phone:rpc", root, function(name, ...)
    local fn = rpc[name]
    if not fn or not isElement(client) then return end
    local ok, err = pcall(fn, client, ...)
    if not ok then outputDebugString("[phone] rpc '" .. tostring(name) .. "' failed: " .. tostring(err), 2) end
end)

addEvent("phone:pull", true)
addEventHandler("phone:pull", root, function()
    runPulls(client)
end)

addEventHandler("onPlayerLogin", root, function()
    local player = source
    setTimer(function() runPulls(player) end, 1500, 1)   -- wait for account data to settle
end)
