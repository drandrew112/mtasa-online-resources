-- Work levels. Every work has its own XP and level per account; the level is derived from the
-- XP. Works use it as a progression: giveWorkXp() after a job, hasWorkLevel() to gate rights
-- (for example work_atc positions), skin `level` in registerWork() to lock outfits.
--
-- Storage: one JSON object { [workId] = xp } in account data (WORK_DATA.LEVEL_STORAGE) through
-- v_mysql. Only logged in players have progress. The client reads it from the synced element
-- data WORK_DATA.PLAYER_LEVELS.
--
-- Events (source = the player):
--   onPlayerWorkXpGain (workId, amount, totalXp)
--   onPlayerWorkLevelChange (workId, newLevel, oldLevel)   level up (or set by an admin)

addEvent("onPlayerWorkXpGain")
addEvent("onPlayerWorkLevelChange")

local progress = {}                -- player -> { [workId] = xp }

local function isLogged(player)
    return isElement(player) and getElementType(player) == "player" and getElementData(player, "isLogged") == true
end

---------------------------------------------------------------- level maths

-- Total XP needed to reach `level` in this work (level 1 = 0)
function getWorkLevelXp(workId, level)
    local w = Works[workId]
    if not w then return false end
    level = math.min(math.max(1, math.floor(tonumber(level) or 1)), w.levels.maxLevel)
    local total = 0
    for i = 1, level - 1 do total = total + w.levels.baseXp + (i - 1) * w.levels.stepXp end
    return total
end

local function levelOf(w, xp)
    local lv, need = 1, 0
    while lv < w.levels.maxLevel do
        local nextNeed = need + w.levels.baseXp + (lv - 1) * w.levels.stepXp
        if xp < nextNeed then break end
        need, lv = nextNeed, lv + 1
    end
    return lv
end

function skinLevel(work, model)
    for _, s in ipairs(work.skins) do
        if s.model == model then return s.level or 1 end
    end
    return 1
end

---------------------------------------------------------------- load / save / sync

local function decode(s)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    local ok, t = pcall(fromJSON, s)
    if not ok or type(t) ~= "table" then return out end
    for id, xp in pairs(t) do
        xp = tonumber(xp)
        if type(id) == "string" and xp and xp > 0 then out[id] = math.floor(xp) end
    end
    return out
end

local function save(player)
    local p = progress[player]
    if p and isLogged(player) then
        exports.v_mysql:setAccData(player, WORK_DATA.LEVEL_STORAGE, toJSON(p, true))
    end
end

local function sync(player)
    local p = progress[player]
    if not p or not isElement(player) then return end
    local t = {}
    for id, w in pairs(Works) do
        local xp = p[id] or 0
        local lv = levelOf(w, xp)
        t[id] = { level = lv, xp = xp, from = getWorkLevelXp(id, lv),
                  to = lv < w.levels.maxLevel and getWorkLevelXp(id, lv + 1) or false }
    end
    setElementData(player, WORK_DATA.PLAYER_LEVELS, t)
end

local function load(player)
    if not isLogged(player) then return end
    progress[player] = decode(exports.v_mysql:getAccData(player, WORK_DATA.LEVEL_STORAGE))
    sync(player)
end

addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function() load(source) end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do load(p) end
end)

addEventHandler("onPlayerQuit", root, function()
    save(source)
    progress[source] = nil
end)

-- called by the registry whenever the set of works (and so the level tables) changes
function resyncAllLevels()
    for p in pairs(progress) do sync(p) end
end

---------------------------------------------------------------- exports

-- -> level (1 when the player has no progress / unknown work)
function getPlayerWorkLevel(player, workId)
    local w, p = Works[workId], progress[player]
    if not w or not p then return 1 end
    return levelOf(w, p[workId] or 0)
end

function getPlayerWorkXp(player, workId)
    local p = progress[player]
    return p and p[workId] or 0
end

-- Name of the highest named level at or below the player's level, or false
function getPlayerWorkLevelName(player, workId)
    local w = Works[workId]
    if not w then return false end
    local lv, best = getPlayerWorkLevel(player, workId), nil
    for k in pairs(w.levels.names) do
        if k <= lv and (not best or k > best) then best = k end
    end
    return best and w.levels.names[best] or false
end

-- hasWorkLevel(player, workId, level) -> bool. Use this for rights.
function hasWorkLevel(player, workId, level)
    return getPlayerWorkLevel(player, workId) >= (tonumber(level) or 1)
end

-- -> { level, xp, from, to (false at max level), maxLevel, name } | false
function getWorkLevelInfo(player, workId)
    local w = Works[workId]
    if not w or not isElement(player) then return false end
    local xp = getPlayerWorkXp(player, workId)
    local lv = levelOf(w, xp)
    return { level = lv, xp = xp, from = getWorkLevelXp(workId, lv),
             to = lv < w.levels.maxLevel and getWorkLevelXp(workId, lv + 1) or false,
             maxLevel = w.levels.maxLevel, name = getPlayerWorkLevelName(player, workId) }
end

local function applyXp(player, workId, newXp, silent)
    local w, p = Works[workId], progress[player]
    local oldLevel = levelOf(w, p[workId] or 0)
    p[workId] = newXp > 0 and newXp or nil
    local newLevel = levelOf(w, newXp)
    save(player)
    sync(player)
    if newLevel ~= oldLevel then
        if not silent and newLevel > oldLevel then
            local lvName = getPlayerWorkLevelName(player, workId)
            notifyPlayer(player, w.name, ("Level up! You reached level %d%s."):format(newLevel,
                lvName and (" · " .. lvName) or ""))
        end
        triggerEvent("onPlayerWorkLevelChange", player, workId, newLevel, oldLevel)
    end
end

-- giveWorkXp(player, workId, amount) -> true, newLevel | false, errorText
-- Only positive amounts (use setPlayerWorkXp to lower). XP past the max level is kept but does
-- nothing more.
function giveWorkXp(player, workId, amount)
    amount = tonumber(amount)
    if not Works[workId] then return false, "unknown work" end
    if not amount or amount < 1 then return false, "bad amount" end
    if not isLogged(player) or not progress[player] then return false, "player not logged in" end
    amount = math.min(math.floor(amount), WORK.MAX_XP_PER_GRANT)
    local total = (progress[player][workId] or 0) + amount
    notifyPlayer(player, Works[workId].name, ("+%d XP"):format(amount))
    applyXp(player, workId, total)
    triggerEvent("onPlayerWorkXpGain", player, workId, amount, total)
    return true, getPlayerWorkLevel(player, workId)
end

function setPlayerWorkXp(player, workId, xp)
    xp = tonumber(xp)
    if not Works[workId] then return false, "unknown work" end
    if not xp or xp < 0 then return false, "bad xp" end
    if not isLogged(player) or not progress[player] then return false, "player not logged in" end
    applyXp(player, workId, math.floor(xp), true)
    return true
end

function setPlayerWorkLevel(player, workId, level)
    level = tonumber(level)
    if not level then return false, "bad level" end
    local xp = getWorkLevelXp(workId, level)
    if not xp then return false, "unknown work" end
    return setPlayerWorkXp(player, workId, xp)
end

---------------------------------------------------------------- admin commands

local function isAdmin(player)
    return isLogged(player)
        and (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= WORK.ADMIN_LEVEL
end

local function reply(player, text)
    outputConsole("[work] " .. text, player)
end

-- /giveworkxp <player> <workId> <xp>
addCommandHandler("giveworkxp", function(admin, _, name, workId, amount)
    if not isAdmin(admin) then return end
    local target = name and getPlayerFromName(name)
    if not (target and workId and amount) then return reply(admin, "usage: /giveworkxp <player> <workId> <xp>") end
    local ok, res = giveWorkXp(target, workId, amount)
    reply(admin, ok and ("XP given, level is now " .. res) or ("failed: " .. tostring(res)))
end)

-- /setworklevel <player> <workId> <level>
addCommandHandler("setworklevel", function(admin, _, name, workId, level)
    if not isAdmin(admin) then return end
    local target = name and getPlayerFromName(name)
    if not (target and workId and level) then return reply(admin, "usage: /setworklevel <player> <workId> <level>") end
    local ok, res = setPlayerWorkLevel(target, workId, level)
    reply(admin, ok and "level set" or ("failed: " .. tostring(res)))
end)
