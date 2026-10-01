-- Server side session handling. Results are reported to other resources via
-- the "onAirwayGameFinish" event (source = player).

addEvent("onAirwayGameFinish", false)
addEvent("mg_airway:onResult", true)
addEvent("mg_airway:ready", true)

local sessions = {} -- [player] = { id, options, ped, animated, startTick, timer, sampler, minSpO2 }
local lastId = 0

local CLIENT_REASONS = { intubated = true, desaturated = true, too_many_mistakes = true }

local function sessionTimeLimit(options)
    if options.liveSpO2 then return AIRWAY.MAX_TIME end
    return math.min(AIRWAY.MAX_TIME, airwayTimeLimit(options))
end

local function finishSession(player, reason, time, details)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil

    if isTimer(session.timer) then killTimer(session.timer) end
    if isTimer(session.sampler) then killTimer(session.sampler) end

    time = time or 0
    details = details or {}
    details.difficulty = session.options.difficulty
    if session.options.liveSpO2 then
        local spo2 = airwayGetPatientSpO2(session.ped)
        if spo2 then session.minSpO2 = math.min(session.minSpO2, spo2) end
        details.minSpO2 = math.floor(session.minSpO2 + 0.5)
    else
        details.minSpO2 = math.floor(airwaySpO2(session.options, time) + 0.5)
    end
    for key in pairs(AIRWAY_MISTAKES) do details[key] = details[key] or 0 end

    local mistakes = airwayCountMistakes(details)
    local success = reason == "intubated"
    local score = success and airwayScore(time, mistakes) or 0

    if isElement(player) then
        if session.animated then setPedAnimation(player) end
        -- success, score, time, mistakes, reason, sessionId, details
        triggerEvent("onAirwayGameFinish", player, success, score, time, mistakes, reason, session.id, details)
    end
end

-- Starts the intubation minigame for a player.
-- ped: optional ped/player being intubated - the player kneels at its head. Its SpO2 is read
--      from the AIRWAY.SPO2_DATA element data (managed by the medic system); without that data
--      the SpO2 is simulated from spo2Start / spo2Drain.
-- options: { difficulty = "easy"|"normal"|"hard"|"nightmare", spo2Start, spo2Drain, maxMistakes, blood }
-- Returns the session id, or false if the player/ped is invalid or the player is already playing.
function startAirwayGame(player, ped, options)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end
    if ped ~= nil then
        if not isElement(ped) or ped == player then return false end
        local pedType = getElementType(ped)
        if pedType ~= "ped" and pedType ~= "player" then return false end
    end

    options = airwayNormalizeOptions(options)
    local spo2 = airwayGetPatientSpO2(ped)
    options.liveSpO2 = spo2 ~= nil
    if ped and isPedInVehicle(player) then removePedFromVehicle(player) end

    lastId = lastId + 1
    local session = {
        id = lastId,
        options = options,
        ped = ped,
        startTick = getTickCount(),
        minSpO2 = spo2 or options.spo2Start,
    }
    local timeout = (AIRWAY.COUNTDOWN + sessionTimeLimit(options) + AIRWAY.RESULT_TIME + 15) * 1000
    session.timer = setTimer(function()
        triggerClientEvent(player, "mg_airway:stop", resourceRoot)
        finishSession(player, "timeout")
    end, timeout, 1)
    if options.liveSpO2 then
        -- track the lowest SpO2 on the server, the client's word is not trusted
        session.sampler = setTimer(function()
            local value = airwayGetPatientSpO2(session.ped)
            if value then session.minSpO2 = math.min(session.minSpO2, value) end
        end, 250, 0)
    end
    sessions[player] = session

    triggerClientEvent(player, "mg_airway:start", resourceRoot, session.id, options, ped)
    return session.id
end

-- Aborts a running game. onAirwayGameFinish fires with reason "cancelled".
function stopAirwayGame(player)
    if not sessions[player] then return false end
    triggerClientEvent(player, "mg_airway:stop", resourceRoot)
    finishSession(player, "cancelled")
    return true
end

function isAirwayGameActive(player)
    return sessions[player] ~= nil
end

-- The client has placed itself at the patient's head, start the (synced) animation
addEventHandler("mg_airway:ready", resourceRoot, function(sessionId)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId or not session.ped or session.animated then return end

    session.animated = true
    setPedAnimation(player, AIRWAY.ANIM_BLOCK, AIRWAY.ANIM_NAME, -1, true, false, false, false)
end)

addEventHandler("mg_airway:onResult", resourceRoot, function(sessionId, reason, time, details)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId then return end

    time = tonumber(time) or -1
    local clean = {}
    local valid = CLIENT_REASONS[reason] and type(details) == "table" and time >= 0
    if valid then
        for key in pairs(AIRWAY_MISTAKES) do
            local n = math.floor(tonumber(details[key]) or -1)
            if n < 0 or n > 50 then valid = false end
            clean[key] = n
        end
        clean.depth = tonumber(details.depth) or 0
        clean.cuffPressure = tonumber(details.cuffPressure) or 0
    end

    local elapsed = (getTickCount() - session.startTick) / 1000
    local limit = sessionTimeLimit(session.options)
    if valid then
        local mistakes = airwayCountMistakes(clean)
        if elapsed < AIRWAY.COUNTDOWN + time * 0.9 or time > limit + 1 then
            valid = false
        elseif reason == "intubated" then
            valid = time >= AIRWAY.MIN_TIME and mistakes <= session.options.maxMistakes
        elseif reason == "desaturated" and session.options.liveSpO2 then
            local spo2 = airwayGetPatientSpO2(session.ped) or 100
            valid = math.min(session.minSpO2, spo2) <= AIRWAY.FAIL_SPO2 + 2
        elseif reason == "desaturated" then
            valid = time >= limit - 1
        elseif reason == "too_many_mistakes" then
            valid = mistakes > session.options.maxMistakes
        end
    end

    if not valid then
        outputDebugString(("mg_airway: rejected result from %s (%s, %.1fs, elapsed %.1fs)")
            :format(getPlayerName(player), tostring(reason), time, elapsed), 2)
        finishSession(player, "invalid")
        return
    end

    finishSession(player, reason, time, clean)
end)

addEventHandler("onPlayerWasted", root, function()
    if not sessions[source] then return end
    triggerClientEvent(source, "mg_airway:stop", resourceRoot)
    finishSession(source, "died")
end)

addEventHandler("onPlayerQuit", root, function()
    finishSession(source, "quit")
end)

---------------------------------------------------------------------------
-- Test command
--   /airwaytest [easy|normal|hard|nightmare] [0]  random emergency case (0 = no ped)
-- The test ped gets SpO2 / heart rate element data that drops the way the medic system
-- would drop it, so the element data path is exercised.
---------------------------------------------------------------------------
if not AIRWAY.TEST_COMMAND then return end

local CASES = {
    { "Heroin overdose, snoring respirations", "easy" },
    { "Post-ictal seizure patient, GCS 6", "easy" },
    { "Cardiac arrest in a gym, CPR in progress", "normal" },
    { "Pulled out of the harbour, near-drowning", "normal" },
    { "Alcohol poisoning, vomited once already", "normal" },
    { "Motorbike crash, facial fractures, blood in the airway", "hard" },
    { "Gunshot wound to the neck", "hard" },
    { "House fire, soot around the mouth, stridor", "nightmare" },
    { "Anaphylaxis after a bee sting, swollen tongue", "nightmare" },
}
local FIRST_NAMES = { "Carl", "Sean", "Melvin", "Lance", "Frank", "Catalina", "Denise", "Kendl", "Cesar", "Mike" }
local LAST_NAMES = { "Johnson", "Harris", "Tenpenny", "Pulaski", "Vialpando", "Toreno", "Wilson", "Hernandez" }

local testPatients = {} -- [player] = { ped, drain }

local function say(player, text)
    outputChatBox("#ff5a5a[AIRWAY] #ffffff" .. text, player, 255, 255, 255, true)
end

local function cleanupPatient(player, delay)
    local patient = testPatients[player]
    testPatients[player] = nil
    if not patient then return end
    if isTimer(patient.drain) then killTimer(patient.drain) end
    if isElement(patient.ped) then
        if delay then setTimer(destroyElement, delay, 1, patient.ped) else destroyElement(patient.ped) end
    end
end

-- Lying test patient with vitals as element data (stand-in for the medic system)
local function spawnPatient(player, options)
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local a = math.rad(rz)
    local ped = createPed(math.random(7, 30), x - math.sin(a) * 2, y + math.cos(a) * 2, z, rz + 90)
    setElementInterior(ped, getElementInterior(player))
    setElementDimension(ped, getElementDimension(player))
    setTimer(function()
        if isElement(ped) then setPedAnimation(ped, "PED", "KO_shot_front", -1, false, false, false, true) end
    end, 100, 1)

    setElementData(ped, AIRWAY.SPO2_DATA, options.spo2Start)
    setElementData(ped, AIRWAY.HR_DATA, 92)
    local startTick = getTickCount() + AIRWAY.COUNTDOWN * 1000
    local drain = setTimer(function()
        if not isElement(ped) then return end
        local spo2 = airwaySpO2(options, (getTickCount() - startTick) / 1000)
        setElementData(ped, AIRWAY.SPO2_DATA, math.floor(spo2 * 10 + 0.5) / 10)
        setElementData(ped, AIRWAY.HR_DATA, math.floor(92 + (options.spo2Start - spo2) * 3))
    end, 250, 0)
    return ped, drain
end

local function describeMistakes(details)
    local list = {}
    for key, label in pairs(AIRWAY_MISTAKES) do
        if (details[key] or 0) > 0 then
            table.insert(list, details[key] > 1 and ("%s x%d"):format(label, details[key]) or label)
        end
    end
    return #list > 0 and table.concat(list, ", ") or "clean"
end

addCommandHandler("airwaytest", function(player, _, difficulty, withPed)
    if difficulty and not AIRWAY.DIFFICULTY[difficulty] then
        say(player, "Usage: /airwaytest [easy|normal|hard|nightmare] [0 = no patient ped]")
        return
    end
    if sessions[player] then
        say(player, "You are already busy with a patient.")
        return
    end

    local pool = {}
    for _, case in ipairs(CASES) do
        if not difficulty or case[2] == difficulty then table.insert(pool, case) end
    end
    local case = pool[math.random(#pool)]
    local options = airwayNormalizeOptions({ difficulty = case[2] })

    local ped, drain
    if withPed ~= "0" then ped, drain = spawnPatient(player, options) end
    if not startAirwayGame(player, ped, options) then
        if isTimer(drain) then killTimer(drain) end
        if ped then destroyElement(ped) end
        return
    end
    testPatients[player] = { ped = ped, drain = drain }

    say(player, ("Patient: #ffd24a%s %s (%d)#ffffff - %s")
        :format(FIRST_NAMES[math.random(#FIRST_NAMES)], LAST_NAMES[math.random(#LAST_NAMES)], math.random(17, 84), case[1]))
    say(player, ("SpO2 #7fd4ff%d%%#ffffff and falling. Difficulty: #ffd24a%s#ffffff, mistakes allowed: %d. Secure the airway!")
        :format(options.spo2Start, options.difficulty:upper(), options.maxMistakes))
end)

addEventHandler("onAirwayGameFinish", root, function(success, score, time, _, reason, _, details)
    local player = source
    local patient = testPatients[player]
    if not patient then return end

    if isTimer(patient.drain) then killTimer(patient.drain) end
    if success and isElement(patient.ped) then
        setElementData(patient.ped, AIRWAY.SPO2_DATA, 97) -- ventilated
    end
    cleanupPatient(player, 4000)

    if success then
        say(player, ("#5aff7aTube confirmed#ffffff - ETCO2 %d mmHg, bilateral breath sounds. Score #ffd24a%d#ffffff, %.1fs, lowest SpO2 %d%% (%s)")
            :format(math.random(33, 42), score, time, details.minSpO2, describeMistakes(details)))
    elseif reason == "desaturated" then
        say(player, ("#ff5a5aSpO2 dropped to %d%%.#ffffff The patient went into cardiac arrest. (%s)")
            :format(details.minSpO2, describeMistakes(details)))
    elseif reason == "too_many_mistakes" then
        say(player, ("#ff5a5aThe senior doctor took over the airway.#ffffff (%s)"):format(describeMistakes(details)))
    else
        say(player, "Procedure aborted: " .. reason)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    cleanupPatient(source)
end)
