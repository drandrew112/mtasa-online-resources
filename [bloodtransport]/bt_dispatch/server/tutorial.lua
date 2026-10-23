if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Hooks of the work_bloodtransport tutorial. The tutorial runs the real panel, service and task flow
-- in a private dimension: the player signs on in the tutorial vehicle, gets one task whose cargo lies
-- on the tutorial copies of the ports (bt_core createTutorialPorts) and signs off at the end.
-- The tutorial shift and task live only in memory: no database row, no stock, no pay, no XP, and
-- they are left out of the unit counts, the generator, the handover and the web page.

local nextTutorialTask = 0

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- vehicle = the tutorial vehicle (sign on works in it without the work duty),
-- ports = { [instId] = portId } of the tutorial ports; nil vehicle ends it (and its shift)
function setTutorialVehicle(player, vehicle, ports)
    if not isElement(player) then return false end
    if not vehicle then
        local shift = Shifts[player]
        if shift and shift.tutorial then endShift(player, "off") end
        TutorialOf[player] = nil
        return true
    end
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    if Shifts[player] and not Shifts[player].tutorial then return false, "in_service" end
    TutorialOf[player] = { vehicle = vehicle, ports = type(ports) == "table" and ports or {} }
    return true
end

-- def: type, product, group, units, from, to (institution ids with a tutorial port) -> id | false, reason
function createTutorialTask(player, def)
    local shift = Shifts[player]
    local tutorial = TutorialOf[player]
    if not shift or not shift.tutorial or not tutorial then return false, "no_shift" end
    if type(def) ~= "table" then return false, "table expected" end
    local rules = BTD.TYPES[def.type]
    if not rules then return false, "unknown type" end
    local fromPort, toPort = tutorial.ports[def.from], tutorial.ports[def.to]
    if not fromPort or not toPort then return false, "no tutorial port" end

    nextTutorialTask = nextTutorialTask + 1
    local task = {
        id = BTD.TUTORIAL_TASK_BASE + nextTutorialTask, tutorial = true,
        type = def.type, urgency = def.urgency or rules.urgency, source = "tutorial",
        product = def.product, group = def.group, units = math.max(1, math.floor(tonumber(def.units) or 1)),
        from = def.from, to = def.to, fromPort = fromPort, toPort = toPort,
        status = "waiting", reserved = false, createdAt = getRealTime().timestamp,
    }
    Tasks[task.id] = task
    task.shift, task.player = shift, player
    shift.order[#shift.order + 1] = task.id

    if not (isRunning("bt_items") and exports.bt_items:spawnCargo(newTaskDescription(task))) then
        closeTask(task, "cancelled", "cargo")
        return false, "cargo"
    end
    notify(player, L.msg("bt_dispatch.notify.title"), L.msg("bt_dispatch.notify.new_task", {
        id = task.id, what = L.msg(taskWhatKey(task)), group = task.group or "", units = task.units,
        from = instName(task.from), to = instName(task.to) }), true)
    refreshItems(player)
    SyncPlayer(player)
    triggerEvent("onBtTaskChanged", resourceRoot, task.id, "waiting")
    return task.id
end

-- The pay rules, for the tutorial's explanation
function getPayRules()
    local pay = BTD.currentPay()
    return { base = pay.BASE, delivered = pay.DELIVERED, inTransit = pay.IN_TRANSIT }
end

addEventHandler("onPlayerQuit", root, function() TutorialOf[source] = nil end)
