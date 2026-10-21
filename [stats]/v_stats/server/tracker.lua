-- Movement tracker: samples every logged-in player each STATS.TICK ms and adds
-- distance (km) and drive time (s) to the right stat.
--
--   on foot            -> walk_km
--   driver, land veh.  -> drive_km, drive_time   (cars, bikes, quads, trains...)
--   driver, boat       -> sail_km,  sail_time
--   driver, plane/heli -> fly_km,   fly_time
--
-- Only the driver is counted. A sample is skipped (and the reference position
-- reset) when the mode, vehicle, interior or dimension changed, the player is
-- dead / frozen, or the move is faster than STATS.MAX_SPEED (teleport).

local last = {}   -- last[player] = { mode, ref, x, y, z, int, dim }

local AIR   = { Plane = true, Helicopter = true }
local WATER = { Boat = true }

local DIST_ID = { foot = "walk_km", land = "drive_km", water = "sail_km", air = "fly_km" }
local TIME_ID = { land = "drive_time", water = "sail_time", air = "fly_time" }

local function classify(player)
    local veh = getPedOccupiedVehicle(player)
    if not veh then return "foot", nil end
    if getVehicleController(veh) ~= player then return nil end
    local t = getVehicleType(veh)
    if AIR[t] then return "air", veh end
    if WATER[t] then return "water", veh end
    return "land", veh
end

local function sample(player)
    if getElementData(player, "isLogged") ~= true then last[player] = nil return end

    local mode, veh = classify(player)
    if not mode or isPedDead(player) or isElementFrozen(veh or player) then
        last[player] = nil
        return
    end

    local x, y, z = getElementPosition(veh or player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    local prev = last[player]
    last[player] = { mode = mode, ref = veh, x = x, y = y, z = z, int = int, dim = dim }
    if not prev or prev.mode ~= mode or prev.ref ~= veh or prev.int ~= int or prev.dim ~= dim then
        return
    end

    local entry = STORE.get(player)
    if not entry then return end

    local dt = STATS.TICK / 1000
    -- on foot: horizontal only, so falling / climbing does not inflate it
    local d
    if mode == "foot" then
        d = getDistanceBetweenPoints2D(x, y, prev.x, prev.y)
    else
        d = getDistanceBetweenPoints3D(x, y, z, prev.x, prev.y, prev.z)
    end
    if d / dt > STATS.MAX_SPEED[mode] then return end

    if d > 0.05 then API_ADD(entry, DIST_ID[mode], d / 1000) end
    if TIME_ID[mode] then API_ADD(entry, TIME_ID[mode], dt) end
end

setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do sample(player) end
end, STATS.TICK, 0)

addEventHandler("onPlayerQuit", root, function() last[source] = nil end)
