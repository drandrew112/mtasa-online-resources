-- player / camera: the probe player (the developer's own client) and its camera.

local function playerState(p)
    local d = Props.describe(p, "medium")
    d.name = getPlayerName(p)
    d.probe = Probe.get() == p
    local c = Probe.clients[p]
    if c and c.info then
        d.camera = c.info.camera and {
            position = M.vec(c.info.camera[1], c.info.camera[2], c.info.camera[3]),
            target = M.vec(c.info.camera[4], c.info.camera[5], c.info.camera[6]),
            fixed = Probe.focused == p,
        } or nil
        d.fps = c.info.fps
        d.windowActive = c.info.windowActive
        d.screen = c.info.screen
    end
    local veh = getPedOccupiedVehicle(p)
    if veh then
        d.vehicle = { id = Refs.of(veh), seat = getPedOccupiedVehicleSeat(p), model = getElementModel(veh), modelName = Util.vehicleName(getElementModel(veh)) }
    end
    return d
end

local function target(p)
    if p.player then
        local el = Refs.require(p.player, "player")
        if getElementType(el) ~= "player" then fail("INVALID_PARAMS", "'" .. p.player .. "' is not a player.") end
        return el
    end
    return Probe.require()
end

Api.register("player", "get", function(p)
    return playerState(target(p))
end, { desc = "Position, heading, vehicle, camera, zone of the probe player (or params.player)." })

Api.register("player", "list", function()
    local out = {}
    for _, pl in ipairs(getElementsByType("player")) do out[#out + 1] = playerState(pl) end
    return { players = out }
end, { desc = "All connected players." })

-- teleport: { position, heading, player, keepVehicle, dimension, interior }
Api.register("player", "teleport", function(p)
    local pl = target(p)
    local x, y, z = P.vec(p.position, "position")
    if not z then
        z = select(3, getElementPosition(pl))
    end
    local veh = getPedOccupiedVehicle(pl)
    local moved = pl
    if veh and p.keepVehicle ~= false and getPedOccupiedVehicleSeat(pl) == 0 then
        moved = veh
    elseif veh then
        removePedFromVehicle(pl)
    end
    if p.dimension then setElementDimension(moved, math.floor(tonumber(p.dimension))) if moved ~= pl then setElementDimension(pl, math.floor(tonumber(p.dimension))) end end
    if p.interior then setElementInterior(moved, math.floor(tonumber(p.interior))) if moved ~= pl then setElementInterior(pl, math.floor(tonumber(p.interior))) end end
    setElementPosition(moved, x, y, z + (p.exactZ and 0 or (moved == pl and 1.0 or 1.5)))
    setElementVelocity(moved, 0, 0, 0)
    if p.heading then
        if moved == pl then
            setElementRotation(pl, 0, 0, tonumber(p.heading), "default", true)
        else
            setElementRotation(moved, 0, 0, tonumber(p.heading))
        end
    end
    setCameraTarget(pl, pl)
    if p.wait ~= false then Async.sleep(tonumber(p.wait) or 1200) end
    return { teleported = true, movedVehicle = moved ~= pl, state = playerState(pl) }
end, { mutates = true, desc = "Moves the probe player (streams collision/models in at the destination)." })

---------------------------------------------------------------- camera

Api.register("camera", "get", function(p)
    local pl = target(p)
    local r = Probe.call("camera", { aim = p.aim ~= false, distance = P.num(p, "distance", 300, 1, 3000) }, nil, pl)
    return r
end, { async = true, desc = "Camera matrix, look direction and what the centre of the screen hits." })

-- set: { position, target, roll, fov }  fixed camera until camera.reset
Api.register("camera", "set", function(p)
    local pl = target(p)
    local x, y, z = Resolve.point(p.position, "position")
    local tx, ty, tz = Resolve.point(p.target, "target")
    if not z or not tz then fail("INVALID_PARAMS", "camera position and target need a z.") end
    setCameraMatrix(pl, x, y, z, tx, ty, tz, P.num(p, "roll", 0), P.num(p, "fov", 70, 5, 170))
    Probe.focused = nil
    return { fixed = true, position = M.vec(x, y, z), target = M.vec(tx, ty, tz),
        note = "The camera stays fixed until camera reset (set_camera mode 'reset')." }
end, { mutates = true, desc = "Fixes the player's camera at a matrix." })

Api.register("camera", "reset", function(p)
    local pl = target(p)
    setCameraTarget(pl, pl)
    return { reset = true }
end, { mutates = true, desc = "Gives the camera back to the player." })

-- setProbe: { player } makes that player the probe client (like /mcp probe)
Api.register("player", "setProbe", function(p)
    local pl = Refs.require(P.str(p, "player"), "player")
    if getElementType(pl) ~= "player" then fail("INVALID_PARAMS", "'" .. p.player .. "' is not a player.") end
    if not Probe.clients[pl] then fail("PROBE_NOT_READY", "That player's claude-mcp client part is not ready.", { retryable = true }) end
    Probe.preferred = pl
    Overlay.push()
    return { success = true, probe = Probe.info(pl) }
end, { mutates = true, desc = "Selects the probe client." })
