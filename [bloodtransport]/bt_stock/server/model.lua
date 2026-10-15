-- Stock model: pure logic without MTA functions (tested with lupa, see tests/).
-- state = { inst = { [instId] = { [product] = { [group] = units } } }, refilled = epoch }

StockModel = {}

local function round(x) return math.floor(x + 0.5) end

-- Capacity of one line (instance kind "bank" | "hospital")
function StockModel.capacity(BT, BTS, kind, group)
    local total = kind == "bank" and BTS.BANK_TOTAL or BTS.HOSPITAL_TOTAL
    local min = kind == "bank" and BTS.BANK_MIN_LINE or BTS.HOSPITAL_MIN_LINE
    local weight = BT.GROUP_WEIGHT[group] or 1
    return math.max(min, round(total * weight / 100))
end

-- A new stock; rnd(a, b) returns a float in [a, b)
function StockModel.create(BT, BTS, rnd)
    local state = { inst = {}, refilled = 0 }
    for _, inst in ipairs(BT.INSTITUTIONS) do
        local lines = {}
        for _, product in ipairs(BT.PRODUCT_ORDER) do
            lines[product] = {}
            for _, group in ipairs(BT.GROUPS) do
                local cap = StockModel.capacity(BT, BTS, inst.kind, group)
                lines[product][group] = round(cap * rnd(BTS.START_FILL[1], BTS.START_FILL[2]))
            end
        end
        state.inst[inst.id] = lines
    end
    return state
end

-- Adds lines missing in a loaded file (new institution / product / group); returns true when it changed
function StockModel.repair(BT, BTS, state, rnd)
    local changed = false
    state.inst = type(state.inst) == "table" and state.inst or {}
    for _, inst in ipairs(BT.INSTITUTIONS) do
        state.inst[inst.id] = state.inst[inst.id] or {}
        for _, product in ipairs(BT.PRODUCT_ORDER) do
            state.inst[inst.id][product] = state.inst[inst.id][product] or {}
            for _, group in ipairs(BT.GROUPS) do
                local n = state.inst[inst.id][product][group]
                if type(n) ~= "number" then
                    local cap = StockModel.capacity(BT, BTS, inst.kind, group)
                    state.inst[inst.id][product][group] = round(cap * rnd(BTS.START_FILL[1], BTS.START_FILL[2]))
                    changed = true
                end
            end
        end
    end
    return changed
end

function StockModel.get(state, instId, product, group)
    local l = state.inst[instId]
    return l and l[product] and l[product][group] or 0
end

-- Adds (negative = removes) units, clamped to 0..capacity. -> new amount, really changed by
function StockModel.add(BT, BTS, state, inst, product, group, units)
    local line = state.inst[inst.id] and state.inst[inst.id][product]
    if not line then return 0, 0 end
    local cap = StockModel.capacity(BT, BTS, inst.kind, group)
    local before = line[group] or 0
    local after = math.max(0, math.min(cap, before + units))
    line[group] = after
    return after, after - before
end

-- Picks the centers that can serve `units` of a product / group for the institution `toInst`.
-- Centers of the same city come first, then the fullest. All or nothing, unless partial (then
-- whatever is available, at least one unit). The units are NOT taken. -> { { from, units } ... } | false
function StockModel.plan(BT, state, product, group, units, toInst, partial)
    local to = toInst and BT.byId and BT.byId[toInst]
    local banks = {}
    for _, inst in ipairs(BT.INSTITUTIONS) do
        if inst.kind == "bank" then
            local have = StockModel.get(state, inst.id, product, group)
            if have > 0 then banks[#banks + 1] = { inst = inst, have = have, same = (to and to.city == inst.city) and 1 or 0 } end
        end
    end
    table.sort(banks, function(a, b)
        if a.same ~= b.same then return a.same > b.same end
        if a.have ~= b.have then return a.have > b.have end
        return a.inst.id < b.inst.id
    end)
    local legs, left = {}, units
    for _, b in ipairs(banks) do
        if left <= 0 then break end
        local take = math.min(left, b.have)
        legs[#legs + 1] = { from = b.inst.id, units = take }
        left = left - take
    end
    if left > 0 and not (partial and #legs > 0) then return false end
    return legs
end

-- Ratio stock / capacity of a line
function StockModel.level(BT, BTS, state, inst, product, group)
    local cap = StockModel.capacity(BT, BTS, inst.kind, group)
    return StockModel.get(state, inst.id, product, group) / cap
end

-- Hospital lines that need a delivery, most empty first. pending[product][group] = units on the way.
-- -> { { product, group, have, cap, need, ratio } ... }
function StockModel.needs(BT, BTS, state, inst, pending)
    local out = {}
    for _, product in ipairs(BT.PRODUCT_ORDER) do
        for _, group in ipairs(BT.GROUPS) do
            local cap = StockModel.capacity(BT, BTS, inst.kind, group)
            local have = StockModel.get(state, inst.id, product, group)
            local onTheWay = pending and pending[product] and pending[product][group] or 0
            if have / cap < BTS.LOW then
                local need = round(cap * BTS.FILL_TO) - have - onTheWay
                if need > 0 then
                    out[#out + 1] = { product = product, group = group, have = have, cap = cap, need = need, ratio = have / cap }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.ratio ~= b.ratio then return a.ratio < b.ratio end
        if a.product ~= b.product then return a.product < b.product end
        return a.group < b.group
    end)
    return out
end

-- Weighted random group; rnd(a, b) float in [a, b)
function StockModel.randomGroup(BT, rnd)
    local total = 0
    for _, g in ipairs(BT.GROUPS) do total = total + (BT.GROUP_WEIGHT[g] or 1) end
    local r = rnd(0, total)
    for _, g in ipairs(BT.GROUPS) do
        r = r - (BT.GROUP_WEIGHT[g] or 1)
        if r < 0 then return g end
    end
    return BT.GROUPS[#BT.GROUPS]
end

-- One unit of a random product / group is used up in the hospital -> product, group | nil
function StockModel.consume(BT, BTS, state, inst, rnd)
    local product = BT.PRODUCT_ORDER[math.floor(rnd(0, #BT.PRODUCT_ORDER)) + 1]
    local group = StockModel.randomGroup(BT, rnd)
    local _, delta = StockModel.add(BT, BTS, state, inst, product, group, -1)
    if delta < 0 then return product, group end
    return nil
end

-- Periodic refill of the centers: +10..35 % of the capacity, never above 90 %
function StockModel.refill(BT, BTS, state, rnd)
    for _, inst in ipairs(BT.INSTITUTIONS) do
        if inst.kind == "bank" then
            for _, product in ipairs(BT.PRODUCT_ORDER) do
                for _, group in ipairs(BT.GROUPS) do
                    local cap = StockModel.capacity(BT, BTS, inst.kind, group)
                    local have = StockModel.get(state, inst.id, product, group)
                    local ceiling = math.floor(cap * BTS.REFILL_MAX)
                    local add = round(cap * rnd(BTS.REFILL_SHARE[1], BTS.REFILL_SHARE[2]))
                    state.inst[inst.id][product][group] = math.max(have, math.min(ceiling, have + add))
                end
            end
        end
    end
end
