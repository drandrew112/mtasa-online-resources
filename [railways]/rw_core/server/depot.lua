-- Depots: railway staff apply for services here (the train is created for the trip and the
-- service starts at once), couple / uncouple coaches and send trains to the shed
-- (client/depot.lua shows the ui_inac menu). Free train creation is for admins only
-- (RW.SPAWN_ADMIN_LEVEL). Every action is re-checked on the server: role, the player standing
-- in the depot marker, the trip's availability (rw_timetable), a free spawn point, and (for
-- assembly) the train standing at one of that depot's spawn points.

local depots = {}

local function notify(player, text, ok)
    triggerClientEvent(player, "rw:notify", resourceRoot, text, ok and true or false)
end

local function depotOf(player)
    for _, d in ipairs(depots) do
        if isElement(d.marker) and isElementWithinMarker(player, d.marker) then return d end
    end
end

local function canSpawnFree(player)
    return getAdminLevel(player) >= RW.SPAWN_ADMIN_LEVEL
end

-- rw_timetable is optional (no include): nil when it is not running
local function tt(fn, ...)
    local r = getResourceFromName("rw_timetable")
    if not r or getResourceState(r) ~= "running" then return nil end
    local ok, a, b = pcall(function(...) return exports.rw_timetable[fn](exports.rw_timetable, ...) end, ...)
    if ok then return a, b end
    return nil
end

local SPAWN_CLEAR = 130     -- m along the track: a consist this close to a spawn point blocks it

local function spawnOccupied(spawnId)
    local s = getSpawnPoint(spawnId)
    if not s then return true end
    local tp = Track.project(s.track, s.x, s.y, 60)
    if not tp then return false end
    for _, info in ipairs(getConsists()) do
        if info.track == s.track and math.abs(Track.delta(s.track, tp, info.tp)) < SPAWN_CLEAR then return true end
    end
    return false
end

local function depotHasSpawn(d, id)
    for _, s in ipairs(d.def.spawns) do if s == id then return true end end
    return false
end

-- consists standing near the depot's spawn points (for assembly / removal)
local function nearbyConsists(d)
    local out = {}
    for _, info in ipairs(getConsists()) do
        for _, sid in ipairs(d.def.spawns) do
            local s = getSpawnPoint(sid)
            if s and info.track == s.track then
                local tp = Track.project(s.track, s.x, s.y, 60)
                if tp and math.abs(Track.delta(s.track, tp, info.tp)) < 250 then
                    out[#out + 1] = info
                    break
                end
            end
        end
    end
    return out
end

local function describe(info)
    local driver = info.driver and getPlayerName(info.driver):gsub("#%x%x%x%x%x%x", "") or "no driver"
    return ("%s + %d car(s), %s"):format(info.label, info.carriages, driver)
end

-- the menu data the client turns into a ui_inac temp menu
local function menuData(player, d)
    local data = { depot = d.def.name, spawns = {}, presets = {}, consists = {}, carriageTypes = {}, services = {},
        admin = canSpawnFree(player) }
    for _, e in ipairs(tt("getDepotServices", d.def.spawns) or {}) do
        data.services[#data.services + 1] = { tripId = e.tripId, number = e.number, name = e.name, toName = e.toName,
            fromName = e.fromName, dep = e.dep, ok = e.ok, reason = e.reason }
    end
    if data.admin then
        for _, sid in ipairs(d.def.spawns) do
            local s = getSpawnPoint(sid)
            if s then data.spawns[#data.spawns + 1] = { id = s.id, name = s.name } end
        end
        for _, p in ipairs(RW.PRESETS) do data.presets[#data.presets + 1] = { id = p.id, name = p.name } end
    end
    for id, def in pairs(RW.VEHICLES) do
        if def.kind ~= "loco" then data.carriageTypes[#data.carriageTypes + 1] = { id = id, name = def.name } end
    end
    for _, info in ipairs(nearbyConsists(d)) do
        data.consists[#data.consists + 1] = { id = info.id, label = describe(info), number = info.label, carriages = info.carriages }
    end
    return data
end

addEvent("rw:depot:open", true)
addEventHandler("rw:depot:open", resourceRoot, function()
    local player = client
    local d = depotOf(player)
    if not d then return end
    if not hasRailwayAccess(player) then
        notify(player, "Only railway staff can use the depot.")
        return
    end
    triggerClientEvent(player, "rw:depot:menu", resourceRoot, menuData(player, d))
end)

addEvent("rw:depot:action", true)
addEventHandler("rw:depot:action", resourceRoot, function(action, a, b)
    local player = client
    local d = depotOf(player)
    if not d or not hasRailwayAccess(player) then return end

    if action == "apply" then
        -- a = trip id. The client only names the trip: availability, window, the depot's spawn
        -- point and the train's fitness are all decided here.
        a = tostring(a)
        if tt("getDepotServices", {}) == nil then notify(player, "The timetable is not available.") return end
        local ok, e = tt("checkDepotService", a, d.def.spawns)
        if not ok then notify(player, "Cannot apply: " .. tostring(e or "not available now")) return end
        if not depotHasSpawn(d, e.spawn) then return end
        if getConsistByDriver(player) then notify(player, "Leave your train first.") return end
        if spawnOccupied(e.spawn) then
            notify(player, ("Cannot apply: %s is occupied."):format(getSpawnPoint(e.spawn).name))
            return
        end
        local id, err = spawnConsist({ preset = e.preset, spawn = e.spawn, owner = player })
        if not id then notify(player, "Cannot apply: " .. tostring(err)) return end
        local started, why = tt("startAppliedService", id, a, player)
        if not started then
            destroyConsist(id, "service could not be started")
            notify(player, "Cannot apply: " .. tostring(why or "not available now"))
            return
        end
        notify(player, ("Service %s to %s: your train is ready at %s. Board it and depart on time."):format(
            e.number, e.toName, getSpawnPoint(e.spawn).name), true)
        return
    end

    if action == "spawn" then
        if not canSpawnFree(player) then return end
        if not depotHasSpawn(d, a) then return end
        if spawnOccupied(a) then notify(player, ("Cannot spawn: %s is occupied."):format(getSpawnPoint(a).name)) return end
        local id, err = spawnConsist({ preset = tostring(b), spawn = a, owner = player })
        if id then notify(player, ("%s is ready at %s."):format(getConsist(id).label, getSpawnPoint(a).name), true)
        else notify(player, "Cannot spawn: " .. tostring(err)) end
        return
    end

    -- the rest works on a train standing at this depot
    local ok = false
    for _, info in ipairs(nearbyConsists(d)) do if info.id == a then ok = true break end end
    if not ok then notify(player, "That train is not at this depot any more.") return end

    local done, err
    if action == "add" then done, err = addCarriage(a, tostring(b))
    elseif action == "remove" then done, err = removeCarriage(a)
    elseif action == "despawn" then
        local info = getConsist(a)
        if tt("getConsistService", a) then err = "it runs a service"
        elseif info and info.driver and info.driver ~= player then err = "somebody is driving it"
        else done = destroyConsist(a, "sent to the shed by " .. getPlayerName(player):gsub("#%x%x%x%x%x%x", "")) end
    end
    if done then notify(player, "Done.", true) else notify(player, "Cannot do it: " .. tostring(err)) end
end)

-- /rwdespawn [running number | id]  (admins): removes a train, or every train without one
addCommandHandler("rwdespawn", function(player, _, id)
    if not isRailwayAdmin(player) then return end
    if id then
        local n = tonumber(id)
        for cid, c in pairs(Consists) do
            if c.number == n then n = cid break end
        end
        outputChatBox(destroyConsist(n, "admin /rwdespawn") and "[SLR] Szerelvény törölve." or "[SLR] Nincs ilyen szerelvény.", player)
    else
        local n = 0
        for cid in pairs(Consists) do destroyConsist(cid, "admin /rwdespawn") n = n + 1 end
        outputChatBox("[SLR] " .. n .. " szerelvény törölve.", player)
    end
end)

-- depot markers and blips only for the players on duty in RW.DEPOT_WORK (work_core)
local function applyDepotVisibility()
    if not RW.DEPOT_WORK then return end
    local res = getResourceFromName("work_core")
    if not res or getResourceState(res) ~= "running" then return end
    for _, d in ipairs(depots) do
        if isElement(d.marker) then exports.work_core:setElementVisibleToWork(d.marker, RW.DEPOT_WORK) end
        if isElement(d.blip) then exports.work_core:setElementVisibleToWork(d.blip, RW.DEPOT_WORK) end
    end
end

addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, applyDepotVisibility)

addEventHandler("onResourceStart", resourceRoot, function()
    for i, def in ipairs(RW.DEPOTS) do
        local m = createMarker(def.x, def.y, def.z - 1, "cylinder", 1.4, 80, 160, 255, 120)
        setElementData(m, "rw.depot", i)
        local blip = createBlipAttachedTo(m, 11, 2, 80, 160, 255, 255, 0, 250)
        setElementData(blip, "tooltipText", RW.COMPANY .. " - " .. def.name)
        depots[#depots + 1] = { def = def, marker = m, blip = blip }
    end
    applyDepotVisibility()
end)

-- rw_core started before work_core: apply once it runs
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "work_core" then setTimer(applyDepotVisibility, 500, 1) end
end)
