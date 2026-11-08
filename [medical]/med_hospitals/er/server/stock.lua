-- ER supplies (er/shared/stock.lua ERC.STOCK): per hospital, per pool (shock, wound, cast, ct, nurse).
-- medsys asks for the equipment of a hospital patient here (exports getHospitalEquipment /
-- consumeHospitalStock, medsys server/equipment.lua): the staff need no EMS bag in the ER; the room's
-- stock is what they have. An order refills everything that was missing when it was placed (30 s,
-- one pending order per hospital); its price is paid from the state account the government picked
-- for supplies (gov_health, er/server/pay.lua ER.paySupplies).

local Stock = {}   -- [hospitalId] = { pools = { [pool] = { [itemId] = amount } }, order = { ends, missing, cost } }

local function defaults()
    local pools = {}
    for pool, list in pairs(ERC.STOCK) do
        pools[pool] = {}
        for _, it in ipairs(list) do pools[pool][it.id] = it.amount end
    end
    return pools
end

local function def(pool, itemId)
    for _, it in ipairs(ERC.STOCK[pool] or {}) do if it.id == itemId then return it end end
end

local saveTimer = {}
local function save(hid)
    if saveTimer[hid] then return end
    saveTimer[hid] = setTimer(function()
        saveTimer[hid] = nil
        if ERDB and Stock[hid] then ERDB.saveStock(hid, { pools = Stock[hid].pools }) end
    end, 3000, 1)
end

local function stockOf(hid)
    local s = Stock[hid]
    if not s then
        s = { pools = defaults() }
        Stock[hid] = s
    end
    return s
end

LoadHandlers[#LoadHandlers + 1] = function()
    local function load()
        if ERDB and not ERDB.ready then return setTimer(load, 500, 1) end
        for hid in pairs(ER.byHospital) do
            local s = stockOf(hid)
            if ERDB then
                ERDB.loadStock(hid, function(data)
                    if type(data) ~= "table" or type(data.pools) ~= "table" then return end
                    -- items added to the catalogue later start full
                    local pools = defaults()
                    for pool, items in pairs(data.pools) do
                        if pools[pool] then for id, n in pairs(items) do if pools[pool][id] ~= nil then pools[pool][id] = tonumber(n) or 0 end end end
                    end
                    s.pools = pools
                end)
            end
        end
    end
    load()
end

---------------------------------------------------------------- use

-- amount left of an item in a pool (devices: always their amount)
function ER.stockLeft(hid, pool, itemId)
    local d = def(pool, itemId)
    if not d then return 0 end
    if d.device then return d.amount end
    return stockOf(hid).pools[pool][itemId] or 0
end

-- uses n pieces of an item (case location -> pool); -> true | false (out of it)
-- Is the item there (without using it)? The minigame treatments check first and use it only after a
-- successful attempt (a failed one can be retried without losing stock).
function ER.hasStock(c, itemId, n, pool)
    pool = pool or ERC.stockPool(c.location)
    local d = def(pool, itemId)
    if not d then
        if pool ~= "nurse" and def("nurse", itemId) then return ER.hasStock(c, itemId, n, "nurse") end
        return false
    end
    if d.device then return true end
    return (stockOf(c.hospital).pools[pool][itemId] or 0) >= (n or 1)
end

function ER.useStock(c, itemId, n, pool)
    pool = pool or ERC.stockPool(c.location)
    local d = def(pool, itemId)
    if not d then
        -- not stocked in this room: the nurses' station has it?
        if pool ~= "nurse" and def("nurse", itemId) then return ER.useStock(c, itemId, n, "nurse") end
        return false
    end
    if d.device then return true end
    local p = stockOf(c.hospital).pools[pool]
    n = n or 1
    if (p[itemId] or 0) < n then return false end
    p[itemId] = p[itemId] - n
    save(c.hospital)
    return true
end

-- medsys stock category totals of a pool (+ the nurses' station for anything the room does not have)
local function categoryTotals(hid, pool, c)
    local s = stockOf(hid)
    local out = { drugs = {}, oxygen = 100, glucometers = 1 }
    if c and ER.oxygenAvailable then out.oxygen = ER.oxygenAvailable(c) end
    local function addPool(name, onlyMissing)
        for _, it in ipairs(ERC.STOCK[name] or {}) do
            if it.cat and it.cat ~= "hosp" and it.cat ~= "blood" and not it.device then
                local n = s.pools[name][it.id] or 0
                if it.cat == "drugs" then
                    if not onlyMissing or out.drugs[it.drug] == nil then out.drugs[it.drug] = (out.drugs[it.drug] or 0) + n end
                elseif not onlyMissing or out[it.cat] == nil then
                    out[it.cat] = (out[it.cat] or 0) + n
                end
            end
        end
    end
    addPool(pool, false)
    if pool ~= "nurse" then addPool("nurse", true) end
    return out
end

-- export (medsys): what the hospital gives this patient + medic, or false (not a hospital patient)
function getHospitalEquipment(target, medic)
    local c = ER.cases[target]
    if not c or not isElement(medic) or not ER.isStaff(medic, c.hospital) then return false end
    local pool = ERC.stockPool(c.location)
    return { bag = "hosp:" .. c.hospital .. ":" .. pool, monitor = "hosp:" .. c.hospital .. ":monitor",
             stock = categoryTotals(c.hospital, pool, c), hospital = true }
end

-- export (medsys): one piece of a medsys category (drugs + id) used on a hospital patient
function consumeHospitalStock(target, category, key)
    local c = ER.cases[target]
    if not c then return false end
    local pool = ERC.stockPool(c.location)
    local function take(name)
        for _, it in ipairs(ERC.STOCK[name] or {}) do
            if it.cat == category and (category ~= "drugs" or it.drug == key) and not it.device then
                local p = stockOf(c.hospital).pools[name]
                if (p[it.id] or 0) > 0 then
                    p[it.id] = p[it.id] - 1
                    save(c.hospital)
                    return true
                end
            end
        end
        return false
    end
    return take(pool) or (pool ~= "nurse" and take("nurse")) or false
end

---------------------------------------------------------------- order (PC "Felszerelés")

-- what is missing now: { { pool, id, n, price } }, total cost
function ER.stockMissing(hid)
    local s, out, cost = stockOf(hid), {}, 0
    for _, pool in ipairs(ERC.STOCK_POOLS) do
        for _, it in ipairs(ERC.STOCK[pool]) do
            if not it.device and it.cat ~= "blood" then
                local n = it.amount - (s.pools[pool][it.id] or 0)
                if n > 0 then
                    out[#out + 1] = { pool = pool, id = it.id, n = n, price = it.price or 0 }
                    cost = cost + n * (it.price or 0)
                end
            end
        end
    end
    return out, math.floor(cost + 0.5)
end

function ER.orderStock(hid, player)
    local s = stockOf(hid)
    if s.order then return false, "pending" end
    local missing, cost = ER.stockMissing(hid)
    if #missing == 0 then return false, "nothing" end
    if ER.paySupplies and not ER.paySupplies(hid, cost, player) then return false, "payment" end
    s.order = { ends = getRealTime().timestamp + ERC.STOCK_ORDER_TIME, missing = missing, cost = cost,
                by = isElement(player) and getPlayerName(player) or "" }
    setTimer(function()
        local o = s.order
        s.order = nil
        if not o then return end
        for _, m in ipairs(o.missing) do
            local p = s.pools[m.pool]
            local d = def(m.pool, m.id)
            if p and d then p[m.id] = math.min(d.amount, (p[m.id] or 0) + m.n) end
        end
        save(hid)
        ER.notifyStaff(hid, function(pl) return L.forPlayer(pl, "med_hospitals.stock.arrived") end)
        if ER.markDirty then ER.markDirty(hid) end
    end, ERC.STOCK_ORDER_TIME * 1000, 1)
    return true, cost
end

-- PC page: every pool with its items (left / full), the pending order
function ER.stockView(hid)
    local s = stockOf(hid)
    local pools = {}
    for _, pool in ipairs(ERC.STOCK_POOLS) do
        local items = {}
        for _, it in ipairs(ERC.STOCK[pool]) do
            items[#items + 1] = { id = it.id, left = it.device and it.amount or (s.pools[pool][it.id] or 0), full = it.amount, device = it.device or false }
        end
        pools[#pools + 1] = { id = pool, items = items }
    end
    local _, cost = ER.stockMissing(hid)
    return { pools = pools, cost = cost, order = s.order and { left = math.max(0, s.order.ends - getRealTime().timestamp), cost = s.order.cost } or false }
end

-- the blood fridge (transfusion module): emergency 0- RBC / AB plasma units
function ER.fridgeTake(hid, itemId)
    local p = stockOf(hid).pools.shock
    if (p[itemId] or 0) <= 0 then return false end
    p[itemId] = p[itemId] - 1
    save(hid)
    return true
end
function ER.fridgeAdd(hid, itemId, n)
    local p = stockOf(hid).pools.shock
    local d = def("shock", itemId)
    p[itemId] = math.min(d and d.amount or 99, (p[itemId] or 0) + (n or 1))
    save(hid)
end
