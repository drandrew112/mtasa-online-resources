-- v_ownveh :: vehicle spawn points
--
-- Hand-maintained. When a player summons a vehicle (spawnOwnedVehicle export)
-- it is placed on the CLOSEST FREE point in the list matching the vehicle's
-- type. If every point in a list is occupied the summon fails.
--
-- Each entry is {x, y, z, rx, ry, rz} (position + rotation).
--
-- To collect points: sit in a vehicle where you want a spawn point and type
-- /vehspawn (admin only). It appends a ready-to-paste line to
-- vehiclespawnpoints.txt - move the lines into the right list below.
--
-- Categories map from getVehicleType():
--   airplanes   <- "Plane"
--   helicopters <- "Helicopter"
--   boats       <- "Boat"
--   land        <- everything else (cars, bikes, quads, monster trucks, ...)

Vehicles = Vehicles or {}

Vehicles.spawnpoints = {
    land        = {
        {0, 0, 3, 0, 0, 0},
    },
    boats       = {
        {0, 0, 3, 0, 0, 0},
    },
    helicopters = {
        {0, 0, 3, 0, 0, 0},
    },
    airplanes   = {
        {0, 0, 3, 0, 0, 0},
    },
}
