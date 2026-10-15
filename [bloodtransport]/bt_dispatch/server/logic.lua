-- Pure dispatch logic without MTA functions (tested with lupa, see tests/).

BTLogic = {}

-- Pay of a service. -> items { { key, count, amount } ... }, total
function BTLogic.pay(PAY, delivered, inTransit)
    local items, total = {}, 0
    if delivered > 0 then
        items[#items + 1] = { key = "base", count = 1, amount = PAY.BASE }
        total = total + PAY.BASE
        items[#items + 1] = { key = "delivered", count = delivered, amount = PAY.DELIVERED * delivered }
        total = total + PAY.DELIVERED * delivered
    end
    if inTransit > 0 then
        items[#items + 1] = { key = "in_transit", count = inTransit, amount = PAY.IN_TRANSIT * inTransit }
        total = total + PAY.IN_TRANSIT * inTransit
    end
    return items, total
end

-- Validates a task definition against the type rules.
-- types = BTD.TYPES, inst = { [id] = { kind } } -> true | false, reason
function BTLogic.checkTask(types, inst, def)
    local t = types[def.type]
    if not t then return false, "unknown type" end
    local from, to = inst[def.from], inst[def.to]
    if not from or not to then return false, "unknown institution" end
    if from.kind ~= t.from or to.kind ~= t.to then return false, "wrong institution kind" end
    if t.differ and def.from == def.to then return false, "same institution" end
    if t.stock and (not def.product or not def.group) then return false, "product and group expected" end
    return true
end

-- Picks the unit that gets a new task: the least loaded one that is not winding down and not full.
-- units = { { open, windDown, dist } ... } (dist: distance to the pickup point, optional)
-- -> index | nil
function BTLogic.pickUnit(units, maxOpen)
    local best, bestOpen, bestDist
    for i, u in ipairs(units) do
        if not u.windDown and u.open < maxOpen then
            local d = u.dist or 0
            if not best or u.open < bestOpen or (u.open == bestOpen and d < bestDist) then
                best, bestOpen, bestDist = i, u.open, d
            end
        end
    end
    return best
end

-- Weighted pick from { key = weight }; rnd(a, b) float in [a, b); keys sorted for determinism
function BTLogic.weighted(map, rnd)
    local keys, total = {}, 0
    for k, w in pairs(map) do keys[#keys + 1] = k; total = total + w end
    table.sort(keys)
    local r = rnd(0, total)
    for _, k in ipairs(keys) do
        r = r - map[k]
        if r < 0 then return k end
    end
    return keys[#keys]
end

-- Splits a number of units into tasks of at most `max` units -> { n ... }
function BTLogic.chunks(units, max)
    local out = {}
    while units > 0 do
        local n = math.min(units, max)
        out[#out + 1] = n
        units = units - n
    end
    return out
end

-- Wanted number of open tasks for the units on duty (not winding down)
function BTLogic.targetOpen(perUnit, units)
    return perUnit * units
end

-- Order of the tasks of a unit for the panel: in transit first (oldest pick-up first), then the
-- waiting ones in the order the player set. tasks = { { id, status, pickedAt } }, order = { id ... }
function BTLogic.sorted(tasks, order)
    local pos = {}
    for i, id in ipairs(order) do pos[id] = i end
    local out = {}
    for _, t in ipairs(tasks) do out[#out + 1] = t end
    table.sort(out, function(a, b)
        local ta, tb = a.status == "transit", b.status == "transit"
        if ta ~= tb then return ta end
        if ta then
            if (a.pickedAt or 0) ~= (b.pickedAt or 0) then return (a.pickedAt or 0) < (b.pickedAt or 0) end
            return a.id < b.id
        end
        return (pos[a.id] or 1e9) < (pos[b.id] or 1e9)
    end)
    return out
end

-- Moves an id in the order list one step (-1 up, +1 down); the list only holds waiting ids.
-- -> true when it moved
function BTLogic.move(order, id, dir)
    for i, v in ipairs(order) do
        if v == id then
            local j = i + dir
            if j < 1 or j > #order then return false end
            order[i], order[j] = order[j], order[i]
            return true
        end
    end
    return false
end
