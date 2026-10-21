-- v_mapcam (server): cinematic spawn / teleport camera. The camera itself runs client-side.
-- Exports:
--   preSpawn(player, x, y, z)                                 -> bool  (camera parked above the spawn point so the world streams in; call playSpawn afterwards)
--   playSpawn(player [, x, y, z, rot])                       -> bool
--   teleportPlayer(player, x, y, z [, rot, interior, dim])    -> bool
--   isActive(player)                                          -> bool
--   cancel(player)                                            -> bool
-- Event (server): "v_mapcam:onFinish" (player, mode)  mode = "spawn" | "teleport"
-- Interior teleports (source or destination interior ~= 0) skip the animation and move instantly.

local TIMEOUT = 45000

local sessions = {} -- [player] = { mode, target, frozen, teleported, timer }

addEvent("v_mapcam:ready", true)
addEvent("v_mapcam:done", true)
addEvent("v_mapcam:onFinish", false)

local function motionElement(player)
    local veh = getPedOccupiedVehicle(player)
    if veh and getVehicleOccupant(veh, 0) == player then return veh end
    return player
end

local function release(player, fire)
    local s = sessions[player]
    if not s then return end
    sessions[player] = nil
    if isTimer(s.timer) then killTimer(s.timer) end
    if isElement(s.frozen) then setElementFrozen(s.frozen, false) end
    if isElement(player) then
        setElementData(player, "mapcam:active", false)
        triggerClientEvent(player, "v_mapcam:stop", resourceRoot)
        if fire then triggerEvent("v_mapcam:onFinish", player, s.mode) end
    end
end

local function begin(player, mode, target)
    local old = sessions[player]
    if old and old.mode == "prespawn" and mode == "spawn" then
        -- keep the client's held camera, no stop/start flicker
        if isTimer(old.timer) then killTimer(old.timer) end
        sessions[player] = nil
    else
        release(player, false)
    end
    local el = motionElement(player)
    local s = { mode = mode, target = target, frozen = el }
    s.timer = setTimer(release, TIMEOUT, 1, player, true)
    sessions[player] = s
    setElementFrozen(el, true)
    setElementData(player, "mapcam:active", true)
    return true
end

function preSpawn(player, x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not isElement(player) or getElementType(player) ~= "player" or not (x and y and z) then return false end
    release(player, false)
    local s = { mode = "prespawn" }
    s.timer = setTimer(release, TIMEOUT, 1, player, false)
    sessions[player] = s
    setElementData(player, "mapcam:active", true)
    triggerClientEvent(player, "v_mapcam:preSpawn", resourceRoot, x, y, z)
    return true
end

function playSpawn(player, x, y, z, rot)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if not x then
        x, y, z = getElementPosition(player)
        rot = select(3, getElementRotation(player))
    end
    begin(player, "spawn")
    triggerClientEvent(player, "v_mapcam:start", resourceRoot, "spawn", x, y, z, rot or 0)
    return true
end

function teleportPlayer(player, x, y, z, rot, interior, dim)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return false end
    interior = interior or 0
    rot = rot or select(3, getElementRotation(player))

    if interior ~= 0 or getElementInterior(player) ~= 0 then
        release(player, false)
        local el = motionElement(player)
        if el == player and getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
        setElementInterior(el, interior)
        if dim then setElementDimension(el, dim) end
        setElementPosition(el, x, y, z)
        setElementRotation(el, 0, 0, rot)
        return true
    end

    if not getPedOccupiedVehicle(player) or motionElement(player) == player then
        if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
    end
    begin(player, "teleport", { x = x, y = y, z = z, rot = rot, dim = dim })
    triggerClientEvent(player, "v_mapcam:start", resourceRoot, "teleport", x, y, z, rot)
    return true
end

function isActive(player)
    return sessions[player] ~= nil
end

function cancel(player)
    if not sessions[player] then return false end
    release(player, false)
    return true
end

-- client reports the camera is hovering over the destination -> do the actual move
addEventHandler("v_mapcam:ready", resourceRoot, function()
    local s = sessions[client]
    if not s or s.mode ~= "teleport" or s.teleported then return end
    s.teleported = true
    local t = s.target
    local el = motionElement(client)
    setElementInterior(el, 0)
    if t.dim then setElementDimension(el, t.dim) end
    setElementPosition(el, t.x, t.y, t.z)
    setElementRotation(el, 0, 0, t.rot)
    triggerClientEvent(client, "v_mapcam:arrived", resourceRoot)
end)

addEventHandler("v_mapcam:done", resourceRoot, function()
    release(client, true)
end)

addEventHandler("onPlayerQuit", root, function() release(source, false) end)
addEventHandler("onPlayerWasted", root, function() release(source, false) end)
addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(sessions) do release(p, false) end
end)
