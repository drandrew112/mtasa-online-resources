-- Handover of waiting tasks between two transporters standing next to each other.

Offers = {}               -- id -> { id, from, to, task, till, timer }
local nextOffer = 0

local function playerDistance(a, b)
    if getElementDimension(a) ~= getElementDimension(b) or getElementInterior(a) ~= getElementInterior(b) then return math.huge end
    local ax, ay, az = getElementPosition(a)
    local bx, by, bz = getElementPosition(b)
    return getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz)
end

-- The closest other unit that may take a task -> shift | nil, distance
function nearestUnit(shift)
    if shift.tutorial then return nil end
    local best, bestD
    for _, other in pairs(Shifts) do
        if other ~= shift and not other.windDown and not other.tutorial and openCount(other) < BTD.MAX_OPEN_PER_UNIT
            and isElement(other.player) and isElement(shift.player) then
            local d = playerDistance(shift.player, other.player)
            if d <= BTD.OFFER_RANGE and (not bestD or d < bestD) then best, bestD = other, d end
        end
    end
    return best, bestD
end

function offerOf(shift)
    for _, o in pairs(Offers) do
        if o.from == shift then return o end
    end
end

local function dropOffer(offer, notifyFrom, key)
    if not Offers[offer.id] then return end
    Offers[offer.id] = nil
    if isTimer(offer.timer) then killTimer(offer.timer) end
    if isElement(offer.to.player) then triggerClientEvent(offer.to.player, "btd:offerEnd", resourceRoot, offer.id) end
    if notifyFrom and key and isElement(offer.from.player) then
        notify(offer.from.player, L.msg("bt_dispatch.notify.title"), L.msg(key, { unit = offer.to.unit, name = offer.to.name }))
    end
    if isElement(offer.from.player) then SyncPlayer(offer.from.player) end
end

function cancelOffersOf(shift)
    for _, o in pairs(Offers) do
        if o.from == shift or o.to == shift then dropOffer(o, false) end
    end
end

-- from the panel: offer one waiting task to the closest unit
function makeOffer(player, taskId)
    local shift = Shifts[player]
    local task = Tasks[taskId]
    if not shift then return false, "no_service" end
    if not task or task.shift ~= shift or task.status ~= "waiting" then return false, "not_waiting" end
    if offerOf(shift) then return false, "offer_open" end
    local target = nearestUnit(shift)
    if not target then return false, "nobody_near" end
    nextOffer = nextOffer + 1
    local offer = { id = nextOffer, from = shift, to = target, task = taskId }
    offer.timer = setTimer(function() dropOffer(offer, true, "bt_dispatch.notify.offer_expired") end, BTD.OFFER_TIMEOUT * 1000, 1)
    Offers[offer.id] = offer
    triggerClientEvent(target.player, "btd:offerIn", resourceRoot, offer.id, {
        unit = shift.unit, name = shift.name, id = task.id, type = task.type, product = task.product, group = task.group,
        units = task.units, fromName = instName(task.from), toName = instName(task.to), seconds = BTD.OFFER_TIMEOUT,
    })
    SyncPlayer(player)
    return true
end

function answerOffer(player, offerId, accept)
    local offer = Offers[offerId]
    if not offer or offer.to.player ~= player then return false end
    if accept ~= true then
        dropOffer(offer, true, "bt_dispatch.notify.offer_declined")
        return true
    end
    local from, to, task = offer.from, offer.to, Tasks[offer.task]
    if not task or task.status ~= "waiting" or task.shift ~= from or Shifts[from.player] ~= from or Shifts[to.player] ~= to then
        dropOffer(offer, true, "bt_dispatch.notify.offer_failed")
        return false
    end
    if to.windDown or openCount(to) >= BTD.MAX_OPEN_PER_UNIT or playerDistance(from.player, to.player) > BTD.OFFER_RANGE * 1.5 then
        dropOffer(offer, true, "bt_dispatch.notify.offer_failed")
        return false
    end
    -- the task changes hands
    for i, id in ipairs(from.order) do
        if id == task.id then table.remove(from.order, i) break end
    end
    DB.releaseShiftTask(from.id, task.id, "handed_over")
    task.shift, task.player = to, to.player
    to.order[#to.order + 1] = task.id
    DB.setTask(task.id, { shift_id = to.id })
    DB.addShiftTask(to.id, task.id)
    DB.log(task.id, "handed_over", from.unit .. " > " .. to.unit)
    if from.route == task.id then
        from.route = nil
        updateRoute(from)
    end
    Offers[offer.id] = nil
    if isTimer(offer.timer) then killTimer(offer.timer) end
    triggerClientEvent(to.player, "btd:offerEnd", resourceRoot, offer.id)
    notify(from.player, L.msg("bt_dispatch.notify.title"), L.msg("bt_dispatch.notify.handed_over", { id = task.id, unit = to.unit, name = to.name }))
    notify(to.player, L.msg("bt_dispatch.notify.title"), L.msg("bt_dispatch.notify.received", { id = task.id, unit = from.unit, name = from.name }), true)
    refreshItems(from.player)
    refreshItems(to.player)
    SyncPlayer(from.player)
    SyncPlayer(to.player)
    triggerEvent("onBtTaskChanged", resourceRoot, task.id, "waiting")
    return true
end
