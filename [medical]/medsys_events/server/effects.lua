-- Effects of the injuries on the player's controls (MEDEV_EFFECTS), e.g. a broken leg: no
-- sprint / jump, a splinted one: no sprint. Recomputed when an injury is added, after a
-- treatment, and on a timer (medsys has no event for healCompletely).

addEvent("medev:effects", true)

local sent = {} -- player -> key of the control list last sent

local function partMatches(effectPart, part)
    return effectPart == part or effectPart == MEDEV_PART_GROUP[part]
end

local function collectControls(player)
    local set = {}
    for _, injury in pairs(getInjuryDetails(player)) do
        for _, effect in ipairs(MEDEV_EFFECTS) do
            if effect.type == injury.type and partMatches(effect.part, injury.part) then
                for _, control in ipairs((injury.treated and effect.treated or effect.untreated) or {}) do
                    set[control] = true
                end
            end
        end
    end
    local list = {}
    for control in pairs(set) do list[#list + 1] = control end
    table.sort(list)
    return list
end

local function send(player, list)
    local key = table.concat(list, ",")
    if (sent[player] or "") == key then return end
    sent[player] = key ~= "" and key or nil
    triggerClientEvent(player, "medev:effects", resourceRoot, list)
end

function refreshEffects(element)
    if not isElement(element) or getElementType(element) ~= "player" then return end
    if isPedDead(element) then
        clearEffects(element)
        return
    end
    send(element, collectControls(element))
end

function clearEffects(element)
    if sent[element] and isElement(element) and getElementType(element) == "player" then
        triggerClientEvent(element, "medev:effects", resourceRoot, {})
    end
    sent[element] = nil
end

addEvent("onMedicalTreatment", false)
addEventHandler("onMedicalTreatment", root, function()
    if InjuryInfo[source] then refreshEffects(source) end
end)

setTimer(function()
    for element in pairs(InjuryInfo) do refreshEffects(element) end
    -- players whose injuries are gone (healed) still have to be released
    for player in pairs(sent) do
        if not InjuryInfo[player] then refreshEffects(player) end
    end
end, MEDEV.EFFECT_CHECK, 0)

addEventHandler("onPlayerQuit", root, function()
    sent[source] = nil
end)
