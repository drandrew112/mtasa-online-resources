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
-- sendWebhook / sendWebhookEmbed are server-side exports only; there is
-- deliberately no remote event.

local MAX_LENGTH = 2000
local MAX_QUEUE = 50
local SEND_INTERVAL = 2100 -- ms between posts: the queue lets exactly one message through per interval

-- Discord embed limits (developer docs: message resource, "Embed Limits")
local LIMIT = {
    embeds = 10, total = 6000, title = 256, description = 4096, fields = 25,
    fieldName = 256, fieldValue = 1024, footer = 2048, author = 256,
}
local MENTION_TYPES = { everyone = true, roles = true, users = true }

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

-- JSON for the Discord API. toJSON is not used: it wraps everything in [] and
-- may write whole numbers (colours) as floats. A table with keys 1..n (or an
-- empty one) becomes an array, any other table an object.
local ESCAPE = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(v)
    -- explicit byte range, not %c: depending on the C locale %c also matches
    -- 0x80-0x9F, which would break UTF-8 (emoji)
    return '"' .. v:gsub('[%z\1-\31\127"\\]', function(c)
        return ESCAPE[c] or ("\\u%04x"):format(c:byte())
    end) .. '"'
end

local function encode(v)
    local t = type(v)
    if t == "string" then return encodeString(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v == math.floor(v) and math.abs(v) < 2^53 then return ("%d"):format(v) end
        return ("%.14g"):format(v)
    end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "null" end
    local n, isArray = #v, true
    for k in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then isArray = false break end
    end
    local out = {}
    if isArray then
        for i = 1, n do out[i] = encode(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then
            out[#out + 1] = encodeString(tostring(k)) .. ":" .. encode(x)
        end
    end
    return "{" .. table.concat(out, ",") .. "}"
end

local function processQueue()
    local item = table.remove(queue, 1)
    if not item then
        sending = false
        return
    end
    sending = true

    fetchRemote(item.url, {
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        postData = encode(item.payload),
    }, function(_, info)
        -- the URL is a secret, never log it
        if not info.success then
            outputDebugString("[discordmanager] webhook '" .. item.id .. "' failed, status " .. tostring(info.statusCode), 1)
        end
    end)
    setTimer(processQueue, SEND_INTERVAL, 1)
end

local function enqueue(id, payload)
    local url = webhooks[id]
    if not url then
        outputDebugString("[discordmanager] unknown webhook id '" .. id .. "'", 2)
        return false
    end
    if #queue >= MAX_QUEUE then return false end
    queue[#queue + 1] = { id = id, url = url, payload = payload }
    if not sending then processQueue() end
    return true
end

function sendWebhook(id, message)
    if sourceResource == nil or type(id) ~= "string" or type(message) ~= "string" or message == "" then
        return false
    end
    if #message > MAX_LENGTH then message = utf8.sub(message, 1, MAX_LENGTH) end
    return enqueue(id, { content = message, allowed_mentions = { parse = {} } })
end

-- embeds ----------------------------------------------------------------------

local function len(v) return utf8.len(v) or #v end

-- text cut to `max` characters (UTF-8); nil for anything that is not text
local function text(v, max)
    if type(v) == "number" then v = tostring(v) end
    if type(v) ~= "string" or v == "" or max < 1 then return nil end
    if len(v) > max then v = utf8.sub(v, 1, max - 1) .. "…" end
    return v
end

local function link(v)
    return type(v) == "string" and v:match("^https?://") and v or nil
end

-- One embed with only the keys Discord knows, inside the limits.
-- budget = characters still allowed in the whole message (6000 over all embeds).
local function cleanEmbed(e, budget)
    if type(e) ~= "table" then return nil, budget end
    local out = {}
    local function take(v, max)
        v = text(v, math.min(max, budget))
        if v then budget = budget - len(v) end
        return v
    end
    out.title = take(e.title, LIMIT.title)
    out.description = take(e.description, LIMIT.description)
    out.url = link(e.url)
    out.timestamp = type(e.timestamp) == "string" and e.timestamp or nil
    local color = tonumber(e.color)
    if color then out.color = math.max(0, math.min(0xFFFFFF, math.floor(color))) end
    if type(e.author) == "table" then
        local name = take(e.author.name, LIMIT.author)
        if name then out.author = { name = name, url = link(e.author.url), icon_url = link(e.author.icon_url) } end
    end
    for _, k in ipairs({ "image", "thumbnail" }) do
        if type(e[k]) == "table" and link(e[k].url) then out[k] = { url = e[k].url } end
    end
    if type(e.fields) == "table" then
        local fields = {}
        for _, f in ipairs(e.fields) do
            if #fields >= LIMIT.fields then break end
            if type(f) == "table" then
                local name, value = take(f.name, LIMIT.fieldName), take(f.value, LIMIT.fieldValue)
                if name and value then
                    fields[#fields + 1] = { name = name, value = value, inline = f.inline == true }
                end
            end
        end
        if #fields > 0 then out.fields = fields end
    end
    if type(e.footer) == "table" then
        local t = take(e.footer.text, LIMIT.footer)
        if t then out.footer = { text = t, icon_url = link(e.footer.icon_url) } end
    end
    if not (out.title or out.description or out.fields or out.image) then return nil, budget end
    return out, budget
end

--- Sends one embed or a list of embeds through the webhook `id`. An embed is a
--- Discord embed object: title, description, url, color (0xRRGGBB), timestamp
--- (ISO 8601), author {name, url, icon_url}, image {url}, thumbnail {url},
--- fields { {name, value, inline}, ... }, footer {text, icon_url}. Texts over
--- Discord's limits are cut.
--- options (optional): content = message text above the embeds,
---   mentions = { "everyone" | "roles" | "users", ... } mention types that may
---   ping (default: none), username / avatar_url = override of the webhook's.
function sendWebhookEmbed(id, embeds, options)
    if sourceResource == nil or type(id) ~= "string" or type(embeds) ~= "table" then
        return false
    end
    if embeds[1] == nil then embeds = { embeds } end
    options = type(options) == "table" and options or {}

    local list, budget = {}, LIMIT.total
    for i = 1, math.min(#embeds, LIMIT.embeds) do
        local e
        e, budget = cleanEmbed(embeds[i], budget)
        if e then list[#list + 1] = e end
    end
    if #list == 0 then return false end

    local parse = {}
    for _, m in ipairs(type(options.mentions) == "table" and options.mentions or {}) do
        if MENTION_TYPES[m] then parse[#parse + 1] = m end
    end
    return enqueue(id, {
        content = text(options.content, MAX_LENGTH),
        username = text(options.username, 80),
        avatar_url = link(options.avatar_url),
        embeds = list,
        allowed_mentions = { parse = parse },
    })
end
