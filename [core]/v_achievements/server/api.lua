-- Achievement logic + exports.
--
-- Every export takes `who` = player element or account-name string (offline
-- accounts work too). Requests for an already completed achievement are
-- ignored and return false.
--
-- Events (server):
--   onPlayerAchievementUnlocked (accountName, id, xp)
--       source = the player, or resourceRoot when the account is offline
--   onPlayerAchievementProgress (id, progress, goal)
--       source = the player; online only, fired when the whole-number
--       progress changes

addEvent("onPlayerAchievementUnlocked")
addEvent("onPlayerAchievementProgress")
addEvent("onPlayerLoaded")

local function now()
    return getRealTime().timestamp
end

local function isOnline(entry)
    return entry.online and isElement(entry.player)
end

-- XP goes through v_levelsys, which only works for a loaded online player;
-- anything it refuses is parked in pendingXp and retried later.
local function grantXp(entry, xp)
    if xp <= 0 then return end
    if isOnline(entry) and exports.v_levelsys:giveXp(entry.player, xp) then return end
    entry.data.pendingXp = entry.data.pendingXp + xp
end

local function payPending(entry)
    local xp = entry.data.pendingXp
    if xp <= 0 or not isOnline(entry) then return end
    if exports.v_levelsys:giveXp(entry.player, xp) then
        entry.data.pendingXp = 0
        STORE.save(entry, true)
    end
end

local function unlock(entry, def)
    local d = entry.data
    if d.done[def.id] then return false end
    d.done[def.id] = now()
    grantXp(entry, def.xp)
    STORE.save(entry, true)

    if isOnline(entry) then
        triggerClientEvent(entry.player, "ach:unlocked", entry.player, def.id, def.name, def.desc, def.xp)
        triggerEvent("onPlayerAchievementUnlocked", entry.player, entry.name, def.id, def.xp)
    else
        triggerEvent("onPlayerAchievementUnlocked", resourceRoot, entry.name, def.id, def.xp)
    end
    return true
end

local function current(data, def)
    if def.type ~= "progress" then return data.done[def.id] and 1 or 0 end
    if def.stat then return data.stats[def.stat] or 0 end
    return data.prog[def.id] or 0
end

local function allDone(data, list)
    for _, def in ipairs(list) do
        if not data.done[def.id] then return false end
    end
    return true
end

local function emitProgress(entry, def, old, new)
    if not isOnline(entry) or entry.data.done[def.id] then return end
    if math.floor(old) == math.floor(new) then return end
    triggerEvent("onPlayerAchievementProgress", entry.player, def.id, math.min(new, def.goal), def.goal)
end

-- Unlocks every progress achievement whose goal the counter reached.
local function evaluate(entry, def)
    if not entry.data.done[def.id] and current(entry.data, def) >= def.goal then
        unlock(entry, def)
    end
end

-- Moves a stat counter to `new` (never down) and advances its achievements.
local function moveStat(who, stat, newFn)
    local list = REG.byStat[stat]
    if not list then return false end
    local entry = STORE.get(who)
    if not entry or allDone(entry.data, list) then return false end

    local old = entry.data.stats[stat] or 0
    local new = newFn(old)
    if new <= old then return false end
    entry.data.stats[stat] = new

    for _, def in ipairs(list) do emitProgress(entry, def, old, new) end
    for _, def in ipairs(list) do evaluate(entry, def) end
    STORE.save(entry)
    return true
end

local function moveProgress(who, id, newFn)
    local def = REG.byId[id]
    if not def or def.type ~= "progress" then return false end
    if def.stat then
        local entry = STORE.get(who)
        if not entry or entry.data.done[id] then return false end
        return moveStat(who, def.stat, newFn)
    end

    local entry = STORE.get(who)
    if not entry or entry.data.done[id] then return false end
    local old = entry.data.prog[id] or 0
    local new = newFn(old)
    if new <= old then return false end
    entry.data.prog[id] = new

    emitProgress(entry, def, old, new)
    evaluate(entry, def)
    STORE.save(entry)
    return true
end

local function record(data, def)
    local done = data.done[def.id] ~= nil
    local goal = def.type == "progress" and def.goal or 1
    local progress = done and goal or math.min(current(data, def), goal)
    return { done = done, unlockedAt = data.done[def.id] or false, progress = progress, goal = goal }
end

--------------------------------------------------------------------------------
-- Exports: definitions
--------------------------------------------------------------------------------

function getAchievements()
    local out = {}
    for i, def in ipairs(REG.list) do out[i] = REG.copy(def) end
    return out
end

function getAchievement(id)
    local def = REG.byId[id]
    return def and REG.copy(def) or false
end

function getAchievementCategories()
    local out = {}
    for i, c in ipairs(REG.categories) do out[i] = { id = c.id, name = c.name } end
    return out
end

--------------------------------------------------------------------------------
-- Exports: player state
--------------------------------------------------------------------------------

-- { [id] = { done, unlockedAt (timestamp|false), progress, goal } }
function getPlayerAchievements(who)
    local entry = STORE.get(who)
    if not entry then return false end
    local out = {}
    for _, def in ipairs(REG.list) do out[def.id] = record(entry.data, def) end
    return out
end

function getPlayerAchievement(who, id)
    local def = REG.byId[id]
    local entry = def and STORE.get(who)
    if not entry then return false end
    return record(entry.data, def)
end

function isAchievementUnlocked(who, id)
    local entry = REG.byId[id] and STORE.get(who)
    return entry and entry.data.done[id] ~= nil or false
end

-- { done, total, xp, maxXp }
function getPlayerAchievementSummary(who)
    local entry = STORE.get(who)
    if not entry then return false end
    local s = { done = 0, total = #REG.list, xp = 0, maxXp = 0 }
    for _, def in ipairs(REG.list) do
        s.maxXp = s.maxXp + def.xp
        if entry.data.done[def.id] then
            s.done = s.done + 1
            s.xp = s.xp + def.xp
        end
    end
    return s
end

function getStat(who, stat)
    local entry = STORE.get(who)
    if not entry then return false end
    return entry.data.stats[tostring(stat)] or 0
end

--------------------------------------------------------------------------------
-- Exports: changes
--------------------------------------------------------------------------------

-- Works for both types; a progress achievement is completed regardless of
-- its counter. true = unlocked now, false = already done / unknown / no account.
function unlockAchievement(who, id)
    local def = REG.byId[id]
    local entry = def and STORE.get(who)
    if not entry then return false end
    return unlock(entry, def)
end

function addAchievementProgress(who, id, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end
    return moveProgress(who, id, function(old) return old + amount end)
end

-- Absolute value; never lowers the counter.
function setAchievementProgress(who, id, value)
    value = tonumber(value)
    if not value then return false end
    return moveProgress(who, id, function() return value end)
end

-- Advances every achievement bound to `stat` (e.g. drive_km -> all tiers).
function addStat(who, stat, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end
    return moveStat(who, tostring(stat), function(old) return old + amount end)
end

-- Absolute value (for v_stats' authoritative counters); never lowers it.
function setStat(who, stat, value)
    value = tonumber(value)
    if not value then return false end
    return moveStat(who, tostring(stat), function() return value end)
end

-- Admin / testing. A stat-bound achievement resets its whole stat group and
-- counter. id == nil resets everything. Granted XP is not taken back.
function resetPlayerAchievement(who, id)
    local entry = STORE.get(who)
    if not entry then return false end
    local d = entry.data
    if id == nil then
        d.done, d.prog, d.stats = {}, {}, {}
    else
        local def = REG.byId[id]
        if not def then return false end
        if def.stat then
            for _, s in ipairs(REG.byStat[def.stat]) do d.done[s.id] = nil end
            d.stats[def.stat] = nil
        else
            d.done[id] = nil
            d.prog[id] = nil
        end
    end
    STORE.save(entry, true)
    return true
end

--------------------------------------------------------------------------------
-- Login / lifecycle
--------------------------------------------------------------------------------

-- Pays parked XP and catches up achievements whose goal was lowered in the
-- config since the counter was saved.
local function onLoaded(player)
    local entry = STORE.get(player)
    if not entry then return end
    for _, def in ipairs(REG.list) do
        if def.type == "progress" then evaluate(entry, def) end
    end
    payPending(entry)
end

-- Delayed so v_levelsys has put level/xp on the player before we grant XP.
addEventHandler("onPlayerLoaded", root, function()
    local player = source
    setTimer(function()
        if not isElement(player) then return end
        onLoaded(player)
        if ACH.LOGIN_ACHIEVEMENT then unlockAchievement(player, ACH.LOGIN_ACHIEVEMENT) end
    end, 2000, 1)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do onLoaded(p) end
end)

setTimer(function()
    for _, entry in pairs(STORE.online()) do payPending(entry) end
end, ACH.FLUSH_INTERVAL, 0)
