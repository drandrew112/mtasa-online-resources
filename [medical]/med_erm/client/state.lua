-- Client-side copy of the unit state pushed by the server.

-- Tutorial (demo) mode, filled in by client/tutorial.lua
TabletTutorial = { active = false }

State = {
    unit       = nil,   -- own unit (nil = not signed in)
    task       = nil,   -- active task of the unit
    messages   = {},
    unread     = 0,     -- total, shown on the menu
    unreadBy   = { dispatch = 0, case = 0 },
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

-- alert = true: play sounds/tablet_alert.mp3 and keep ui_core's notification silent.
function State.notify(title, text, alert)
    if alert then playSound("sounds/tablet_alert.mp3") end
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(title, text, alert == true)
    else
        outputChatBox("#E03C31[" .. title .. "] #FFFFFF" .. text, 255, 255, 255, true)
    end
end

local function radarRunning()
    local res = getResourceFromName("v_radar")
    return res and getResourceState(res) == "running"
end

function State.updateObjective()
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
        State.updateObjective()
    end
end, 1000, 0)

-- v_radar (re)started: its objectives are gone, place ours again.
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) == "v_radar" then
        objectiveId, objectiveTask = nil, nil
        State.updateObjective()
    end
end)

addEvent("erm:sync", true)
addEventHandler("erm:sync", resourceRoot, function(data)
    if TabletTutorial.active then return end -- tutorial: demo data only
    State.unit = data.unit
    State.task = data.task or nil
    State.timeOffset = data.serverTime - getRealTime().timestamp
    State.updateObjective()
end)

-- Tablet channel of a message: "case" (task chat) or "dispatch" (direct + broadcast).
function State.channelOf(msg)
    return msg.channel == "task" and "case" or "dispatch"
end

function State.markRead(channel)
    State.unreadBy[channel] = 0
    State.unread = State.unreadBy.dispatch + State.unreadBy.case
end

addEvent("erm:messages", true)
addEventHandler("erm:messages", resourceRoot, function(list)
    if TabletTutorial.active then return end
    State.messages = list or {}
    State.unread, State.unreadBy = 0, { dispatch = 0, case = 0 }
end)

addEvent("erm:message", true)
addEventHandler("erm:message", resourceRoot, function(msg)
    if TabletTutorial.active then return end
    State.receiveMessage(msg)
end)

function State.receiveMessage(msg)
    table.insert(State.messages, msg)
    while #State.messages > 100 do table.remove(State.messages, 1) end

    local own = not msg.fromDispatch and State.unit and msg.fromUnit == State.unit.id
    if own then return end

    local channel = State.channelOf(msg)
    local reading = Tablet.open and Tablet.page == "messages" and Pages.messages.channel == channel
    if not reading then
        State.unreadBy[channel] = State.unreadBy[channel] + 1
        State.unread = State.unread + 1
        local title = msg.channel == "broadcast" and "Dispatch broadcast"
            or channel == "case" and (msg.label or "Case chat") or "Dispatch"
        State.notify(title, msg.fromDispatch and msg.text or (msg.from:gsub("#%x%x%x%x%x%x", "") .. ": " .. msg.text))
    end
end

addEvent("erm:signedOut", true)
addEventHandler("erm:signedOut", resourceRoot, function(reason)
    if TabletTutorial.active then return end
    State.unit, State.task = nil, nil
    State.messages, State.unread, State.unreadBy = {}, 0, { dispatch = 0, case = 0 }
    State.updateObjective()
    if Tablet.open then Tablet.close() end
    State.notify("EMS Tablet", reason or "Signed out.")
end)

addEvent("erm:notify", true)
addEventHandler("erm:notify", resourceRoot, function(title, text, alert)
    State.notify(title, text, alert)
end)

-- Driver of a unit with an active case drives off without Start Response: the
-- response is started automatically, once per leg (to the scene, then away from
-- it). Ending it by hand is respected for the rest of that leg.
local autoStarted = {}   -- ["<task id>:go" | "<task id>:scene"] = true
setTimer(function()
    local u, t = State.unit, State.task
    local veh = getPedOccupiedVehicle(localPlayer)
    if not u or not t or u.responding or u.status == "handover" or not veh
        or getVehicleOccupant(veh, 0) ~= localPlayer or not Config.TABLET_VEHICLES[getElementModel(veh)] then
        return
    end
    local leg = t.id .. (u.reachedScene and ":scene" or ":go")
    if autoStarted[leg] then return end

    local vx, vy, vz = getElementVelocity(veh)
    if (vx * vx + vy * vy + vz * vz) ^ 0.5 * 180 <= Config.RESPONSE_AUTO_SPEED then return end
    -- leaving the scene: moving the ambulance around on scene does not count
    if u.reachedScene then
        local x, y = getElementPosition(veh)
        if getDistanceBetweenPoints2D(x, y, t.x, t.y) <= Config.ARRIVE_RADIUS then return end
    end

    autoStarted[leg] = true
    Tablet.send("erm:caseAction", "start")
    State.notify("EMS Tablet", string.format("Response started automatically for case #%d.", t.id))
end, 500, 0)
