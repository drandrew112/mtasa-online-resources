-- Exports. `who` = player element or account name (offline accounts work too).
-- Values are in the stat's unit (km, seconds, count). Unknown id / no account
-- -> false.

addEvent("onPlayerLoaded")

local achPending = {}   -- achPending[accName] = { [statId] = true }

local function achReady()
    local res = getResourceFromName("v_achievements")
    return res and getResourceState(res) == "running"
end

-- Forwards the current values of the changed stats to v_achievements.
-- Always addressed by account name, so it is safe during player quit.
local function pushAch(entry)
    local set = achPending[entry.name]
    if not set then return end
    achPending[entry.name] = nil
    if not achReady() then return end
    for id in pairs(set) do
        local def = REG.byId[id]
        if def and def.achStat then
            exports.v_achievements:setStat(entry.name, def.achStat, entry.data.s[id] or 0)
        end
    end
end

-- Internal (tracker / events): raise a stat. Returns the new value or false.
function API_ADD(entry, id, amount)
    local def = REG.byId[id]
    if not def or not entry or amount <= 0 then return false end
    local new = (entry.data.s[id] or 0) + amount
    entry.data.s[id] = new
    STORE.save(entry)
    if def.achStat then
        local set = achPending[entry.name]
        if not set then set = {}; achPending[entry.name] = set end
        set[id] = true
    end
    return new
end

-- Throttled forward of changed stats.
setTimer(function()
    for _, entry in pairs(STORE.online()) do pushAch(entry) end
end, STATS.ACH_PUSH_INTERVAL, 0)

-- Catch up on login (achievements may have been added / the resource was
-- down while the stats grew).
addEventHandler("onPlayerLoaded", root, function()
    local player = source
    setTimer(function()
        local entry = isElement(player) and STORE.get(player)
        if not entry then return end
        local set = {}
        for _, def in ipairs(REG.list) do
            if def.achStat then set[def.id] = true end
        end
        achPending[entry.name] = set
        pushAch(entry)
    end, 3000, 1)
end)

-- last forward before the entry leaves the cache on quit
STORE.beforeDrop = pushAch

addEventHandler("onResourceStop", resourceRoot, function()
    for _, entry in pairs(STORE.online()) do pushAch(entry) end
end)

--------------------------------------------------------------------------------

local function publicDef(def)
    return { id = def.id, name = def.name, unit = def.unit, achStat = def.achStat }
end

function getStatDefinitions()
    local out = {}
    for i, def in ipairs(REG.list) do out[i] = publicDef(def) end
    return out
end

function getStatDefinition(id)
    local def = REG.byId[tostring(id)]
    return def and publicDef(def) or false
end

function getStat(who, id)
    id = tostring(id)
    if not REG.byId[id] then return false end
    local entry = STORE.get(who)
    if not entry then return false end
    return entry.data.s[id] or 0
end

-- { [statId] = value } for every registered stat.
function getStats(who)
    local entry = STORE.get(who)
    if not entry then return false end
    local out = {}
    for _, def in ipairs(REG.list) do out[def.id] = entry.data.s[def.id] or 0 end
    return out
end

function addStat(who, id, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end
    return API_ADD(STORE.get(who), tostring(id), amount)
end
