if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Server side of the player's panel (client/panel.lua): state snapshots and the button events.

addEvent("btd:requestState", true)
addEvent("btd:signOn", true)
addEvent("btd:signOff", true)
addEvent("btd:windDown", true)
addEvent("btd:move", true)
addEvent("btd:route", true)
addEvent("btd:offer", true)
addEvent("btd:answer", true)

local pending = {}

local function taskView(t, doneIn)
    return {
        id = t.id, type = t.type, urgency = t.urgency, status = t.status, product = t.product, group = t.group,
        units = t.units, from = t.from, to = t.to, fromName = instName(t.from), toName = instName(t.to), doneIn = doneIn,
    }
end

local function snapshot(player)
    local shift = Shifts[player]
    if not shift then return { onDuty = false } end
    local tasks = {}
    for _, t in ipairs(BTLogic.sorted(openTasksOf(shift), shift.order)) do
        local v = taskView(t)
        v.route = shift.route == t.id
        tasks[#tasks + 1] = v
    end
    local now, recent = getTickCount(), {}
    for _, r in ipairs(Recent[player] or {}) do
        if r.till > now then
            local v = taskView(r.task, math.ceil((r.till - now) / 1000))
            v.status = r.task.status
            tasks[#tasks + 1] = v
            recent[#recent + 1] = r
        end
    end
    Recent[player] = recent
    local near = nearestUnit(shift)
    local offer = offerOf(shift)
    local pay = estimatePay(shift)
    return {
        onDuty = true, unit = shift.unit, name = shift.name, windDown = shift.windDown, delivered = shift.delivered,
        since = math.floor((getTickCount() - shift.startedTick) / 1000), pay = pay, tasks = tasks,
        nearby = near and { unit = near.unit, name = near.name } or false, offered = offer and offer.task or false,
    }
end

function SyncPlayer(player)
    if not isElement(player) or pending[player] then return end
    pending[player] = true
    setTimer(function()
        pending[player] = nil
        if isElement(player) then triggerClientEvent(player, "btd:state", resourceRoot, snapshot(player)) end
    end, 50, 1)
end

-- nearby unit changes without any task change
local lastNearby = {}
setTimer(function()
    for player, shift in pairs(Shifts) do
        local near = nearestUnit(shift)
        local key = near and near.id or false
        if lastNearby[player] ~= key then
            lastNearby[player] = key
            SyncPlayer(player)
        end
    end
end, BTD.NEARBY_INTERVAL, 0)

local function fail(player, reason)
    notify(player, L.msg("bt_dispatch.notify.title"), L.msg("bt_dispatch.err." .. tostring(reason)))
end

addEventHandler("btd:requestState", root, function()
    if isElement(client) then SyncPlayer(client) end
end)

addEventHandler("btd:signOn", root, function()
    local ok, reason = signOn(client)
    if not ok then fail(client, reason) end
end)

addEventHandler("btd:signOff", root, function()
    endShift(client, "off")
end)

addEventHandler("btd:windDown", root, function(on)
    setWindDown(client, on == true)
end)

addEventHandler("btd:move", root, function(taskId, dir)
    local shift = Shifts[client]
    if not shift or (dir ~= -1 and dir ~= 1) then return end
    taskId = tonumber(taskId)
    local task = taskId and Tasks[taskId]
    if not task or task.shift ~= shift or task.status ~= "waiting" then return end
    if BTLogic.move(shift.order, taskId, dir) then SyncPlayer(client) end
end)

addEventHandler("btd:route", root, function(taskId)
    local shift = Shifts[client]
    if not shift then return end
    taskId = tonumber(taskId)
    if taskId and shift.route == taskId then taskId = nil end        -- the same button again switches it off
    local task = taskId and Tasks[taskId]
    if task and task.shift ~= shift then return end
    shift.route = task and task.id or nil
    updateRoute(shift)
    SyncPlayer(client)
end)

addEventHandler("btd:offer", root, function(taskId)
    local ok, reason = makeOffer(client, tonumber(taskId))
    if not ok then fail(client, reason) end
end)

addEventHandler("btd:answer", root, function(offerId, accept)
    answerOffer(client, tonumber(offerId), accept == true)
end)
