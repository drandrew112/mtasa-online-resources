-- EMS tutorial: one session per player in its own dimension. The server owns the session and
-- the world (ambulance, patient, hospital markers); the client shows the tutorial card and
-- drives the tablet / equipment / panel explanations (client/*.lua).
--
-- Steps: tablet -> equipment -> examine -> treat -> stretcher -> transfer -> handover -> restock -> done
-- One patient goes through the whole tutorial: examined and treated at the scene, loaded with the
-- equipment riding on the stretcher, handed over at the hospital. The equipment (med_bag) steps are
-- skipped while med_bag is not running (medsys then asks for no equipment either).
--
-- The tutorial is never required. It is offered the first time a player goes on duty as EMS
-- (or every time with TUTORIAL.DEBUG), and /tutorial_ems starts it any time.

Tutorial = { sessions = {} }

local sessions = Tutorial.sessions    -- player -> session
local STEPS = { "tablet", "equipment", "examine", "treat", "stretcher", "transfer", "handover", "restock", "done" }
local EQUIPMENT_STEPS = { equipment = true, restock = true }

-- The treatments of the treat step: medsys action (+ medicine) -> key of s.done
local TREATMENTS = { bandage = "bandage", splint = "splint", iv = "iv", oxygen = "oxygen" }

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function chat(player, text)
    outputChatBox("#e0474c[EMS tutorial] #ffffff" .. text, player, 255, 255, 255, true)
end

local function send(player, name, ...)
    if isElement(player) then triggerClientEvent(player, name, resourceRoot, ...) end
end

local function later(s, ms, fn)
    local timer = setTimer(function()
        if sessions[s.player] == s then fn() end
    end, ms, 1)
    s.timers[#s.timers + 1] = timer
    return timer
end

local function fadeMs() return math.floor(TUTORIAL.FADE_TIME * 1000) end

-- Vehicle-local { x, y } offset -> world position at the vehicle's height
local function besideVehicle(vehicle, ox, oy)
    local m = getElementMatrix(vehicle)
    return ox * m[1][1] + oy * m[2][1] + m[4][1],
           ox * m[1][2] + oy * m[2][2] + m[4][2],
           m[4][3]
end

local function freeDimension()
    local used = {}
    for _, s in pairs(sessions) do used[s.dimension] = true end
    local d = TUTORIAL.DIMENSION_BASE
    while used[d] do d = d + 1 end
    return d
end

---------------------------------------------------------------- account flag

function Tutorial.isDone(player)
    if not isRunning("v_mysql") then return false end
    return exports.v_mysql:getAccData(player, TUTORIAL.ACC_KEY) == true
end

local function markDone(player)
    if isElement(player) and isRunning("v_mysql") then
        exports.v_mysql:setAccData(player, TUTORIAL.ACC_KEY, true)
    end
end

---------------------------------------------------------------- world elements

local function spawnPed(s, offset)
    local skins = TUTORIAL.PATIENT_SKINS
    local x, y, z = besideVehicle(s.vehicle, offset[1], offset[2])
    local px, py = getElementPosition(s.vehicle)
    local rot = math.deg(math.atan2(px - x, y - py)) % 360   -- facing the ambulance
    local ped = createPed(skins[math.random(#skins)], x, y, z, rot)
    if not ped then return nil end
    setElementDimension(ped, s.dimension)
    setElementInterior(ped, getElementInterior(s.vehicle))
    setElementData(ped, "ems.tutorialPed", true)  -- clients cancel damage on it
    s.elements[#s.elements + 1] = ped
    return ped
end

local function destroySessionElements(s)
    for _, e in ipairs(s.elements) do
        if isElement(e) then destroyElement(e) end
    end
    s.elements = {}
    if isElement(s.vehicle) then destroyElement(s.vehicle) end
    if s.handoverId and isRunning("med_hospitals") then
        exports.med_hospitals:destroyTutorialHandover(s.handoverId)
    end
    s.handoverId = nil
end

local function stretcherOf(s)
    if not isElement(s.vehicle) or not isRunning("med_stretcher") then return false end
    return exports.med_stretcher:getVehicleStretcher(s.vehicle)
end

-- The equipment is taught while med_bag runs (medsys checks it only then)
local function equipmentOn()
    return isRunning("med_bag")
end

---------------------------------------------------------------- steps

local enterStep -- forward

local function setStep(s, step)
    s.step = step
    s.lastInfo = nil
    send(s.player, "ems:tut:step", step)
    enterStep(s, step)
end

local function nextStep(s)
    for i, step in ipairs(STEPS) do
        if step == s.step then
            -- without med_bag the equipment steps are left out
            local n = i + 1
            while STEPS[n] and EQUIPMENT_STEPS[STEPS[n]] and not equipmentOn() do n = n + 1 end
            if STEPS[n] then setStep(s, STEPS[n]) end
            return
        end
    end
end

-- World progress, polled from the equipment step on:
--   stretcher = { state = stowed | moving | ground | pushing | none, patient, loaded }
--   items     = { bag = { state, mine }, monitor = ... }  (med_bag item states; nil without med_bag)
--   restocked = the bag is full again (after something was used)
local function worldInfo(s)
    local info = { stretcher = { state = "none" } }
    local obj = stretcherOf(s)
    if obj then
        local ms = exports.med_stretcher
        local patient = s.patient
        info.stretcher = {
            state = ms:getStretcherState(obj) or "none",
            patient = isElement(patient) and ms:getPatientStretcher(patient) == obj,
            loaded = isElement(patient) and getPedOccupiedVehicle(patient) == s.vehicle,
        }
    end
    if equipmentOn() and isElement(s.vehicle) then
        local mb = exports.med_bag
        local kit = mb:getVehicleKit(s.vehicle)
        if kit then
            info.items = {}
            for _, kind in ipairs({ "bag", "monitor" }) do
                local item = mb:getItemInfo(kit[kind])
                info.items[kind] = item and { state = item.state, mine = item.carrier == s.player } or { state = "none" }
            end
            local stock = mb:getItemStock(kit.bag)
            if stock then
                -- the first look at the bag (a new kit) is the full stock
                if not s.fullStock or s.kitBag ~= kit.bag then s.fullStock, s.kitBag = stock, kit.bag end
                local full = stock.ivKits >= s.fullStock.ivKits and stock.oxygen >= s.fullStock.oxygen - 0.5
                for id, count in pairs(s.fullStock.drugs) do
                    if (stock.drugs[id] or 0) < count then full = false end
                end
                info.restocked = full
            end
        end
    end
    return info
end

local function itemsStowed(info)
    if not info.items then return true end
    return info.items.bag.state == "stowed" and info.items.monitor.state == "stowed"
end

local function encode(info)
    local st, items = info.stretcher, info.items
    local key = st.state .. tostring(st.patient) .. tostring(st.loaded) .. tostring(info.restocked)
    if items then
        for _, kind in ipairs({ "bag", "monitor" }) do
            key = key .. items[kind].state .. tostring(items[kind].mine)
        end
    end
    return key
end

local function startPolling(s)
    if s.poll then return end
    s.poll = setTimer(function()
        if sessions[s.player] ~= s then return end
        local info = worldInfo(s)
        local key = encode(info)
        if key ~= s.lastInfo then
            s.lastInfo = key
            send(s.player, "ems:tut:info", "world", info)
        end
        local st = info.stretcher
        if s.step == "stretcher" and st.loaded and st.state == "stowed" and itemsStowed(info) then
            nextStep(s)
        elseif s.step == "restock" and st.state == "stowed" and itemsStowed(info) and info.restocked then
            nextStep(s)
        end
    end, TUTORIAL.POLL, 0)
end

local function spawnPatient(s)
    local ped = spawnPed(s, TUTORIAL.SCENE.patientOffset)
    s.patient = ped
    s.done = {}
    if not ped or not isRunning("medsys") then return nil end
    for _, injury in ipairs(TUTORIAL.SCENE.injuries) do
        exports.medsys:applyInjury(ped, injury[1], injury[2])
    end
    -- no transport for it; the equipment rules apply when med_bag runs
    exports.medsys:setTutorialPatient(ped, true, true)
    return ped
end

local STEP_ENTER = {}

STEP_ENTER.equipment = function(s)
    setElementFrozen(s.vehicle, false)
    if not s.patient then spawnPatient(s) end
    startPolling(s)
end

STEP_ENTER.examine = function(s)
    setElementFrozen(s.vehicle, false)
    startPolling(s)
    if not s.patient and not spawnPatient(s) then
        chat(s.player, "The medical system is not running - the patient steps are skipped.")
        return later(s, 2000, function() setStep(s, "done") end)
    end
end

STEP_ENTER.restock = function(s)
    -- the restock needs the bay of the tutorial hospital copy
    if not s.handoverId then return later(s, 500, function() nextStep(s) end) end
end

STEP_ENTER.transfer = function(s)
    local player = s.player
    later(s, 1500, function()
        fadeCamera(player, false, TUTORIAL.FADE_TIME)
        later(s, fadeMs() + 200, function()
            local h = TUTORIAL.HOSPITAL
            local vehicle = s.vehicle
            if getPedOccupiedVehicle(player) ~= vehicle then
                if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
                warpPedIntoVehicle(player, vehicle, 0)
            end
            local v = h.vehicle
            setElementVelocity(vehicle, 0, 0, 0)
            setElementPosition(vehicle, v[1], v[2], v[3])
            setElementRotation(vehicle, 0, 0, v[4])
            if isRunning("med_hospitals") then
                s.handoverId = exports.med_hospitals:createTutorialHandover(player, h.id, s.dimension, vehicle) or nil
            end
            if not s.handoverId then chat(player, "The hospital markers could not be created (med_hospitals).") end
            later(s, 600, function()
                fadeCamera(player, true, TUTORIAL.FADE_TIME)
                later(s, fadeMs(), function() nextStep(s) end)
            end)
        end)
    end)
end

function enterStep(s, step)
    local fn = STEP_ENTER[step]
    if fn then fn(s) end
end

---------------------------------------------------------------- start / finish

-- -> true | false, reason
function Tutorial.start(player)
    if sessions[player] then return false, "The tutorial is already running." end
    if isPedDead(player) then return false, "You cannot start the tutorial now." end
    if getElementData(player, "isLogged") ~= true then return false, "Log in first." end
    if not isRunning("medsys") or not isRunning("med_stretcher") then
        return false, "The medical system is not running."
    end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local s = {
        player = player,
        step = "starting",
        dimension = freeDimension(),
        saved = { x = x, y = y, z = z, rot = rot, int = getElementInterior(player), dim = getElementDimension(player) },
        elements = {},
        timers = {},
        games = {},
        done = {},
    }
    sessions[player] = s

    -- v_accounts saves this position instead of the tutorial one
    setElementData(player, "save.position", { x, y, z, s.saved.int, s.saved.dim }, false)
    if not exports.medsys:isPlayerMedic(player) then
        exports.medsys:setPlayerMedic(player, true)
        s.grantedMedic = true
    end
    if isRunning("med_erm") then
        exports.med_erm:removePlayerFromUnit(player, "You started the EMS tutorial.")
    end

    fadeCamera(player, false, TUTORIAL.FADE_TIME)
    later(s, fadeMs() + 200, function()
        if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
        local v = TUTORIAL.SCENE.vehicle
        local vehicle = createVehicle(416, v[1], v[2], v[3], 0, 0, v[4],
            EMS.PLATE_PREFIX .. ("%0" .. EMS.PLATE_DIGITS .. "d"):format(math.random(0, 10 ^ EMS.PLATE_DIGITS - 1)))
        if not vehicle then
            Tutorial.finish(player, "error")
            return chat(player, "The tutorial could not be started.")
        end
        s.vehicle = vehicle
        setElementDimension(vehicle, s.dimension)
        setElementInterior(player, 0)
        setElementDimension(player, s.dimension)
        warpPedIntoVehicle(player, vehicle, 0)
        setElementFrozen(vehicle, true)  -- unfrozen after the tablet step
        setCameraTarget(player, player)
        send(player, "ems:tut:begin", vehicle, equipmentOn())
        setStep(s, "tablet")
        later(s, 300, function() fadeCamera(player, true, TUTORIAL.FADE_TIME) end)
    end)
    return true
end

-- reason: "completed" | "skipped" | "died" | "quit" | "error" | "stopped"
function Tutorial.finish(player, reason)
    local s = sessions[player]
    if not s then return false end
    sessions[player] = nil

    for _, timer in ipairs(s.timers) do
        if isTimer(timer) then killTimer(timer) end
    end
    if isTimer(s.poll) then killTimer(s.poll) end
    if s.gameRunning then Tutorial.stopGame(s) end
    if isElement(player) and isRunning("medsys") then exports.medsys:closeExamination(player) end
    destroySessionElements(s)

    if reason == "quit" or not isElement(player) then return true end
    if reason == "completed" or reason == "skipped" then markDone(player) end

    send(player, "ems:tut:end", reason)
    if s.grantedMedic and isRunning("medsys") and not isPlayerEms(player) then
        exports.medsys:setPlayerMedic(player, false)
    end

    local saved = s.saved
    local function restore()
        removeElementData(player, "save.position")
        if isPedDead(player) then return end
        if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
        setElementInterior(player, saved.int)
        setElementDimension(player, saved.dim)
        setElementPosition(player, saved.x, saved.y, saved.z)
        setElementRotation(player, 0, 0, saved.rot)
        setCameraTarget(player, player)
        fadeCamera(player, true, TUTORIAL.FADE_TIME)
    end
    if reason == "died" then
        -- the spawn manager places the player; only the saved position override goes
        removeElementData(player, "save.position")
        if getElementDimension(player) == s.dimension then setElementDimension(player, saved.dim) end
    else
        fadeCamera(player, false, TUTORIAL.FADE_TIME)
        setTimer(function() if isElement(player) then restore() end end, fadeMs() + 200, 1)
    end

    if reason == "completed" then
        chat(player, "Tutorial completed. Good luck on duty!")
    elseif reason == "skipped" then
        chat(player, ("Tutorial skipped. You can start it again any time with /%s."):format(TUTORIAL.COMMAND))
    end
    return true
end

function Tutorial.isActive(player)
    return sessions[player] ~= nil
end

---------------------------------------------------------------- minigame practice (optional, on the final card)

local GAMES = {
    arrows = { start = function(p) return exports.mg_arrows:startArrowsGame(p, 12, { speed = 1 }) end,
               stop = function(p) exports.mg_arrows:stopArrowsGame(p) end,
               event = "onArrowsGameFinish", sessionArg = 6 },
    cpr    = { start = function(p) return exports.mg_cpr:startCPRGame(p, 20) end,
               stop = function(p) exports.mg_cpr:stopCPRGame(p) end,
               event = "onCPRGameFinish", sessionArg = 6 },
    iv     = { start = function(p) return exports.mg_intravenous:startIVGame(p, nil, { difficulty = 1 }) end,
               stop = function(p) exports.mg_intravenous:stopIVGame(p) end,
               event = "onIVGameFinish", sessionArg = 5 },
    airway = { start = function(p) return exports.mg_airway:startAirwayGame(p, nil, { difficulty = "easy" }) end,
               stop = function(p) exports.mg_airway:stopAirwayGame(p) end,
               event = "onAirwayGameFinish", sessionArg = 6 },
    splinting = { start = function(p) return exports.mg_splinting:startSplintGame(p, nil, 6) end,
               stop = function(p) exports.mg_splinting:stopSplintGame(p) end,
               event = "onSplintGameFinish", sessionArg = 6 },
}

local function gameDef(id)
    for _, g in ipairs(TUTORIAL.GAMES) do
        if g.id == id then return g end
    end
end

function Tutorial.stopGame(s)
    local running = s.gameRunning
    s.gameRunning = nil
    if running and isElement(s.player) then GAMES[running.id].stop(s.player) end
end

local function startGame(s, id)
    local game, def = GAMES[id], gameDef(id)
    if not game or not def or s.step ~= "done" or s.gameRunning then return end
    if not isRunning(def.resource) then
        return send(s.player, "ems:tut:info", "gameError", "This minigame is not available right now.")
    end
    if getPedOccupiedVehicle(s.player) then removePedFromVehicle(s.player) end
    local sessionId = game.start(s.player)
    if not sessionId then
        return send(s.player, "ems:tut:info", "gameError", "The minigame could not be started.")
    end
    s.gameRunning = { id = id, sessionId = sessionId }
    send(s.player, "ems:tut:games", s.games, id)
end

for id, game in pairs(GAMES) do
    addEvent(game.event)
    addEventHandler(game.event, root, function(success, ...)
        local s = sessions[source]
        local running = s and s.gameRunning
        if not running or running.id ~= id then return end
        if select(game.sessionArg - 1, ...) ~= running.sessionId then return end
        s.gameRunning = nil
        local stats = s.games[id] or { played = 0, success = 0 }
        s.games[id] = stats
        stats.played = stats.played + 1
        if success then stats.success = stats.success + 1 end
        send(s.player, "ems:tut:games", s.games, false, id, success == true)
    end)
end

---------------------------------------------------------------- client requests

local function handle(name, fn)
    addEvent(name, true)
    addEventHandler(name, resourceRoot, function(...)
        if isElement(client) then fn(client, ...) end
    end)
end

-- answer to the first-duty offer
handle("ems:tut:answer", function(player, accept)
    if Tutorial.isActive(player) then return end
    if accept then
        local ok, err = Tutorial.start(player)
        if not ok then chat(player, err) end
    else
        markDone(player)
        chat(player, ("No problem. You can start the tutorial any time with /%s."):format(TUTORIAL.COMMAND))
    end
end)

local function treatmentsDone(s)
    for _, key in ipairs(TUTORIAL.TREATMENTS) do
        if not s.done[key] then return false end
    end
    return true
end

-- the client finished its part of a step (explanations, the final card)
local CLIENT_STEPS = { tablet = true, equipment = true, examine = true, treat = true, done = true }

handle("ems:tut:next", function(player, step)
    local s = sessions[player]
    if not s or s.step ~= step or not CLIENT_STEPS[step] then return end
    if step == "treat" and not treatmentsDone(s) then return end
    if step == "done" then
        if s.gameRunning then return end
        return Tutorial.finish(player, "completed")
    end
    nextStep(s)
end)

handle("ems:tut:skip", function(player)
    Tutorial.finish(player, "skipped")
end)

handle("ems:tut:game", function(player, id)
    local s = sessions[player]
    if s then startGame(s, id) end
end)

---------------------------------------------------------------- world events

-- Treatments on the tutorial patient. Done early (in the examine step) counts too.
addEvent("onMedicalTreatment")
addEventHandler("onMedicalTreatment", root, function(medic, action, success, option)
    local s = sessions[medic]
    if not s or source ~= s.patient then return end
    local key = TREATMENTS[action]
    if action == "medication" and option == TUTORIAL.PAINKILLER then key = "painkiller" end
    if action == "monitor" then key = "monitor" end
    if not key then return end
    if success then s.done[key] = true end
    send(medic, "ems:tut:info", "treatment", { key = key, success = success == true, done = s.done })
end)

addEvent("onHospitalTutorialHandover")
addEventHandler("onHospitalTutorialHandover", root, function(id)
    local s = sessions[source]
    if not s or s.step ~= "handover" or id ~= s.handoverId then return end
    s.patient = nil -- med_hospitals destroys the ped
    nextStep(s)
end)

addEventHandler("onPlayerWasted", root, function()
    if sessions[source] then
        Tutorial.finish(source, "died")
        chat(source, "The tutorial ended because you died.")
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Tutorial.finish(source, "quit")
end)

-- The patient died anyway (damage is cancelled on the clients): a new patient, from the examination
local PATIENT_STEPS = { equipment = true, examine = true, treat = true, stretcher = true }

addEventHandler("onPedWasted", root, function()
    for player, s in pairs(sessions) do
        if source == s.patient and PATIENT_STEPS[s.step] then
            local ped = source
            chat(player, "The patient died - a new patient is waiting.")
            later(s, 2000, function()
                if isRunning("medsys") then exports.medsys:closeExamination(player) end
                if isElement(ped) then
                    local obj = stretcherOf(s)
                    if obj and exports.med_stretcher:getPatientStretcher(ped) == obj then
                        exports.med_stretcher:takePatientOff(obj)
                    end
                    destroyElement(ped)
                end
                s.patient = nil
                spawnPatient(s)
                if s.step ~= "equipment" then setStep(s, "examine") end
            end)
        end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do Tutorial.finish(player, "stopped") end
end)

-- the tutorial ambulance stays with the tutorial
addEventHandler("onVehicleExplode", root, function()
    for player, s in pairs(sessions) do
        if s.vehicle == source then
            Tutorial.finish(player, "error")
            chat(player, "The tutorial ambulance was destroyed. Start again with /" .. TUTORIAL.COMMAND .. ".")
        end
    end
end)

---------------------------------------------------------------- command

addCommandHandler(TUTORIAL.COMMAND, function(player, _, arg)
    if arg == "skip" or arg == "stop" then
        if not Tutorial.finish(player, "skipped") then chat(player, "The tutorial is not running.") end
        return
    end
    local ok, err = Tutorial.start(player)
    if not ok then chat(player, err) end
end)

---------------------------------------------------------------- work_ems module hooks

EmsModules.register("tutorial", {
    -- first duty start (or every one in debug mode): offer the tutorial
    onDutyStart = function(player)
        if Tutorial.isActive(player) then return end
        if TUTORIAL.DEBUG or not Tutorial.isDone(player) then
            send(player, "ems:tut:offer", TUTORIAL.DEBUG)
        end
    end,
    -- the core takes the medic role on duty end; the tutorial keeps it while it runs
    onDutyEnd = function(player)
        local s = sessions[player]
        if s and isElement(player) and isRunning("medsys") then
            exports.medsys:setPlayerMedic(player, true)
            s.grantedMedic = true
        end
    end,
})
