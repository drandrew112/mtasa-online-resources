-- Same limit as the client input box (c_chat.lua max_char), checked again here:
-- the client can send anything.
local MAX_CHARS = 150

-- Flood control: at most FLOOD_MAX messages in FLOOD_WINDOW ms, then a short cooldown.
local FLOOD_MAX = 3
local FLOOD_WINDOW = 5000
local FLOOD_COOLDOWN = 5000

local flood = {} -- [player] = { times = { tick, ... }, blockedUntil = tick }

local function alert(player, text)
    triggerClientEvent(player, "chat:muteAlert", player, text, 255, 90, 90, 4000)
end

-- -> cleaned text | nil (nothing left to send)
local function cleanText(text)
    if type(text) ~= "string" then return nil end
    -- the chat line is drawn colour coded: a "#RRGGBB" in the text would recolour it
    repeat
        local before = text
        text = text:gsub("#%x%x%x%x%x%x", "")
    until text == before
    text = text:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local len = utf8.len(text)
    if not len then return nil end -- invalid UTF-8
    if len > MAX_CHARS then text = utf8.sub(text, 1, MAX_CHARS) end
    return text
end

-- true if the player may send now (and records the message)
local function allowMessage(player)
    local now = getTickCount()
    local f = flood[player]
    if not f then
        f = { times = {}, blockedUntil = 0 }
        flood[player] = f
    end
    if now < f.blockedUntil then return false end

    local keep = {}
    for _, t in ipairs(f.times) do
        if now - t < FLOOD_WINDOW then keep[#keep + 1] = t end
    end
    if #keep >= FLOOD_MAX then
        f.times = keep
        f.blockedUntil = now + FLOOD_COOLDOWN
        return false
    end
    keep[#keep + 1] = now
    f.times = keep
    return true
end

-- Local chat reaches players within this many metres, in the same dimension and interior.
local LOCAL_RANGE = 30

-- channel: "global" (default) | "local"
-- Discord sender: "[ADMIN] :flag: **DisplayName** (accountname)" (admin tag only with an admin level,
-- flag = the ui_core country code as a regional-indicator emoji)
local ADMIN_TAGS = { "Trial Mod", "Mod", "Admin", "Superadmin", "Dev", "Owner" }

local function flagEmoji(code)
    if type(code) ~= "string" or not code:match("^%a%a$") then return nil end
    code = code:upper()
    return utf8.char(0x1F1E6 + code:byte(1) - 65, 0x1F1E6 + code:byte(2) - 65)
end

function discordSender(player)
    local acc = tostring(getElementData(player, "accName") or getPlayerName(player))
    local display = tostring(getElementData(player, "displayName") or acc)
    local clean = function(s) return (s:gsub("#%x%x%x%x%x%x", ""):gsub("[*_`~|]", "")) end
    local parts = {}
    local level = tonumber(getElementData(player, "admin_level")) or 0
    if ADMIN_TAGS[level] then parts[#parts + 1] = "**[" .. ADMIN_TAGS[level] .. "]**" end
    local flag = flagEmoji(getElementData(player, "country"))
    if flag then parts[#parts + 1] = flag end
    parts[#parts + 1] = "**" .. clean(display) .. "**"
    parts[#parts + 1] = "(" .. clean(acc) .. ")"
    return table.concat(parts, " ")
end

function sendMessageToAll(sender, text, channel)
    channel = (channel == "local") and "local" or "global"
    local x, y, z, dim, int
    if channel == "local" then
        x, y, z = getElementPosition(sender)
        dim, int = getElementDimension(sender), getElementInterior(sender)
    end
    for i,player in ipairs( getElementsByType("player") ) do
        local reach = true
        if channel == "local" and player ~= sender then
            local px, py, pz = getElementPosition(player)
            reach = getElementDimension(player) == dim and getElementInterior(player) == int
                and getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= LOCAL_RANGE
        end
        if reach then
            triggerClientEvent(player, "addMessage", sender, sender, text, channel)
        end
    end
end

-- Fired (server side only) after a chat message has been accepted and sent.
-- source = the sender, arguments: the cleaned message text, channel ("global" | "local").
addEvent("onPlayerChatMessage")

addEvent("sendMessageToAll", true)
addEventHandler("sendMessageToAll", getRootElement(), function(_, text, channel)
    -- The sender is always the real caller: the first argument from the client is ignored.
    local player = client
    if not isElement(player) or getElementType(player) ~= "player" then return end
    if getElementData(player, "isLogged") ~= true then return end

    -- Drop the message if the sender is muted (mute.lua).
    if isChatMuted(player) then
        notifyMuteBlocked(player)
        return
    end

    text = cleanText(text)
    if not text then return end

    if not allowMessage(player) then
        alert(player, L.msg("v_chat.chat.slow_down"))
        return
    end

    channel = (channel == "local") and "local" or "global"
    sendMessageToAll(player, text, channel)
    local tag = (channel == "local") and "[Local] " or ""
    exports.v_discordmanager:sendWebhook("chat", tag..discordSender(player)..": "..text)
    triggerEvent("onPlayerChatMessage", player, text, channel)
end)

addEventHandler("onPlayerQuit", root, function()
    flood[source] = nil
end)
