-- Scene variety: history of the spawned scenes and the rules of Auto.pickScene.
--
-- History, saved in MSM.VARIETY.FILE (entries older than RETENTION are deleted):
--   global  - every spawned scene, any source (onMedSceneSpawned)
--   players - per account: the scenes whose task was assigned to a unit the account
--             was in (onErmTaskAssigned), i.e. who really got it, not who was guessed
-- A "location" is a position, not a scene: two scenes whose centres are within
-- LOCATION_RADIUS are the same location.
--
-- Variety.choose(candidates) gets the scenes that passed the mandatory checks. The
-- variety rules exclude more of them; while nothing is left they are relaxed level by level:
--   0 every rule
--   1 category repeat dropped
--   2 global history dropped
--   3 player history dropped
--   4 geographic spread dropped (= every candidate)
-- The pool is then weighted (category balance + frequency, location use, spread) and
-- only the last step is random.

Variety = {
    global = {},    -- { entry, ... } oldest first; entry = { name, category, x, y, interior, time }
    players = {},   -- [account] = { entry, ... } oldest first
    dirty = false,
    last = nil,     -- { name, level, pool, candidates, time } of the last pick
}

local V = MSM.VARIETY
local FORMAT = 1
local MAX_LEVEL = 4
Variety.MAX_LEVEL = MAX_LEVEL
Variety.LEVELS = { [0] = "all rules", "category repeat dropped", "global history dropped",
    "player history dropped", "spread dropped" }

local function now()
    return getRealTime().timestamp
end
Variety.now = now

local function makeEntry(name, category, x, y, interior, time)
    return {
        name = name, category = category or "",
        x = msmRound(x, 1), y = msmRound(y, 1),
        interior = interior or 0, time = time or now(),
    }
end
Variety.makeEntry = makeEntry

local function readEntry(e)
    if type(e) ~= "table" or type(e.name) ~= "string" then return nil end
    local x, y, time = tonumber(e.x), tonumber(e.y), tonumber(e.time)
    if not x or not y or not time then return nil end
    return makeEntry(e.name, tostring(e.category or ""), x, y, math.floor(tonumber(e.interior) or 0), time)
end

local function byTime(a, b)
    return a.time < b.time
end

-- Entries younger than RETENTION, at most `limit` of the newest
local function trim(list, limit)
    local cut = now() - V.RETENTION
    local kept = {}
    for _, e in ipairs(list) do
        if e.time >= cut then kept[#kept + 1] = e end
    end
    if #kept <= limit then return kept end
    local out = {}
    for i = #kept - limit + 1, #kept do out[#out + 1] = kept[i] end
    return out
end

function Variety.prune()
    local changed = false
    local kept = trim(Variety.global, V.GLOBAL_MAX)
    if #kept ~= #Variety.global then changed = true end
    Variety.global = kept
    for account, list in pairs(Variety.players) do
        kept = trim(list, V.PLAYER_MAX)
        if #kept ~= #list then changed = true end
        Variety.players[account] = #kept > 0 and kept or nil
    end
    if changed then Variety.dirty = true end
end

---------------------------------------------------------------- file

function Variety.load()
    Variety.global, Variety.players = {}, {}
    local data = msmDecodeJSON(msmReadFile(V.FILE) or "")
    if not data then return end
    for _, e in ipairs(type(data.global) == "table" and data.global or {}) do
        Variety.global[#Variety.global + 1] = readEntry(e)
    end
    table.sort(Variety.global, byTime)
    for _, p in ipairs(type(data.players) == "table" and data.players or {}) do
        if type(p) == "table" and type(p.account) == "string" and type(p.entries) == "table" then
            local list = {}
            for _, e in ipairs(p.entries) do list[#list + 1] = readEntry(e) end
            table.sort(list, byTime)
            if #list > 0 then Variety.players[p.account] = list end
        end
    end
    Variety.prune()
    Variety.dirty = false
end

function Variety.save()
    Variety.prune()
    local players = {}
    for account, list in pairs(Variety.players) do
        players[#players + 1] = { account = account, entries = list }
    end
    table.sort(players, function(a, b) return a.account < b.account end)
    local json = msmEncodeJSON({ format = FORMAT, global = Variety.global, players = players })
    if msmWriteFile(V.FILE, json) then
        Variety.dirty = false
    else
        msmLog("variety: could not write %s", V.FILE)
    end
end

function Variety.clear()
    Variety.global, Variety.players, Variety.last = {}, {}, nil
    Variety.save()
end

---------------------------------------------------------------- recording

local function summaryEntry(name)
    local s = Storage.summary[name]
    return s and makeEntry(name, s.category, s.center[1], s.center[2], s.interior)
end

addEventHandler("onMedSceneSpawned", resourceRoot, function(_, name)
    local e = summaryEntry(name)
    if not e then return end
    Variety.global[#Variety.global + 1] = e
    Variety.dirty = true
    if #Variety.global > V.GLOBAL_MAX then Variety.prune() end
end)

-- The accounts of the unit that really got the task (once per scene and account)
addEventHandler("onErmTaskAssigned", root, function(taskId, unitId)
    local id = Live.byTask[taskId]
    local scene = id and Live.scenes[id]
    if not scene or not msmResourceRunning(MSM.ERM) then return end
    local unit = exports[MSM.ERM]:getUnitData(unitId)
    if not unit then return end
    scene.varietyAccounts = scene.varietyAccounts or {}
    for _, account in ipairs(unit.accounts or {}) do
        account = tostring(account)
        if account ~= "" and not scene.varietyAccounts[account] then
            scene.varietyAccounts[account] = true
            local e = summaryEntry(scene.name)
            if e then
                local list = Variety.players[account] or {}
                list[#list + 1] = e
                Variety.players[account] = list
                Variety.dirty = true
                if #list > V.PLAYER_MAX then Variety.prune() end
            end
        end
    end
end)

---------------------------------------------------------------- history views

local function cellKey(x, y)
    local size = V.LOCATION_RADIUS
    return math.floor(x / size) .. ":" .. math.floor(y / size)
end

-- Same location: same interior, centres within LOCATION_RADIUS
local function near(e, s, radius)
    if e.interior ~= s.interior then return false end
    local dx, dy = e.x - s.center[1], e.y - s.center[2]
    return dx * dx + dy * dy < radius * radius
end

local function nearAny(list, s, radius)
    for _, e in ipairs(list) do
        if near(e, s, radius) then return true end
    end
    return false
end

-- A history (oldest first) seen through the windows of MSM.VARIETY.GLOBAL / PLAYER
local function profile(list, w)
    local p = { names = {}, locs = {}, spread = {}, lastCats = {}, cats = {}, grid = {} }
    local n = #list
    for k = 1, n do
        local e = list[n - k + 1] -- newest first
        if k <= w.scenes then p.names[e.name] = true end
        if k <= w.locations then p.locs[#p.locs + 1] = e end
        if k <= w.spread then p.spread[#p.spread + 1] = e end
        if k <= w.categoryRepeat and e.category ~= "" then p.lastCats[e.category] = true end
        if k <= w.categoryWindow then p.cats[e.category] = (p.cats[e.category] or 0) + 1 end
        local key = cellKey(e.x, e.y)
        p.grid[key] = p.grid[key] or {}
        table.insert(p.grid[key], e)
    end
    return p
end

-- History of a unit: the entries of all its accounts (one per scene spawn)
local function unitHistory(accounts)
    if #accounts == 1 then return Variety.players[tostring(accounts[1])] or {} end
    local out, seen = {}, {}
    for _, account in ipairs(accounts) do
        for _, e in ipairs(Variety.players[tostring(account)] or {}) do
            local key = e.name .. "@" .. e.time
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = e
            end
        end
    end
    table.sort(out, byTime)
    return out
end

local function accountsKey(accounts)
    local list = {}
    for i, a in ipairs(accounts) do list[i] = tostring(a) end
    table.sort(list)
    return table.concat(list, "\0")
end

---------------------------------------------------------------- rules + weights

local function historyAllows(p, s)
    return not p.names[s.name] and not nearAny(p.locs, s, V.LOCATION_RADIUS)
end

-- { level from which the rule no longer applies, test(scene, global, player | nil) }
local RULES = {
    { 1, function(s, g, p) -- category repeat
        return not g.lastCats[s.category] and not (p and p.lastCats[s.category])
    end },
    { 2, function(s, g) return historyAllows(g, s) end },
    { 3, function(s, _, p) return not p or historyAllows(p, s) end },
    { 4, function(s, g, p) -- geographic spread
        return not nearAny(g.spread, s, V.MIN_SPREAD) and not (p and nearAny(p.spread, s, V.MIN_SPREAD))
    end },
}

local function allowed(s, g, p, level)
    for _, rule in ipairs(RULES) do
        if level < rule[1] and not rule[2](s, g, p) then return false end
    end
    return true
end

-- Decayed number of uses of the scene's location (3x3 grid cells around it)
local function locationUses(p, s, t)
    local size = V.LOCATION_RADIUS
    local cx, cy = math.floor(s.center[1] / size), math.floor(s.center[2] / size)
    local uses = 0
    for ix = cx - 1, cx + 1 do
        for iy = cy - 1, cy + 1 do
            for _, e in ipairs(p.grid[ix .. ":" .. iy] or {}) do
                if near(e, s, size) then
                    uses = uses + 0.5 ^ (math.max(0, t - e.time) / V.LOCATION_HALF_LIFE)
                end
            end
        end
    end
    return uses
end

local function minDistance(s, ...)
    local best
    for _, list in ipairs({ ... }) do
        for _, e in ipairs(list) do
            if e.interior == s.interior then
                local dx, dy = e.x - s.center[1], e.y - s.center[2]
                local d = math.sqrt(dx * dx + dy * dy)
                if not best or d < best then best = d end
            end
        end
    end
    return best
end

local function weight(s, g, p, poolSize, t)
    local cat = s.category
    local w = s.weight * (tonumber(V.CATEGORY_WEIGHT[cat]) or 1)
    -- an uncategorized scene is not a type of its own: it gets the chance of an average scene
    if V.BALANCE_CATEGORIES then w = w / (cat ~= "" and poolSize[cat] or poolSize.average) end

    local catUses = (g.cats[cat] or 0) * V.CATEGORY_K_GLOBAL + (p and (p.cats[cat] or 0) * V.CATEGORY_K_PLAYER or 0)
    w = w / (1 + catUses)

    local locUses = locationUses(g, s, t) + (p and locationUses(p, s, t) or 0)
    w = w / (1 + V.LOCATION_K * locUses)

    local d = minDistance(s, g.spread, p and p.spread or {})
    if d then
        w = w * math.min(1, V.SPREAD_BONUS_MIN + (1 - V.SPREAD_BONUS_MIN) * d / V.SPREAD_BONUS_RANGE)
    end
    return w
end

local function weightedPick(pool, weights, total)
    if total <= 0 then return pool[math.random(#pool)] end
    local roll = math.random() * total
    for i, c in ipairs(pool) do
        roll = roll - weights[i]
        if roll <= 0 and weights[i] > 0 then return c end
    end
    for i = #pool, 1, -1 do
        if weights[i] > 0 then return pool[i] end
    end
end

---------------------------------------------------------------- choose

-- candidates: { { scene = summary, accounts = { account, ... } | nil }, ... } (mandatory
-- checks already passed). accounts = the probable recipient unit's accounts.
-- globalHistory: optional history to use instead of Variety.global (simulation).
-- -> summary, level, pool size | nil
function Variety.choose(candidates, globalHistory)
    if #candidates == 0 then return nil end

    if not V.ENABLED then
        local weights, total = {}, 0
        for i, c in ipairs(candidates) do
            weights[i] = c.scene.weight
            total = total + weights[i]
        end
        return weightedPick(candidates, weights, total).scene, 0, #candidates
    end

    local t = now()
    local g = profile(globalHistory or Variety.global, V.GLOBAL)
    local players, profiles = {}, {}
    for i, c in ipairs(candidates) do
        if not globalHistory and type(c.accounts) == "table" and #c.accounts > 0 then
            local key = accountsKey(c.accounts)
            players[key] = players[key] or profile(unitHistory(c.accounts), V.PLAYER)
            profiles[i] = players[key]
        end
    end

    for level = 0, MAX_LEVEL do
        local pool, poolProfiles, poolSize = {}, {}, {}
        for i, c in ipairs(candidates) do
            if allowed(c.scene, g, profiles[i], level) then
                pool[#pool + 1] = c
                poolProfiles[#pool] = profiles[i]
                poolSize[c.scene.category] = (poolSize[c.scene.category] or 0) + 1
            end
        end
        if #pool > 0 then
            local categories, categorized = 0, 0
            for cat, n in pairs(poolSize) do
                if cat ~= "" then categories, categorized = categories + 1, categorized + n end
            end
            poolSize.average = categories > 0 and categorized / categories or 1
            local weights, total = {}, 0
            for i, c in ipairs(pool) do
                weights[i] = weight(c.scene, g, poolProfiles[i], poolSize, t)
                total = total + weights[i]
            end
            local picked = weightedPick(pool, weights, total)
            return picked.scene, level, #pool
        end
    end
end

---------------------------------------------------------------- lifecycle

addEventHandler("onResourceStart", resourceRoot, function()
    Variety.load()
    setTimer(function()
        Variety.prune()
        if Variety.dirty then Variety.save() end
    end, V.SAVE_INTERVAL * 1000, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if Variety.dirty then Variety.save() end
end)
