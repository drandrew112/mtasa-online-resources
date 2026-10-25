if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- bt_dispatch core: tasks, services (shifts), assignment, status changes, payment.
--
-- A task is waiting (cargo on the pickup port) -> transit (cargo in the unit's box) -> delivered
-- (cargo on the destination port) or cancelled. The service of a transporter ("shift") is not the
-- work duty: it starts in the own work vehicle and ends on request or when the duty ends, the
-- vehicle is lost or the player dies.

addEvent("onBtShiftStart")
addEvent("onBtShiftEnd")
addEvent("onBtTutorialShiftStart")
addEvent("onBtTutorialShiftEnd")
addEvent("onBtTaskChanged")
addEvent("onBtCoreStart")
addEvent("onBtItemsStart")
addEvent("onPlayerWorkDutyEnd")

Tasks = {}           -- id -> task
Shifts = {}          -- player -> shift
ShiftById = {}       -- shift id -> shift
Recent = {}          -- player -> { { task, till } } closed tasks still shown for DONE_VISIBLE s
TotalDelivered = 0   -- since the resource started (the web page adds the database count)
-- Tutorial (work_bloodtransport tutorial, server/tutorial.lua): player -> { vehicle, ports }. Its shift
-- and task are flagged `tutorial`: memory only (no database, stock, pay, XP), never counted as a unit.
TutorialOf = {}

local C                         -- bt_core config (+ byId)

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- pay and XP: adjustable on the /gov Works page (gov_works), the BTD values are the defaults
local WAGE_PARAMS = {
    { key = "base",        label = "Base pay (per service)",    default = BTD.PAY.BASE },
    { key = "delivered",   label = "Per delivered task",        default = BTD.PAY.DELIVERED },
    { key = "in_transit",  label = "Per task still in transit", default = BTD.PAY.IN_TRANSIT },
    { key = "xp_delivery", label = "XP per delivery",           default = BTD.XP_PER_DELIVERY, kind = "xp" },
}
local wageDefault = {}
for _, p in ipairs(WAGE_PARAMS) do wageDefault[p.key] = p.default end

local function wage(key)
    if isRunning("gov_works") then
        local v = exports.gov_works:getWage(BTD.WORK_ID, key)
        if v then return v end
    end
    return wageDefault[key]
end

--- the pay table of BTLogic.pay with the /gov values
function BTD.currentPay()
    return { BASE = wage("base"), DELIVERED = wage("delivered"), IN_TRANSIT = wage("in_transit") }
end

addEventHandler("onResourceStart", root, function(res)
    if (res == getThisResource() or getResourceName(res) == "gov_works") and isRunning("gov_works") then
        exports.gov_works:registerWage(BTD.WORK_ID, WAGE_PARAMS)
    end
end)

function BTC()
    if not C and isRunning("bt_core") then
        C = exports.bt_core:getConfig()
        C.byId = {}
        for _, inst in ipairs(C.INSTITUTIONS) do C.byId[inst.id] = inst end
    end
    return C
end
addEventHandler("onBtCoreStart", root, function() C = nil end)

function instName(id)
    local c = BTC()
    local inst = c and c.byId[id]
    return inst and inst.name or tostring(id)
end

-- sound = true: silent ui_core notification + the dispatch tone (assets/new.wav) instead
function notify(player, title, text, sound)
    if isElement(player) then triggerClientEvent(player, "btd:notify", resourceRoot, title, text, sound == true) end
end

local function rnd(a, b) return a + math.random() * (b - a) end
BTRandom = rnd

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

function openTasksOf(shift)
    local list = {}
    for _, t in pairs(Tasks) do
        if t.shift == shift and (t.status == "waiting" or t.status == "transit") then list[#list + 1] = t end
    end
    return list
end

function openCount(shift)
    local n = 0
    for _, t in pairs(Tasks) do
        if t.shift == shift and (t.status == "waiting" or t.status == "transit") then n = n + 1 end
    end
    return n
end

function shiftList()
    local list = {}
    for _, s in pairs(Shifts) do
        if not s.tutorial then list[#list + 1] = s end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Units that may get a new task (not winding down)
function activeUnitCount()
    local n = 0
    for _, s in pairs(Shifts) do if not s.windDown and not s.tutorial then n = n + 1 end end
    return n
end

function dutyCount()
    local n = 0
    for _, s in pairs(Shifts) do if not s.tutorial then n = n + 1 end end
    return n
end

function openTaskTotal()
    local n = 0
    for _, t in pairs(Tasks) do
        if not t.tutorial and (t.status == "waiting" or t.status == "transit") then n = n + 1 end
    end
    return n
end

function refreshItems(player)
    if isElement(player) and isRunning("bt_items") then exports.bt_items:refreshPlayer(player) end
end

-- Objective of the route button: the pickup point of a waiting task, the destination of a task in transit
function updateRoute(shift)
    local player = shift.player
    if not isRunning("v_radar") then return end
    local task = shift.route and Tasks[shift.route]
    if not task or task.shift ~= shift or (task.status ~= "waiting" and task.status ~= "transit") then
        if shift.route then
            shift.route = nil
            pcall(exports.v_radar.clearObjectives, exports.v_radar, player)
        end
        return
    end
    local instId = task.status == "waiting" and task.from or task.to
    local inst = BTC().byId[instId]
    if not inst then return end
    pcall(exports.v_radar.clearObjectives, exports.v_radar, player)
    exports.v_radar:addObjective(player, inst.x, inst.y, inst.z, inst.name)
end

-- ---------------------------------------------------------------------------------------------
-- Tasks
-- ---------------------------------------------------------------------------------------------

function newTaskDescription(task)
    return {
        id = task.id, type = task.type, product = task.product, group = task.group, units = task.units,
        from = task.from, to = task.to, fromPort = task.fromPort, toPort = task.toPort,
    }
end

local function assign(task, shift)
    task.shift, task.player = shift, shift.player
    shift.order[#shift.order + 1] = task.id
    DB.setTask(task.id, { shift_id = shift.id, assigned_at = DB.nowText() })
    DB.addShiftTask(shift.id, task.id)
    DB.log(task.id, "assigned", shift.unit)
end

-- def: type, urgency, product, group, units, from, to, source, reserved (the units are already taken
-- from the stock) -> id | false, reason
function makeTask(def, callerName)
    local c = BTC()
    if not c then return false, "bt_core" end
    local rules = BTD.TYPES[def.type]
    local ok, why = BTLogic.checkTask(BTD.TYPES, c.byId, def)
    if not ok then return false, why end
    if rules.only and callerName ~= rules.only then return false, "not allowed for " .. tostring(callerName) end
    local units = math.max(1, math.floor(tonumber(def.units) or 1))

    -- who gets it: the least loaded unit
    local list, units_ = {}, {}
    local inst = c.byId[def.from]
    for _, s in ipairs(shiftList()) do
        local dist = 0
        if isElement(s.vehicle) then
            local x, y, z = getElementPosition(s.vehicle)
            dist = getDistanceBetweenPoints2D(x, y, inst.x, inst.y)
        end
        list[#list + 1] = s
        units_[#units_ + 1] = { open = openCount(s), windDown = s.windDown, dist = dist }
    end
    local idx = BTLogic.pickUnit(units_, BTD.MAX_OPEN_PER_UNIT)
    if not idx then return false, "no_unit" end
    local shift = list[idx]

    local task = {
        type = def.type, urgency = def.urgency or rules.urgency, source = def.source or "random",
        product = def.product, group = def.group, units = units, from = def.from, to = def.to,
        status = "waiting", reserved = def.reserved == true, createdAt = getRealTime().timestamp,
    }
    task.id = DB.insertTask(task)
    if not task.id then return false, "database" end
    Tasks[task.id] = task
    DB.log(task.id, "created", task.source)
    assign(task, shift)

    if not (isRunning("bt_items") and exports.bt_items:spawnCargo(newTaskDescription(task))) then
        closeTask(task, "cancelled", "cargo")
        return false, "cargo"
    end

    notify(shift.player, L.msg("bt_dispatch.notify.title"), L.msg("bt_dispatch.notify.new_task", {
        id = task.id, what = L.msg(taskWhatKey(task)), group = task.group or "", units = task.units,
        from = instName(task.from), to = instName(task.to) }), true)
    refreshItems(shift.player)
    SyncPlayer(shift.player)
    triggerEvent("onBtTaskChanged", resourceRoot, task.id, "waiting")
    return task.id
end

-- Message key of "RBC 0- x4" style names
function taskWhatKey(task)
    if task.type == "lab_sample" then return "bt_dispatch.what.lab_sample" end
    if task.type == "urgent_medicine" then return "bt_dispatch.what.urgent_medicine" end
    return "bt_dispatch.what." .. tostring(task.product)
end

-- Supply tasks (blood from the centers): takes the units from the stock and creates the tasks.
-- req: type, urgency, product, group, units, to -> { ids } | false, reason
function makeSupply(req, callerName)
    if activeUnitCount() == 0 then return false, "no_unit" end
    if not isRunning("bt_stock") then return false, "bt_stock" end
    local rules = BTD.TYPES[req.type]
    if not rules or not rules.stock then return false, "unknown type" end
    local legs = exports.bt_stock:allocate(req.product, req.group, req.units, req.to, false)
    if not legs then return false, "no_stock" end
    local ids = {}
    for _, leg in ipairs(legs) do
        for _, n in ipairs(BTLogic.chunks(leg.units, BTD.MAX_UNITS_PER_TASK)) do
            local id = makeTask({ type = req.type, urgency = req.urgency, product = req.product, group = req.group,
                units = n, from = leg.from, to = req.to, source = req.source or "random", reserved = true }, callerName)
            if id then ids[#ids + 1] = id
            else exports.bt_stock:release(leg.from, req.product, req.group, n) end
        end
    end
    if #ids == 0 then return false, "no_unit" end
    return ids
end

-- Closes a task as delivered / cancelled
function closeTask(task, status, reason)
    if task.status == "delivered" or task.status == "cancelled" then return end
    local shift, player = task.shift, task.player
    local pickedUp = task.pickedAt ~= nil
    task.status = status
    local at = DB.nowText()
    local db = not task.tutorial
    if status == "delivered" then
        task.deliveredAt = getRealTime().timestamp
        if db then DB.setTask(task.id, { status = status, delivered_at = at }) end
    else
        task.cancelReason = reason
        if db then DB.setTask(task.id, { status = status, cancelled_at = at, cancel_reason = reason }) end
    end
    if db then DB.log(task.id, status, reason) end
    if shift then
        if db then DB.releaseShiftTask(shift.id, task.id, status) end
        for i, id in ipairs(shift.order) do
            if id == task.id then table.remove(shift.order, i) break end
        end
        if shift.route == task.id then updateRoute(shift) end
    end
    if isRunning("bt_items") then exports.bt_items:destroyCargo(task.id) end
    if db and isRunning("bt_stock") then
        exports.bt_stock:taskClosed({ type = task.type, status = status, from = task.from, to = task.to,
            product = task.product, group = task.group, units = task.units, source = task.source,
            pickedUp = pickedUp })
    end
    if isElement(player) then
        Recent[player] = Recent[player] or {}
        Recent[player][#Recent[player] + 1] = { task = task, till = getTickCount() + BTD.DONE_VISIBLE * 1000 }
        refreshItems(player)
        SyncPlayer(player)
        setTimer(SyncPlayer, BTD.DONE_VISIBLE * 1000 + 100, 1, player)
    end
    triggerEvent("onBtTaskChanged", resourceRoot, task.id, status)
    -- closed tasks leave the memory after the panel stopped showing them
    setTimer(function() Tasks[task.id] = nil end, (BTD.DONE_VISIBLE + 5) * 1000, 1)
end

-- bt_items: the cargo left the pickup port into the box of the player
function onPickedUp(taskId, player)
    local task = Tasks[taskId]
    if not task or task.status ~= "waiting" or task.player ~= player then return false end
    task.status, task.pickedAt = "transit", getRealTime().timestamp
    for i, id in ipairs(task.shift.order) do
        if id == task.id then table.remove(task.shift.order, i) break end
    end
    if not task.tutorial then
        DB.setTask(task.id, { status = "transit", picked_at = DB.nowText() })
        DB.log(task.id, "picked_up", task.shift.unit)
    end
    updateRoute(task.shift)
    refreshItems(player)
    SyncPlayer(player)
    triggerEvent("onBtTaskChanged", resourceRoot, task.id, "transit")
    return true
end

-- bt_items: the cargo was put on the destination port
function onDelivered(taskId, player)
    local task = Tasks[taskId]
    if not task or task.status ~= "transit" or task.player ~= player then return false end
    local shift = task.shift
    shift.delivered = shift.delivered + 1
    if not task.tutorial then TotalDelivered = TotalDelivered + 1 end
    closeTask(task, "delivered")
    if not task.tutorial and isRunning("work_core") then exports.work_core:giveWorkXp(player, BTD.WORK_ID, wage("xp_delivery")) end
    if not task.tutorial and isRunning("v_stats") then exports.v_stats:addStat(player, "bt_deliveries", 1) end
    notify(player, L.msg("bt_dispatch.notify.title"), L.msg("bt_dispatch.notify.delivered", { id = task.id, to = instName(task.to) }))
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Service (shift)
-- ---------------------------------------------------------------------------------------------

local nextTutorialShift = 0

function signOn(player)
    if Shifts[player] then return false, "already" end
    if not isRunning("bt_core") or not exports.bt_core:hasRight(player) then return false, "no_right" end
    local tutorial = TutorialOf[player]
    local vehicle = getPedOccupiedVehicle(player)
    if tutorial then
        -- the tutorial vehicle instead of the work duty and the work vehicle
        if not vehicle or vehicle ~= tutorial.vehicle then return false, "no_vehicle" end
    else
        if not isRunning("work_core") or not exports.work_core:isPlayerOnDuty(player, BTD.WORK_ID) then return false, "no_duty" end
        if not vehicle or vehicle ~= exports.work_core:getPlayerWorkVehicle(player) or not BTD.VEHICLE_MODELS[getElementModel(vehicle)] then
            return false, "no_vehicle"
        end
    end
    if isPedDead(player) then return false, "dead" end
    local unit = (getVehiclePlateText(vehicle) or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local account = isRunning("acc_auth") and exports.acc_auth:getName(player) or nil
    local shift = {
        player = player, vehicle = vehicle, unit = unit, name = getPlayerName(player):gsub("#%x%x%x%x%x%x", ""),
        account = account or getPlayerName(player), windDown = false, order = {}, delivered = 0, startedTick = getTickCount(),
        startedAt = getRealTime().timestamp, tutorial = tutorial and true or nil,
    }
    if tutorial then
        nextTutorialShift = nextTutorialShift - 1
        shift.id = nextTutorialShift
    else
        shift.id = DB.insertShift(shift)
    end
    if not shift.id then return false, "database" end
    Shifts[player], ShiftById[shift.id] = shift, shift
    refreshItems(player)
    SyncPlayer(player)
    if tutorial then
        triggerEvent("onBtTutorialShiftStart", player)
    else
        triggerEvent("onBtShiftStart", player, shift.id)
    end
    return true
end

function setWindDown(player, on)
    local shift = Shifts[player]
    if not shift then return false end
    shift.windDown = on == true
    SyncPlayer(player)
    return true
end

-- Pay of the running service as it would be now -> total, items
function estimatePay(shift)
    local inTransit = 0
    for _, t in ipairs(openTasksOf(shift)) do if t.status == "transit" then inTransit = inTransit + 1 end end
    local items, total = BTLogic.pay(BTD.currentPay(), shift.delivered, inTransit)
    return total, items
end

local PAY_REASON = {
    off = "bt_dispatch.pay.reason_off", duty_end = "bt_dispatch.pay.reason_duty_end", vehicle_lost = "bt_dispatch.pay.reason_vehicle_lost",
    died = "bt_dispatch.pay.reason_died", quit = "bt_dispatch.pay.reason_quit",
}
local PAY_LABEL = { base = "bt_dispatch.pay.base", delivered = "bt_dispatch.pay.delivered", in_transit = "bt_dispatch.pay.in_transit" }

-- reason: "off" | "duty_end" | "vehicle_lost" | "died" | "quit"
function endShift(player, reason)
    local shift = Shifts[player]
    if not shift then return false end
    local open = openTasksOf(shift)
    local inTransit = 0
    for _, t in ipairs(open) do if t.status == "transit" then inTransit = inTransit + 1 end end
    local items, total = BTLogic.pay(BTD.currentPay(), shift.delivered, inTransit)

    Shifts[player], ShiftById[shift.id] = nil, nil
    if cancelOffersOf then cancelOffersOf(shift) end
    for _, t in ipairs(open) do closeTask(t, "cancelled", "shift_" .. reason) end
    if isElement(shift.vehicle) and isRunning("bt_items") then exports.bt_items:clearBox(shift.vehicle) end
    if isRunning("v_radar") and isElement(player) then pcall(exports.v_radar.clearObjectives, exports.v_radar, player) end

    if not shift.tutorial then
        DB.endShift(shift.id, { reason = reason, delivered = shift.delivered, inTransit = inTransit, cancelled = #open,
            pay = total, items = items })
    end

    local list = {}
    if isElement(player) then
        for _, it in ipairs(items) do
            -- plain texts: message objects lose their metatable across the export
            list[#list + 1] = { label = L.forPlayer(player, PAY_LABEL[it.key], { count = it.count }), amount = it.amount }
        end
    end
    if shift.tutorial then
        -- no money: the tutorial shows the receipt it would have been
        triggerEvent("onBtTutorialShiftEnd", player, reason, total, list)
    elseif isElement(player) and reason ~= "quit" and #items > 0 and isRunning("work_core") then
        exports.work_core:payWork(player, BTD.WORK_ID, list, L.forPlayer(player, PAY_REASON[reason] or PAY_REASON.off))
    end
    if isElement(player) then
        refreshItems(player)
        SyncPlayer(player)
    end
    Recent[player] = nil
    if not shift.tutorial then triggerEvent("onBtShiftEnd", resourceRoot, shift.id, reason) end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Watching the service
-- ---------------------------------------------------------------------------------------------

addEventHandler("onPlayerWasted", root, function() endShift(source, "died") end)
addEventHandler("onPlayerQuit", root, function() endShift(source, "quit") end)
addEventHandler("onPlayerWorkDutyEnd", root, function(workId)
    -- the tutorial shift does not need the work duty
    if workId == BTD.WORK_ID and Shifts[source] and not Shifts[source].tutorial then endShift(source, "duty_end") end
end)
addEventHandler("onVehicleExplode", root, function()
    for player, shift in pairs(Shifts) do
        if shift.vehicle == source then endShift(player, "vehicle_lost") end
    end
end)
addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    for player, shift in pairs(Shifts) do
        if shift.vehicle == source then
            shift.vehicle = nil
            endShift(player, "vehicle_lost")
        end
    end
end)

setTimer(function()
    for player, shift in pairs(Shifts) do
        if not isElement(shift.vehicle) or isVehicleBlown(shift.vehicle) then endShift(player, "vehicle_lost") end
    end
end, BTD.VEHICLE_CHECK, 0)

-- Cargo is volatile: when bt_items (v_inventory) restarts every open task is lost
addEventHandler("onBtItemsStart", root, function()
    for _, t in pairs(Tasks) do
        if t.status == "waiting" or t.status == "transit" then closeTask(t, "cancelled", "items_reset") end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Exports used by bt_items, bt_stock, bt_web
-- ---------------------------------------------------------------------------------------------

function getTask(id)
    local t = Tasks[id]
    if not t then return false end
    return { id = t.id, type = t.type, status = t.status, from = t.from, to = t.to, player = t.player,
        product = t.product, group = t.group, units = t.units, fromPort = t.fromPort, toPort = t.toPort,
        tutorial = t.tutorial == true }
end

function getPlayerTasks(player)
    local shift = Shifts[player]
    local out = {}
    if not shift then return out end
    for _, t in ipairs(openTasksOf(shift)) do
        out[#out + 1] = { id = t.id, status = t.status, from = t.from, to = t.to, type = t.type,
            fromPort = t.fromPort, toPort = t.toPort }
    end
    return out
end

function getDutyCount() return dutyCount() end
function isPlayerInService(player) return Shifts[player] ~= nil and not Shifts[player].tutorial end
