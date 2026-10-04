-- Locomotive state (server authority): battery, fuel pump, engine, lights, passenger doors.
-- Clients only request changes ("rw:loco:action"); the driver of the lead is checked, and
-- the state is mirrored to the lead as element data:
--   rw.loco  = { bat = bool, fuel = bool, eng = "off"|"cranking"|"running", lights = bool }
--   rw.doors = "closed" | "left" | "right" | "both"
-- rw_core copies element data when a train is re-created on another track, so a running
-- engine survives a switch.

-- looked up on every call: a reloaded rw_core is a new resource and a cached exports table
-- would keep calling the old one (everything froze after rw_core reloaded)
local core = setmetatable({}, { __index = function(_, fn) return function(_, ...) return exports.rw_core[fn](nil, ...) end end })
local State = {}       -- [consistId] = state

addEvent("onRailSifaBrake")        -- source: lead, (consistId, player)
addEvent("onRailEngineChange")     -- source: lead, (consistId, eng)

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function tell(player, text)
    if isElement(player) then triggerClientEvent(player, "rw:loco:notify", resourceRoot, text) end
end

local function stateOf(id)
    local s = State[id]
    if not s then
        s = { bat = false, fuel = false, eng = "off", lights = false, doors = "closed" }
        State[id] = s
    end
    return s
end

local function push(id, info)
    local s = State[id]
    info = info or core:getConsist(id)
    if not s or not info or not isElement(info.lead) then return end
    setElementData(info.lead, "rw.loco", { bat = s.bat, fuel = s.fuel, eng = s.eng, lights = s.lights })
    setElementData(info.lead, "rw.doors", s.doors)
    setVehicleEngineState(info.lead, s.eng == "running")
    setVehicleOverrideLights(info.lead, s.lights and 2 or 1)
end

local function setEngine(id, s, eng, info)
    if s.eng == eng then return end
    s.eng = eng
    push(id, info)
    info = info or core:getConsist(id)
    if info and isElement(info.lead) then triggerEvent("onRailEngineChange", info.lead, id, eng) end
end

local function hasPassengerCars(info)
    return info.passengerCars and info.passengerCars > 0
end

local actions = {}

function actions.battery(id, s, info)
    s.bat = not s.bat
    if not s.bat then
        s.fuel = false
        s.lights = false
        if s.eng ~= "off" then setEngine(id, s, "off", info) return end
    end
    push(id, info)
end

function actions.fuel(id, s, info, player)
    if not s.bat and not s.fuel then tell(player, "No power - switch the battery on first.") return end
    s.fuel = not s.fuel
    if not s.fuel and s.eng ~= "off" then setEngine(id, s, "off", info) return end
    push(id, info)
end

function actions.start(id, s, info, player)
    if s.eng ~= "off" then return end
    if not s.bat then tell(player, "No power - switch the battery on first.") return end
    if not s.fuel then tell(player, "No fuel pressure - switch the fuel pump on.") return end
    setEngine(id, s, "cranking", info)
    setTimer(function()
        local st = State[id]
        if st and st.eng == "cranking" then
            if st.bat and st.fuel then setEngine(id, st, "running") else setEngine(id, st, "off") end
        end
    end, LOCO.ENGINE_CRANK_TIME, 1)
end

function actions.stop(id, s, info)
    setEngine(id, s, "off", info)
end

function actions.lights(id, s, info, player)
    if not s.bat then tell(player, "No power.") return end
    s.lights = not s.lights
    push(id, info)
end

function actions.doors(id, s, info, player, side)
    if side == "closed" then
        s.doors = "closed"
        push(id, info)
        return
    end
    if side ~= "left" and side ~= "right" then return end
    if not hasPassengerCars(info) then tell(player, "This train has no passenger coaches.") return end
    if not s.bat then tell(player, "No power.") return end
    local ok, reason = true, nil
    if running("rw_timetable") then
        ok, reason = exports.rw_timetable:canOpenDoors(id)
    elseif info.speed > 2 then
        ok, reason = false, "the train is moving"
    end
    if not ok then tell(player, "Doors stay closed: " .. tostring(reason) .. ".") return end
    s.doors = (s.doors ~= "closed" and s.doors ~= side) and "both" or side
    push(id, info)
end

function actions.sifa(id, s, info, player)
    triggerEvent("onRailSifaBrake", info.lead, id, player)
end

addEvent("rw:loco:action", true)
addEventHandler("rw:loco:action", resourceRoot, function(action, arg)
    local player = client
    local id = core:getConsistByDriver(player)
    if not id or not actions[action] then return end
    local info = core:getConsist(id)
    if not info or not LOCO.TYPES[info.loco] then return end
    actions[action](id, stateOf(id), info, player, arg)
end)

-- doors close themselves when the train moves (the door control would not allow traction
-- in reality - this keeps the state honest if the client lock is bypassed)
setTimer(function()
    for id, s in pairs(State) do
        if s.doors ~= "closed" then
            local info = core:getConsist(id)
            if info and info.speed > 4 and not info.auto then
                s.doors = "closed"
                push(id, info)
            end
        end
    end
end, 1000, 0)

-- a new consist starts cold
addEventHandler("onRailConsistSpawn", root, function(id)
    State[id] = nil
    stateOf(id)
    push(id)
end)

addEventHandler("onRailConsistDestroy", root, function(id)
    State[id] = nil
end)

-- the re-created lead got the element data copy; re-apply engine / lights on the new vehicle
addEventHandler("onRailConsistRebuilt", root, function(id)
    if State[id] then setTimer(push, 100, 1, id) end
end)

-- the game switches the engine on when someone gets in: put the simulated state back
addEventHandler("onVehicleEnter", root, function()
    local id = core:getVehicleConsist(source)
    if id and State[id] then setTimer(push, 150, 1, id) end
end)

-- signal passed at danger: emergency stop for the driver
addEventHandler("onRailSignalPassedAtDanger", root, function(id, _, name)
    local info = core:getConsist(id)
    local driver = info and info.driver
    if driver then
        triggerClientEvent(driver, "rw:loco:emergency", resourceRoot, ("Signal %s passed at danger!"):format(name))
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    -- trains that already exist (rw_loco restarted) keep a fresh cold state
    for _, info in ipairs(core:getConsists()) do
        stateOf(info.id)
        push(info.id, info)
    end
end)

-- Sets the state directly, without the cab checks (rw_auto drives its trains with it).
-- t = { bat, fuel, eng = "off"|"running", lights, doors = "closed"|"left"|"right"|"both" }
function setLocoState(id, t)
    if type(t) ~= "table" or not core:getConsist(id) then return false end
    local s = stateOf(id)
    for _, k in ipairs({ "bat", "fuel", "lights" }) do
        if t[k] ~= nil then s[k] = t[k] and true or false end
    end
    if t.eng == "off" or t.eng == "running" then s.eng = t.eng end
    if t.doors == "closed" or t.doors == "left" or t.doors == "right" or t.doors == "both" then s.doors = t.doors end
    push(id)
    return true
end

function getLocoState(id)
    local s = State[id]
    if not s then return false end
    return { bat = s.bat, fuel = s.fuel, eng = s.eng, lights = s.lights, doors = s.doors }
end
