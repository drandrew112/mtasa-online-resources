-- Watches the medical state of every patient (elements with medsys's "medic.status" data).
--   * every patient (player / ped): the forced animation key goes to element data (MEDFX.DATA_ANIM),
--     every client plays it on the elements it streams (client/anim.lua)
--   * players: their own condition is sent to them (client/effects.lua) and the walking style is set
--
-- Tracked[element] = true while the element has a medical status

Tracked = {}

addEvent("medfx:state", true)  -- server -> player: own condition (nil = healthy)
addEvent("medfx:hit", true)    -- server -> player: a new injury arrived (screen flash)

local sent = {}       -- player -> { key, deathEnd } of the last payload
local walking = {}    -- player -> { original = style, current = style }
TestParts = {}        -- player -> { [injuryId] = part } (injuries of the test module)

local function resourceRunning(name)
    local resource = getResourceFromName(name)
    return resource and getResourceState(resource) == "running"
end

function medsys()
    return resourceRunning(MEDFX.MEDSYS) and exports[MEDFX.MEDSYS] or nil
end

---------------------------------------------------------------------------
-- Forced animation key
---------------------------------------------------------------------------

local function animKeyFor(element, status)
    if not status or isPedDead(element) then return nil end
    local elementType = getElementType(element)
    local byState = MEDFX_STATE_ANIM[elementType]
    local key = byState and byState[status] or nil
    -- struggling for air while up: bent over and panting (the confused sway gives way to it)
    if (status == "stable" or status == "confused") and MEDFX_DYSPNEA[getElementData(element, MEDFX.DATA_BREATH)] then
        key = MEDFX_DYSPNEA_ANIM[elementType] or key
    end
    return key
end

local function updateAnim(element)
    if not isElement(element) then return end
    local key = animKeyFor(element, getElementData(element, MEDFX.DATA_STATUS))
    if getElementData(element, MEDFX.DATA_ANIM) == key then return end
    if key then
        setElementData(element, MEDFX.DATA_ANIM, key)
    else
        removeElementData(element, MEDFX.DATA_ANIM)
    end
end

---------------------------------------------------------------------------
-- Walking style (server side, so everybody sees it)
---------------------------------------------------------------------------

local function setWalk(player, style)
    local w = walking[player]
    if style then
        if not w then
            w = { original = getPedWalkingStyle(player) or 0 }
            walking[player] = w
        end
        if w.current ~= style then
            w.current = style
            setPedWalkingStyle(player, style)
        end
    elseif w then
        walking[player] = nil
        if isElement(player) then setPedWalkingStyle(player, w.original) end
    end
end

---------------------------------------------------------------------------
-- The player's own condition
---------------------------------------------------------------------------

-- body part of every injury: medsys_events knows the ones it made, the test module its own
local function injuryParts(player)
    local parts = {}
    if resourceRunning(MEDFX.EVENTS) then
        local details = exports[MEDFX.EVENTS]:getInjuryDetails(player)
        if type(details) == "table" then
            for id, detail in pairs(details) do parts[id] = detail.part end
        end
    end
    for id, part in pairs(TestParts[player] or {}) do parts[id] = part end
    return parts
end

-- controls + walking style from the injuries (MEDFX_INJURY_EFFECTS)
local function injuryEffects(player, snapshot)
    local parts = injuryParts(player)
    local controls, walk = {}, nil
    for _, injury in ipairs(snapshot.injuries) do
        local part = parts[injury.id]
        for _, effect in ipairs(MEDFX_INJURY_EFFECTS) do
            if effect.type == injury.type and medfxPartMatches(effect.part, part) then
                local e = injury.treated and effect.treated or effect.untreated
                if e then
                    for _, control in ipairs(e.controls or {}) do controls[control] = true end
                    walk = walk or e.walk
                end
            end
        end
    end
    local list = {}
    for control in pairs(controls) do list[#list + 1] = control end
    table.sort(list)
    return list, walk
end

local function sendState(player, payload)
    local last = sent[player]
    if not payload then
        if last then
            sent[player] = nil
            triggerClientEvent(player, "medfx:state", resourceRoot, nil)
        end
        return
    end

    local key = table.concat({ payload.status, payload.pain, payload.bleeding, payload.spo2,
        payload.blood, table.concat(payload.controls, ",") }, "|")
    local deathEnd = payload.deathLeft and getTickCount() + payload.deathLeft * 1000 or nil
    local deathMoved = (deathEnd == nil) ~= (last and last.deathEnd == nil)
        or (deathEnd and math.abs(deathEnd - last.deathEnd) > 2000)
    if last and last.key == key and not deathMoved then return end

    sent[player] = { key = key, deathEnd = deathEnd }
    triggerClientEvent(player, "medfx:state", resourceRoot, payload)
end

function refreshPlayer(player)
    if not isElement(player) then return end
    local ms = medsys()
    local snapshot = ms and not isPedDead(player) and ms:getMedicalState(player)
    if not snapshot or not snapshot.isPatient or snapshot.dead then
        setWalk(player, nil)
        sendState(player, nil)
        return
    end

    local controls, walk = injuryEffects(player, snapshot)
    if MEDFX_DYSPNEA[snapshot.breathing] then
        local seen = {}
        for _, control in ipairs(controls) do seen[control] = true end
        for _, control in ipairs(MEDFX_DYSPNEA_PLAYER.controls) do
            if not seen[control] then controls[#controls + 1] = control end
        end
        table.sort(controls)
    end
    local stateDef = MEDFX_STATES[snapshot.consciousness]
    if stateDef and stateDef.walk then walk = stateDef.walk end
    if stateDef and stateDef.lock then walk = nil end
    setWalk(player, walk)

    sendState(player, {
        status = snapshot.consciousness,
        pain = math.floor(snapshot.pain / 5 + 0.5) * 5,
        bleeding = snapshot.bleeding,
        spo2 = snapshot.spo2,
        blood = snapshot.bloodPercent,
        deathLeft = snapshot.deathTimeLeft,
        controls = controls,
    })
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

local function isPatientType(element)
    local t = isElement(element) and getElementType(element)
    return t == "player" or t == "ped"
end

local function track(element)
    if not isPatientType(element) then return end
    if getElementData(element, MEDFX.DATA_STATUS) then
        Tracked[element] = true
    else
        Tracked[element] = nil
        TestParts[element] = nil
    end
    updateAnim(element)
    if getElementType(element) == "player" then refreshPlayer(element) end
end

addEventHandler("onElementDataChange", root, function(key)
    if key == MEDFX.DATA_STATUS or key == MEDFX.DATA_BREATH then track(source) end
end)

-- medsys fires it on every state transition (backup for the data change)
addEvent("onMedicalStateChange", false)
addEventHandler("onMedicalStateChange", root, function()
    track(source)
end)

addEvent("onMedicalInjury", false)
addEventHandler("onMedicalInjury", root, function()
    if getElementType(source) ~= "player" then return end
    triggerClientEvent(source, "medfx:hit", resourceRoot)
    -- the parts of medsys_events arrive right after this event
    local player = source
    setTimer(function() if isElement(player) then refreshPlayer(player) end end, 50, 1)
end)

addEvent("onMedicalTreatment", false)
addEventHandler("onMedicalTreatment", root, function()
    if Tracked[source] and getElementType(source) == "player" then refreshPlayer(source) end
end)

setTimer(function()
    for element in pairs(Tracked) do
        if not isElement(element) then
            Tracked[element] = nil
        elseif getElementType(element) == "player" then
            refreshPlayer(element)
        end
    end
end, MEDFX.TICK, 0)

local function forget(element)
    Tracked[element] = nil
    TestParts[element] = nil
    sent[element] = nil
    walking[element] = nil
end

addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEventHandler("onElementDestroy", root, function()
    if Tracked[source] then forget(source) end
end)

local function onWasted()
    updateAnim(source)
    if getElementType(source) == "player" then refreshPlayer(source) end
end
addEventHandler("onPlayerWasted", root, onWasted)
addEventHandler("onPedWasted", root, onWasted)

addEventHandler("onPlayerSpawn", root, function() track(source) end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, elementType in ipairs({ "player", "ped" }) do
        for _, element in ipairs(getElementsByType(elementType)) do
            if getElementData(element, MEDFX.DATA_STATUS) then track(element) end
        end
    end
end)

-- a late client gets its own condition again
addEvent("medfx:ready", true)
addEventHandler("medfx:ready", resourceRoot, function()
    sent[client] = nil
    if Tracked[client] then refreshPlayer(client) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(walking) do setWalk(player, nil) end
    for _, elementType in ipairs({ "player", "ped" }) do
        for _, element in ipairs(getElementsByType(elementType)) do
            removeElementData(element, MEDFX.DATA_ANIM)
            removeElementData(element, MEDFX.DATA_BLOCK)
        end
    end
end)
