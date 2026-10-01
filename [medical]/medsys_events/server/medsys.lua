-- Bridge to the medsys exports, plus what medsys does not store itself: which body part an
-- injury is on and what caused it (InjuryInfo, keyed by the medsys injury id).
--
-- InjuryInfo[element] = { [injuryId] = { type, severity, part, cause, tick } }

InjuryInfo = {}

local KNOCKOUT_RANK = { stable = 1, dazed = 2, unconscious = 3, clinical_death = 4, dead = 5 }

local function medsys()
    local resource = getResourceFromName(MEDEV.MEDSYS)
    if resource and getResourceState(resource) == "running" then
        return exports[MEDEV.MEDSYS]
    end
end

function isMedsysTarget(element)
    if not isElement(element) then return false end
    local elementType = getElementType(element)
    if elementType == "player" then return true end
    return elementType == "ped" and MEDEV.APPLY_TO_PEDS
end

function medGetState(element)
    local ms = medsys()
    return ms and ms:getMedicalState(element) or false
end

local function canHurt(state)
    return state and not state.dead and not state.clinicalDeath
end

-- The details passed to onMedicalInjury while our own applyInjury call runs
local creating

-- Adds a medsys injury and remembers its body part and cause. Returns the injury id or false.
function medApplyInjury(element, injuryType, severity, part, cause)
    local ms = medsys()
    if not ms then return false end
    local state = ms:getMedicalState(element)
    if not canHurt(state) or #state.injuries >= MEDEV.MAX_INJURIES then return false end

    creating = { part = part, cause = cause }
    local id = ms:applyInjury(element, injuryType, severity)
    creating = nil
    if not id then return false end

    triggerEvent("onMedicalEventInjury", element, id, injuryType, severity, part, cause)
    refreshEffects(element)
    return id
end

addEvent("onMedicalInjury", false)
addEvent("onMedicalEventInjury", false)
addEventHandler("onMedicalInjury", root, function(injuryType, severity, id)
    local info = InjuryInfo[source]
    if creating then
        if not info then
            info = {}
            InjuryInfo[source] = info
        end
        info[id] = { type = injuryType, severity = severity, part = creating.part,
            cause = creating.cause, tick = getTickCount() }
    elseif info then
        -- someone else added it: an old entry with the same id is from a previous medical state
        info[id] = nil
    end
end)

-- Pain spike: only raises the pain, never lowers it
function medPain(element, pain)
    local state = medGetState(element)
    if not canHurt(state) or state.pain >= pain then return end
    medsys():setMedicalState(element, "pain", pain)
end

-- Bleeding not tied to an injury (cuts). Only raises the level.
function medBleed(element, level)
    local state = medGetState(element)
    if not canHurt(state) or state.bleeding >= level then return end
    medsys():setMedicalState(element, "bleeding", level)
end

-- SpO2 falls to at most this value (the simulation recovers it)
function medLimitSpO2(element, spo2)
    local state = medGetState(element)
    if not canHurt(state) or state.spo2 <= spo2 then return end
    medsys():setMedicalState(element, "spo2", spo2)
end

-- Forced dazed / unconscious state (medsys keeps it for its KNOCKOUT_TIME)
function medKnockout(element, level)
    local state = medGetState(element)
    if not canHurt(state) or KNOCKOUT_RANK[state.consciousness] >= KNOCKOUT_RANK[level] then return end
    medsys():setMedicalState(element, "consciousness", level)
end

-- Our injuries that still exist in medsys, with their current medsys data:
-- { [injuryId] = { type, severity, treated, part, partLabel, cause, causeLabel } }
-- Stale entries (healed, new medical state) are dropped on the way.
function getInjuryDetails(element)
    local info = InjuryInfo[element]
    if not info then return {} end
    local state = medGetState(element)
    if not state or state.dead then
        InjuryInfo[element] = nil
        return {}
    end

    local current = {}
    for _, injury in ipairs(state.injuries) do current[injury.id] = injury end

    local result, any = {}, false
    for id, entry in pairs(info) do
        local injury = current[id]
        if injury and injury.type == entry.type and injury.severity == entry.severity then
            result[id] = {
                type = entry.type,
                severity = entry.severity,
                treated = injury.treated,
                part = entry.part,
                partLabel = MEDEV_BODYPART_LABELS[entry.part],
                cause = entry.cause,
                causeLabel = MEDEV_CAUSE_LABELS[entry.cause],
            }
            any = true
        else
            info[id] = nil
        end
    end
    if not any then InjuryInfo[element] = nil end
    return result
end

---------------------------------------------------------------------------
-- Players have no clinical death: the death is final, nobody can do CPR on them
---------------------------------------------------------------------------

addEvent("onMedicalCardiacArrest", false)
addEventHandler("onMedicalCardiacArrest", root, function()
    if not MEDEV.PLAYER_DEATH_IS_FINAL or getElementType(source) ~= "player" then return end
    local player = source
    setTimer(function()
        if not isElement(player) then return end
        local state = medGetState(player)
        if state and state.clinicalDeath then
            medsys():setMedicalState(player, "consciousness", "dead") -- kills the player
        end
    end, math.max(50, MEDEV.PLAYER_ARREST_DEATH_DELAY), 1)
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local function forget()
    InjuryInfo[source] = nil
    clearEffects(source)
end
addEventHandler("onPlayerQuit", root, forget)
addEventHandler("onElementDestroy", root, function()
    if InjuryInfo[source] then forget() end
end)
-- a new spawn is a new body (medsys resets the medical state too)
addEventHandler("onPlayerSpawn", root, forget)
addEventHandler("onPlayerWasted", root, forget)
addEventHandler("onPedWasted", root, function() InjuryInfo[source] = nil end)
