-- Damage events -> injuries. GTA still takes the health, these rules add the medical side:
-- falls, gunshots, melee, explosions, fire, drowning, tear gas, being run over.

-- Damage that comes in ticks (fire, drowning, gas) is summed into an episode:
-- episodes[element][cause] = { total, timer }
local episodes = {}

local function finishEpisode(element, cause)
    local list = episodes[element]
    local episode = list and list[cause]
    if not episode then return end
    list[cause] = nil
    if isElement(element) and not isPedDead(element) then
        applyTier(element, pickTier(MEDEV_RULES[cause], episode.total), cause)
    end
end

local function addToEpisode(element, cause, loss)
    local list = episodes[element]
    if not list then
        list = {}
        episodes[element] = list
    end
    local episode = list[cause]
    if not episode then
        episode = { total = 0 }
        list[cause] = episode
    end
    episode.total = episode.total + loss
    if isTimer(episode.timer) then killTimer(episode.timer) end
    episode.timer = setTimer(finishEpisode, MEDEV_EPISODES[cause].gap, 1, element, cause)
end

-- armored: a torso hit while wearing a vest (the vest stops the bullet)
local function runHit(element, cause, part, loss, armored)
    local group = MEDEV_PART_GROUP[part] or "torso"
    if not checkCooldown(element, cause .. ":" .. group, MEDEV_COOLDOWN[cause]) then return end

    local rules = MEDEV_RULES[cause]
    local tiers = rules and rules[group]
    if cause == "gun" and group == "torso" and armored then
        tiers = MEDEV_RULES.gunArmored
    end
    applyTier(element, pickTier(tiers, loss), cause, part)
end

local function runSimple(element, cause, loss)
    if not checkCooldown(element, cause, MEDEV_COOLDOWN[cause]) then return end
    applyTier(element, pickTier(MEDEV_RULES[cause], loss), cause)
end

local HIT_CAUSES = { gun = true, fist = true, blunt = true, sharp = true }

local function onDamage(attacker, weapon, bodypart, loss)
    local element = source
    if not isMedsysTarget(element) or not loss or loss <= 0 then return end
    local cause = MEDEV_WEAPONS[weapon]
    if not cause then return end

    if MEDEV_EPISODES[cause] then
        addToEpisode(element, cause, loss)
        return
    end

    -- armor is read now: after the hit it may already be 0
    local armored = getPedArmor(element) > 0
    local part = MEDEV_BODYPARTS[bodypart] or "torso"
    -- run after the damage is applied, so a hit that killed is skipped
    setTimer(function()
        if not isElement(element) or isPedDead(element) then return end
        if HIT_CAUSES[cause] then
            runHit(element, cause, part, loss, armored)
        else
            runSimple(element, cause, loss)
        end
    end, MEDEV.DEFER, 1)
end
addEventHandler("onPlayerDamage", root, onDamage)
addEventHandler("onPedDamage", root, onDamage)

local function forget()
    local list = episodes[source]
    if not list then return end
    for _, episode in pairs(list) do
        if isTimer(episode.timer) then killTimer(episode.timer) end
    end
    episodes[source] = nil
end
addEventHandler("onPlayerQuit", root, forget)
addEventHandler("onElementDestroy", root, forget)
addEventHandler("onPlayerWasted", root, forget)
addEventHandler("onPedWasted", root, forget)
