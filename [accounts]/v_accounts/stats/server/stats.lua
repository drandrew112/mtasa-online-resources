-- stats module (server): player count history for the login screen's Players panel.
-- stats.json (gitignored) = { samples = { { t = timestamp, n = playerCount }, ... } }.
-- A sample is taken every 15 minutes; samples older than 24 h are dropped.
-- The client gets the last 12 h in 30-minute slots (24 slots); a slot without
-- any sample is "missing" (drawn red, at 0).

local FILE        = "stats/stats.json"
local INTERVAL    = 15 * 60          -- seconds between samples
local KEEP        = 24 * 3600        -- samples older than this are removed
local SLOT        = 30 * 60          -- chart resolution
local SLOTS       = 24               -- 12 h

local samples = {}                   -- { { t, n } } oldest first

local function now() return getRealTime().timestamp end

local function load()
    samples = {}
    if not fileExists(FILE) then return end
    local f = fileOpen(FILE, true)
    if not f then return end
    local raw = fileRead(f, fileGetSize(f))
    fileClose(f)
    local data = raw and raw ~= "" and fromJSON(raw)
    if type(data) ~= "table" or type(data.samples) ~= "table" then return end
    for _, s in ipairs(data.samples) do
        local t, n = tonumber(s.t), tonumber(s.n)
        if t and n then samples[#samples + 1] = { t = t, n = n } end
    end
end

local function save()
    if fileExists(FILE) then fileDelete(FILE) end
    local f = fileCreate(FILE)
    if not f then return end
    fileWrite(f, toJSON({ samples = samples }, true))
    fileClose(f)
end

local function prune()
    local since = now() - KEEP
    local out = {}
    for _, s in ipairs(samples) do
        if s.t >= since then out[#out + 1] = s end
    end
    samples = out
end

local function record()
    local t = now()
    -- align to the 15-minute grid: the timestamp identifies the moment
    t = t - (t % INTERVAL)
    local last = samples[#samples]
    if last and last.t == t then
        last.n = getPlayerCount()
    else
        samples[#samples + 1] = { t = t, n = getPlayerCount() }
    end
    prune()
    save()
end

-- 24 slots, oldest first: { n = maxPlayers seen in the slot | nil (no data) }
local function buildSlots()
    local t = now()
    local endT = t - (t % SLOT) + SLOT           -- end of the current slot
    local startT = endT - SLOTS * SLOT
    local slots = {}
    for i = 1, SLOTS do slots[i] = false end
    for _, s in ipairs(samples) do
        if s.t >= startT and s.t < endT then
            local i = math.floor((s.t - startT) / SLOT) + 1
            if slots[i] == false or s.n > slots[i] then slots[i] = s.n end
        end
    end
    -- the running slot always has the live value
    slots[SLOTS] = math.max(slots[SLOTS] or 0, getPlayerCount())
    return slots
end

local function payload()
    return { current = getPlayerCount(), max = getMaxPlayers(), slots = buildSlots(), slotSeconds = SLOT }
end

local function sendTo(player)
    triggerClientEvent(player, "v_accounts:stats", player, payload())
end

local function waitingPlayers()
    local out = {}
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "isLogged") ~= true then out[#out + 1] = p end
    end
    return out
end

addEvent("v_accounts:requestStats", true)
addEventHandler("v_accounts:requestStats", root, function()
    if isElement(client) then sendTo(client) end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    load()
    prune()
    record()
    setTimer(record, INTERVAL * 1000, 0)
    -- keep the open login screens fresh
    setTimer(function()
        for _, p in ipairs(waitingPlayers()) do sendTo(p) end
    end, 60000, 0)
end)

addEventHandler("onPlayerJoin", root, function() setTimer(sendTo, 1500, 1, source) end)
