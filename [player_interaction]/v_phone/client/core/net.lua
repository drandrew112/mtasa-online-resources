--[[
    v_phone / client/core/net.lua
    Thin client <-> server transport shared by every app.

      phoneRPC(name, ...)          -> server  (server sees it as `client`)
      phoneOnServer(name, fn)      <- server  push, fn(...)
      phonePull()                  ask the server to re-send everything

    Plus the global toast / close hooks the server can trigger.
]]

function phoneRPC(name, ...)
    triggerServerEvent("phone:rpc", localPlayer, name, ...)
end

function phonePull()
    triggerServerEvent("phone:pull", localPlayer)
end

local handlers = {}

function phoneOnServer(name, fn)
    handlers[name] = fn
end

addEvent("phone:event", true)
addEventHandler("phone:event", root, function(name, ...)
    local fn = handlers[name]
    if fn then fn(...) end
end)

addEvent("phone:toast", true)
addEventHandler("phone:toast", root, function(text)
    local ok = pcall(function() exports.ui_core:addNotification("Phone", tostring(text)) end)
    if not ok then
        outputChatBox("#5aaaff[Phone] #ffffff" .. tostring(text), 255, 255, 255, true)
    end
end)

addEvent("phone:close", true)
addEventHandler("phone:close", root, function()
    if Phone then Phone.close() end
end)
