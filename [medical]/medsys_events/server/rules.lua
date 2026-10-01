-- Rule engine: picks the tier for a measured value and applies it through the medsys bridge.

local SIDES = { leg = { "left_leg", "right_leg" }, arm = { "left_arm", "right_arm" } }

local function roll(chance)
    return chance and chance > 0 and math.random() < chance
end

local function rollSeverity(range)
    return math.random(range[1], range[2] or range[1])
end

-- The highest tier whose min is at or below the value, or nil
function pickTier(tiers, value)
    local picked
    for _, tier in ipairs(tiers or {}) do
        if value >= (tier.min or 0) then picked = tier end
    end
    return picked
end

-- "hit" -> the hit part, "leg" / "arm" -> a random side not used yet in this event
local function resolvePart(part, hitPart, used)
    if part == "hit" then return hitPart or "torso" end
    local sides = SIDES[part]
    if not sides then return part end
    local first = math.random(1, 2)
    for i = 0, 1 do
        local side = sides[(first + i - 1) % 2 + 1]
        if not used[side] then return side end
    end
    return nil -- both sides are already hurt by this event
end

-- Applies one tier. hitPart: the body part that was hit (for part = "hit"), may be nil
function applyTier(element, tier, cause, hitPart)
    if not tier or not isElement(element) or isPedDead(element) then return end

    local used = {}
    for _, rule in ipairs(tier.injuries or {}) do
        if roll(rule.chance) then
            local part = resolvePart(rule.part, hitPart, used)
            if part then
                used[part] = true
                medApplyInjury(element, rule.type, rollSeverity(rule.severity), part, cause)
            end
        end
    end

    if tier.bleeding then medBleed(element, tier.bleeding) end
    if tier.spo2 then medLimitSpO2(element, tier.spo2) end
    if tier.pain then medPain(element, tier.pain) end

    if tier.health and tier.health > 0 then
        -- extra damage where GTA does not hurt (crashes); it never kills on its own
        setElementHealth(element, math.max(1, getElementHealth(element) - tier.health))
    end

    local knockout = tier.knockout
    if knockout then
        if roll(knockout.unconscious) then
            medKnockout(element, "unconscious")
        elseif roll(knockout.dazed) then
            medKnockout(element, "dazed")
        end
    end
end

-- Cooldowns: lastRun[element][key] = tick
local lastRun = {}

function checkCooldown(element, key, ms)
    if not ms then return true end
    local now = getTickCount()
    local runs = lastRun[element]
    if not runs then
        runs = {}
        lastRun[element] = runs
    end
    if runs[key] and now - runs[key] < ms then return false end
    runs[key] = now
    return true
end

local function forget()
    lastRun[source] = nil
end
addEventHandler("onPlayerQuit", root, forget)
addEventHandler("onElementDestroy", root, forget)
