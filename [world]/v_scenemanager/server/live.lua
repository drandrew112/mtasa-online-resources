-- Live scenes: the vehicles + peds of a scene in the world, plus one task per needed agency (server/agencies.lua).
--
-- Spawn: every agency with need 2 gets its task; one with need 1 gets it when a unit of it is free in range (the
-- generator) or always (a manual spawn). A need-1 agency without a task keeps waiting LATE_JOIN seconds: when a unit
-- of it gets free in range meanwhile (and the scene is still open), it gets the task too.
-- A scene lives until every task it has is closed. After that it is removed once no player is near it
-- (CLEANUP_DELAY / CLEANUP_RANGE), at the latest after CLEANUP_FORCE. MAX_LIFETIME closes everything.
-- EMS: the last patient taken away by a medsys transport closes the ERM task; a scene without patients (false call)
-- closes it FALSE_CALL_CLOSE seconds after a unit is On Scene. PD: agencies.pd.close conditions (vehicles towed,
-- suspects handled) close the call automatically once a unit responded to it and the scene is safe.
--
-- Events (on this resource's root):
--   onSceneSpawned (instanceId, sceneName, tasks = { ems = taskId, pd = callId })
--   onSceneRemoved (instanceId, sceneName, reason)

Live = {
    scenes = {},    -- [instanceId] = scene
    byTask = {},    -- [agency] = { [taskId] = instanceId }
}
for _, id in ipairs(VSM.AGENCY_ORDER) do Live.byTask[id] = {} end

local nextId = 1

addEvent("onSceneSpawned", false)
addEvent("onSceneRemoved", false)

function Live.isActive(name)
    for _, scene in pairs(Live.scenes) do
        if scene.name == name then return true end
    end
    return false
end

function Live.count()
    local n = 0
    for _ in pairs(Live.scenes) do n = n + 1 end
    return n
end

function Live.byAgencyTask(agency, taskId)
    local id = Live.byTask[agency] and Live.byTask[agency][tonumber(taskId) or taskId]
    return id and Live.scenes[id] or nil
end

-- open scene tasks of an agency that no unit took yet
function Live.pendingCount(agency)
    local a = Agencies.get(agency)
    if not a or not a.running() then return 0 end
    local n = 0
    for _, scene in pairs(Live.scenes) do
        local t = scene.tasks[agency]
        if t and not t.closed and not scene.closedAt and a.isPending(t.id) then n = n + 1 end
    end
    return n
end

function Live.public(scene)
    local tasks = {}
    for id, t in pairs(scene.tasks) do tasks[id] = { id = t.id, closed = t.closed == true } end
    local late = {}
    for id in pairs(scene.late) do late[#late + 1] = id end
    return {
        id = scene.id, name = scene.name, taskId = scene.tasks.ems and scene.tasks.ems.id or false, tasks = tasks,
        late = late, source = scene.source,
        center = { scene.center[1], scene.center[2], scene.center[3] },
        createdAt = scene.createdAt, closed = scene.closedAt ~= nil,
        peds = #scene.peds, vehicles = #scene.vehicles, patients = scene.patients,
        safety = scene.safety and scene.safety.state or false,
    }
end

-- Open scene (some task not closed yet) within radius of a point -> scene | nil
function Live.sceneAt(x, y, z, radius, includeClosed)
    for _, scene in pairs(Live.scenes) do
        if includeClosed or not scene.closedAt then
            local points = { scene.center }
            for _, list in ipairs({ scene.peds, scene.vehicles }) do
                for _, element in ipairs(list) do
                    if isElement(element) then points[#points + 1] = { getElementPosition(element) } end
                end
            end
            for _, p in ipairs(points) do
                if getDistanceBetweenPoints3D(x, y, z, p[1], p[2], p[3]) <= radius then return scene end
            end
        end
    end
end

---------------------------------------------------------------- tasks

-- Peds that get injuries / a medical state (the rest are bystanders)
local function countPatients(data)
    local count = 0
    for _, entry in ipairs(data.peds) do
        if #(entry.injuries or {}) > 0 or next(type(entry.state) == "table" and entry.state or {}) then
            count = count + 1
        end
    end
    return count
end

-- creates the task of one agency and links it with the scene's other tasks -> taskId | false, error
function Live.createTask(scene, agency)
    local a = Agencies.get(agency)
    local block = Storage.agency(scene.data, agency)
    if not a.running() then return false, agency .. " is not running" end
    local links = {}
    for id, t in pairs(scene.tasks) do links[id] = t.id end
    local taskId, err = a.create(scene, block, links)
    if not taskId then return false, err end
    scene.tasks[agency] = { id = taskId }
    Live.byTask[agency][taskId] = scene.id
    scene.late[agency] = nil
    for id, t in pairs(scene.tasks) do
        if id ~= agency and not t.closed then Agencies.get(id).link(t.id, agency, taskId) end
    end
    return taskId
end

local function allClosed(scene)
    for _, t in pairs(scene.tasks) do
        if not t.closed then return false end
    end
    return true
end

local function closeScene(scene)
    if scene.closedAt then return end
    scene.closedAt = getTickCount()
    scene.late = {}
    Safety.stop(scene)
end

-- adapters: a task of a live scene closed
function Live.agencyClosed(agency, taskId)
    local scene = Live.byAgencyTask(agency, taskId)
    local t = scene and scene.tasks[agency]
    if not t or t.closed then return end
    t.closed = true
    if allClosed(scene) then closeScene(scene) end
end

-- adapters: a unit took a task of a live scene (accounts of the unit: scene variety per player)
function Live.agencyTaken(agency, taskId, accounts)
    local scene = Live.byAgencyTask(agency, taskId)
    if not scene then return end
    if agency == "ems" then scene.emsAssignedAt = scene.emsAssignedAt or vsmNow() end
    Variety.recordAccounts(scene, accounts)
end

---------------------------------------------------------------- spawn

local function spawnPed(scene, entry, data, vehiclesById)
    local role = vsmRoleById(entry.role)
    local ped = role and role.ai and not entry.vehicle and Npc.create(scene, entry, data)
    if not ped then
        ped = Builder.createPed(entry, data.interior, data.dimension, vehiclesById)
        if ped then Builder.applyPedPose(ped, entry) end
    end
    return ped
end

-- spawn(name [, source [, opts]]) -> instanceId, warning | false, error
-- opts.auto: generator spawn (need-1 agencies only with a free unit in range, the rest waits for a late join)
function Live.spawn(name, source, opts)
    opts = opts or {}
    if Live.isActive(name) then return false, L.msg("v_scenemanager.err.already_active", { name = tostring(name) }) end
    local data, err = Storage.load(name)
    if not data then return false, err end

    local id = nextId
    nextId = nextId + 1
    local scene = {
        id = id, name = name, source = source or "script", data = data,
        center = data.center, interior = data.interior, dimension = data.dimension, createdAt = getTickCount(),
        vehicles = {}, peds = {}, pedEntries = {}, vehicleEntries = {}, patients = countPatients(data),
        tasks = {}, late = {},
    }
    local needs = {}
    for _, a in ipairs(VSM.AGENCY_ORDER) do needs[a] = Storage.agency(data, a).need end
    -- only EMS 2 + PD 2 can start not safe (validation reports the rest)
    local safe = true
    if needs.ems == 2 and needs.pd == 2 and data.safe == false then safe = false end
    Safety.start(scene, safe)

    local vehiclesById = {}
    for _, entry in ipairs(data.vehicles) do
        local vehicle = Builder.createVehicle(entry, data.interior, data.dimension)
        if vehicle then
            vehiclesById[entry.id] = vehicle
            scene.vehicles[#scene.vehicles + 1] = vehicle
            scene.vehicleEntries[vehicle] = entry
            setElementData(vehicle, VSM.DATA_SCENE, id, false)
        else
            vsmLog("scene '%s': could not create vehicle %s (model %s)", name, entry.id, tostring(entry.model))
        end
    end

    local pedsById = {}
    for _, entry in ipairs(data.peds) do
        local ped = spawnPed(scene, entry, data, vehiclesById)
        if ped then
            pedsById[entry.id] = ped
            scene.peds[#scene.peds + 1] = ped
            scene.pedEntries[ped] = entry
            setElementData(ped, VSM.DATA_SCENE, id, false)
            setElementData(ped, VSM.DATA_NAME, entry.record and entry.record.name or vsmRandomName(getElementModel(ped)))
            local rolled = Npc.roll(entry)
            Npc.applyRecord(scene, ped, entry, rolled)
            -- let the ped reach the clients first, so medsys' animations sync
            setTimer(function()
                if isElement(ped) then Builder.applyMedical(ped, entry, rolled) end
            end, VSM.MEDSYS_DELAY, 1)
        else
            vsmLog("scene '%s': could not create ped %s", name, entry.id)
        end
    end
    for vehicle, entry in pairs(scene.vehicleEntries) do Npc.applyVehicleRecord(scene, vehicle, entry, pedsById) end

    Live.scenes[id] = scene
    Npc.setup(scene)

    local warnings = {}
    for _, agency in ipairs(VSM.AGENCY_ORDER) do
        local block = Storage.agency(data, agency)
        if block.need > 0 then
            local send = true
            if opts.auto and block.need == 1 then
                send = Agencies.nearestFree(agency, data.center, data.interior) ~= nil
            end
            local taskId, terr
            if send then taskId, terr = Live.createTask(scene, agency) end
            if not taskId then
                if terr then warnings[#warnings + 1] = agency .. ": " .. tostring(terr) end
                if block.need == 1 and block.lateJoin and (VSM.AGENCIES[agency].LATE_JOIN or 0) > 0 then
                    scene.late[agency] = getTickCount() + VSM.AGENCIES[agency].LATE_JOIN * 1000
                end
            end
        end
    end
    Safety.announce(scene)
    if next(scene.tasks) == nil and next(scene.late) == nil then closeScene(scene) end

    local tasks = {}
    for a, t in pairs(scene.tasks) do tasks[a] = t.id end
    vsmLog("scene '%s' spawned as #%d (%s), tasks: ems %s, pd %s%s", name, id, scene.source,
        tostring(tasks.ems or "-"), tostring(tasks.pd or "-"), scene.safety and ", NOT SAFE" or "")
    triggerEvent("onSceneSpawned", resourceRoot, id, name, tasks)
    return id, #warnings > 0 and table.concat(warnings, "; ") or nil
end

---------------------------------------------------------------- remove

-- remove(instanceId [, reason]) -> bool. Closes the open tasks too.
function Live.remove(id, reason)
    local scene = Live.scenes[id]
    if not scene then return false end
    Live.scenes[id] = nil
    reason = reason or "removed"

    for agency, t in pairs(scene.tasks) do
        Live.byTask[agency][t.id] = nil
        if not t.closed then Agencies.get(agency).close(t.id, "Scene removed (" .. reason .. ")") end
    end
    Safety.stop(scene)
    Npc.cleanup(scene)

    for _, ped in ipairs(scene.peds) do Npc.destroy(ped) end
    for _, vehicle in ipairs(scene.vehicles) do
        if isElement(vehicle) then destroyElement(vehicle) end
    end

    vsmLog("scene '%s' #%d removed (%s)", scene.name, id, reason)
    triggerEvent("onSceneRemoved", resourceRoot, id, scene.name, reason)
    return true
end

---------------------------------------------------------------- EMS specifics

local function emsTask(scene)
    local t = scene.tasks.ems
    return t and not t.closed and t.id or nil
end

-- False call: a unit of a scene without patients arrived, the task closes a bit later
addEventHandler("onErmUnitStatusChange", root, function(unitId, status)
    if status ~= "onscene" then return end
    local unit = Agencies.call(VSM.ERM, "getUnitData", unitId)
    local scene = unit and unit.task ~= 0 and Live.byAgencyTask("ems", unit.task)
    if not scene or scene.patients > 0 or scene.closedAt or scene.falseCallTimer or not emsTask(scene) then return end
    local id, taskId = scene.id, emsTask(scene)
    scene.falseCallTimer = setTimer(function()
        if Live.scenes[id] then Agencies.get("ems").close(taskId, "False call - no patient found on scene") end
    end, VSM.FALSE_CALL_CLOSE * 1000, 1)
end)

-- medsys "Request transport": source = the ped, fired right before it is destroyed
local function onPatientTransported()
    local id = getElementData(source, VSM.DATA_SCENE)
    local scene = id and Live.scenes[id]
    if not scene or scene.closedAt or not emsTask(scene) then return end
    for _, ped in ipairs(scene.peds) do
        if ped ~= source and isElement(ped) then return end -- a patient is still left
    end
    Agencies.get("ems").close(emsTask(scene), "Completed - patients transported")
end

-- (re)attached whenever medsys (re)starts and registers the event again
local function hookMedsys()
    if not vsmResourceRunning(VSM.MEDSYS) then return end
    for _, fn in ipairs(getEventHandlers("onMedicalPatientTransported", root) or {}) do
        if fn == onPatientTransported then return end
    end
    addEventHandler("onMedicalPatientTransported", root, onPatientTransported)
end

addEventHandler("onResourceStart", root, function(res)
    if res == resource or getResourceName(res) == VSM.MEDSYS then hookMedsys() end
end)

---------------------------------------------------------------- PD automatic close

local function handled(ped)
    return not isElement(ped) or Npc.isCuffed(ped) or Npc.isDown(ped)
end

local function pdConditionsMet(scene)
    local close = Storage.agency(scene.data, "pd").close
    if not next(close) then return false end
    if close.towed then
        for vehicle, entry in pairs(scene.vehicleEntries) do
            if entry.tow and isElement(vehicle) then return false end
        end
    end
    if close.suspects then
        for ped, entry in pairs(scene.pedEntries) do
            if (entry.role == "suspect" or entry.role == "hostile" or entry.role == "fighter") and not handled(ped) then return false end
        end
    end
    return true
end

---------------------------------------------------------------- lifecycle

local function anyPlayerNear(scene)
    local points = { scene.center }
    for _, list in ipairs({ scene.peds, scene.vehicles }) do
        for _, element in ipairs(list) do
            if isElement(element) then points[#points + 1] = { getElementPosition(element) } end
        end
    end
    for _, player in ipairs(getElementsByType("player")) do
        local px, py, pz = getElementPosition(player)
        for _, p in ipairs(points) do
            if getDistanceBetweenPoints3D(px, py, pz, p[1], p[2], p[3]) < VSM.CLEANUP_RANGE then
                return true
            end
        end
    end
    return false
end

local function lateJoin(scene, now)
    for agency, deadline in pairs(scene.late) do
        if now >= deadline then
            scene.late[agency] = nil
        elseif Agencies.nearestFree(agency, scene.center, scene.interior) then
            local taskId = Live.createTask(scene, agency)
            if taskId then
                vsmLog("scene '%s' #%d: %s joined late (task %s)", scene.name, scene.id, agency, tostring(taskId))
                Safety.trackers(scene)
            end
        end
    end
end

local function tick()
    local now = getTickCount()
    for id, scene in pairs(Live.scenes) do
        if scene.closedAt then
            local age = (now - scene.closedAt) / 1000
            if age >= VSM.CLEANUP_FORCE then
                Live.remove(id, "cleanup timeout")
            elseif age >= VSM.CLEANUP_DELAY and not anyPlayerNear(scene) then
                Live.remove(id, "tasks closed")
            end
        elseif (now - scene.createdAt) / 1000 >= VSM.MAX_LIFETIME then
            for agency, t in pairs(scene.tasks) do
                if not t.closed then Agencies.get(agency).close(t.id, "Scene expired") end
            end
            closeScene(scene)
        else
            -- tasks that disappeared (their resource restarted) count as closed
            for agency, t in pairs(scene.tasks) do
                if not t.closed and Agencies.get(agency).running() and not Agencies.get(agency).isOpen(t.id) then
                    t.closed = true
                end
            end
            local pd = scene.tasks.pd
            if pd and not pd.closed and not Safety.isUnsafe(scene) and Agencies.get("pd").responded(pd.id) and pdConditionsMet(scene) then
                Agencies.get("pd").close(pd.id, "Completed - scene cleared")
            end
            lateJoin(scene, now)
            if next(scene.tasks) and allClosed(scene) then closeScene(scene) end
            if not next(scene.tasks) and not next(scene.late) then closeScene(scene) end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(tick, VSM.CHECK_INTERVAL, 0)
end)

-- an agency resource stopped: its tasks are gone, the scenes clean up when nothing else is open
addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    local agency = name == VSM.ERM and "ems" or name == VSM.POLICE and "pd" or nil
    if not agency then return end
    for _, scene in pairs(Live.scenes) do
        local t = scene.tasks[agency]
        if t and not t.closed then
            t.closed = true
            if allClosed(scene) then closeScene(scene) end
        end
    end
end)

-- Our own stop: close the open tasks (the elements go with the resource; AI peds are destroyed here)
addEventHandler("onResourceStop", resourceRoot, function()
    for _, scene in pairs(Live.scenes) do
        for agency, t in pairs(scene.tasks) do
            if not t.closed then pcall(function() Agencies.get(agency).close(t.id, "Scene manager stopped") end) end
        end
        Npc.cleanup(scene)
        for _, ped in ipairs(scene.peds) do pcall(Npc.destroy, ped) end
    end
end)
