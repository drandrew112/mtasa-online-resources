-- Server side player count source for the Discord rich presence

local function broadcast(quitting)
    local count = getPlayerCount()
    if quitting then count = math.max(0, count - 1) end
    triggerClientEvent(root, "discord:serverInfo", resourceRoot, count, getMaxPlayers())
end

addEvent("discord:requestServerInfo", true)
addEventHandler("discord:requestServerInfo", resourceRoot, function()
    if not client then return end
    triggerClientEvent(client, "discord:serverInfo", resourceRoot, getPlayerCount(), getMaxPlayers())
end)

addEventHandler("onPlayerJoin", root, function() setTimer(broadcast, 500, 1, false) end)
-- onPlayerQuit fires before the player is removed from the count
addEventHandler("onPlayerQuit", root, function() broadcast(true) end)

-- Discord webhooks -----------------------------------------------------------
-- URLs live in webhooks.json (git-ignored, see webhooks.example.json).
-- sendWebhook is a server-side export only; there is deliberately no remote event.

local MAX_LENGTH = 2000
local MAX_QUEUE = 50
local SEND_INTERVAL = 600 -- ms between posts, keeps us under Discord's rate limit

local webhooks = {}
local queue = {}
local sending = false

local function loadWebhooks()
    webhooks = {}
    local file = fileExists("webhooks.json") and fileOpen("webhooks.json", true)
    if not file then
        outputDebugString("[discordmanager] webhooks.json missing, copy webhooks.example.json", 2)
        return
    end
    local content = fileRead(file, fileGetSize(file))
    fileClose(file)
    local data = content and fromJSON(content)
    if type(data) ~= "table" then
        outputDebugString("[discordmanager] webhooks.json is not valid JSON", 1)
        return
    end
    for id, url in pairs(data) do
        if type(id) == "string" and type(url) == "string" and url ~= "" then
            webhooks[id] = url
        end
    end
end
addEventHandler("onResourceStart", resourceRoot, loadWebhooks)

local function processQueue()
    local item = table.remove(queue, 1)
    if not item then
        sending = false
        return
    end
    sending = true

    -- toJSON wraps the table in [] ; Discord wants a bare object
    local body = toJSON({ content = item.message, allowed_mentions = { parse = {} } }, true)
    body = string.sub(body, 2, -2)

    fetchRemote(item.url, {
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        postData = body,
    }, function(_, info)
        -- the URL is a secret, never log it
        if not info.success then
            outputDebugString("[discordmanager] webhook '" .. item.id .. "' failed, status " .. tostring(info.statusCode), 1)
        end
    end)
    setTimer(processQueue, SEND_INTERVAL, 1)
end

function sendWebhook(id, message)
    if sourceResource == nil or type(id) ~= "string" or type(message) ~= "string" or message == "" then
        return false
    end
    local url = webhooks[id]
    if not url then
        outputDebugString("[discordmanager] unknown webhook id '" .. id .. "'", 2)
        return false
    end
    if #queue >= MAX_QUEUE then return false end

    if #message > MAX_LENGTH then message = utf8.sub(message, 1, MAX_LENGTH) end
    queue[#queue + 1] = { id = id, url = url, message = message }
    if not sending then processQueue() end
    return true
end
