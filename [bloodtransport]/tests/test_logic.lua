-- Unit tests of the pure blood transport logic. Run: python tests/run.py
local failures = 0
local function check(cond, name)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. name)
    end
end
local function eq(a, b, name) check(a == b, name .. " (got " .. tostring(a) .. ", wanted " .. tostring(b) .. ")") end

local function load(path)
    local f = assert(io.open(BASE .. path, "rb"))
    local src = f:read("*a")
    f:close()
    assert(loadstring(src, path))()
end
load("bt_core/config.lua")
load("bt_stock/config.lua")
load("bt_stock/server/model.lua")
load("bt_dispatch/config.lua")
load("bt_dispatch/server/logic.lua")

math.randomseed(42)
local function rnd(a, b) return a + math.random() * (b - a) end

BT.byId = {}
for _, inst in ipairs(BT.INSTITUTIONS) do BT.byId[inst.id] = inst end

-- ------------------------------------------------------------------ capacity / create
eq(StockModel.capacity(BT, BTS, "bank", "0+"), 114, "bank 0+ capacity")
eq(StockModel.capacity(BT, BTS, "bank", "AB-"), 4, "bank AB- hits the minimum")
eq(StockModel.capacity(BT, BTS, "hospital", "AB-"), 2, "hospital AB- hits the minimum")
eq(StockModel.capacity(BT, BTS, "hospital", "A+"), 20, "hospital A+ capacity")

local state = StockModel.create(BT, BTS, rnd)
local lines = 0
for _, inst in ipairs(BT.INSTITUTIONS) do
    for _, product in ipairs(BT.PRODUCT_ORDER) do
        for _, group in ipairs(BT.GROUPS) do
            lines = lines + 1
            local n = StockModel.get(state, inst.id, product, group)
            local cap = StockModel.capacity(BT, BTS, inst.kind, group)
            check(n >= 0 and n <= cap, "new stock within capacity " .. inst.id .. product .. group)
        end
    end
end
eq(lines, 7 * 3 * 8, "line count (7 institutions x 3 products x 8 groups)")

-- repair adds missing lines
local broken = { inst = { ls_bank = { rbc = { ["0+"] = 5 } } } }
check(StockModel.repair(BT, BTS, broken, rnd), "repair reports a change")
check(type(broken.inst.sf_medical.ffp["A-"]) == "number", "repair fills the missing lines")
eq(broken.inst.ls_bank.rbc["0+"], 5, "repair keeps the existing value")

-- ------------------------------------------------------------------ add / clamp
local s = { inst = { ls_bank = { rbc = { ["A+"] = 10 } } } }
local after, delta = StockModel.add(BT, BTS, s, BT.byId.ls_bank, "rbc", "A+", -25)
eq(after, 0, "add clamps at zero"); eq(delta, -10, "add reports the real change")
after = StockModel.add(BT, BTS, s, BT.byId.ls_bank, "rbc", "A+", 1000)
eq(after, StockModel.capacity(BT, BTS, "bank", "A+"), "add clamps at the capacity")

-- ------------------------------------------------------------------ plan
local st = { inst = {} }
for _, inst in ipairs(BT.INSTITUTIONS) do st.inst[inst.id] = { rbc = {}, ffp = {}, platelets = {} } end
st.inst.ls_bank.rbc["0+"], st.inst.lv_bank.rbc["0+"], st.inst.sf_bank.rbc["0+"] = 5, 20, 3
local legs = StockModel.plan(BT, st, "rbc", "0+", 4, "ls_allsaints", false)
eq(#legs, 1, "same city center serves a small request"); eq(legs[1].from, "ls_bank", "same city first")
legs = StockModel.plan(BT, st, "rbc", "0+", 8, "ls_allsaints", false)
eq(#legs, 2, "a bigger request is split"); eq(legs[1].units, 5, "leg 1 takes the whole same-city stock"); eq(legs[2].from, "lv_bank", "leg 2 from the fullest other center")
eq(legs[1].units + legs[2].units, 8, "legs add up")
check(StockModel.plan(BT, st, "rbc", "0+", 40, "ls_allsaints", false) == false, "not enough in all centers -> no task")
legs = StockModel.plan(BT, st, "rbc", "0+", 40, "ls_allsaints", true)
eq(#legs, 3, "partial takes everything there is")
check(StockModel.plan(BT, st, "rbc", "AB-", 1, "ls_allsaints", true) == false, "nothing at all -> false even when partial")

-- ------------------------------------------------------------------ needs
local hosp = BT.byId.ls_allsaints
local hs = { inst = { ls_allsaints = { rbc = {}, ffp = {}, platelets = {} } } }
for _, p in ipairs(BT.PRODUCT_ORDER) do for _, g in ipairs(BT.GROUPS) do
    hs.inst.ls_allsaints[p][g] = StockModel.capacity(BT, BTS, "hospital", g)
end end
eq(#StockModel.needs(BT, BTS, hs, hosp, nil), 0, "a full hospital needs nothing")
hs.inst.ls_allsaints.rbc["0+"] = 3     -- cap 23
hs.inst.ls_allsaints.ffp["A+"] = 0     -- cap 20
local needs = StockModel.needs(BT, BTS, hs, hosp, nil)
eq(#needs, 2, "two low lines"); eq(needs[1].group, "A+", "the emptiest line first")
eq(needs[1].need, 16, "fill up to 80 %")
needs = StockModel.needs(BT, BTS, hs, hosp, { ffp = { ["A+"] = 16 } })
eq(#needs, 1, "units on the way are not asked again")

-- ------------------------------------------------------------------ consume / refill
local consumed = 0
for _ = 1, 300 do
    if StockModel.consume(BT, BTS, hs, hosp, rnd) then consumed = consumed + 1 end
end
check(consumed > 0, "the hospital consumes")
for _, p in ipairs(BT.PRODUCT_ORDER) do for _, g in ipairs(BT.GROUPS) do
    check(hs.inst.ls_allsaints[p][g] >= 0, "consumption never goes below zero")
end end

local rs = StockModel.create(BT, BTS, rnd)
for _, p in ipairs(BT.PRODUCT_ORDER) do for _, g in ipairs(BT.GROUPS) do rs.inst.ls_bank[p][g] = 0 end end
for _ = 1, 50 do StockModel.refill(BT, BTS, rs, rnd) end
local never100 = true
for _, p in ipairs(BT.PRODUCT_ORDER) do for _, g in ipairs(BT.GROUPS) do
    local cap = StockModel.capacity(BT, BTS, "bank", g)
    if rs.inst.ls_bank[p][g] > math.floor(cap * BTS.REFILL_MAX) then never100 = false end
end end
check(never100, "a center is never refilled above 90 %")
local before = rs.inst.ls_allsaints.rbc["0+"]
StockModel.refill(BT, BTS, rs, rnd)
eq(rs.inst.ls_allsaints.rbc["0+"], before, "hospitals are not refilled")

-- ------------------------------------------------------------------ dispatch logic
local items, total = BTLogic.pay(BTD.PAY, 3, 1)
eq(total, 2000 + 3 * 2500 - 1500, "pay: base + deliveries - cargo on the way")
eq(#items, 3, "pay: three receipt lines")
items, total = BTLogic.pay(BTD.PAY, 0, 2)
eq(total, -3000, "pay: no delivery means no base pay"); eq(#items, 1, "pay: only the penalty line")
items, total = BTLogic.pay(BTD.PAY, 0, 0)
eq(total, 0, "pay: nothing"); eq(#items, 0, "pay: no lines")

local units = { { open = 3 }, { open = 1, windDown = true }, { open = 1, dist = 500 }, { open = 1, dist = 100 }, { open = 4 } }
eq(BTLogic.pickUnit(units, 4), 4, "least loaded, then nearest, not winding down, not full")
eq(BTLogic.pickUnit({ { open = 4 }, { open = 1, windDown = true } }, 4), nil, "nobody can take it")

eq(table.concat(BTLogic.chunks(19, 8), ","), "8,8,3", "chunks")
local ok, why = BTLogic.checkTask(BTD.TYPES, BT.byId, { type = "lab_sample", from = "ls_allsaints", to = "ls_bank" })
check(ok, "lab sample hospital -> bank is valid")
ok = BTLogic.checkTask(BTD.TYPES, BT.byId, { type = "lab_sample", from = "ls_bank", to = "ls_allsaints" })
check(not ok, "lab samples never go from a bank to a hospital")
ok = BTLogic.checkTask(BTD.TYPES, BT.byId, { type = "urgent_medicine", from = "ls_allsaints", to = "ls_allsaints" })
check(not ok, "urgent medicine needs two different hospitals")
ok = BTLogic.checkTask(BTD.TYPES, BT.byId, { type = "urgent_blood", from = "ls_bank", to = "ls_country", product = "rbc", group = "A+" })
check(ok, "urgent blood bank -> hospital")
ok = BTLogic.checkTask(BTD.TYPES, BT.byId, { type = "urgent_blood", from = "ls_bank", to = "ls_country" })
check(not ok, "blood needs product and group")

local tasks = { { id = 5, status = "waiting" }, { id = 6, status = "transit", pickedAt = 20 }, { id = 7, status = "waiting" }, { id = 8, status = "transit", pickedAt = 10 } }
local sorted = BTLogic.sorted(tasks, { 7, 5 })
eq(sorted[1].id, 8, "transit first, oldest pick-up first"); eq(sorted[2].id, 6, "second transit")
eq(sorted[3].id, 7, "waiting in the player's order"); eq(sorted[4].id, 5, "waiting in the player's order (2)")
local order = { 1, 2, 3 }
check(BTLogic.move(order, 3, -1), "move up"); eq(table.concat(order, ","), "1,3,2", "order after moving up")
check(not BTLogic.move(order, 1, -1), "cannot move the first one up")

-- ------------------------------------------------------------------ weighted
local counts = {}
for _ = 1, 2000 do
    local k = BTLogic.weighted(BTD.GEN_WEIGHTS, rnd)
    counts[k] = (counts[k] or 0) + 1
end
check(counts.urgent_blood > counts.urgent_medicine * 3, "weights are respected")

print(failures == 0 and "all logic tests passed" or (failures .. " logic test(s) failed"))
return failures
