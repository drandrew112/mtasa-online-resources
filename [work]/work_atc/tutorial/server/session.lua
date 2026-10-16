if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Air traffic controller tutorial: one session per player in the SA Control room (interior 3) in a
-- dimension of its own. It runs the real ATC flow on the tower position TUTORIAL.POSITION: the
-- avi_core console marker (a tutorial copy), the avi_controller scope (a tutorial login: the live
-- position stays free, no pay, no XP) and two tutorial aircraft of avi_traffic that fly in a world of
-- their own (no live traffic around them). The server owns the session, the aircraft and the steps;
-- the client shows the tutorial card and follows the scope (client/*.lua).
--
-- Steps: console -> scope -> label -> delivery -> ground -> air -> arrival -> alerts -> done
--
-- The tutorial is never required. It is offered the first time a player goes on duty as an air
-- traffic controller (or every time with TUTORIAL.DEBUG), and /tutorial_atc starts it any time.

Tutorial = { sessions = {} }

local sessions = Tutorial.sessions    -- player -> session
local STEPS = { "console", "scope", "label", "delivery", "ground", "air", "arrival", "alerts", "done" }

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function call(resource, fn, ...)
    if not isRunning(resource) then return nil end
    local ok, a, b = pcall(function(...) return exports[resource][fn](exports[resource], ...) end, ...)
    if not ok then
        outputDebugString(("[work_atc] tutorial: %s:%s failed: %s"):format(resource, fn, tostring(a)), 2)
        return nil
    end
    return a, b
end

local function send(player, name, ...)
    if isElement(player) then triggerClientEvent(player, name, resourceRoot, ...) end
end

-- outputChatBox is hidden (v_chat): messages go to ui_core notifications on the client
local function tell(player, msg)
    send(player, "atc:tut:notify", msg)
end

local function later(s, ms, fn)
    local timer = setTimer(function()
        if sessions[s.player] == s then fn() end
    end, ms, 1)
    s.timers[#s.timers + 1] = timer
    return timer
end

local function fadeMs() return math.floor(TUTORIAL.FADE_TIME * 1000) end

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

---------------------------------------------------------------- tutorial aircraft

-- the fields of an avi_traffic snapshot the client needs
local function compact(snap)
    if not snap then return nil end
    return { id = snap.id, cs = snap.cs, phase = snap.phase, req = snap.req, ready = snap.ready, ctl = snap.ctl,
        appClr = snap.appClr, landClr = snap.landClr, proc = snap.proc, gnd = snap.gnd, x = snap.x, y = snap.y,
        rwy = snap.rwy, holdRwy = snap.holdRwy }
end

local function aircraftOf(s)
    local out = {}
    for _, snap in ipairs(call("avi_traffic", "getTutorialSnapshot", s.player) or {}) do
        if snap.id == s.depId then out.dep = snap end
        if snap.id == s.arrId then out.arr = snap end
    end
    return out
end

-- the departure is out of the tutorial position's hands (gone, or left the CTR airborne)
local function depLost(s, ac)
    local dep = (ac or aircraftOf(s)).dep
    return not dep or (not dep.gnd and dep.ctl ~= TUTORIAL.POSITION)
end

local function removeRole(s, role)
    local key = role .. "Id"
    if s[key] then call("avi_traffic", "removeTutorialFlight", s.player, s[key]) end
    s[key] = nil
    s.cmds[role] = {}
end

-- -> id | nil (the reason is told to the player)
local function spawnRole(s, role)
    local def = role == "dep" and TUTORIAL.DEPARTURE or TUTORIAL.ARRIVAL
    local id, err = call("avi_traffic", "spawnTutorialFlight", s.player, {
        kind = role, icao = TUTORIAL.AIRPORT, callsign = def.callsign, gateWait = def.gateWait,
    })
    if not id then
        outputDebugString("[work_atc] tutorial aircraft: " .. tostring(err), 2)
        return nil
    end
    s[role .. "Id"] = id
    s.cmds[role] = {}
    local snap = aircraftOf(s)[role]
    send(s.player, "atc:tut:info", "spawn", role, compact(snap))
    return id
end

---------------------------------------------------------------- steps

local enterStep -- forward

local function setStep(s, step)
    s.step = step
    send(s.player, "atc:tut:step", step)
    enterStep(s, step)
end

local function nextStep(s)
    for i, step in ipairs(STEPS) do
        if step == s.step then
            if STEPS[i + 1] then setStep(s, STEPS[i + 1]) end
            return
        end
    end
end

local function failed(s)
    tell(s.player, L.msg("work_atc.tut.server.aircraft_failed"))
    later(s, 2000, function() Tutorial.finish(s.player, "error") end)
end

local STEP_ENTER = {}

-- (also after an early logout: everything from the start of the scope part again)
STEP_ENTER.console = function(s)
    removeRole(s, "dep")
    removeRole(s, "arr")
end

STEP_ENTER.label = function(s)
    if not s.depId and not spawnRole(s, "dep") then failed(s) end
end

STEP_ENTER.arrival = function(s)
    removeRole(s, "dep")
    if not spawnRole(s, "arr") then failed(s) end
end

STEP_ENTER.alerts = function(s)
    if s.arrId then call("avi_traffic", "setTutorialSquawk", s.player, s.arrId, TUTORIAL.ALERT_SQUAWK) end
end

function enterStep(s, step)
    local fn = STEP_ENTER[step]
    if fn then fn(s) end
end

-- every POLL: the aircraft state to the client; a lost aircraft comes again
local function poll(s)
    local ac = aircraftOf(s)
    send(s.player, "atc:tut:info", "aircraft", { dep = compact(ac.dep), arr = compact(ac.arr) })
    local st = s.step
    if s.depId and not ac.dep and (st == "label" or st == "delivery" or st == "ground") then
        -- the departure was removed (an admin, a sim error): a new one, from its first step
        tell(s.player, L.msg("work_atc.tut.server.aircraft_lost"))
        removeRole(s, "dep")
        setStep(s, "label")
    elseif s.arrId and not ac.arr and (st == "arrival" or st == "alerts") then
        tell(s.player, L.msg("work_atc.tut.server.aircraft_lost"))
        removeRole(s, "arr")
        setStep(s, "arrival")
    end
end

---------------------------------------------------------------- start / finish

local function requiredRunning()
    for _, name in ipairs({ "avi_core", "avi_controller", "avi_traffic", "avi_airports", "avi_nav", "avi_airspace" }) do
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

-- -> true | false, reason
function Tutorial.start(player)
    if sessions[player] then return false, L.msg("work_atc.tut.server.already_running") end
    if isPedDead(player) then return false, L.msg("work_atc.tut.server.cannot_start_now") end
    if getElementData(player, "isLogged") ~= true then return false, L.msg("work_atc.tut.server.log_in_first") end
    if not requiredRunning() then return false, L.msg("work_atc.tut.server.system_not_running") end
    if call("avi_controller", "getPlayerATCPosition", player) then
        return false, L.msg("work_atc.tut.server.log_out_first")
    end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local s = {
        player = player,
        step = "starting",
        dimension = freeDimension(),
        saved = { x = x, y = y, z = z, rot = rot, int = getElementInterior(player), dim = getElementDimension(player) },
        timers = {},
        cmds = { dep = {}, arr = {} },
    }
    sessions[player] = s

    -- v_accounts saves this position instead of the tutorial one
    setElementData(player, "save.position", { x, y, z, s.saved.int, s.saved.dim }, false)

    fadeCamera(player, false, TUTORIAL.FADE_TIME)
    later(s, fadeMs() + 200, function()
        if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
        s.marker = call("avi_core", "createTutorialMarker", player, s.dimension, TUTORIAL.POSITION)
        if not s.marker then
            Tutorial.finish(player, "error")
            return tell(player, L.msg("work_atc.tut.server.could_not_start"))
        end
        local p = TUTORIAL.START
        setElementInterior(player, p.interior or 0)
        setElementDimension(player, s.dimension)
        setElementPosition(player, p[1], p[2], p[3])
        setElementRotation(player, 0, 0, p[4] or 0)
        setCameraTarget(player, player)
        local mx, my, mz = getElementPosition(s.marker)
        send(player, "atc:tut:begin", {
            position = TUTORIAL.POSITION,
            airport = TUTORIAL.AIRPORT,
            marker = { x = mx, y = my, z = mz },
            pay = call("avi_controller", "getATCPayRules") or {},
            ranks = { app = levelOf("APP") or 5, radar = levelOf("RADAR") or 8 },
            runways = (call("avi_airports", "getActiveRunways") or {})[TUTORIAL.AIRPORT],
        })
        setStep(s, "console")
        s.poll = setTimer(function()
            if sessions[player] ~= s then return end
            poll(s)
        end, TUTORIAL.POLL, 0)
        later(s, 300, function() fadeCamera(player, true, TUTORIAL.FADE_TIME) end)
    end)
    return true
end

local function destroySessionWorld(s)
    local player = s.player
    -- the tutorial login first (its logout event finds no session any more), then the aircraft and
    -- the console
    if isElement(player) then call("avi_controller", "endATCTutorial", player, true) end
    call("avi_traffic", "removeTutorialFlights", player)
    if s.marker then call("avi_core", "destroyTutorialMarker", s.marker) end
    s.marker = nil
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
    destroySessionWorld(s)

    if reason == "quit" or not isElement(player) then return true end
    if reason == "completed" or reason == "skipped" then markDone(player) end

    send(player, "atc:tut:end", reason)

    local saved = s.saved
    local function restore()
        removeElementData(player, "save.position")
        if isPedDead(player) then return end
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
        tell(player, L.msg("work_atc.tut.server.completed"))
    elseif reason == "skipped" then
        tell(player, L.msg("work_atc.tut.server.skipped", { command = TUTORIAL.COMMAND }))
    end
    return true
end

function Tutorial.isActive(player)
    return sessions[player] ~= nil
end

---------------------------------------------------------------- client requests

local function handle(name, fn)
    addEvent(name, true)
    addEventHandler(name, resourceRoot, function(...)
        if isElement(client) then fn(client, ...) end
    end)
end

-- answer to the first-duty offer
handle("atc:tut:answer", function(player, accept)
    if Tutorial.isActive(player) then return end
    if accept then
        local ok, err = Tutorial.start(player)
        if not ok then tell(player, err) end
    else
        markDone(player)
        tell(player, L.msg("work_atc.tut.server.no_problem", { command = TUTORIAL.COMMAND }))
    end
end)

-- The client finished its part of a step; the server checks what it can
local CLIENT_STEPS = {
    scope = function() return true end,
    label = function(s) return s.depId ~= nil end,
    delivery = function(s) return s.cmds.dep.push == true end,
    ground = function(s) return s.cmds.dep.takeoff == true end,
    air = function(s) return depLost(s) end,
    arrival = function(s)
        local arr = aircraftOf(s).arr
        return arr ~= nil and arr.phase == "parked"
    end,
    done = function() return true end,
}

handle("atc:tut:next", function(player, step)
    local s = sessions[player]
    if not s or s.step ~= step or not CLIENT_STEPS[step] or not CLIENT_STEPS[step](s) then return end
    if step == "done" then return Tutorial.finish(player, "completed") end
    nextStep(s)
end)

-- the alert demonstration is over: the arrival squawks its own code again
handle("atc:tut:restoreSquawk", function(player)
    local s = sessions[player]
    if s and s.arrId then call("avi_traffic", "setTutorialSquawk", player, s.arrId, nil) end
end)

handle("atc:tut:skip", function(player)
    Tutorial.finish(player, "skipped")
end)

---------------------------------------------------------------- avi_controller events

addEvent("onATCTutorialLogin")
addEventHandler("onATCTutorialLogin", root, function(player)
    local s = sessions[player]
    if s and s.step == "console" then nextStep(s) end
end)

-- Logout on the last step = the receipt, the tutorial is done. Earlier the scope part starts again
-- (the aircraft fly on their own without the controller).
addEvent("onATCTutorialLogout")
addEventHandler("onATCTutorialLogout", root, function(player, _, total, items)
    local s = sessions[player]
    if not s then return end
    if s.step == "alerts" then
        send(player, "atc:tut:info", "receipt", { total = total, items = items })
        nextStep(s)
    elseif s.step ~= "console" and s.step ~= "done" then
        tell(player, L.msg("work_atc.tut.server.logged_out_early", { console = TUTORIAL.KEYS.console }))
        setStep(s, "console")
    end
end)

addEvent("onATCTutorialCommand")
addEventHandler("onATCTutorialCommand", root, function(player, action, id)
    local s = sessions[player]
    if not s then return end
    local role = (id == s.depId and "dep") or (id == s.arrId and "arr") or nil
    if not role then return end
    s.cmds[role][action] = true
    send(player, "atc:tut:info", "cmd", role, action)
end)

---------------------------------------------------------------- world events

addEventHandler("onPlayerWasted", root, function()
    if sessions[source] then
        Tutorial.finish(source, "died")
        tell(source, L.msg("work_atc.tut.server.ended_died"))
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Tutorial.finish(source, "quit")
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do Tutorial.finish(player, "stopped") end
end)

-- avi_controller / avi_traffic stopped: the tutorial cannot go on
addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    if name ~= "avi_controller" and name ~= "avi_traffic" and name ~= "avi_core" then return end
    for player in pairs(sessions) do
        Tutorial.finish(player, "error")
        tell(player, L.msg("work_atc.tut.server.system_not_running"))
    end
end)

---------------------------------------------------------------- command

addCommandHandler(TUTORIAL.COMMAND, function(player, _, arg)
    if arg == "skip" or arg == "stop" then
        if not Tutorial.finish(player, "skipped") then tell(player, L.msg("work_atc.tut.server.not_running")) end
        return
    end
    local ok, err = Tutorial.start(player)
    if not ok then tell(player, err) end
end)

---------------------------------------------------------------- work duty

addEvent("onPlayerWorkDutyStart")

-- first duty start (or every one in debug mode): offer the tutorial
addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId ~= ATC.WORK_ID or Tutorial.isActive(source) then return end
    if TUTORIAL.DEBUG or not Tutorial.isDone(source) then
        send(source, "atc:tut:offer", TUTORIAL.DEBUG)
    end
end)
