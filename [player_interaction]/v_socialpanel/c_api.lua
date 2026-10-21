-- Social API (client): the social panel's server actions for other resources
-- (the account menu, before the spawn - only a login is needed, not "loaded").
-- Every call sends the same request the panel sends; the answers come back as
-- local client events (source = localPlayer):
--
--   v_socialpanel:onClientSnapshot      (snap)                  friends, requests, crew, crews, conversations
--   v_socialpanel:onClientProfile       (profile | false, name)
--   v_socialpanel:onClientSearchResults (results, errorText)
--   v_socialpanel:onClientThread        (kind, target, messages)
--   v_socialpanel:onClientNotify        (kind, from, text, crewTag)  a new message arrived
--   v_socialpanel:onClientAchievements  (data)
--   v_socialpanel:onClientInfo          (text)                  result / error of an action

local function send(name, ...)
    triggerServerEvent(name, localPlayer, ...)
    return true
end

function spRequestSnapshot()           return send("sp:pull") end
function spFriendAdd(name)             return send("sp:friend:add", tostring(name or "")) end
function spFriendAccept(name)          return send("sp:friend:accept", tostring(name or "")) end
function spFriendDecline(name)         return send("sp:friend:decline", tostring(name or "")) end
function spFriendRemove(name)          return send("sp:friend:remove", tostring(name or "")) end
function spViewProfile(name)           return send("sp:profile:view", tostring(name or "")) end
function spSearch(query)               return send("sp:search", tostring(query or "")) end
function spOpenThread(kind, target)    return send("sp:msg:open", kind, target) end
function spSendMessage(kind, target, text) return send("sp:msg:send", kind, target, tostring(text or "")) end
function spCrewCreate(name, tag, r, g, b)  return send("sp:crew:create", name, tag, r, g, b) end
function spCrewJoin(name)              return send("sp:crew:join", tostring(name or "")) end
function spCrewLeave()                 return send("sp:crew:leave") end
function spCrewKick(member)            return send("sp:crew:kick", tostring(member or "")) end
function spCrewCustomize(tag, desc, r, g, b) return send("sp:crew:customize", tag, desc, r, g, b) end
function spRequestAchievements()       return send("sp:ach:pull") end

-- server answers -> local events (c_ui.lua handles the same server events for the panel)
local FORWARD = {
    ["sp:push"]           = "v_socialpanel:onClientSnapshot",
    ["sp:profile:show"]   = "v_socialpanel:onClientProfile",
    ["sp:search:results"] = "v_socialpanel:onClientSearchResults",
    ["sp:msg:data"]       = "v_socialpanel:onClientThread",
    ["sp:notify"]         = "v_socialpanel:onClientNotify",
    ["sp:ach:data"]       = "v_socialpanel:onClientAchievements",
    ["sp:info"]           = "v_socialpanel:onClientInfo",
}

for serverEvent, localEvent in pairs(FORWARD) do
    addEvent(serverEvent, true)
    addEvent(localEvent)
    addEventHandler(serverEvent, root, function(...)
        triggerEvent(localEvent, localPlayer, ...)
    end)
end
