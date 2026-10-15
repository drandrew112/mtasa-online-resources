if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- bt_stock: the stock of the blood supply centers and the hospitals (data/stock.json).
-- Hospitals consume and ask bt_dispatch for resupply; the centers are refilled hourly and give
-- their units up when a task is created.

addEvent("onBtCoreStart")
addEvent("onBtStockStart")

local State
local Cfg                    -- bt_core config (+ byId)
local dirty, saveTimer = false, nil
local Pending = {}           -- hospital id -> { [product] = { [group] = units } } on the way
local PendingTasks = {}      -- hospital id -> open resupply task count
local nextConsume = {}       -- hospital id -> tick
local lastCheck = 0

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function rnd(a, b) return a + math.random() * (b - a) end

local function loadConfig()
    if not isRunning("bt_core") then return false end
    Cfg = exports.bt_core:getConfig()
    Cfg.byId = {}
    for _, inst in ipairs(Cfg.INSTITUTIONS) do Cfg.byId[inst.id] = inst end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------------------------

local function save()
    dirty = false
    if not State then return end
    local f = fileExists(BTS.FILE) and fileOpen(BTS.FILE) or fileCreate(BTS.FILE)
    if not f then return outputDebugString("[bt_stock] cannot write " .. BTS.FILE, 1) end
    fileSetPos(f, 0)
    fileWrite(f, toJSON(State, true))
    fileClose(f)
end

local function markDirty()
    dirty = true
    if not saveTimer or not isTimer(saveTimer) then
        saveTimer = setTimer(function() if dirty then save() end end, BTS.SAVE_DELAY * 1000, 1)
    end
end

local function load()
    local state
    if fileExists(BTS.FILE) then
        local f = fileOpen(BTS.FILE, true)
        if f then
            local text = fileRead(f, fileGetSize(f))
            fileClose(f)
            state = text and text ~= "" and fromJSON(text)
        end
    end
    if type(state) == "table" and type(state.inst) == "table" then
        if StockModel.repair(Cfg, BTS, state, rnd) then markDirty() end
        State = state
    else
        State = StockModel.create(Cfg, BTS, rnd)
        State.refilled = getRealTime().timestamp
        save()
    end
end

-- ---------------------------------------------------------------------------------------------
-- Simulation
-- ---------------------------------------------------------------------------------------------

local function dutyCount()
    if not isRunning("bt_dispatch") then return 0 end
    return exports.bt_dispatch:getDutyCount() or 0
end

local function pendingOf(instId)
    Pending[instId] = Pending[instId] or {}
    return Pending[instId]
end

local function addPending(instId, product, group, units)
    local p = pendingOf(instId)
    p[product] = p[product] or {}
    p[product][group] = math.max(0, (p[product][group] or 0) + units)
end

-- Asks bt_dispatch for the deliveries one hospital line needs
local function requestLine(inst, need)
    if (PendingTasks[inst.id] or 0) >= BTS.MAX_PENDING_TASKS then return false end
    local legs = StockModel.plan(Cfg, State, need.product, need.group, need.need, inst.id, true)
    if not legs or #legs == 0 then return false end
    local leg = legs[1]
    local source = Cfg.byId[leg.from]
    local urgent = StockModel.level(Cfg, BTS, State, source, need.product, need.group) < BTS.URGENT_LEVEL
    local units = math.min(leg.units, urgent and BTS.URGENT_BATCH or BTS.BATCH)
    local _, taken = StockModel.add(Cfg, BTS, State, source, need.product, need.group, -units)
    taken = -taken
    if taken <= 0 then return false end
    markDirty()
    local id = exports.bt_dispatch:createTask({
        type = "resupply", urgency = urgent and "urgent" or "routine", product = need.product, group = need.group,
        units = taken, from = leg.from, to = inst.id, source = "stock", reserved = true,
    })
    if not id then
        StockModel.add(Cfg, BTS, State, source, need.product, need.group, taken)
        markDirty()
        return false
    end
    addPending(inst.id, need.product, need.group, taken)
    PendingTasks[inst.id] = (PendingTasks[inst.id] or 0) + 1
    return true
end

local function tick()
    if not State or not Cfg then return end
    local now = getTickCount()
    local realNow = getRealTime().timestamp

    -- centers: hourly refill, also without transporters
    if realNow - (State.refilled or 0) >= BTS.REFILL_INTERVAL then
        StockModel.refill(Cfg, BTS, State, rnd)
        State.refilled = realNow
        markDirty()
    end

    if dutyCount() <= 0 then return end

    -- hospitals: consumption
    for _, inst in ipairs(Cfg.INSTITUTIONS) do
        if inst.kind == "hospital" then
            if not nextConsume[inst.id] then nextConsume[inst.id] = now + rnd(BTS.CONSUME_INTERVAL[1], BTS.CONSUME_INTERVAL[2]) * 1000 end
            if now >= nextConsume[inst.id] then
                nextConsume[inst.id] = now + rnd(BTS.CONSUME_INTERVAL[1], BTS.CONSUME_INTERVAL[2]) * 1000
                if StockModel.consume(Cfg, BTS, State, inst, rnd) then markDirty() end
            end
        end
    end

    -- hospitals: resupply requests
    if now - lastCheck >= BTS.CHECK_INTERVAL * 1000 then
        lastCheck = now
        for _, inst in ipairs(Cfg.INSTITUTIONS) do
            if inst.kind == "hospital" then
                local needs = StockModel.needs(Cfg, BTS, State, inst, pendingOf(inst.id))
                for _, need in ipairs(needs) do
                    if not requestLine(inst, need) then break end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------------

-- -> { [product] = { [group] = units } } | false
function getStock(instId)
    return State and State.inst[instId] or false
end

-- Everything with the capacities, for the web page:
-- { [instId] = { kind, lines = { [product] = { [group] = { have, cap } } } } }
function getAllStock()
    if not State or not Cfg then return {} end
    local out = {}
    for _, inst in ipairs(Cfg.INSTITUTIONS) do
        local lines = {}
        for _, product in ipairs(Cfg.PRODUCT_ORDER) do
            lines[product] = {}
            for _, group in ipairs(Cfg.GROUPS) do
                lines[product][group] = { have = StockModel.get(State, inst.id, product, group),
                                          cap = StockModel.capacity(Cfg, BTS, inst.kind, group) }
            end
        end
        out[inst.id] = { kind = inst.kind, lines = lines }
    end
    return out
end

-- Takes the units from the centers (all or nothing, or whatever there is with partial)
-- -> { { from, units } ... } | false. Called by bt_dispatch for tasks it creates itself.
function allocate(product, group, units, toInst, partial)
    if not State or not Cfg then return false end
    units = math.floor(tonumber(units) or 0)
    if units < 1 then return false end
    local legs = StockModel.plan(Cfg, State, product, group, units, toInst, partial == true)
    if not legs then return false end
    for _, leg in ipairs(legs) do
        StockModel.add(Cfg, BTS, State, Cfg.byId[leg.from], product, group, -leg.units)
    end
    markDirty()
    return legs
end

-- Gives units back to a center (a task that was not picked up was cancelled)
function release(instId, product, group, units)
    if not State or not Cfg or not Cfg.byId[instId] then return false end
    StockModel.add(Cfg, BTS, State, Cfg.byId[instId], product, group, math.floor(tonumber(units) or 0))
    markDirty()
    return true
end

-- Total units a request could get right now (for deciding without taking)
function canFulfill(product, group, units, toInst)
    if not State or not Cfg then return false end
    return StockModel.plan(Cfg, State, product, group, units, toInst, false) ~= false
end

-- bt_dispatch tells how a task ended. info = { type, status = "delivered" | "cancelled", to, from,
-- product, group, units, source, pickedUp }
function taskClosed(info)
    if type(info) ~= "table" or not State or not Cfg then return false end
    if info.type == "resupply" and info.source == "stock" then
        addPending(info.to, info.product, info.group, -(info.units or 0))
        PendingTasks[info.to] = math.max(0, (PendingTasks[info.to] or 0) - 1)
    end
    local hospital = Cfg.byId[info.to]
    if info.status == "delivered" then
        -- a resupply fills the hospital, everything else is used up on arrival
        if info.type == "resupply" and hospital and hospital.kind == "hospital" and info.product then
            StockModel.add(Cfg, BTS, State, hospital, info.product, info.group, info.units or 0)
            markDirty()
        end
    elseif info.status == "cancelled" and not info.pickedUp and info.product and info.from and Cfg.byId[info.from] then
        -- reserved at the center but never left: back into the stock
        StockModel.add(Cfg, BTS, State, Cfg.byId[info.from], info.product, info.group, info.units or 0)
        markDirty()
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Lifetime
-- ---------------------------------------------------------------------------------------------

local function start()
    if not loadConfig() then return end
    load()
    triggerEvent("onBtStockStart", resourceRoot)
end

addEventHandler("onResourceStart", resourceRoot, function()
    start()
    setTimer(tick, 5000, 0)
end)

addEventHandler("onBtCoreStart", root, function() loadConfig() end)

addEventHandler("onResourceStop", resourceRoot, function() if State and dirty then save() end end)
