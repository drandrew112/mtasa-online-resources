if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Blood transport tutorial: one session per player in its own dimension. It runs the real flow of
-- the service: the bt_dispatch panel, a tutorial shift and one tutorial task, the bt_items blood box
-- and the v_inventory ports (tutorial copies from bt_core). The server owns the session and the
-- world; the client shows the tutorial card and follows the panel / inventory (client/*.lua).
--
-- Steps: panel -> task -> box -> pickup -> drive -> deliver -> signoff -> done
--
-- The tutorial is never required. It is offered the first time a player goes on duty as a blood
-- transporter (or every time with TUTORIAL.DEBUG), and /tutorial_bt starts it any time.

Tutorial = { sessions = {} }

local sessions = Tutorial.sessions    -- player -> session
local STEPS = { "panel", "task", "box", "pickup", "drive", "deliver", "signoff", "done" }

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function send(player, name, ...)
    if isElement(player) then triggerClientEvent(player, name, resourceRoot, ...) end
end

-- outputChatBox is hidden (v_chat): messages go to ui_core notifications on the client
local function tell(player, msg)
    send(player, "bt:tut:notify", msg)
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

local function institution(id)
    return isRunning("bt_core") and exports.bt_core:getInstitution(id) or nil
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

---------------------------------------------------------------- steps

local enterStep -- forward

local function setStep(s, step)
    s.step = step
    send(s.player, "bt:tut:step", step)
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

local function taskStatus(s)
    local t = s.taskId and isRunning("bt_dispatch") and exports.bt_dispatch:getTask(s.taskId)
    return t and t.status or nil
end

local STEP_ENTER = {}

STEP_ENTER.panel = function(s)
    -- the vehicle stays put while the panel is explained
    if isElement(s.vehicle) then setElementFrozen(s.vehicle, true) end
    s.taskId = nil
end

STEP_ENTER.task = function(s)
    later(s, TUTORIAL.TASK_DELAY, function()
        local id, err = exports.bt_dispatch:createTutorialTask(s.player, TUTORIAL.TASK)
        if not id then
            outputDebugString("[work_bloodtransport] tutorial task: " .. tostring(err), 2)
            tell(s.player, L.msg("work_bloodtransport.tut.server.task_failed"))
            return later(s, 2000, function() Tutorial.finish(s.player, "error") end)
        end
        s.taskId = id
        send(s.player, "bt:tut:info", "task", id)
    end)
end

STEP_ENTER.box = function(s)
    if isElement(s.vehicle) then setElementFrozen(s.vehicle, false) end
end

-- The drive step ends at the destination, with the player driving the tutorial vehicle
STEP_ENTER.drive = function(s)
    local dest = institution(TUTORIAL.TASK.to)
    if not dest then return end
    s.poll = setTimer(function()
        if sessions[s.player] ~= s or s.step ~= "drive" then
            if isTimer(s.poll) then killTimer(s.poll) end
            s.poll = nil
            return
        end
        if not isElement(s.vehicle) or getPedOccupiedVehicle(s.player) ~= s.vehicle then return end
        local x, y, z = getElementPosition(s.vehicle)
        if getDistanceBetweenPoints3D(x, y, z, dest.x, dest.y, dest.z) <= TUTORIAL.ARRIVE_RANGE then
            killTimer(s.poll)
            s.poll = nil
            nextStep(s)
        end
    end, TUTORIAL.POLL, 0)
end

function enterStep(s, step)
    local fn = STEP_ENTER[step]
    if fn then fn(s) end
end

---------------------------------------------------------------- start / finish

local function requiredRunning()
    for _, name in ipairs({ "bt_core", "bt_items", "bt_dispatch", "v_inventory" }) do
        if not isRunning(name) then return false end
    end
    return true
end

-- -> true | false, reason
function Tutorial.start(player)
    if sessions[player] then return false, L.msg("work_bloodtransport.tut.server.already_running") end
    if isPedDead(player) then return false, L.msg("work_bloodtransport.tut.server.cannot_start_now") end
    if getElementData(player, "isLogged") ~= true then return false, L.msg("work_bloodtransport.tut.server.log_in_first") end
    if not requiredRunning() then return false, L.msg("work_bloodtransport.tut.server.system_not_running") end
    if exports.bt_dispatch:isPlayerInService(player) then
        return false, L.msg("work_bloodtransport.tut.server.end_service_first")
    end
    if not exports.v_inventory:isPlayerHandsFree(player) then
        return false, L.msg("work_bloodtransport.tut.server.hands_not_free")
    end
    local from, to = institution(TUTORIAL.TASK.from), institution(TUTORIAL.TASK.to)
    if not from or not to then return false, L.msg("work_bloodtransport.tut.server.system_not_running") end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local s = {
        player = player,
        step = "starting",
        dimension = freeDimension(),
        saved = { x = x, y = y, z = z, rot = rot, int = getElementInterior(player), dim = getElementDimension(player) },
        timers = {},
    }
    sessions[player] = s

    -- v_accounts saves this position instead of the tutorial one
    setElementData(player, "save.position", { x, y, z, s.saved.int, s.saved.dim }, false)
    if not exports.bt_core:hasRight(player) then
        exports.bt_core:setRight(player, true)
        s.grantedRight = true
    end

    fadeCamera(player, false, TUTORIAL.FADE_TIME)
    later(s, fadeMs() + 200, function()
        if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
        local v = TUTORIAL.VEHICLE
        local plate = BTWORK.PLATE_PREFIX .. ("%0" .. BTWORK.PLATE_DIGITS .. "d"):format(math.random(0, 10 ^ BTWORK.PLATE_DIGITS - 1))
        local vehicle = createVehicle(BTWORK.VEHICLES[1].model, v[1], v[2], v[3], 0, 0, v[4], plate)
        if not vehicle then
            Tutorial.finish(player, "error")
            return tell(player, L.msg("work_bloodtransport.tut.server.could_not_start"))
        end
        s.vehicle = vehicle
        setElementDimension(vehicle, s.dimension)
        setVehicleDamageProof(vehicle, true)
        setElementFrozen(vehicle, true)

        -- the tutorial copies of the two ports, the blood box, the tutorial vehicle for sign on
        s.ports = exports.bt_core:createTutorialPorts(s.dimension, { TUTORIAL.TASK.from, TUTORIAL.TASK.to }, player) or nil
        local box = exports.bt_items:addVehicleBox(vehicle, player)
        local ok = s.ports and box and exports.bt_dispatch:setTutorialVehicle(player, vehicle, s.ports)
        if not ok then
            Tutorial.finish(player, "error")
            return tell(player, L.msg("work_bloodtransport.tut.server.could_not_start"))
        end

        setElementInterior(player, 0)
        setElementDimension(player, s.dimension)
        warpPedIntoVehicle(player, vehicle, 0)
        setCameraTarget(player, player)
        local cargo = exports.bt_core:getConfig().PRODUCTS[TUTORIAL.TASK.product]
        send(player, "bt:tut:begin", vehicle, {
            from = { name = from.name, x = from.x, y = from.y, z = from.z },
            to = { name = to.name, x = to.x, y = to.y, z = to.z },
            cargoItem = cargo and cargo.item or "",
            pay = exports.bt_dispatch:getPayRules(),
        })
        setStep(s, "panel")
        later(s, 300, function() fadeCamera(player, true, TUTORIAL.FADE_TIME) end)
    end)
    return true
end

local function destroySessionWorld(s)
    local player = s.player
    -- the tutorial shift first (its task, cargo and box contents go with it), then the vehicle and
    -- the box, then the ports
    if isRunning("bt_dispatch") and isElement(player) then exports.bt_dispatch:setTutorialVehicle(player, nil) end
    if isElement(s.vehicle) then destroyElement(s.vehicle) end
    s.vehicle = nil
    if s.ports and isRunning("bt_core") then exports.bt_core:destroyTutorialPorts(s.ports) end
    s.ports = nil
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
    if isElement(player) and isRunning("v_inventory") then pcall(exports.v_inventory.closeInventory, exports.v_inventory, player) end
    destroySessionWorld(s)

    if reason == "quit" or not isElement(player) then return true end
    if reason == "completed" or reason == "skipped" then markDone(player) end

    send(player, "bt:tut:end", reason)
    if s.grantedRight and isRunning("bt_core") and not isPlayerBloodTransporter(player) then
        exports.bt_core:setRight(player, false)
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
        tell(player, L.msg("work_bloodtransport.tut.server.completed"))
    elseif reason == "skipped" then
        tell(player, L.msg("work_bloodtransport.tut.server.skipped", { command = TUTORIAL.COMMAND }))
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
handle("bt:tut:answer", function(player, accept)
    if Tutorial.isActive(player) then return end
    if accept then
        local ok, err = Tutorial.start(player)
        if not ok then tell(player, err) end
    else
        markDone(player)
        tell(player, L.msg("work_bloodtransport.tut.server.no_problem", { command = TUTORIAL.COMMAND }))
    end
end)

-- The client finished its part of a step; the server checks what it can
local CLIENT_STEPS = {
    task = function(s) return s.taskId ~= nil end,
    box = function() return true end,
    pickup = function(s) local st = taskStatus(s) return st == "transit" end,
    deliver = function(s) return s.delivered == true end,
    done = function() return true end,
}

handle("bt:tut:next", function(player, step)
    local s = sessions[player]
    if not s or s.step ~= step or not CLIENT_STEPS[step] or not CLIENT_STEPS[step](s) then return end
    if step == "done" then return Tutorial.finish(player, "completed") end
    nextStep(s)
end)

handle("bt:tut:skip", function(player)
    Tutorial.finish(player, "skipped")
end)

---------------------------------------------------------------- bt_dispatch events

addEvent("onBtTutorialShiftStart")
addEventHandler("onBtTutorialShiftStart", root, function()
    local s = sessions[source]
    if s and s.step == "panel" then nextStep(s) end
end)

-- reason "off" = Sign off. Before the sign off step it starts the service part again (the task is
-- cancelled with the shift); the other reasons (died, vehicle lost, quit) end the tutorial elsewhere.
addEvent("onBtTutorialShiftEnd")
addEventHandler("onBtTutorialShiftEnd", root, function(reason, total, items)
    local s = sessions[source]
    if not s or reason ~= "off" then return end
    if s.step == "signoff" then
        send(s.player, "bt:tut:info", "receipt", { total = total, items = items })
        nextStep(s)
    elseif s.step ~= "panel" and s.step ~= "done" then
        tell(s.player, L.msg("work_bloodtransport.tut.server.signed_off_early"))
        s.delivered = nil
        setStep(s, "panel")
    end
end)

addEvent("onBtTaskChanged")
addEventHandler("onBtTaskChanged", root, function(taskId, status)
    for player, s in pairs(sessions) do
        if s.taskId == taskId then
            if status == "delivered" then s.delivered = true end
            send(player, "bt:tut:info", "taskStatus", status)
        end
    end
end)

---------------------------------------------------------------- world events

addEventHandler("onPlayerWasted", root, function()
    if sessions[source] then
        Tutorial.finish(source, "died")
        tell(source, L.msg("work_bloodtransport.tut.server.ended_died"))
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Tutorial.finish(source, "quit")
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do Tutorial.finish(player, "stopped") end
end)

-- the tutorial vehicle stays with the tutorial
addEventHandler("onVehicleExplode", root, function()
    for player, s in pairs(sessions) do
        if s.vehicle == source then
            Tutorial.finish(player, "error")
            tell(player, L.msg("work_bloodtransport.tut.server.vehicle_destroyed", { command = TUTORIAL.COMMAND }))
        end
    end
end)

---------------------------------------------------------------- command

addCommandHandler(TUTORIAL.COMMAND, function(player, _, arg)
    if arg == "skip" or arg == "stop" then
        if not Tutorial.finish(player, "skipped") then tell(player, L.msg("work_bloodtransport.tut.server.not_running")) end
        return
    end
    local ok, err = Tutorial.start(player)
    if not ok then tell(player, err) end
end)

-- v_chat command list (CMD helper, no <include> needed)
loadstring(exports.v_chat:importCommands())()
CMD.register(TUTORIAL.COMMAND, "[skip]", 0, "Starts the blood transport tutorial, or ends it with skip.")

---------------------------------------------------------------- work duty

for _, name in ipairs({ "onPlayerWorkDutyStart", "onPlayerWorkDutyEnd" }) do addEvent(name) end

-- first duty start (or every one in debug mode): offer the tutorial
addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId ~= BTWORK.WORK_ID or Tutorial.isActive(source) then return end
    if TUTORIAL.DEBUG or not Tutorial.isDone(source) then
        send(source, "bt:tut:offer", TUTORIAL.DEBUG)
    end
end)

-- server/main.lua takes the right on duty end; the tutorial keeps it while it runs
addEventHandler("onPlayerWorkDutyEnd", root, function(workId)
    local s = sessions[source]
    if s and workId == BTWORK.WORK_ID and isRunning("bt_core") then
        exports.bt_core:setRight(source, true)
        s.grantedRight = true
    end
end)
