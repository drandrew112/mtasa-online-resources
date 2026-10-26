-- Per-account stats, stored as one JSON string in account data
-- (v_mysql accData key STATS.STORAGE_KEY):
--
--   { v = 1, s = { [statId] = number } }
--
-- Online (logged in) accounts are cached; changes mark them dirty and a timer
-- flushes them. Offline accounts are read and written straight through.

STORE = {}

local cache = {}      -- cache[accName] = entry
local byPlayer = {}   -- byPlayer[player] = accName

local function decode(s)
    local d = { v = 1, s = {} }
    if type(s) ~= "string" or s == "" then return d end
    local ok, t = pcall(fromJSON, s)
    if not ok or type(t) ~= "table" or type(t.s) ~= "table" then return d end
    for k, v in pairs(t.s) do
        v = tonumber(v)
        if type(k) == "string" and v then d.s[k] = v end
    end
    return d
end

local function readData(name)
    return decode(exports.v_mysql:getAccData(name, STATS.STORAGE_KEY))
end

local function write(entry)
    entry.dirty = false
    return exports.v_mysql:setAccData(entry.name, STATS.STORAGE_KEY, toJSON(entry.data, true))
end

local function loggedName(player)
    if getElementData(player, "isLogged") ~= true then return nil end
    local n = getElementData(player, "accName")
    return (type(n) == "string" and n ~= "") and n or nil
end

local function loadOnline(player, name)
    local entry = cache[name]
    if not entry then
        entry = { name = name, player = player, online = true, data = readData(name) }
        cache[name] = entry
    end
    entry.player = player
    byPlayer[player] = name
    return entry
end

-- who = player element or account name string -> entry | nil
function STORE.get(who)
    if isElement(who) then
        if getElementType(who) ~= "player" then return nil end
        local name = loggedName(who)
        return name and loadOnline(who, name) or nil
    end
    if type(who) ~= "string" or who == "" then return nil end

    if cache[who] then return cache[who] end
    local lower = who:lower()
    for name, entry in pairs(cache) do
        if name:lower() == lower then return entry end
    end

    local canon = exports.v_accounts:accountNameExists(who)
    if not canon then return nil end
    for _, p in ipairs(getElementsByType("player")) do
        if loggedName(p) == canon then return loadOnline(p, canon) end
    end
    return { name = canon, online = false, data = readData(canon) }
end

-- Offline entries and `immediate` writes go out now, the rest on the timer.
function STORE.save(entry, immediate)
    if not entry.online or immediate then return write(entry) end
    entry.dirty = true
    return true
end

function STORE.flushAll()
    for _, entry in pairs(cache) do
        if entry.dirty then write(entry) end
    end
end

function STORE.online()
    return cache
end

-- Account name of a logged-in player (nil otherwise).
STORE.loggedName = loggedName

function STORE.drop(player)
    local name = byPlayer[player]
    byPlayer[player] = nil
    local entry = name and cache[name]
    if not entry then return end
    if STORE.beforeDrop then STORE.beforeDrop(entry) end
    if entry.dirty then write(entry) end
    cache[name] = nil
end

addEventHandler("onPlayerQuit", root, function()
    STORE.drop(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    STORE.flushAll()
end)

setTimer(STORE.flushAll, STATS.FLUSH_INTERVAL, 0)
