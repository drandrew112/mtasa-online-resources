-- Transport to hospital: when a unit that reached its scene drives away from it
-- (Config.HOSPITAL_DEPART_RADIUS), every crew member gets a v_radar objective to
-- the nearest hospital (med_hospitals). The objective stays until the unit gets
-- the Handover status (med_hospitals ambulance bay), then it is removed for good
-- for that case. Nothing happens while med_hospitals is stopped.

local routes = {}  -- [unitId] = { task = taskId, hospital = hospitalId, players = { [player] = true } }
local done   = {}  -- [unitId] = taskId whose handover already started (no new route for it)

local function hospitalsRunning()
    local res = getResourceFromName("med_hospitals")
    return res and getResourceState(res) == "running"
end

local function setObjective(player, hospitalId)
    exports.med_hospitals:setObjectiveToHospital(player, hospitalId, nil, true)
end

local function removeObjective(player)
    if isElement(player) and hospitalsRunning() then
        exports.med_hospitals:removeHospitalObjective(player)
    end
end

local function clearRoute(unitId)
    local r = routes[unitId]
    if not r then return end
    routes[unitId] = nil
    for p in pairs(r.players) do removeObjective(p) end
end

-- The unit's vehicle (on foot: its first member) is out of the scene radius.
local function departed(u, t)
    local e = isElement(u.vehicle) and u.vehicle or u.members[1]
    if not isElement(e) then return false end
    local x, y = getElementPosition(e)
    return getDistanceBetweenPoints2D(x, y, t.x, t.y) > Config.HOSPITAL_DEPART_RADIUS, e
end

local function startRoute(u, t, e)
    -- same interior / dimension first, then any hospital
    local hospitalId, name = exports.med_hospitals:getNearestHospital(e)
    if not hospitalId then
        local x, y, z = getElementPosition(e)
        hospitalId, name = exports.med_hospitals:getNearestHospital(x, y, z)
    end
    if not hospitalId then return end

    local r = { task = t.id, hospital = hospitalId, players = {} }
    routes[u.id] = r
    for _, p in ipairs(u.members) do
        setObjective(p, hospitalId)
        r.players[p] = true
    end
    Units.notify(u, "Transport", "Nearest hospital: " .. tostring(name) .. ".")
end

-- Members who left the unit lose the objective, missing ones get it.
local function reconcile(u, r)
    local current = {}
    for _, p in ipairs(u.members) do
        current[p] = true
        if not r.players[p] then
            setObjective(p, r.hospital)
            r.players[p] = true
        end
    end
    for p in pairs(r.players) do
        if not current[p] then
            r.players[p] = nil
            removeObjective(p)
        end
    end
end

setTimer(function()
    for unitId in pairs(routes) do
        if not Units.get(unitId) then clearRoute(unitId) end
    end
    for unitId in pairs(done) do
        if not Units.get(unitId) then done[unitId] = nil end
    end
    if not hospitalsRunning() then
        routes = {}
        return
    end

    for _, u in pairs(Units.list) do
        local t = u.task and Tasks.get(u.task)
        local r = routes[u.id]
        if r and (not t or r.task ~= t.id) then
            clearRoute(u.id)
            r = nil
        end
        if done[u.id] and (not t or done[u.id] ~= t.id) then done[u.id] = nil end

        if t and u.reachedScene and u.status ~= "handover" and done[u.id] ~= t.id then
            if r then
                reconcile(u, r)
            else
                local away, e = departed(u, t)
                if away then startRoute(u, t, e) end
            end
        end
    end
end, 1000, 0)

-- Handover status (hospital bay): objective off, no new one for this case.
addEventHandler("onErmUnitStatusChange", resourceRoot, function(unitId, status)
    if status ~= "handover" then return end
    local u = Units.get(unitId)
    done[unitId] = u and u.task or nil
    clearRoute(unitId)
end)

-- med_hospitals / v_radar (re)started: their objectives are gone, set them again.
addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if name == "med_hospitals" or name == "v_radar" then routes = {} end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for unitId in pairs(routes) do clearRoute(unitId) end
end)
