if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Air traffic controller training: the scope tour (SCOPE) and three position modules (ADC tower, APC
-- approach, ACC area control), one
-- session per player in the SA Control room (interior 3) in a dimension of its own. A module runs the
-- real ATC flow on its position (TRAINING.MODULES): the avi_core console marker (a tutorial copy), the
-- avi_controller scope (a tutorial login: the live position stays free, no pay, no XP) and training
-- aircraft of avi_traffic that fly in a world of their own. The server owns the session, the aircraft
-- and the steps (the module definitions are in server/modules.lua); the client shows the card and
-- follows the scope (client/*.lua).
--
-- Modules are started at the training marker of the room (TRAINING.MARKER, on duty). Each one is
-- unlocked by an ATC right of avi_core (work level): SCOPE and ADC = TWR, APC = APP, ACC = RADAR. The
-- first duty start offers SCOPE (TRAINING.OFFER). A completed module sets the account data TRAINING.ACC_PREFIX .. id.

Training = { sessions = {}, modules = {} }

local sessions = Training.sessions    -- player -> session

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function call(resource, fn, ...)
    if not isRunning(resource) then return nil end
    local ok, a, b = pcall(function(...) return exports[resource][fn](exports[resource], ...) end, ...)
    if not ok then
        outputDebugString(("[work_atc] training: %s:%s failed: %s"):format(resource, fn, tostring(a)), 2)
        return nil
    end
    return a, b
end
Training.call = call

local function send(player, name, ...)
    if isElement(player) then triggerClientEvent(player, name, resourceRoot, ...) end
end
Training.send = send

-- outputChatBox is hidden (v_chat): messages go to ui_core notifications on the client
local function tell(player, msg)
    send(player, "atc:trn:notify", msg)
end
Training.tell = tell

local function later(s, ms, fn)
    local timer = setTimer(function()
        if sessions[s.player] == s then fn() end
    end, ms, 1)
    s.timers[#s.timers + 1] = timer
    return timer
end
Training.later = later

local function fadeMs() return math.floor(TRAINING.FADE_TIME * 1000) end

local function freeDimension()
    local used = {}
    for _, s in pairs(sessions) do used[s.dimension] = true end
    local d = TRAINING.DIMENSION_BASE
    while used[d] do d = d + 1 end
    return d
end

---------------------------------------------------------------- account flags / unlocks

function Training.isDone(player, id)
    if not isRunning("v_mysql") then return false end
    return exports.v_mysql:getAccData(player, TRAINING.ACC_PREFIX .. id) == true
end

local function setAcc(player, key)
    if isElement(player) and isRunning("v_mysql") then exports.v_mysql:setAccData(player, key, true) end
end

-- the ATC right of the module (avi_core) unlocks it
function Training.isUnlocked(player, id)
    local def = TRAINING.MODULES[id]
    if not def then return false end
    return call("avi_core", "hasATCRight", player, def.right) == true
end

local function onDuty(player)
    return isRunning("work_core") and exports.work_core:isPlayerOnDuty(player, ATC.WORK_ID) == true
end

---------------------------------------------------------------- training aircraft

-- the fields of an avi_traffic snapshot the client needs (+ had = it was under the trainee's control)
local function compact(s, role, snap)
    if not snap then return nil end
    return { id = snap.id, cs = snap.cs, phase = snap.phase, req = snap.req, ready = snap.ready, ctl = snap.ctl,
        appClr = snap.appClr, landClr = snap.landClr, proc = snap.proc, gnd = snap.gnd, x = snap.x, y = snap.y,
        hdg = snap.hdg, alt = snap.alt, cfl = snap.cfl, rwy = snap.rwy, holdRwy = snap.holdRwy,
        had = s.had[role] == true, entry = s.entry[role] }
end

-- role -> snapshot of the session's aircraft
local function aircraftOf(s)
    local byId = {}
    for role, id in pairs(s.ids) do byId[id] = role end
    local out = {}
    for _, snap in ipairs(call("avi_traffic", "getTutorialSnapshot", s.player) or {}) do
        local role = byId[snap.id]
        if role then out[role] = snap end
    end
    return out
end
Training.aircraftOf = aircraftOf

-- the aircraft of the role was under the trainee's control and is not any more (gone, or left the
-- trainee's sector)
function Training.handedOff(s, role, ac)
    if not s.had[role] then return false end
    local snap = (ac or aircraftOf(s))[role]
    return not snap or snap.ctl ~= s.position
end

function Training.cmd(s, role, ...)
    local c = s.cmds[role]
    if not c then return false end
    for _, a in ipairs({ ... }) do
        if c[a] then return true end
    end
    return false
end

function Training.removeRole(s, role)
    local id = s.ids[role]
    if id then call("avi_traffic", "removeTutorialFlight", s.player, id) end
    s.ids[role], s.had[role], s.entry[role] = nil, nil, nil
    s.cmds[role] = {}
end

function Training.removeAll(s)
    for role in pairs(s.ids) do Training.removeRole(s, role) end
end

-- -> true | nil (the reason goes to the debug log). A role of kind "conflict" spawns its pair too.
function Training.spawnRole(s, role)
    local mod = s.module
    local def = mod.roles[role]
    local cs = TRAINING.CALLSIGNS[s.id] or {}
    local ids = {}
    if def.kind == "conflict" then
        local a, b = call("avi_traffic", "spawnTutorialConflict", s.player, { callsigns = { cs[role], cs[def.pair] } })
        if not a then
            outputDebugString("[work_atc] training conflict: " .. tostring(b), 2)
            return nil
        end
        ids[role], ids[def.pair] = a, b
    else
        local avoid = def.avoidFixOf and s.entry[def.avoidFixOf]
        local id, err = call("avi_traffic", "spawnTutorialFlight", s.player, {
            kind = def.kind, icao = def.icao or TRAINING.AIRPORT, callsign = cs[role], gateWait = TRAINING.GATE_WAIT,
            avoidFix = avoid, star = def.star,
        })
        if not id then
            outputDebugString("[work_atc] training aircraft: " .. tostring(err), 2)
            return nil
        end
        ids[role] = id
    end
    for r, id in pairs(ids) do s.ids[r], s.had[r], s.cmds[r] = id, nil, {} end
    local ac = aircraftOf(s)
    for r in pairs(ids) do
        local snap = ac[r]
        -- the first fix ahead = the TMA entry of an approach training arrival
        s.entry[r] = snap and snap.route and snap.route[1] or nil
        send(s.player, "atc:trn:info", "spawn", r, compact(s, r, snap))
    end
    return true
end

---------------------------------------------------------------- steps

local enterStep -- forward

local function setStep(s, step)
    s.step = step
    s.fastOk = false
    send(s.player, "atc:trn:step", step)
    enterStep(s, step)
end
Training.setStep = setStep

local function nextStep(s)
    for i, step in ipairs(s.module.steps) do
        if step == s.step then
            if s.module.steps[i + 1] then setStep(s, s.module.steps[i + 1]) end
            return
        end
    end
end

function Training.failed(s)
    tell(s.player, L.msg("work_atc.trn.server.aircraft_failed"))
    later(s, 2000, function() Training.finish(s.player, "error") end)
end

-- spawn the role (unless it is there) or end the module
function Training.ensure(s, role)
    if not s.ids[role] and not Training.spawnRole(s, role) then Training.failed(s) end
end

function enterStep(s, step)
    -- every module: the console step starts the scope part again without aircraft
    if step == "console" then Training.removeAll(s) end
    local fn = s.module.enter and s.module.enter[step]
    if fn then fn(s) end
end

-- the phases nobody has to act in (pushback, taxi, take-off, climb-out, approach, landing roll, taxi in)
local BUSY = { gate = true, pushback = true, pushed = true, taxi_out = true, lined = true, takeoff = true, air = true,
    final = true, landing = true, vacate = true, vacated = true, taxi_in = true, hold = true }

-- the time scale of the training aircraft: TRAINING.FAST_SCALE while the client allows it (the sub-step
-- only waits), one of them is on the move and none of the trainee's own asks for something, else 1
local function timeScale(s, ac)
    if not s.fastOk then return 1 end
    local moving = false
    for _, a in pairs(ac) do
        if a.req and a.ready and a.ctl == s.position then return 1 end
        if BUSY[a.phase] then moving = true end
    end
    return moving and TRAINING.FAST_SCALE or 1
end

local function setScale(s, scale)
    if s.scale == scale then return end
    s.scale = scale
    call("avi_traffic", "setTutorialTimeScale", s.player, scale)
end

-- every POLL: control tracking, the aircraft state to the client; a lost aircraft comes again
local function poll(s)
    local ac = aircraftOf(s)
    for role, snap in pairs(ac) do
        if snap.ctl == s.position then s.had[role] = true end
    end
    setScale(s, timeScale(s, ac))
    local out = {}
    for role in pairs(s.ids) do out[role] = compact(s, role, ac[role]) end
    send(s.player, "atc:trn:info", "aircraft", out, s.scale > 1 and s.scale or nil)

    -- an aircraft removed before the trainee had it (an admin, a sim error): a new one, from the
    -- step that brings it (lostAlways: even after the trainee had it)
    for role, steps in pairs(s.module.lost or {}) do
        local restart = steps[s.step]
        if restart and s.ids[role] and not ac[role] and (s.module.lostAlways or not s.had[role]) then
            tell(s.player, L.msg("work_atc.trn.server.aircraft_lost"))
            Training.removeRole(s, role)
            local pair = s.module.roles[role] and s.module.roles[role].pair
            if pair then Training.removeRole(s, pair) end
            return setStep(s, restart)
        end
    end
end

---------------------------------------------------------------- start / finish

local function requiredRunning()
    for _, name in ipairs({ "avi_core", "avi_controller", "avi_traffic", "avi_airports", "avi_nav", "avi_airspace",
            TRAINING.MAP_RESOURCE }) do
        if not isRunning(name) then return false end
    end
    return true
end

local function levelOf(right)
    for lv, def in ipairs(ATC.LEVELS) do
        for _, r in ipairs(def.rights) do
            if r == right then return lv end
        end
    end
end

local function nearMarker(player)
    local m = TRAINING.MARKER
    if getElementInterior(player) ~= m.interior then return false end
    local x, y, z = getElementPosition(player)
    return getDistanceBetweenPoints3D(x, y, z, m.x, m.y, m.z) < 15
end

-- -> true | false, reason
function Training.start(player, id)
    local def, mod = TRAINING.MODULES[id], Training.modules[id]
    if not def or not mod then return false, L.msg("work_atc.trn.server.unknown_module") end
    if sessions[player] then return false, L.msg("work_atc.trn.server.already_running") end
    if isPedDead(player) then return false, L.msg("work_atc.trn.server.cannot_start_now") end
    if getElementData(player, "isLogged") ~= true then return false, L.msg("work_atc.trn.server.log_in_first") end
    if not requiredRunning() then return false, L.msg("work_atc.trn.server.system_not_running") end
    if not Training.isUnlocked(player, id) then
        return false, L.msg("work_atc.trn.server.locked", { code = def.code, level = levelOf(def.right) or "?" })
    end
    if call("avi_controller", "getPlayerATCPosition", player) then
        return false, L.msg("work_atc.trn.server.log_out_first")
    end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local s = {
        player = player,
        id = id,
        def = def,
        module = mod,
        position = def.position,
        step = "starting",
        dimension = freeDimension(),
        saved = { x = x, y = y, z = z, rot = rot, int = getElementInterior(player), dim = getElementDimension(player) },
        stay = nearMarker(player),     -- started in the room: the same spot in the session's dimension
        timers = {},
        ids = {}, had = {}, entry = {}, cmds = {},
        scale = 1,
    }
    sessions[player] = s

    -- v_accounts saves this position instead of the training one
    local f = TRAINING.FINISH
    setElementData(player, "save.position", { f[1], f[2], f[3], f.interior, f.dimension }, false)

    fadeCamera(player, false, TRAINING.FADE_TIME)
    later(s, fadeMs() + 200, function()
        if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
        -- the SA Control room itself (map_int_sacontrol objects) in the session's dimension
        s.mapCopy = call(TRAINING.MAP_RESOURCE, "createDimensionCopy", s.dimension) == true
        if not s.mapCopy then outputDebugString("[work_atc] training: " .. TRAINING.MAP_RESOURCE .. " copy failed", 2) end
        s.marker = call("avi_core", "createTutorialMarker", player, s.dimension, s.position)
        if not s.marker then
            Training.finish(player, "error")
            return tell(player, L.msg("work_atc.trn.server.could_not_start"))
        end
        if s.stay then
            setElementDimension(player, s.dimension)
        else
            local p = TRAINING.START
            setElementInterior(player, p.interior or 0)
            setElementDimension(player, s.dimension)
            setElementPosition(player, p[1], p[2], p[3])
            setElementRotation(player, 0, 0, p[4] or 0)
        end
        setCameraTarget(player, player)
        local mx, my, mz = getElementPosition(s.marker)
        send(player, "atc:trn:begin", {
            module = id,
            code = def.code,
            steps = mod.steps,
            position = s.position,
            airport = TRAINING.AIRPORT,
            marker = { x = mx, y = my, z = mz },
            pay = call("avi_controller", "getATCPayRules") or {},
            ranks = { app = levelOf("APP") or 5, radar = levelOf("RADAR") or 8 },
            runways = (call("avi_airports", "getActiveRunways") or {})[TRAINING.AIRPORT],
        })
        setStep(s, mod.steps[1])
        s.poll = setTimer(function()
            if sessions[player] ~= s then return end
            poll(s)
        end, TRAINING.POLL, 0)
        later(s, 300, function() fadeCamera(player, true, TRAINING.FADE_TIME) end)
    end)
    return true
end

local function destroySessionWorld(s)
    local player = s.player
    -- the tutorial login first (its logout event finds no session any more), then the aircraft and
    -- the console
    if isElement(player) then call("avi_controller", "endATCTutorial", player, true) end
    call("avi_traffic", "removeTutorialFlights", player)
    call("avi_traffic", "setTutorialTimeScale", player, 1)
    s.scale = 1
    if s.marker then call("avi_core", "destroyTutorialMarker", s.marker) end
    s.marker = nil
    if s.mapCopy then call(TRAINING.MAP_RESOURCE, "destroyDimensionCopy", s.dimension) end
    s.mapCopy = nil
end

-- reason: "completed" | "quit_training" | "died" | "quit" | "error" | "stopped"
function Training.finish(player, reason)
    local s = sessions[player]
    if not s then return false end
    sessions[player] = nil

    for _, timer in ipairs(s.timers) do
        if isTimer(timer) then killTimer(timer) end
    end
    if isTimer(s.poll) then killTimer(s.poll) end
    destroySessionWorld(s)

    if reason == "quit" or not isElement(player) then return true end
    if reason == "completed" then setAcc(player, TRAINING.ACC_PREFIX .. s.id) end

    send(player, "atc:trn:end", reason)

    local saved = s.saved
    local f = TRAINING.FINISH
    local function restore()
        removeElementData(player, "save.position")
        setElementFrozen(player, false)
        if isPedDead(player) then return end
        setElementInterior(player, f.interior)
        setElementDimension(player, f.dimension)
        setElementPosition(player, f[1], f[2], f[3])
        setElementRotation(player, 0, 0, saved.rot)
        setCameraTarget(player, player)
        fadeCamera(player, true, TRAINING.FADE_TIME)
    end
    if reason == "died" then
        -- the spawn manager places the player; only the saved position override goes
        removeElementData(player, "save.position")
        if getElementDimension(player) == s.dimension then setElementDimension(player, saved.dim) end
    else
        -- the room copy is already gone: no falling through the floor while the screen fades
        setElementFrozen(player, true)
        fadeCamera(player, false, TRAINING.FADE_TIME)
        setTimer(function() if isElement(player) then restore() end end, fadeMs() + 200, 1)
    end

    if reason == "completed" then
        tell(player, L.msg("work_atc.trn.server.completed", { code = s.def.code }))
    elseif reason == "quit_training" then
        tell(player, L.msg("work_atc.trn.server.quit", { code = s.def.code }))
    end
    return true
end

function Training.isActive(player)
    return sessions[player] ~= nil
end

---------------------------------------------------------------- the training marker

local marker

local function applyMarkerVisibility()
    if not isElement(marker) then return end
    setElementVisibleTo(marker, root, false)
    if isRunning("work_core") then exports.work_core:setElementVisibleToWork(marker, ATC.WORK_ID) end
end

addEventHandler("onResourceStart", resourceRoot, function()
    local m = TRAINING.MARKER
    local c = m.color
    marker = createMarker(m.x, m.y, m.z, "cylinder", m.size, c[1], c[2], c[3], c[4])
    if not marker then return end
    setElementInterior(marker, m.interior or 0)
    setElementDimension(marker, m.dimension or 0)
    setElementData(marker, "atc.training", true)
    applyMarkerVisibility()
end)

addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, applyMarkerVisibility)

-- the module list for the card: { { id, code, unlocked, done, level, minutes } }
local function moduleList(player)
    local list = {}
    for _, id in ipairs(TRAINING.ORDER) do
        local def = TRAINING.MODULES[id]
        list[#list + 1] = { id = id, code = def.code, unlocked = Training.isUnlocked(player, id),
            done = Training.isDone(player, id), level = levelOf(def.right), minutes = def.minutes }
    end
    return list
end

local lastUse = {}

local function handle(name, fn)
    addEvent(name, true)
    addEventHandler(name, resourceRoot, function(...)
        if isElement(client) then fn(client, ...) end
    end)
end

-- E in the training marker: the module list
handle("atc:trn:marker", function(player)
    local now = getTickCount()
    if lastUse[player] and now - lastUse[player] < 750 then return end
    lastUse[player] = now
    if not isElement(marker) or Training.isActive(player) then return end
    if getElementDimension(player) ~= getElementDimension(marker)
        or getElementInterior(player) ~= getElementInterior(marker) then return end
    local px, py, pz = getElementPosition(player)
    local x, y, z = getElementPosition(marker)
    if getDistanceBetweenPoints2D(px, py, x, y) > TRAINING.MARKER.size / 2 + 3 or math.abs(pz - z) > 5 then return end
    if not onDuty(player) then return tell(player, L.msg("work_atc.trn.server.duty_first")) end
    send(player, "atc:trn:menu", moduleList(player))
end)

-- a module picked from the list
handle("atc:trn:choose", function(player, id)
    if Training.isActive(player) or not TRAINING.MODULES[id] then return end
    if not onDuty(player) then return tell(player, L.msg("work_atc.trn.server.duty_first")) end
    if not nearMarker(player) then return end
    local ok, err = Training.start(player, id)
    if not ok then tell(player, err) end
end)

---------------------------------------------------------------- client requests

-- answer to the first-duty offer (TRAINING.OFFER, the scope module)
handle("atc:trn:answer", function(player, accept)
    if Training.isActive(player) then return end
    setAcc(player, TRAINING.OFFER_KEY)
    if accept then
        local ok, err = Training.start(player, TRAINING.OFFER)
        if not ok then tell(player, err) end
    else
        tell(player, L.msg("work_atc.trn.server.no_problem"))
    end
end)

-- The client finished its part of a step; the server checks what it can
handle("atc:trn:next", function(player, step)
    local s = sessions[player]
    if not s or s.step ~= step then return end
    local check = s.module.checks and s.module.checks[step]
    if not check or not check(s, aircraftOf(s)) then return end
    if step == "done" then return Training.finish(player, "completed") end
    nextStep(s)
end)

-- the client sub-step only waits: the aircraft may fly faster
handle("atc:trn:fast", function(player, allowed)
    local s = sessions[player]
    if s then s.fastOk = allowed == true end
end)

-- the alert demonstration (ADC) is over: the arrival squawks its own code again
handle("atc:trn:restoreSquawk", function(player)
    local s = sessions[player]
    if s and s.ids.arr then call("avi_traffic", "setTutorialSquawk", player, s.ids.arr, nil) end
end)

handle("atc:trn:quit", function(player)
    Training.finish(player, "quit_training")
end)

---------------------------------------------------------------- avi_controller events

addEvent("onATCTutorialLogin")
addEventHandler("onATCTutorialLogin", root, function(player)
    local s = sessions[player]
    if s and s.step == "console" then nextStep(s) end
end)

-- Logout on the logout step of the module ("alerts", or its logoutStep) = the receipt, the module is
-- done. Earlier the scope part starts again (the aircraft fly on their own without the controller).
addEvent("onATCTutorialLogout")
addEventHandler("onATCTutorialLogout", root, function(player, _, total, items)
    local s = sessions[player]
    if not s then return end
    if s.step == (s.module.logoutStep or "alerts") then
        send(player, "atc:trn:info", "receipt", { total = total, items = items })
        nextStep(s)
    elseif s.step ~= "console" and s.step ~= "done" then
        tell(player, L.msg("work_atc.trn.server.logged_out_early", { console = TRAINING.KEYS.console }))
        setStep(s, "console")
    end
end)

addEvent("onATCTutorialCommand")
addEventHandler("onATCTutorialCommand", root, function(player, action, id)
    local s = sessions[player]
    if not s then return end
    local role
    for r, rid in pairs(s.ids) do
        if rid == id then role = r end
    end
    if not role then return end
    s.cmds[role] = s.cmds[role] or {}
    s.cmds[role][action] = true
    send(player, "atc:trn:info", "cmd", role, action)
end)

---------------------------------------------------------------- world events

addEventHandler("onPlayerWasted", root, function()
    if sessions[source] then
        Training.finish(source, "died")
        tell(source, L.msg("work_atc.trn.server.ended_died"))
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Training.finish(source, "quit")
    lastUse[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do Training.finish(player, "stopped") end
end)

-- avi_controller / avi_traffic stopped: the training cannot go on
addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    if name ~= "avi_controller" and name ~= "avi_traffic" and name ~= "avi_core" then return end
    for player in pairs(sessions) do
        Training.finish(player, "error")
        tell(player, L.msg("work_atc.trn.server.system_not_running"))
    end
end)

---------------------------------------------------------------- command

addCommandHandler(TRAINING.COMMAND, function(player, _, arg)
    if arg == "stop" or arg == "skip" or arg == "quit" then
        if not Training.finish(player, "quit_training") then tell(player, L.msg("work_atc.trn.server.not_running")) end
        return
    end
    tell(player, L.msg("work_atc.trn.server.usage", { command = TRAINING.COMMAND }))
end)

---------------------------------------------------------------- work duty

addEvent("onPlayerWorkDutyStart")

-- first duty start (or every one in debug mode): offer the scope module
addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId ~= ATC.WORK_ID or Training.isActive(source) then return end
    if not isRunning("v_mysql") then return end
    if TRAINING.DEBUG or (not Training.isDone(source, TRAINING.OFFER)
            and exports.v_mysql:getAccData(source, TRAINING.OFFER_KEY) ~= true) then
        send(source, "atc:trn:offer", TRAINING.MODULES[TRAINING.OFFER].minutes)
    end
end)
