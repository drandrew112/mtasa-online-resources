-- Client-side copy of the unit state pushed by the server.

State = {
    unit       = nil,   -- own unit (nil = not signed in)
    task       = nil,   -- active task of the unit
    messages   = {},
    unread     = 0,
    timeOffset = 0,     -- serverTime - local time
}

-- The active task is shown as a v_radar objective (yellow marker + route).
local objectiveId, objectiveTask
local arrivedTask   -- task id the player already reached (no objective any more)

function State.serverNow()
    return getRealTime().timestamp + State.timeOffset
end

function State.formatClock(ts)
    local t = getRealTime(ts)
    return string.format("%02d:%02d", t.hour, t.minute)
end

function State.formatDuration(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
    end
    return string.format("%02d:%02d", sec / 60, sec % 60)
end

function State.notify(title, text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(title, text)
    else
        outputChatBox("#E03C31[" .. title .. "] #FFFFFF" .. text, 255, 255, 255, true)
    end
end

local function radarRunning()
    local res = getResourceFromName("v_radar")
    return res and getResourceState(res) == "running"
end

local function updateObjective()
    local t = State.task
    if not radarRunning() then
        objectiveId, objectiveTask = nil, nil
        return
    end

    if t and (State.unit.reachedScene or arrivedTask == t.id) then
        arrivedTask = t.id
        t = nil
    end

    if not t then
        if objectiveId then exports.v_radar:removeObjective(objectiveId) end
        objectiveId, objectiveTask = nil, nil
        return
    end

    -- tasks created on the web have z = 0: let v_radar find the ground
    local z = (t.z ~= 0) and t.z or nil
    local label = string.format("#%d %s", t.id, t.title)
    if objectiveId and objectiveTask == t.id then
        exports.v_radar:updateObjective(objectiveId, t.x, t.y, z, label)
    else
        if objectiveId then exports.v_radar:removeObjective(objectiveId) end
        objectiveId = exports.v_radar:addObjective(t.x, t.y, z, label) or nil
        objectiveTask = objectiveId and t.id or nil
    end
end

-- Arrival check: close enough to the scene -> objective removed for good.
setTimer(function()
    local t = State.task
    if not t or not objectiveId or arrivedTask == t.id then return end
    local x, y = getElementPosition(localPlayer)
    if getDistanceBetweenPoints2D(x, y, t.x, t.y) <= Config.ARRIVE_RADIUS then
        arrivedTask = t.id
        updateObjective()
    end
end, 1000, 0)

-- v_radar (re)started: its objectives are gone, place ours again.
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) == "v_radar" then
        objectiveId, objectiveTask = nil, nil
        updateObjective()
    end
end)

addEvent("erm:sync", true)
addEventHandler("erm:sync", resourceRoot, function(data)
    State.unit = data.unit
    State.task = data.task or nil
    State.timeOffset = data.serverTime - getRealTime().timestamp
    updateObjective()
end)

addEvent("erm:messages", true)
addEventHandler("erm:messages", resourceRoot, function(list)
    State.messages = list or {}
    State.unread = 0
end)

addEvent("erm:message", true)
addEventHandler("erm:message", resourceRoot, function(msg)
    table.insert(State.messages, msg)
    while #State.messages > 100 do table.remove(State.messages, 1) end

    local reading = Tablet.open and Tablet.page == "messages"
    if not reading then State.unread = State.unread + 1 end
    if msg.fromDispatch and not reading then
        State.notify(msg.channel == "broadcast" and "Dispatch broadcast" or "Dispatch", msg.text)
    end
end)

addEvent("erm:signedOut", true)
addEventHandler("erm:signedOut", resourceRoot, function(reason)
    State.unit, State.task = nil, nil
    State.messages, State.unread = {}, 0
    updateObjective()
    if Tablet.open then Tablet.close() end
    State.notify("EMS Tablet", reason or "Signed out.")
end)

addEvent("erm:notify", true)
addEventHandler("erm:notify", resourceRoot, function(title, text)
    State.notify(title, text)
end)
