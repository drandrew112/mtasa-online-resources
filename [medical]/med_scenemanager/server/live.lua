-- Live scenes: the vehicles + injured peds of a scene in the world, plus its ERM task.
--
-- A scene lives until its ERM task closes. After that it is removed once no player
-- is near it (CLEANUP_DELAY / CLEANUP_RANGE), at the latest after CLEANUP_FORCE.
-- A scene whose task never closes is closed after MAX_LIFETIME.
-- When the last patient of a scene is taken away by a medsys transport ("Request
-- transport") and no other scene ped is left (none on a stretcher / in an ambulance),
-- the task is closed: there is nobody left to hand over at a hospital.
-- A scene without patients (a false call: nobody there, or only people who are fine) closes its
-- task MSM.FALSE_CALL_CLOSE seconds after a unit reports On Scene.
--
-- Events (on this resource's root):
--   onMedSceneSpawned (instanceId, sceneName, taskId | false)
--   onMedSceneRemoved (instanceId, sceneName, reason)

Live = {
    scenes = {},    -- [instanceId] = scene
    byTask = {},    -- [taskId] = instanceId
}

local nextId = 1

addEvent("onMedSceneSpawned", false)
addEvent("onMedSceneRemoved", false)

local function ermRunning()
    return msmResourceRunning(MSM.ERM)
end

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

-- Scenes of this resource whose task has no unit yet
function Live.pendingCount()
    if not ermRunning() then return 0 end
    local n = 0
    for _, scene in pairs(Live.scenes) do
        if scene.taskId and not scene.closedAt then
            local task = exports[MSM.ERM]:getTask(scene.taskId)
            if task and task.status ~= "closed" and #(task.units or {}) == 0 then n = n + 1 end
        end
    end
    return n
end

function Live.public(scene)
    return {
        id = scene.id, name = scene.name, taskId = scene.taskId or false, source = scene.source,
        center = { scene.center[1], scene.center[2], scene.center[3] },
        createdAt = scene.createdAt, closed = scene.closedAt ~= nil,
        peds = #scene.peds, vehicles = #scene.vehicles,
    }
end

-- Open scene (task not closed yet) within radius of a point -> scene | nil
function Live.sceneAt(x, y, z, radius)
    for _, scene in pairs(Live.scenes) do
        if not scene.closedAt then
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

---------------------------------------------------------------- spawn

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

local function createTask(scene, data)
    if not ermRunning() then return false, "med_erm is not running" end
    local c, erm = data.center, data.erm
    local meta = {
        scene = scene.name,
        sceneInstance = scene.id,
        priority = erm.priority,
        patients = scene.patients,
    }
    local id, err = exports[MSM.ERM]:createTask(erm.title, erm.description, c[1], c[2], c[3], erm.caller, nil, meta)
    return id, err
end

-- spawn(name [, source]) -> instanceId | false, error
function Live.spawn(name, source)
    if Live.isActive(name) then return false, "Scene '" .. tostring(name) .. "' is already active" end
    local data, err = Storage.load(name)
    if not data then return false, err end

    local id = nextId
    nextId = nextId + 1
    local scene = {
        id = id, name = name, source = source or "script",
        center = data.center, createdAt = getTickCount(),
        vehicles = {}, peds = {}, patients = countPatients(data),
    }

    local vehiclesById = {}
    for _, entry in ipairs(data.vehicles) do
        local vehicle = Builder.createVehicle(entry, data.interior, data.dimension)
        if vehicle then
            vehiclesById[entry.id] = vehicle
            scene.vehicles[#scene.vehicles + 1] = vehicle
            setElementData(vehicle, "msm.scene", id, false)
        else
            msmLog("scene '%s': could not create vehicle %s (model %s)", name, entry.id, tostring(entry.model))
        end
    end

    for _, entry in ipairs(data.peds) do
        local ped = Builder.createPed(entry, data.interior, data.dimension, vehiclesById)
        if ped then
            scene.peds[#scene.peds + 1] = ped
            setElementData(ped, "msm.scene", id, false)
            setElementData(ped, MSM.DATA_NAME, msmRandomName(getElementModel(ped)))
            Builder.applyPedPose(ped, entry)
            -- let the ped reach the clients first, so medsys' animations sync
            setTimer(function()
                if isElement(ped) then Builder.applyMedical(ped, entry) end
            end, MSM.MEDSYS_DELAY, 1)
        else
            msmLog("scene '%s': could not create ped %s", name, entry.id)
        end
    end

    Live.scenes[id] = scene
    local taskId, terr = createTask(scene, data)
    if taskId then
        scene.taskId = taskId
        Live.byTask[taskId] = id
    else
        msmLog("scene '%s' #%d spawned without an ERM task: %s", name, id, tostring(terr))
    end

    msmLog("scene '%s' spawned as #%d (%s), task %s", name, id, scene.source, tostring(taskId or "-"))
    triggerEvent("onMedSceneSpawned", resourceRoot, id, name, taskId or false)
    return id, taskId and nil or terr
end

---------------------------------------------------------------- remove

-- remove(instanceId [, reason]) -> bool. Closes the ERM task too when it is still open.
function Live.remove(id, reason)
    local scene = Live.scenes[id]
    if not scene then return false end
    Live.scenes[id] = nil
    reason = reason or "removed"

    if scene.taskId then
        Live.byTask[scene.taskId] = nil
        if not scene.closedAt and ermRunning() then
            local task = exports[MSM.ERM]:getTask(scene.taskId)
            if task and task.status ~= "closed" then
                exports[MSM.ERM]:closeTask(scene.taskId, "Scene removed (" .. reason .. ")")
            end
        end
    end

    for _, list in ipairs({ scene.peds, scene.vehicles }) do
        for _, element in ipairs(list) do
            if isElement(element) then destroyElement(element) end
        end
    end

    msmLog("scene '%s' #%d removed (%s)", scene.name, id, reason)
    triggerEvent("onMedSceneRemoved", resourceRoot, id, scene.name, reason)
    return true
end

---------------------------------------------------------------- lifecycle

addEventHandler("onErmTaskClosed", root, function(taskId)
    local id = Live.byTask[taskId]
    local scene = id and Live.scenes[id]
    if scene and not scene.closedAt then
        scene.closedAt = getTickCount()
    end
end)

-- False call: a unit of a scene without patients arrived, the task closes a bit later
addEventHandler("onErmUnitStatusChange", root, function(unitId, status)
    if status ~= "onscene" or not ermRunning() then return end
    local unit = exports[MSM.ERM]:getUnitData(unitId)
    local id = unit and unit.task ~= 0 and Live.byTask[unit.task]
    local scene = id and Live.scenes[id]
    if not scene or scene.patients > 0 or scene.closedAt or scene.falseCallTimer then return end
    local taskId = scene.taskId
    scene.falseCallTimer = setTimer(function()
        if not Live.scenes[id] or scene.closedAt or not ermRunning() then return end
        local task = exports[MSM.ERM]:getTask(taskId)
        if task and task.status ~= "closed" then
            exports[MSM.ERM]:closeTask(taskId, "False call - no patient found on scene")
        end
    end, MSM.FALSE_CALL_CLOSE * 1000, 1)
end)

-- medsys "Request transport": source = the ped, fired right before it is destroyed
local function onPatientTransported()
    local id = getElementData(source, "msm.scene")
    local scene = id and Live.scenes[id]
    if not scene or scene.closedAt or not scene.taskId or not ermRunning() then return end
    for _, ped in ipairs(scene.peds) do
        if ped ~= source and isElement(ped) then return end -- a patient is still left
    end
    local task = exports[MSM.ERM]:getTask(scene.taskId)
    if task and task.status ~= "closed" then
        exports[MSM.ERM]:closeTask(scene.taskId, "Completed - patients transported")
    end
end

-- (re)attached whenever medsys (re)starts and registers the event again
local function hookMedsys()
    if not msmResourceRunning(MSM.MEDSYS) then return end
    for _, fn in ipairs(getEventHandlers("onMedicalPatientTransported", root) or {}) do
        if fn == onPatientTransported then return end
    end
    addEventHandler("onMedicalPatientTransported", root, onPatientTransported)
end

addEventHandler("onResourceStart", root, function(res)
    if res == resource or getResourceName(res) == MSM.MEDSYS then hookMedsys() end
end)

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
            if getDistanceBetweenPoints3D(px, py, pz, p[1], p[2], p[3]) < MSM.CLEANUP_RANGE then
                return true
            end
        end
    end
    return false
end

local function tick()
    local now = getTickCount()
    for id, scene in pairs(Live.scenes) do
        if scene.closedAt then
            local age = (now - scene.closedAt) / 1000
            if age >= MSM.CLEANUP_FORCE then
                Live.remove(id, "cleanup timeout")
            elseif age >= MSM.CLEANUP_DELAY and not anyPlayerNear(scene) then
                Live.remove(id, "task closed")
            end
        elseif (now - scene.createdAt) / 1000 >= MSM.MAX_LIFETIME then
            if scene.taskId and ermRunning() then
                exports[MSM.ERM]:closeTask(scene.taskId, "Scene expired")
            end
            scene.closedAt = now
        elseif scene.taskId and ermRunning() and not exports[MSM.ERM]:getTask(scene.taskId) then
            scene.closedAt = now -- the task disappeared (e.g. med_erm restarted)
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(tick, MSM.CHECK_INTERVAL, 0)
end)

-- med_erm restarted: the old tasks are gone, the scenes will be cleaned up
addEventHandler("onResourceStop", root, function(res)
    if getResourceName(res) ~= MSM.ERM then return end
    for _, scene in pairs(Live.scenes) do
        if scene.taskId and not scene.closedAt then scene.closedAt = getTickCount() end
    end
end)

-- Our own stop: close the open tasks (the elements go with the resource)
addEventHandler("onResourceStop", resourceRoot, function()
    if not ermRunning() then return end
    for _, scene in pairs(Live.scenes) do
        if scene.taskId and not scene.closedAt then
            pcall(function() exports[MSM.ERM]:closeTask(scene.taskId, "Scene manager stopped") end)
        end
    end
end)
