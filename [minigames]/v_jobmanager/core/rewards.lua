-- End-of-match payouts. Cash + XP are computed from the game's own data (route
-- length, player count, placement / kills), paid on the server the moment the
-- match ends, and sent to the client for the results screen
-- (core/client/results.lua) that plays before the scoreboard.
--
-- Per-game multipliers are runtime only (never persisted) and always apply to
-- the final total. Other resources (v_weekly) set them via the exports below.

REWARDS = {
    soloMoney = 500,                -- fixed cash when the match started with one player
    race = { perKm = 200, minBase = 300, maxBase = 3000 },
    deathmatch = { perMinute = 120, maxMinutes = 15, minBase = 200, maxBase = 1800, perKill = 150 },
    playerBonus = 0.05,             -- x(1 + playerBonus * (players - 1)) ...
    playerBonusMax = 1.5,           -- ... capped here
    place = { 1.5, 1.25, 1.1 },     -- money multiplier by place, others x1.0
    dnf = 0.25,                     -- race not finished
    xp = { participation = 100, finished = 80, perKill = 25, place = { 160, 100, 50 } },
}

--------------------------------------------------------------------------------
-- runtime multipliers: jobId -> { money, xp, label }
--------------------------------------------------------------------------------

local multipliers = {}

-- money / xp default to 1; setting both to 1 removes the entry.
function jobmanagerSetMultiplier(jobId, money, xp, label)
    if type(jobId) ~= "string" or jobId == "" then return false end
    money, xp = tonumber(money) or 1, tonumber(xp) or 1
    if money < 0 or xp < 0 then return false end
    if money == 1 and xp == 1 then
        multipliers[jobId] = nil
    else
        multipliers[jobId] = { money = money, xp = xp, label = type(label) == "string" and label ~= "" and label or "Bonus" }
    end
    return true
end

-- -> money, xp, label|false
function jobmanagerGetMultiplier(jobId)
    local m = multipliers[jobId]
    if not m then return 1, 1, false end
    return m.money, m.xp, m.label
end

-- -> { [jobId] = { money, xp, label } }
function jobmanagerGetMultipliers()
    local copy = {}
    for jobId, m in pairs(multipliers) do copy[jobId] = { money = m.money, xp = m.xp, label = m.label } end
    return copy
end

function jobmanagerClearMultiplier(jobId)
    multipliers[jobId] = nil
    return true
end

function jobmanagerClearMultipliers()
    multipliers = {}
    return true
end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function round(v) return math.floor(v + 0.5) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function euro(v)
    local s = tostring(round(v))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return "€" .. out
end

local function mult(v)
    return "x" .. (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function ordinal(n)
    local suffix = "th"
    if n % 100 < 11 or n % 100 > 13 then
        suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
    end
    return n .. suffix
end

local function dist(a, b)
    return getDistanceBetweenPoints3D(a[1], a[2], a[3], b[1], b[2], b[3])
end

-- spawn -> checkpoints -> finish, in km
local function routeKm(race)
    local points = {}
    if race.spawnpoints and race.spawnpoints[1] then table.insert(points, race.spawnpoints[1]) end
    for _, cp in ipairs(race.checkpoints or {}) do table.insert(points, cp) end
    if race.finish then table.insert(points, race.finish) end
    local total = 0
    for i = 2, #points do total = total + dist(points[i - 1], points[i]) end
    return total / 1000
end

-- Survivor first, then kills desc, deaths asc (same order the scoreboard shows).
local function dmPlaces(match)
    local order = {}
    for _, player in ipairs(match.players) do table.insert(order, player) end
    table.sort(order, function(a, b)
        local aw, bw = not match.eliminated[a], not match.eliminated[b]
        if aw ~= bw then return aw end
        local ak, bk = match.kills[a] or 0, match.kills[b] or 0
        if ak ~= bk then return ak > bk end
        return (match.deaths[a] or 0) < (match.deaths[b] or 0)
    end)
    local places = {}
    for place, player in ipairs(order) do places[player] = place end
    return places
end

local function levelsysReady()
    local res = getResourceFromName("v_levelsys")
    return res and getResourceState(res) == "running"
end

-- Cumulative XP needed to leave `level`. Asks v_levelsys; falls back to a copy
-- of its formula (1000 + 600 * (1 + ... + level)) when the export is missing,
-- e.g. v_levelsys was not restarted after getNextXp got exported.
local function nextXp(level)
    local ok, value = pcall(function() return exports.v_levelsys:getNextXp(level) end)
    if ok and tonumber(value) then return tonumber(value) end
    if level <= 0 then return 0 end
    return 1000 + 600 * level * (level + 1) / 2
end

--------------------------------------------------------------------------------
-- computing
--------------------------------------------------------------------------------

local function computeOne(match, player, ctx)
    local job = match.job
    local isRace = job.type == JOB_TYPE_RACE
    local players = match.startPlayers or #match.players
    local solo = players <= 1
    local place, finished
    if isRace then
        place = ctx.racePlace[player] or false
        finished = place and true or false
    else
        place, finished = ctx.dmPlace[player], true
    end

    local moneyLines, xpLines = {}, {}
    local money, xp = 0, REWARDS.xp.participation
    table.insert(xpLines, { "Participation", "+" .. REWARDS.xp.participation })

    if solo then
        money = REWARDS.soloMoney
        table.insert(moneyLines, { "Solo game", euro(money) })
    else
        if isRace then
            local cfg, km = REWARDS.race, ctx.km
            money = clamp(round(km * cfg.perKm), cfg.minBase, cfg.maxBase)
            table.insert(moneyLines, { string.format("Route %.1f km", km), euro(money) })
        else
            local cfg = REWARDS.deathmatch
            local minutes = math.min(ctx.minutes, cfg.maxMinutes)
            money = clamp(round(minutes * cfg.perMinute), cfg.minBase, cfg.maxBase)
            table.insert(moneyLines, { string.format("Match %d min", math.max(1, round(minutes))), euro(money) })
            local kills = match.kills[player] or 0
            if kills > 0 then
                money = money + kills * cfg.perKill
                table.insert(moneyLines, { kills .. (kills == 1 and " kill" or " kills"), "+" .. euro(kills * cfg.perKill) })
            end
        end
        local pf = math.min(1 + REWARDS.playerBonus * (players - 1), REWARDS.playerBonusMax)
        money = money * pf
        table.insert(moneyLines, { players .. " players", mult(pf) })
        local pm = finished and (REWARDS.place[place] or 1) or REWARDS.dnf
        money = money * pm
        if pm ~= 1 then
            table.insert(moneyLines, { finished and (ordinal(place) .. " place") or "Not finished", mult(pm) })
        end
    end

    if isRace and finished then
        xp = xp + REWARDS.xp.finished
        table.insert(xpLines, { "Finished", "+" .. REWARDS.xp.finished })
    end
    if not isRace and (match.kills[player] or 0) > 0 then
        local k = match.kills[player]
        xp = xp + k * REWARDS.xp.perKill
        table.insert(xpLines, { k .. (k == 1 and " kill" or " kills"), "+" .. (k * REWARDS.xp.perKill) })
    end
    if not solo and finished and REWARDS.xp.place[place] then
        xp = xp + REWARDS.xp.place[place]
        table.insert(xpLines, { ordinal(place) .. " place", "+" .. REWARDS.xp.place[place] })
    end

    local mMoney, mXp, mLabel = jobmanagerGetMultiplier(job.id)
    if mMoney ~= 1 then table.insert(moneyLines, { mLabel, mult(mMoney) }) end
    if mXp ~= 1 then table.insert(xpLines, { mLabel, mult(mXp) }) end

    return {
        place = place, players = players, solo = solo, finished = finished,
        timeMs = isRace and match.finishTime[player] or false,
        kills = match.kills[player] or 0, deaths = match.deaths[player] or 0,
        money = { total = round(money * mMoney), lines = moneyLines },
        xp = { total = round(xp * mXp), lines = xpLines },
    }
end

-- -> { [player] = reward }
function buildRewards(match)
    local ctx = { racePlace = {} }
    if match.job.type == JOB_TYPE_RACE then
        for place, player in ipairs(match.finishOrder) do ctx.racePlace[player] = place end
        ctx.km = routeKm(match.job.race or {})
    else
        ctx.dmPlace = dmPlaces(match)
        ctx.minutes = (getTickCount() - (match.startTick or getTickCount())) / 60000
    end
    local rewards = {}
    for _, player in ipairs(match.players) do
        if isElement(player) then rewards[player] = computeOne(match, player, ctx) end
    end
    return rewards
end

-- Pays cash + XP and attaches the level progression the client animates:
-- reward.level = { xpFrom, xpTo, steps = { {level, min, max}, ... } }
function payReward(player, reward)
    if not isElement(player) then return end
    if reward.money.total > 0 then givePlayerMoney(player, reward.money.total) end

    if not levelsysReady() then return end
    local level, xpFrom = tonumber(getElementData(player, "level")), tonumber(getElementData(player, "xp"))
    if not level or not xpFrom or level < 1 then return end
    if reward.xp.total > 0 and not exports.v_levelsys:giveXp(player, reward.xp.total) then return end
    local levelTo = tonumber(getElementData(player, "level")) or level
    local steps = {}
    for lv = level, math.max(level, levelTo) do
        table.insert(steps, { level = lv, min = nextXp(lv - 1), max = nextXp(lv) })
    end
    reward.level = { xpFrom = xpFrom, xpTo = tonumber(getElementData(player, "xp")) or xpFrom, steps = steps }
end
