if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- bt_dispatch: start-up, exports.

addEvent("onBtStockStart")

local function callerName()
    return sourceResource and getResourceName(sourceResource) or nil
end

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

addEvent("mysql:connected")

local dbReady = false

local function startDb()
    if dbReady or not DB.init() then return end
    dbReady = true
    -- leftovers of the last run lost their cargo: close them, the stock takes the reserved units back
    local rows = DB.closeLeftovers() or {}
    if not isRunning("bt_stock") then return end
    for _, r in ipairs(rows) do
        if tonumber(r.reserved) == 1 and r.status == "waiting" and r.product and r.from_inst then
            exports.bt_stock:release(r.from_inst, r.product, r.grp, tonumber(r.units) or 0)
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    startDb()
    if not dbReady then outputDebugString("[bt_dispatch] v_mysql not connected yet, waiting for mysql:connected", 2) end
end)

-- v_mysql (re)connected: the first time it also creates the tables and closes the leftovers
addEventHandler("mysql:connected", root, startDb)

---------------------------------------------------------------- exports

-- Raw task (bt_stock for the resupply of a hospital, with the units already taken from the stock)
-- def: type, urgency, product, group, units, from, to, source, reserved -> id | false, reason
function createTask(def)
    if type(def) ~= "table" then return false, "table expected" end
    return makeTask(def, callerName())
end

-- Blood tasks that take the units from the centers' stock -> { ids } | false, reason
function requestSupply(req)
    if type(req) ~= "table" then return false, "table expected" end
    return makeSupply(req, callerName())
end

-- Number of transporters in service (they all keep the hospitals consuming)
-- (getDutyCount, getTask, getPlayerTasks, isPlayerInService, onPickedUp, onDelivered: core.lua)

-- The public state for the web page: units with their tasks, counters
function getPublicState()
    local units, active = {}, 0
    for _, shift in ipairs(shiftList()) do
        local x, y = 0, 0
        if isElement(shift.vehicle) then x, y = getElementPosition(shift.vehicle) end
        local tasks = {}
        for _, t in ipairs(BTLogic.sorted(openTasksOf(shift), shift.order)) do
            tasks[#tasks + 1] = { id = t.id, type = t.type, urgency = t.urgency, status = t.status, product = t.product or "",
                group = t.group or "", units = t.units, from = t.from, to = t.to }
            active = active + 1
        end
        units[#units + 1] = { unit = shift.unit, driver = shift.name, x = x, y = y, delivered = shift.delivered,
            since = math.floor((getTickCount() - shift.startedTick) / 1000), windDown = shift.windDown, tasks = tasks }
    end
    return { onDuty = #units, active = active, completed = getCompletedCount(), units = units }
end

-- Total delivered tasks since the beginning (database count at start + delivered since then)
function getCompletedCount()
    return DB.completed + TotalDelivered
end

-- Test / admin helper: generate one random task now
function generateTask()
    return generateNow()
end
