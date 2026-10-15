-- What a player has seen of the introduction, in their account data (v_mysql).
--   intro.seen      JSON { moduleId = version }
--   intro.rewarded  JSON { moduleId = xp given }
--   intro.done      true once the full introduction was finished
--   intro.rules     accepted INTRO.RULES_VERSION
-- `who` is a player element or an account name (offline reset).

Progress = {}

local function getData(who, key) return exports.v_mysql:getAccData(who, key) end
local function setData(who, key, value) return exports.v_mysql:setAccData(who, key, value) end

local function readMap(who, key)
    local raw = getData(who, key)
    if type(raw) ~= "string" or raw == "" then return {} end
    local t = fromJSON(raw)
    return type(t) == "table" and t or {}
end

local function writeMap(who, key, t)
    setData(who, key, toJSON(t, true))
end

function Progress.getSeen(who) return readMap(who, INTRO.ACC_SEEN) end
function Progress.getRewarded(who) return readMap(who, INTRO.ACC_REWARDED) end
function Progress.getSkipped(who) return readMap(who, INTRO.ACC_SKIPPED) end
function Progress.isDone(who) return getData(who, INTRO.ACC_DONE) == true end

function Progress.markSeen(who, id, version)
    local seen = Progress.getSeen(who)
    seen[id] = version
    writeMap(who, INTRO.ACC_SEEN, seen)
end

function Progress.markSeenMany(who, defs)
    if #defs == 0 then return end
    local seen = Progress.getSeen(who)
    for _, def in ipairs(defs) do seen[def.id] = def.version end
    writeMap(who, INTRO.ACC_SEEN, seen)
end

-- A skipped module counts as seen (it is not shown again) but gives no XP
function Progress.markSkipped(who, id, version)
    local skipped = Progress.getSkipped(who)
    skipped[id] = version
    writeMap(who, INTRO.ACC_SKIPPED, skipped)
    Progress.markSeen(who, id, version)
end

-- -> XP to give now (0 when this module was rewarded before)
function Progress.reward(who, def)
    local rewarded = Progress.getRewarded(who)
    if rewarded[def.id] then return 0 end
    local xp = def.xp
    if def.final then
        -- makes up for main-line modules that cannot run now (their resource is stopped), so
        -- the total stays INTRO.REWARD_TOTAL_XP; modules the player skipped are not made up
        local available = 0
        for _, other in ipairs(Intro.available("main")) do available = available + other.xp end
        xp = def.xp + math.max(0, INTRO.REWARD_TOTAL_XP - available)
    end
    rewarded[def.id] = xp
    writeMap(who, INTRO.ACC_REWARDED, rewarded)
    return xp
end

function Progress.setDone(who) setData(who, INTRO.ACC_DONE, true) end
function Progress.setRules(who, version) setData(who, INTRO.ACC_RULES, version) end

-- Forget everything (the XP already given stays with the player and is not given again,
-- unless `rewards` is true)
function Progress.reset(who, rewards)
    local d = { [INTRO.ACC_SEEN] = "{}", [INTRO.ACC_SKIPPED] = "{}", [INTRO.ACC_DONE] = false, [INTRO.ACC_RULES] = 0 }
    if rewards then d[INTRO.ACC_REWARDED] = "{}" end
    setData(who, d)
end
