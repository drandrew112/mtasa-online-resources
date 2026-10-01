-- Units (signed-in ambulance crews). One unit = one shift row in the DB.

Units = {
    list     = {},   -- [id] = unit
    byPlayer = {},   -- [player] = unit
    nextId   = 1,
}

function Units.get(id)
    return Units.list[tonumber(id) or -1]
end

function Units.ofPlayer(player)
    return Units.byPlayer[player]
end

local function callsignUsed()
    local used = {}
    for _, u in pairs(Units.list) do used[u.callsign] = true end
    return used
end

local function freeCallsign(unitType)
    local used = callsignUsed()
    local n = 1
    while used[string.format("%s-%02d", unitType, n)] do n = n + 1 end
    return string.format("%s-%02d", unitType, n)
end

function Units.position(u)
    local e = isElement(u.vehicle) and u.vehicle or u.members[1]
    if isElement(e) then return getElementPosition(e) end
    return 0, 0, 0
end

---------------------------------------------------------------- client sync

function Units.payload(u)
    local members = {}
    for _, p in ipairs(u.members) do
        members[#members + 1] = { player = p, name = getPlayerName(p), account = accountName(p) }
    end
    local t = u.task and Tasks.get(u.task)
    return {
        unit = {
            id           = u.id,
            callsign     = u.callsign,
            type         = u.type,
            plate        = u.plate,
            status       = u.status,
            responding   = u.responseEntry and true or false,
            responseFrom = u.responseEntry and u.responseEntry.start or 0,
            reachedScene = u.reachedScene,
            handoverEnds = u.handoverEnds or 0,
            startedAt    = u.startedAt,
            members      = members,
            closedTasks  = u.closedTasks,
        },
        task = t and Tasks.public(t) or false,
        serverTime = now(),
    }
end

-- 3D "EMS unit" label above the vehicle (client/unitlabel.lua).
Units.LABEL_KEY = "erm.unit"

function Units.tagVehicle(u)
    if not isElement(u.vehicle) then return end
    local cur = getElementData(u.vehicle, Units.LABEL_KEY)
    if type(cur) == "table" and cur.callsign == u.callsign and cur.status == u.status then return end
    setElementData(u.vehicle, Units.LABEL_KEY, { callsign = u.callsign, type = u.type, status = u.status })
end

function Units.untagVehicle(u)
    if isElement(u.vehicle) then removeElementData(u.vehicle, Units.LABEL_KEY) end
end

function Units.sync(u)
    Units.tagVehicle(u)
    local data = Units.payload(u)
    for _, p in ipairs(u.members) do
        triggerClientEvent(p, "erm:sync", resourceRoot, data)
    end
end

-- alert = true plays the tablet alert sound instead of the ui_core one.
function Units.notify(u, title, text, alert)
    for _, p in ipairs(u.members) do
        triggerClientEvent(p, "erm:notify", resourceRoot, title, text, alert)
    end
end

---------------------------------------------------------------- sign in / out

-- unitNumber: digits chosen on the tablet, "" / nil = automatic.
function Units.signIn(player, unitType, candidates, unitNumber)
    if Units.byPlayer[player] then return false, "You are already signed in." end
    if not isAccountLoggedIn(player) then return false, "You are not logged in." end

    local veh = getPedOccupiedVehicle(player)
    if not veh or not Config.TABLET_VEHICLES[getElementModel(veh)] then
        return false, "You must be inside an ambulance to sign in."
    end
    if not hasValue(Config.UNIT_TYPES, unitType) then return false, "Select a unit type." end

    local callsign
    unitNumber = tostring(unitNumber or ""):gsub("%s", "")
    if unitNumber ~= "" then
        local n = tonumber(unitNumber:match("^%d%d?%d?$"))
        if not n or n < 1 then return false, "Invalid unit number (1-999)." end
        callsign = string.format("%s-%02d", unitType, n)
        if callsignUsed()[callsign] then return false, callsign .. " is already on duty." end
    else
        callsign = freeCallsign(unitType)
    end

    local members = { player }
    local px, py, pz = getElementPosition(player)
    for _, p in ipairs(type(candidates) == "table" and candidates or {}) do
        if isElement(p) and getElementType(p) == "player" and p ~= player and not hasValue(members, p) then
            local x, y, z = getElementPosition(p)
            if Units.byPlayer[p] then
                return false, getPlayerName(p) .. " is already in another unit."
            elseif not isAccountLoggedIn(p) then
                return false, getPlayerName(p) .. " is not logged in."
            elseif getDistanceBetweenPoints3D(px, py, pz, x, y, z) > Config.ADD_MEMBER_RADIUS + 5 then
                return false, getPlayerName(p) .. " is too far away."
            end
            members[#members + 1] = p
        end
    end

    local u = {
        id          = Units.nextId,
        callsign    = callsign,
        type        = unitType,
        plate       = trim(getVehiclePlateText(veh)),
        vehicle     = veh,
        members     = members,
        accounts    = {},
        status      = "available",
        task        = nil,
        reachedScene = false,
        startedAt   = now(),
        closedTasks = {},
    }
    Units.nextId = Units.nextId + 1

    for _, p in ipairs(members) do
        u.accounts[#u.accounts + 1] = accountName(p)
        Units.byPlayer[p] = u
    end
    u.shiftId = DB.startShift(u)
    Units.list[u.id] = u

    Units.sync(u)
    for _, p in ipairs(members) do
        triggerClientEvent(p, "erm:messages", resourceRoot, Chat.forUnit(u.id))
    end
    Units.notify(u, "Shift started", "Signed in as " .. u.callsign .. ".")
    Events.fire("onErmUnitSignIn", u.id)
    return u
end

function Units.signOut(u, reason)
    if not Units.list[u.id] then return end
    if u.task then Tasks.unassign(u.task, u.id, true, "shift ended") end
    if isTimer(u.handoverTimer) then killTimer(u.handoverTimer) end

    DB.endShift(u)
    Units.untagVehicle(u)
    for _, p in ipairs(u.members) do
        Units.byPlayer[p] = nil
        if isElement(p) then triggerClientEvent(p, "erm:signedOut", resourceRoot, reason or "Shift ended.") end
    end
    Units.list[u.id] = nil
    Events.fire("onErmUnitSignOut", u.id, u.callsign, reason or "Shift ended.")
end

function Units.removeMember(player, reason)
    local u = Units.byPlayer[player]
    if not u then return end
    Units.byPlayer[player] = nil
    removeValue(u.members, player)
    if isElement(player) then triggerClientEvent(player, "erm:signedOut", resourceRoot, reason or "You left the unit.") end

    if #u.members == 0 then
        Units.signOut(u, "Unit disbanded.")
    else
        Units.sync(u)
    end
end

---------------------------------------------------------------- status / case flow

local function stopResponse(u)
    if not u.responseEntry then return end
    local t = u.task and Tasks.get(u.task)
    if t then Tasks.stopResponse(t, u.responseEntry) end
    u.responseEntry = nil
end

local function startResponse(u)
    local t = u.task and Tasks.get(u.task)
    if t and not u.responseEntry then
        u.responseEntry = Tasks.startResponse(t, u)
    end
end

-- Called by Tasks when the unit leaves its task (unassign / close / handover).
function Units.releaseTask(u)
    stopResponse(u)
    u.task = nil
    u.reachedScene = false
    local old = u.status
    if u.status ~= "handover" then u.status = "available" end
    Units.sync(u)
    if old ~= u.status then Events.fire("onErmUnitStatusChange", u.id, u.status, old) end
end

function Units.creditTask(u, t)
    for _, c in ipairs(u.closedTasks) do
        if c.id == t.id then return end
    end
    u.closedTasks[#u.closedTasks + 1] = {
        id = t.id, title = t.title, zone = t.zone, priority = t.priority or 0, closedAt = now(),
    }
    DB.updateShift(u)
end

function Units.finishHandover(u)
    if isTimer(u.handoverTimer) then killTimer(u.handoverTimer) end
    u.handoverTimer, u.handoverEnds = nil, nil
    u.status = "available"

    local t = u.task and Tasks.get(u.task)
    local taskId = t and t.id or false
    if t then
        Units.creditTask(u, t)
        Tasks.unassign(t.id, u.id, true, "handover")
        if #t.units == 0 then
            Tasks.close(t.id, "Completed - handover by " .. u.callsign)
        end
    end
    Units.sync(u)
    Events.fire("onErmUnitHandoverComplete", u.id, taskId)
    Events.fire("onErmUnitStatusChange", u.id, "available", "handover")
end

-- (Re)times a running handover. ms > 0: finishes after ms; false / 0: waits
-- for Units.finishHandover (external resource via completeHandover).
function Units.scheduleHandover(u, ms)
    if isTimer(u.handoverTimer) then killTimer(u.handoverTimer) end
    u.handoverTimer = nil
    ms = tonumber(ms)
    if ms and ms > 0 then
        local id = u.id
        u.handoverEnds = now() + math.ceil(ms / 1000)
        u.handoverTimer = setTimer(function()
            local unit = Units.get(id)
            if unit and unit.status == "handover" then Units.finishHandover(unit) end
        end, math.max(50, ms), 1)
    else
        u.handoverEnds = 0
    end
end

-- handoverTime (ms, only for "handover"): nil = Config.HANDOVER_TIME,
-- false / 0 = no automatic finish.
function Units.setStatus(u, status, handoverTime)
    if not Config.STATUS[status] then return false, "Unknown status" end

    if status ~= "handover" and u.status == "handover" then
        if isTimer(u.handoverTimer) then killTimer(u.handoverTimer) end
        u.handoverTimer, u.handoverEnds = nil, nil
    end

    if status == "enroute" then
        startResponse(u)
    elseif status == "onscene" then
        stopResponse(u)
        if u.task then u.reachedScene = true end
    elseif status == "handover" then
        stopResponse(u)
        if u.status ~= "handover" then
            local duration = Config.HANDOVER_TIME
            if handoverTime ~= nil then duration = handoverTime end
            -- a listener may take over the handover (marker, animation, ...)
            if not Events.fire("onErmUnitHandoverStart", u.id, u.task or false, tonumber(duration) or 0) then
                duration = false
            end
            Units.scheduleHandover(u, duration)
        end
    else
        stopResponse(u)
    end

    local old = u.status
    u.status = status
    Units.sync(u)
    local t = u.task and Tasks.get(u.task)
    if t then Tasks.syncUnits(t) end
    if old ~= status then Events.fire("onErmUnitStatusChange", u.id, status, old) end
    return true
end

-- Active Case panel buttons.
function Units.caseAction(u, action)
    if not u.task then return false, "No active case." end
    if action == "start" then
        if u.status == "handover" then return false, "Handover in progress." end
        return Units.setStatus(u, "enroute")
    elseif action == "stop" then
        -- only the log stops; On Scene is set automatically at the scene
        if not u.responseEntry then return false, "Response not started." end
        stopResponse(u)
        Units.sync(u)
        local t = Tasks.get(u.task)
        if t then Tasks.syncUnits(t) end
        return true
    elseif action == "onscene" then
        if not u.responseEntry then return false, "Start the response first." end
        return Units.setStatus(u, "onscene")
    elseif action == "handover" then
        if not u.reachedScene then return false, "Reach the scene first." end
        if u.status == "handover" then return false, "Handover already in progress." end
        return Units.setStatus(u, "handover")
    end
    return false, "Unknown action"
end

---------------------------------------------------------------- public data

function Units.public(u)
    local x, y, z = Units.position(u)
    local members = {}
    for _, p in ipairs(u.members) do members[#members + 1] = getPlayerName(p) end
    local t = u.task and Tasks.get(u.task)
    return {
        id           = u.id,
        callsign     = u.callsign,
        type         = u.type,
        plate        = u.plate,
        status       = u.status,
        statusLabel  = Config.STATUS[u.status].label,
        task         = u.task or 0,
        taskTitle    = t and t.title or "",
        responding   = u.responseEntry and true or false,
        members      = members,
        accounts     = { unpack(u.accounts) },
        x = x, y = y, z = z,
        zone         = zoneLabel(x, y, z),
        startedAt    = u.startedAt,
        handoverEnds = u.handoverEnds or 0,
        closedTasks  = #u.closedTasks,
    }
end

function Units.publicList()
    local out = {}
    for _, u in pairs(Units.list) do out[#out + 1] = Units.public(u) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

---------------------------------------------------------------- automatic On Scene

-- Vehicle or any crew member within Config.ARRIVE_RADIUS of the unit's OWN
-- task. Scenes of tasks assigned to other units never count.
local function atScene(u, t)
    local elements = { unpack(u.members) }
    if isElement(u.vehicle) then elements[#elements + 1] = u.vehicle end
    for _, e in ipairs(elements) do
        if isElement(e) then
            local x, y = getElementPosition(e)
            if getDistanceBetweenPoints2D(x, y, t.x, t.y) <= Config.ARRIVE_RADIUS then return true end
        end
    end
    return false
end

setTimer(function()
    for _, u in pairs(Units.list) do
        local t = u.task and Tasks.get(u.task)
        if t and not u.reachedScene and u.status ~= "handover" and atScene(u, t) then
            Units.setStatus(u, "onscene")
            Units.notify(u, "On scene", string.format("Arrived at case #%d.", t.id))
        end
    end
end, 1000, 0)
