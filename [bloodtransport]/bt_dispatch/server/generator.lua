-- Random task generator: urgent / planned blood, lab samples and urgent medicine. The resupply of the
-- hospitals is asked by bt_stock. Nothing is generated without a transporter that can take a task.

local nextGen, lastGen = 0, 0   -- required (activity-weighted) wait in ms, tick of the last task

local function rndInt(a, b) return math.floor(BTRandom(a, b + 1)) end

local function institutions(kind)
    local list = {}
    for _, inst in ipairs(BTC().INSTITUTIONS) do
        if inst.kind == kind then list[#list + 1] = inst end
    end
    return list
end

local function pick(list) return list[rndInt(1, #list)] end

-- A bank of the hospital's city when there is one
local function bankFor(hospital)
    local banks, same = institutions("bank"), {}
    for _, b in ipairs(banks) do if b.city == hospital.city then same[#same + 1] = b end end
    return pick(#same > 0 and same or banks)
end

local function generate()
    local c = BTC()
    if not c then return false end
    local kind = BTLogic.weighted(BTD.GEN_WEIGHTS, BTRandom)
    local hospitals = institutions("hospital")
    if kind == "urgent_blood" or kind == "planned_blood" then
        local range = BTD.GEN_UNITS[kind]
        local ids = makeSupply({
            type = kind, product = BTLogic.weighted(BTD.PRODUCT_WEIGHTS, BTRandom),
            group = BTLogic.weighted(c.GROUP_WEIGHT, BTRandom), units = rndInt(range[1], range[2]),
            to = pick(hospitals).id, source = "random",
        }, "bt_dispatch")
        return ids ~= false
    elseif kind == "lab_sample" then
        local h = pick(hospitals)
        return makeTask({ type = kind, from = h.id, to = bankFor(h).id, units = 1, source = "random" }, "bt_dispatch") ~= false
    elseif kind == "urgent_medicine" then
        if #hospitals < 2 then return false end
        local a = pick(hospitals)
        local b = a
        while b == a do b = pick(hospitals) end
        return makeTask({ type = kind, from = a.id, to = b.id, units = 1, source = "random" }, "bt_dispatch") ~= false
    end
    return false
end

-- Activity 0..1 at the game time (piecewise linear over BTD.NIGHT_ACTIVITY)
local function activity()
    local h, m = 12, 0
    if getTime then h, m = getTime() end
    local t, pts = h + (m or 0) / 60, BTD.NIGHT_ACTIVITY
    for i = 2, #pts do
        if t <= pts[i][1] then
            local a, b = pts[i - 1], pts[i]
            return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
        end
    end
    return pts[#pts][2]
end

setTimer(function()
    local n = activeUnitCount()
    local act = activity()
    -- elapsed time counts weighted by the activity, so a night wait does not run into the morning
    if n == 0 or (getTickCount() - lastGen) * act < nextGen then return end
    -- at night the open-task target shrinks too (at least 1 while some activity is left)
    local target = math.max(1, math.floor(BTLogic.targetOpen(BTD.OPEN_PER_UNIT, n) * act + 0.5))
    if openTaskTotal() >= target then return end
    if generate() then
        lastGen = getTickCount()
        nextGen = BTRandom(BTD.GEN_INTERVAL[1], BTD.GEN_INTERVAL[2]) * 1000
    end
end, BTD.GEN_CHECK * 1000, 0)

-- Admin / test: one task of a kind right now
function generateNow()
    return generate()
end
