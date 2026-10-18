-- v_customs :: configuration (shared)

Customs = Customs or {}

-- Multiplies every price in shared/tuning.lua. 1.0 = the stock SA Customs prices.
Customs.PRICE_MULT = 1.0

-- Map blip of every workshop.
Customs.BLIP_ICON = 27

-- Workshops. Every one is a real building with a garage door:
--   door   - the stock door model is removed from the map and re-created as a
--            script object so it can move. open = position offset, openRot =
--            rotation offset of the opened door (moveObject does both at once).
--   approach - a vehicle with a driver inside this sphere opens the door.
--   inside - box past the door; a vehicle reaching it starts the session
--            (private dimension + drive-in animation, then the menu).
--   enter  - the car is snapped here (floor z, yaw) before the drive-in, however
--            it came in; the animation rolls it from here to park.
--   park   - where the car stops inside (floor z, yaw).
--   exit   - where the car ends up outside after the drive-out (floor z, yaw).
--   cam    - fixed camera of the drive-in animation (inside).
--   exitCam - fixed camera of the drive-out (outside, facing the door).
Customs.WORKSHOPS = {
    {
        id   = "ls_idlewood",  -- Idlewood, the old Pay 'n' Spray
        blip = { 2064.0, -1831.4, 13.5 },
        door = {
            model = 5422, x = 2071.4766, y = -1831.4219, z = 14.5625, rx = 0, ry = 0, rz = 0,
            -- up-and-over: ends as a horizontal panel under the ceiling, inside
            open    = { -2.02, 0, 2.19 },
            openRot = { 0, -90, 0 },
            time  = 1600,
        },
        approach = { 2076.0, -1831.4, 13.5, 9.0 },
        inside   = { minX = 2057.0, minY = -1835.8, minZ = 12.0, maxX = 2068.5, maxY = -1827.1, maxZ = 17.5 },
        park     = { 2063.5, -1831.4, 12.55, 90 },
        enter    = { 2069.5, -1831.4, 12.55, 90 },
        exit     = { 2075.0, -1831.4, 12.55, 270 },
        cam      = { 2058.2, -1835.0, 16.4 },
        exitCam  = { 2085.0, -1839.5, 15.2 },
    },
}

-- Door closes this long after the last vehicle left the approach zone (ms).
Customs.DOOR_CLOSE_DELAY = 2500

-- Animation timings (ms).
Customs.ANIM = {
    enter     = 2600,  -- car rolls from the door to the park spot
    driveOut  = 2300,  -- park spot -> outside (ends at ~5 m/s, the hand-over speed)
}
