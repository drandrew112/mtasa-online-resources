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

-- One hit (onPlayerDamage / onPedDamage, or a lethal ped hit the clients cancelled) -> the rules
function processDamage(element, weapon, bodypart, loss)
    if not isMedsysTarget(element) or not loss or loss <= 0 then return end
    local cause = MEDEV_WEAPONS[weapon]
    if not cause then return end
    -- players hit by a vehicle get no medical status / bleeding (peds still do)
    if cause == "vehicle_hit" and getElementType(element) == "player" then return end

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

local function onDamage(_, weapon, bodypart, loss)
    processDamage(source, weapon, bodypart, loss)
end
addEventHandler("onPlayerDamage", root, onDamage)
addEventHandler("onPedDamage", root, onDamage)

---------------------------------------------------------------------------
-- Peds do not die from GTA damage (MEDEV.PED_SAVE_LETHAL): the clients cancel the lethal hit
-- (client/detect.lua) and one of them reports it here; the ped goes down in medsys instead
---------------------------------------------------------------------------

local function goDown(ped, cause, part)
    if not isElement(ped) or isPedDead(ped) then return end
    local chances = MEDEV.PED_LETHAL_ARREST
    local key = (cause == "gun" and part == "head") and "gun_head" or cause
    if math.random() < (chances[key] or chances.default or 0) then
        medArrest(ped)
    else
        medKnockout(ped, "unconscious")
    end
end

-- the reporter has to be the attacker's client (its player, vehicle or a ped it syncs), or the ped's syncer
local function isReporter(player, ped, attacker)
    if not isElement(attacker) then return getElementSyncer(ped) == player end
    if attacker == player then return true end
    local attackerType = getElementType(attacker)
    if attackerType == "vehicle" then return getVehicleController(attacker) == player end
    if attackerType == "ped" then return getElementSyncer(attacker) == player end
    return false
end

addEvent("medev:pedLethal", true)
addEventHandler("medev:pedLethal", resourceRoot, function(ped, attacker, weapon, bodypart, loss)
    if not MEDEV.PED_SAVE_LETHAL or not isElement(ped) or getElementType(ped) ~= "ped" then return end
    if not getElementData(ped, MEDEV.DATA_SAVE_LETHAL) then return end
    if not isMedsysTarget(ped) or isPedDead(ped) then return end
    local state = medGetState(ped)
    if not state or state.dead or not isReporter(client, ped, attacker) then return end
    local px, py, pz = getElementPosition(ped)
    local cx, cy, cz = getElementPosition(client)
    if getDistanceBetweenPoints3D(px, py, pz, cx, cy, cz) > 150 then return end

    weapon, bodypart = tonumber(weapon) or 0, tonumber(bodypart) or 3
    loss = math.min(tonumber(loss) or 0, 200)
    if getElementHealth(ped) > MEDEV.PED_DOWN_HEALTH then setElementHealth(ped, MEDEV.PED_DOWN_HEALTH) end
    processDamage(ped, weapon, bodypart, loss)
    local cause, part = MEDEV_WEAPONS[weapon], MEDEV_BODYPARTS[bodypart]
    -- after the rules (they run MEDEV.DEFER later)
    setTimer(function() goDown(ped, cause, part) end, MEDEV.DEFER + 20, 1)
end)

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
