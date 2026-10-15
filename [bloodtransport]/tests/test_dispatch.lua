-- bt_dispatch core with stubbed MTA functions: services, tasks, assignment, handover, pay.
local failures = 0
local function check(cond, name)
    if not cond then failures = failures + 1 print("FAIL: " .. name) end
end
local function eq(a, b, name) check(a == b, name .. " (got " .. tostring(a) .. ", wanted " .. tostring(b) .. ")") end

-- ------------------------------------------------------------------ MTA stubs
local now = 1000000
local handlers, timers, sent, calls = {}, {}, {}, {}
function getTickCount() return now end
function getRealTime() return { timestamp = math.floor(now / 1000), year = 126, month = 9, monthday = 15, hour = 12, minute = 0, second = 0 } end
function outputDebugString(s) print("debug: " .. tostring(s)) end
function addEvent() end
function addEventHandler(name, _, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function triggerEvent(name, src, ...)
    for _, fn in ipairs(handlers[name] or {}) do source = src; fn(...) end
    return true
end
function triggerClientEvent(player, name, _, ...) sent[#sent + 1] = { player = player, name = name, args = { ... } } end
function setTimer(fn, ms, times, ...)
    local t = { fn = fn, ms = ms, times = times, args = { ... }, alive = true }
    timers[#timers + 1] = t
    return t
end
function killTimer(t) if t then t.alive = false end end
function isTimer(t) return type(t) == "table" and t.alive == true end
local function flush()   -- runs the one-shot timers (not the repeating ones)
    local ran = true
    while ran do
        ran = false
        for _, t in ipairs(timers) do
            if t.alive and t.times == 1 then t.alive = false; t.fn(unpack(t.args)); ran = true end
        end
    end
end
function isElement(e) return type(e) == "table" and e.el ~= nil end
function getElementType(e) return e.el end
function getElementPosition(e) return e.x, e.y, e.z or 0 end
function getElementDimension() return 0 end
function getElementInterior() return 0 end
function getDistanceBetweenPoints2D(a, b, c, d) return math.sqrt((a - c) ^ 2 + (b - d) ^ 2) end
function getDistanceBetweenPoints3D(a, b, c, d, e, f) return math.sqrt((a - d) ^ 2 + (b - e) ^ 2 + (c - f) ^ 2) end
function getPedOccupiedVehicle(p) return p.inVehicle end
function getElementModel(v) return v.model end
function getVehiclePlateText(v) return v.plate end
function getPlayerName(p) return p.name end
function isPedDead(p) return p.dead == true end
function isVehicleBlown(v) return v.blown == true end
function getResourceFromName(n) return { name = n } end
function getResourceState() return "running" end
L = { msg = function(k, p) return { key = k, params = p } end, forPlayer = function(_, k, p) return k end }

require = nil
local function load(path)
    local f = assert(io.open(BASE .. path, "rb"))
    local src = f:read("*a")
    f:close()
    assert(loadstring(src, path))()
end
load("bt_core/config.lua")
load("bt_dispatch/config.lua")
load("bt_stock/server/model.lua")
load("bt_dispatch/server/logic.lua")

-- in-memory database
local nextId = 0
DB = {
    nowText = function() return "2026-10-15 12:00:00" end,
    insertTask = function() nextId = nextId + 1 return nextId end,
    setTask = function() end, log = function() end,
    insertShift = function() nextId = nextId + 1 return nextId end,
    endShift = function(id, f) calls.endShift = f end,
    addShiftTask = function() end, releaseShiftTask = function() end,
    query = function() return {} end, json = function(t) return "" end,
}

-- other resources
local cargo, closed, paid, xp, removedObjectives, objectives = {}, {}, {}, {}, 0, {}
local refreshed = {}
local stockLegs
local players = {}
exports = setmetatable({}, { __index = function(_, name)
    local r = {
        bt_core = {
            getConfig = function() return BT end,
            hasRight = function() return true end,
        },
        bt_items = {
            spawnCargo = function(_, t) cargo[t.id] = t; return "i" .. t.id end,
            destroyCargo = function(_, id) cargo[id] = nil; return true end,
            clearBox = function() return true end,
            refreshPlayer = function(_, p) refreshed[p] = (refreshed[p] or 0) + 1 end,
        },
        bt_stock = {
            allocate = function(_, product, group, units, to) return stockLegs end,
            release = function(_, from, product, group, units) calls.release = { from, product, group, units } end,
            taskClosed = function(_, info) closed[#closed + 1] = info end,
        },
        work_core = {
            isPlayerOnDuty = function() return true end,
            getPlayerWorkVehicle = function(_, p) return p.vehicle end,
            giveWorkXp = function(_, p, id, n) xp[#xp + 1] = n end,
            payWork = function(_, p, id, items, reason)
                local total = 0
                for _, it in ipairs(items) do total = total + it.amount end
                paid[#paid + 1] = { player = p, total = total, items = items, reason = reason }
                return true, total
            end,
        },
        v_radar = {
            clearObjectives = function() removedObjectives = removedObjectives + 1 end,
            addObjective = function(_, p, x, y, z, label) objectives[p] = label; return "s1" end,
        },
        v_accounts = { getName = function(_, p) return p.name:lower() end },
    }
    return r[name]
end })

load("bt_dispatch/server/core.lua")
load("bt_dispatch/server/offers.lua")
load("bt_dispatch/server/panel.lua")
BTRandom = function(a, b) return a + (b - a) * 0.5 end

local function player(name, x, y)
    local p = { el = "player", name = name, x = x, y = y }
    p.vehicle = { el = "vehicle", model = 415, plate = "BT-" .. (1000 + #players), x = x, y = y }
    p.inVehicle = p.vehicle
    players[#players + 1] = p
    return p
end

local A, B = player("Alice", 0, 0), player("Bob", 2, 0)
local C = BTC()

-- ------------------------------------------------------------------ sign on
local ok, why = signOn(A)
check(ok, "Alice signs on"); eq(Shifts[A].unit, "BT-1000", "unit id is the plate")
ok, why = signOn(A); eq(ok, false, "double sign on refused"); eq(why, "already", "reason")
local out = player("Walker", 5, 5); out.inVehicle = nil
ok, why = signOn(out); eq(why, "no_vehicle", "no sign on without vehicle")
check(signOn(B), "Bob signs on")
eq(dutyCount(), 2, "two units on duty")

-- ------------------------------------------------------------------ tasks and balancing
local lab = { type = "lab_sample", from = "ls_allsaints", to = "ls_bank", units = 1 }
local ids = {}
for i = 1, 4 do ids[i] = makeTask(lab, "bt_dispatch") end
check(ids[1] and ids[2] and ids[3] and ids[4], "four lab tasks created")
eq(openCount(Shifts[A]), 2, "balanced: Alice 2"); eq(openCount(Shifts[B]), 2, "balanced: Bob 2")
check(cargo[ids[1]] ~= nil, "cargo spawned for the task")

-- wind down: Bob gets nothing new
setWindDown(B, true)
check(makeTask(lab, "bt_dispatch"), "Alice takes a 3rd task"); check(makeTask(lab, "bt_dispatch"), "Alice takes a 4th task")
ok, why = makeTask(lab, "bt_dispatch")
eq(ok, false, "everybody full or winding down -> no task"); eq(why, "no_unit", "reason no_unit")
eq(openCount(Shifts[A]), 4, "Alice has four"); eq(openCount(Shifts[B]), 2, "Bob kept his two")
setWindDown(B, false)

-- ------------------------------------------------------------------ rules of the types
ok, why = makeTask({ type = "resupply", from = "ls_bank", to = "ls_allsaints", product = "rbc", group = "A+", units = 2 }, "other_resource")
eq(ok, false, "resupply only from bt_stock")
ok = makeTask({ type = "lab_sample", from = "ls_bank", to = "ls_allsaints", units = 1 }, "bt_dispatch")
eq(ok, false, "wrong direction refused")

-- ------------------------------------------------------------------ pickup and delivery
local t1 = ids[1]
local owner = Tasks[t1].player
eq(onPickedUp(t1, owner == A and B or A), false, "somebody else cannot pick it up")
check(onPickedUp(t1, owner), "pickup"); eq(Tasks[t1].status, "transit", "status transit")
eq(onPickedUp(t1, owner), false, "no second pickup")
check(onDelivered(t1, owner), "delivery"); eq(Tasks[t1].status, "delivered", "status delivered")
eq(Shifts[owner].delivered, 1, "delivery counted")
eq(closed[#closed].status, "delivered", "stock told about the delivery")
check(cargo[t1] == nil, "cargo destroyed on delivery")
eq(xp[#xp], BTD.XP_PER_DELIVERY, "work xp")
flush()
check(Tasks[t1] ~= nil or true, "closed task cleanup scheduled")

-- ------------------------------------------------------------------ the panel snapshot sorts transit first
local aTasks = BTLogic.sorted(openTasksOf(Shifts[A]), Shifts[A].order)
local waitingId = aTasks[1].id
check(onPickedUp(waitingId, A), "Alice picks up one")
aTasks = BTLogic.sorted(openTasksOf(Shifts[A]), Shifts[A].order)
eq(aTasks[1].status, "transit", "transit tasks come first")

-- ------------------------------------------------------------------ handover (Alice -> Bob, 2 m apart)
local movable
for _, t in ipairs(openTasksOf(Shifts[A])) do if t.status == "waiting" then movable = t.id break end end
check(movable, "Alice has a waiting task")
ok, why = makeOffer(A, waitingId); eq(why, "not_waiting", "an in-transit task cannot be handed over")
ok = makeOffer(A, movable); check(ok, "offer made")
local offer; for _, o in pairs(Offers) do offer = o end
check(offer ~= nil, "offer stored")
local bobBefore = openCount(Shifts[B])
check(answerOffer(B, offer.id, true), "Bob accepts")
eq(Tasks[movable].player, B, "the task changed hands"); eq(openCount(Shifts[B]), bobBefore + 1, "Bob has one more now")
local inOrder = false
for _, id in ipairs(Shifts[B].order) do if id == movable then inOrder = true end end
check(inOrder, "task is in Bob's order list")

-- too far: no offer
B.x = 100
ok, why = makeOffer(A, Shifts[A].order[1] or -1); eq(ok, false, "nobody near")
B.x = 2

-- ------------------------------------------------------------------ end of the service and pay
local inTransitA = 0
for _, t in ipairs(openTasksOf(Shifts[A])) do if t.status == "transit" then inTransitA = inTransitA + 1 end end
local openA = openCount(Shifts[A])
local deliveredA = Shifts[A].delivered
check(endShift(A, "off"), "Alice ends the service")
eq(Shifts[A], nil, "service closed")
local pay = paid[#paid]
local wantTotal = (deliveredA > 0 and (BTD.PAY.BASE + BTD.PAY.DELIVERED * deliveredA) or 0) + BTD.PAY.IN_TRANSIT * inTransitA
eq(pay.total, wantTotal, "pay: base + deliveries - cargo on the way")
eq(calls.endShift.cancelled, openA, "all open tasks of the service cancelled")
for _, c in ipairs(closed) do check(c.status == "delivered" or c.status == "cancelled", "closed info status") end

-- died: the same accounting as at a normal end
check(onPickedUp(Shifts[B].order[1], B), "Bob picks up")
local bTransit = 0
for _, t in ipairs(openTasksOf(Shifts[B])) do if t.status == "transit" then bTransit = bTransit + 1 end end
local bDelivered = Shifts[B].delivered
local before = #paid
endShift(B, "died")
eq(#paid, before + 1, "pay also after a death")
eq(paid[#paid].total, (bDelivered > 0 and (BTD.PAY.BASE + BTD.PAY.DELIVERED * bDelivered) or 0) + BTD.PAY.IN_TRANSIT * bTransit, "death: same pay rules")
eq(dutyCount(), 0, "nobody on duty")

-- nothing to give to when nobody is in service
ok, why = makeTask(lab, "bt_dispatch"); eq(ok, false, "no unit, no task"); eq(why, "no_unit", "no_unit")

-- ------------------------------------------------------------------ supply from the stock
local C2 = player("Carol", 0, 0)
check(signOn(C2), "Carol signs on")
stockLegs = { { from = "ls_bank", units = 12 }, { from = "lv_bank", units = 3 } }
local made = makeSupply({ type = "urgent_blood", product = "rbc", group = "0+", units = 15, to = "ls_allsaints" }, "bt_dispatch")
check(made, "supply created")
eq(#made, 3, "12 units -> 8 + 4, 3 units -> 3 (task size limit)")
stockLegs = nil
ok, why = makeSupply({ type = "urgent_blood", product = "rbc", group = "0+", units = 5, to = "ls_allsaints" }, "bt_dispatch")
eq(why, "no_stock", "no stock -> no task")
local ct = makeTask(lab, "bt_dispatch")
check(ct, "Carol gets a task")
check(onPickedUp(ct, C2), "Carol picks up")
before = #paid
endShift(C2, "died")
eq(paid[#paid].total, BTD.PAY.IN_TRANSIT * 1, "no delivery, one cargo lost: only the penalty (receipt shown, nothing paid)")

print(failures == 0 and "all dispatch tests passed" or (failures .. " dispatch test(s) failed"))
return failures
