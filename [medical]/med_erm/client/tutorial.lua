-- Tutorial (demo) mode of the unit tablet, driven by an outside tutorial (work_ems).
-- While it runs nothing reaches the server: sign-in, case buttons and messages are answered
-- locally with demo data, and the real server pushes are ignored (client/state.lua).
--
-- Client exports:
--   startTabletTutorial()            demo mode on (not signed in, no case)
--   stopTabletTutorial()             demo mode off, demo data cleared
--   isTabletTutorial()
--   setTabletTutorialCase(task)      demo case for the demo unit (alert + notification)
--                                    task = { title, description, caller, zone, priority, x, y, z }
--   setTabletTutorialUnit(fields)    changes the demo unit (status, reachedScene, ...)
--   addTabletTutorialMessage(text [, channel])   message from dispatch ("dispatch" | "case")
--
-- Every step is reported with the client event onClientErmTabletTutorial (source = localPlayer):
--   "open", "close", "page" (name), "signIn" (callsign), "signOut", "caseAction" ("start" | "stop"),
--   "leaveCase", "closeCase", "message" (text, channel), "case" (task id)

addEvent("onClientErmTabletTutorial", false)

local DEMO_UNIT_ID = -1
local nextTaskId = 1000

function TabletTutorial.report(action, ...)
    if TabletTutorial.active then
        triggerEvent("onClientErmTabletTutorial", localPlayer, action, ...)
    end
end

local function clock()
    local t = getRealTime()
    return string.format("%02d:%02d", t.hour, t.minute)
end

local function plainName(player)
    return (getPlayerName(player):gsub("#%x%x%x%x%x%x", ""))
end

local function resetState()
    State.unit, State.task = nil, nil
    State.messages, State.unread, State.unreadBy = {}, 0, { dispatch = 0, case = 0 }
    State.timeOffset = 0
    Tablet.page = "home"
    State.updateObjective()
end

local function syncTaskUnits()
    local u, t = State.unit, State.task
    if not u or not t then return end
    t.units = { { id = u.id, callsign = u.callsign, status = u.status } }
end

---------------------------------------------------------------- requests answered locally

local handlers = {}

handlers["erm:signIn"] = function(unitType, members, unitNumber)
    if not unitType then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    local n = tonumber(tostring(unitNumber or ""):match("^%d%d?%d?$")) or 1
    State.unit = {
        id           = DEMO_UNIT_ID,
        callsign     = string.format("%s-%02d", unitType, math.max(1, n)),
        type         = unitType,
        plate        = veh and (getVehiclePlateText(veh):gsub("%s+$", "")) or "",
        status       = "available",
        responding   = false,
        responseFrom = 0,
        reachedScene = false,
        handoverEnds = 0,
        startedAt    = State.serverNow(),
        members      = { { player = localPlayer, name = getPlayerName(localPlayer) } },
        closedTasks  = {},
    }
    Tablet.setPage("home")
    State.notify("Shift started", "Signed in as " .. State.unit.callsign .. ".")
    TabletTutorial.report("signIn", State.unit.callsign)
end

handlers["erm:signOut"] = function()
    State.unit, State.task = nil, nil
    if Tablet.open then Tablet.close() end
    State.notify("EMS Tablet", "Signed out.")
    TabletTutorial.report("signOut")
end

handlers["erm:caseAction"] = function(action)
    local u = State.unit
    if not u or not State.task then return end
    if action == "start" then
        u.responding, u.responseFrom = true, State.serverNow()
        if u.status == "available" then u.status = "enroute" end
    elseif action == "stop" then
        u.responding = false
    else
        return
    end
    syncTaskUnits()
    TabletTutorial.report("caseAction", action)
end

handlers["erm:leaveCase"] = function()
    State.notify("EMS Tablet", "Leave Case is only possible while another unit stays on the case.")
    TabletTutorial.report("leaveCase")
end

handlers["erm:closeCase"] = function()
    State.notify("EMS Tablet", "Closing the case is not available in the tutorial.")
    TabletTutorial.report("closeCase")
end

handlers["erm:sendMessage"] = function(text, channel)
    local u, t = State.unit, State.task
    if not u then return end
    local case = channel == "case" and t
    State.receiveMessage({
        channel = case and "task" or "unit",
        target = case and t.id or u.id,
        label = case and string.format("Case #%d", t.id) or u.callsign,
        from = u.callsign .. " (" .. plainName(localPlayer) .. ")",
        fromDispatch = false,
        fromUnit = u.id,
        text = tostring(text),
        time = clock(),
    })
    TabletTutorial.report("message", text, channel)
end

function TabletTutorial.handle(name, ...)
    local fn = handlers[name]
    if fn then fn(...) end
end

---------------------------------------------------------------- exports

function startTabletTutorial()
    if Tablet.open then Tablet.close() end
    TabletTutorial.active = true
    resetState()
    return true
end

function stopTabletTutorial()
    if not TabletTutorial.active then return false end
    if Tablet.open then Tablet.close() end
    TabletTutorial.active = false
    resetState()
    return true
end

function isTabletTutorial()
    return TabletTutorial.active
end

function setTabletTutorialCase(task)
    if not TabletTutorial.active or not State.unit or type(task) ~= "table" then return false end
    nextTaskId = nextTaskId + 1
    local x, y, z = getElementPosition(localPlayer)
    State.task = {
        id          = nextTaskId,
        title       = tostring(task.title or "Injured person"),
        description = tostring(task.description or ""),
        caller      = tostring(task.caller or ""),
        x = tonumber(task.x) or x, y = tonumber(task.y) or y, z = tonumber(task.z) or z,
        zone        = tostring(task.zone or getZoneName(x, y, z)),
        priority    = tonumber(task.priority) or 2,
        status      = "assigned",
        units       = {},
        responseLog = {},
        createdAt   = State.serverNow(),
        closedAt    = 0,
        closedLabel = "",
    }
    syncTaskUnits()
    State.notify("New case assigned", string.format("#%d %s", State.task.id, State.task.title), true)
    TabletTutorial.report("case", State.task.id)
    return State.task.id
end

function setTabletTutorialUnit(fields)
    if not TabletTutorial.active or not State.unit or type(fields) ~= "table" then return false end
    for k, v in pairs(fields) do State.unit[k] = v end
    syncTaskUnits()
    return true
end

function addTabletTutorialMessage(text, channel)
    local u, t = State.unit, State.task
    if not TabletTutorial.active or not u then return false end
    local case = channel == "case" and t
    State.receiveMessage({
        channel = case and "task" or "unit",
        target = case and t.id or u.id,
        label = case and string.format("Case #%d", t.id) or u.callsign,
        from = "Dispatch",
        fromDispatch = true,
        text = tostring(text),
        time = clock(),
    })
    return true
end
