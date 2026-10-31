if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ai_peds server: start-up, brain loop, admin command.

AIPedsMain = {}

local T = AIPEDS
local nextSync, nextSpawn, nextCull = 0, 0, 0

-- players the ped traffic lives around: { { el, x, y, z } } (dimension 0, interior 0)
local function trafficPlayers()
    local out = {}
    for _, pl in ipairs(getElementsByType("player")) do
        if getElementDimension(pl) == 0 and getElementInterior(pl) == 0 then
            local x, y, z = getElementPosition(pl)
            out[#out + 1] = { el = pl, x = x, y = y, z = z }
        end
    end
    return out
end

local function tick()
    local now = getTickCount()
    for el, p in pairs(Peds.list) do
        if not isElement(el) then
            Peds.remove(p, "destroyed")
        else
            -- a ped sitting in a vehicle is not synced (its own server position is stale, e.g. the spawn point of a
            -- traffic driver): the vehicle's position stands for it
            local veh = getPedOccupiedVehicle(el)
            p.x, p.y, p.z = getElementPosition(veh or el)
            -- peds without a syncer stand still: nothing to decide (dead bodies still get cleaned up)
            -- a vehicle task (aiPedEnterVehicle / aiPedExitVehicle) runs first: the behaviour waits for it
            if p.vt and VehTasks.update(p, now) then
                -- busy getting in / out
            elseif p.syncer or p.dead or p.behaviour == "exiting" then
                local b = Behaviours[p.behaviour]
                if b and b.update then
                    local ok, err = pcall(b.update, p, now)
                    if not ok then outputDebugString("[ai_peds] " .. tostring(p.behaviour) .. ": " .. tostring(err), 1) end
                end
            end
        end
    end
    if now >= nextSync then
        nextSync = now + T.SYNC_CHECK
        Peds.checkSyncers()
    end
    if now >= nextSpawn or now >= nextCull then
        local players = trafficPlayers()
        if now >= nextCull then nextCull = now + 1000; PedTraffic.cull(players, now) end
        if now >= nextSpawn then nextSpawn = now + T.SPAWN_INTERVAL; PedTraffic.spawn(players, now) end
    end
end

addEvent("onAIPedArrived")             -- (ped) tag, x, y, z
addEvent("onAIPedTaskFailed")          -- (ped) tag, reason
addEvent("onAIPedTargetAcquired")      -- (ped) target
addEvent("onAIPedTargetLost")          -- (ped) target, reason
addEvent("onAIPedBehaviourChanged")    -- (ped) new, old
addEvent("onAIPedWasted")              -- (ped) killer, weapon
addEvent("onAIPedRemoved")             -- (ped) reason
addEvent("onAIPedDamaged")             -- (ped) attacker, weapon, loss
addEvent("onAIPedArrestTarget")        -- (ped) target: police behaviour stood next to its target for arrestTime
addEvent("onAIPedEnteredVehicle")      -- (ped) vehicle, seat
addEvent("onAIPedExitedVehicle")       -- (ped) vehicle
addEvent("onAIPedVehicleTaskFailed")   -- (ped) "enter" | "exit", reason

addEventHandler("onResourceStart", resourceRoot, function()
    if not Nav.available() then
        outputDebugString("[ai_peds] navmesh is not running: no ped traffic, straight-line moves only", 2)
    end
    setTimer(tick, T.TICK, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    -- own peds go with the resource; adopted drivers are left as they are
    for _, p in pairs(Peds.list) do
        if not p.own and isElement(p.el) then
            removeElementData(p.el, "ai_peds")
            removeElementData(p.el, DATA_MOVE)
            removeElementData(p.el, DATA_FIGHT)
            removeElementData(p.el, DATA_SAVE_LETHAL)
            if p.behaviour == "scared" and p.b.cowering then setPedAnimation(p.el) end
        end
    end
end)

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "ped" then return end
    local p = Peds.list[source]
    if p then Peds.remove(p, "destroyed", true) end
end)

------------------------------------------------------------------------ stats + admin command

function AIPedsMain.stats()
    local beh, synced = {}, 0
    for _, p in pairs(Peds.list) do
        beh[p.behaviour or "?"] = (beh[p.behaviour or "?"] or 0) + 1
        if p.syncer then synced = synced + 1 end
    end
    local routes = 0
    for _ in pairs(Nav.pending) do routes = routes + 1 end
    return { total = Peds.count, traffic = Peds.byKind.traffic, drivers = Peds.byKind.driver,
             scripted = Peds.byKind.scripted, synced = synced, behaviours = beh, pendingRoutes = routes,
             trafficEnabled = PedTraffic.enabled }
end

local function isAdmin(pl)
    return (tonumber(getElementData(pl, "admin_level")) or 0) >= T.ADMIN_LEVEL
end

local function notify(pl, msg)
    triggerClientEvent(pl, EV_NOTIFY, resourceRoot, msg)
end

addCommandHandler("aipeds", function(pl, _, arg)
    if not isAdmin(pl) then return end
    if arg == "on" then
        setAIPedTrafficEnabled(true)
        notify(pl, L.msg("ai_peds.main.traffic_on"))
    elseif arg == "off" then
        setAIPedTrafficEnabled(false)
        notify(pl, L.msg("ai_peds.main.traffic_off"))
    elseif arg == "clear" then
        PedTraffic.clear()
        notify(pl, L.msg("ai_peds.main.traffic_cleared"))
    elseif arg == "debug" then
        triggerClientEvent(pl, EV_DEBUG, resourceRoot)
    else
        local s = AIPedsMain.stats()
        local b = {}
        for k, v in pairs(s.behaviours) do b[#b + 1] = k .. " " .. v end
        local c = PedTraffic.cache[pl]
        notify(pl, L.msg("ai_peds.main.stats", {
            enabled = s.trafficEnabled and "on" or "off", total = s.total, traffic = s.traffic, drivers = s.drivers,
            scripted = s.scripted, synced = s.synced, b = table.concat(b, ", "),
            sidewalk = c and math.floor(c.settle) or 0, target = c and c.target or 0,
        }))
    end
end)
