-- ai_land_traffic server: start-up, main loop, events, commands, exports.

Traffic = { enabled = true, players = {} }

local T = TRAFFIC
local lastTick = 0
local nextObstacles, nextEls, nextSpawn, nextCleanup, nextReleased = 0, 0, 0, 0, 0

-- players the traffic is simulated around: { { el, x, y, z } }
local function activePlayers()
    local out = {}
    for _, p in ipairs(getElementsByType("player")) do
        if getElementDimension(p) == 0 and getElementInterior(p) == 0 then
            local x, y, z = getElementPosition(p)
            out[#out + 1] = { el = p, x = x, y = y, z = z }
        end
    end
    return out
end

local function refreshServerPositions(now)
    for _, ag in pairs(Agents.list) do
        if now >= ag.posRefresh then
            ag.posRefresh = now + T.SERVER_POS_REFRESH
            if isElement(ag.veh) then
                local rx, ry, rz = Geo.rotation(ag.fx, ag.fy, ag.fz)
                setElementPosition(ag.veh, ag.x, ag.y, ag.z + 0.6, false)
                setElementRotation(ag.veh, rx, ry, rz)
            end
        end
    end
end

local function tick()
    local now = getTickCount()
    local dt = (now - lastTick) / 1000
    lastTick = now
    if dt > 0.5 then dt = 0.5 end

    local players = activePlayers()
    Traffic.players = players
    if #players == 0 then
        if Agents.count > 0 then Agents.clear() end
        Signals.update(now)
        return
    end

    if now >= nextObstacles then nextObstacles = now + 200; Obstacles.rebuild(players) end
    if now >= nextEls then nextEls = now + 250; Els.update(now) end

    Sim.step(dt, now)

    if now >= nextSpawn then nextSpawn = now + T.SPAWN_INTERVAL; Spawner.update(players, now) end
    if now >= nextCleanup then nextCleanup = now + 1000; Spawner.cleanup(players, now) end
    if now >= nextReleased then nextReleased = now + 5000; Agents.cleanupReleased(players, now) end

    refreshServerPositions(now)
    Sync.flush(players, now)
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not Net.load() then return end
    Signals.start()
    Els.init()
    lastTick = getTickCount()
    setTimer(tick, T.TICK, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    Signals.stop()
    Agents.clear()
    for veh, r in pairs(Agents.released) do
        local keep = isElement(veh) and Agents.hasPlayerInside(veh)
        if isElement(r.ped) and getElementType(r.ped) == "ped" then destroyElement(r.ped) end
        if isElement(veh) and not keep then destroyElement(veh) end
    end
end)

------------------------------------------------------------------------ release triggers

addEventHandler("onVehicleStartEnter", root, function(player)
    local ag = Agents.byVeh[source]
    if ag and getElementType(player) == "player" then Agents.release(ag, "enter") end
end)

addEventHandler("onVehicleExplode", root, function()
    local ag = Agents.byVeh[source]
    if ag then Agents.release(ag, "damage") end
end)

addEventHandler("onPedWasted", root, function()
    local ag = Agents.byPed[source]
    if ag then Agents.release(ag, "damage") end
end)

addEventHandler("onElementDestroy", root, function()
    local t = getElementType(source)
    if t == "vehicle" then
        local ag = Agents.byVeh[source]
        if ag and Agents.list[ag.id] then Agents.vehicleDestroyed(ag) end
    elseif t == "ped" then
        local ag = Agents.byPed[source]
        if ag and Agents.list[ag.id] then Agents.release(ag, "damage") end
    end
end)

-- the local player of a client crashed into / shot a traffic vehicle
local lastReport = {}
addEvent(EV_REPORT, true)
addEventHandler(EV_REPORT, resourceRoot, function(veh, kind)
    local now = getTickCount()
    if lastReport[client] and now - lastReport[client] < 150 then return end
    lastReport[client] = now
    local ag = isElement(veh) and Agents.byVeh[veh]
    if not ag then return end
    local x, y, z = getElementPosition(client)
    if (x - ag.x) ^ 2 + (y - ag.y) ^ 2 + (z - ag.z) ^ 2 > 45 * 45 then return end
    Agents.release(ag, kind == "damage" and "damage" or "crash")
end)

addEventHandler("onPlayerQuit", root, function() lastReport[source] = nil end)

------------------------------------------------------------------------ admin command

local function isAdmin(p)
    return (tonumber(getElementData(p, "admin_level")) or 0) >= T.ADMIN_LEVEL
end

local function notify(p, text)
    triggerClientEvent(p, "ai_traffic:notify", resourceRoot, text)
end

function Traffic.stats()
    local released = 0
    for _ in pairs(Agents.released) do released = released + 1 end
    local holds = {}
    for _, ag in pairs(Agents.list) do
        local h = ag.hold or (ag.v < 0.3 and "stopped" or "moving")
        holds[h] = (holds[h] or 0) + 1
    end
    return { agents = Agents.count, released = released, players = #Traffic.players, enabled = Traffic.enabled,
             holds = holds, els = #Els.list }
end

addCommandHandler("traffic", function(p, _, arg)
    if not isAdmin(p) then return end
    if arg == "on" then
        Traffic.enabled = true
        notify(p, "AI traffic enabled")
    elseif arg == "off" then
        Traffic.enabled = false
        Agents.clear()
        notify(p, "AI traffic disabled and cleared")
    elseif arg == "clear" then
        Agents.clear()
        notify(p, "AI traffic cleared")
    elseif arg == "debug" then
        triggerClientEvent(p, "ai_traffic:debug", resourceRoot)
    else
        local s = Traffic.stats()
        local h = {}
        for k, v in pairs(s.holds) do h[#h + 1] = k .. " " .. v end
        notify(p, string.format("Traffic %s: %d vehicles, %d released, %d players, %d emergency | %s",
            s.enabled and "on" or "off", s.agents, s.released, s.players, s.els, table.concat(h, ", ")))
    end
end)

------------------------------------------------------------------------ exports

-- true = simulated traffic vehicle, "released" = former traffic vehicle (physics), false otherwise
function isTrafficVehicle(veh)
    if Agents.byVeh[veh] then return true end
    if Agents.released[veh] then return "released" end
    return false
end

function getTrafficVehicles()
    local out = {}
    for _, ag in pairs(Agents.list) do out[#out + 1] = ag.veh end
    return out
end

function releaseTrafficVehicle(veh)
    local ag = Agents.byVeh[veh]
    return ag and Agents.release(ag, "export") or false
end

function setTrafficEnabled(on)
    Traffic.enabled = on and true or false
    if not Traffic.enabled then Agents.clear() end
    return true
end

function isTrafficEnabled() return Traffic.enabled end

function getTrafficStats() return Traffic.stats() end

-- current traffic light colour for a phase (1 = north-south, 2 = east-west)
function getTrafficLight(phase) return Signals.light(phase) end
