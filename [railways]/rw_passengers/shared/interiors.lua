-- Coach interiors (measured live in phase 0, 2026-10-04, see DESIGN.md section 10).
-- World coordinates of the interior; every coach uses the same place, its dimension is the
-- coach id. The cabin's +y points towards the (closed) cockpit = the coach's front.

RWP = RWP or {}

RWP.INTERIORS = {
    -- Shamal cabin: GTA object jet_interior (14404) at 1.719, 30.406, 1200.344, rotation 0
    coach = {
        interior = 1,
        floorZ   = 1198.594,
        centreX  = 1.73,                          -- aisle centre line
        rearY    = 22.242,                        -- rear wall (toilet door)
        frontY   = 34.359,                        -- cockpit door frame, cabin side
        walls    = { left = 0.05, right = 3.40 }, -- side walls (x); windows on both

        -- where a boarding passenger appears: inside the side door, facing the rear (into the cabin)
        spawn = { x = 2.3, y = 33.1, z = 1199.6, rz = 180 },

        -- the "Leave the train" anchor in the side door recess (ld_747_door, x 2.76 - 3.42,
        -- y 31.88 - 34.36)
        exit = { x = 3.2, y = 33.1, z = 1199.6 },

        -- cockpit doorway: collision opening x 1.08 - 2.38, top z 1201.19 (frame y 34.36 - 34.58).
        -- Closed by a double door: two ab_casdorLok (3089) leaves, the second one mirrored
        -- (rz 180). Collision verified by rays, look verified by screenshot.
        blockers = {
            { model = 3089, x = 0.21,  y = 34.32, z = 1199.90, rz = 0,   doubleSided = true },
            { model = 3089, x = 3.187, y = 34.32, z = 1199.90, rz = 180, doubleSided = true },
        },

        -- passenger information display above the cockpit door (covers the gap between the door
        -- top and the arch), cabin side, facing -y
        display = { x = 1.73, y = 34.28, z = 1201.58, w = 1.30, h = 0.55, nx = 0, ny = -1 },

        -- windows: the panes are painted into this texture (256 x 256, two windows side by side)
        window = {
            texture = "mp_jet_wall",
            model   = 14404,                       -- engineGetModelTextures(model)[texture]
            size    = 256,
            panes   = { { 38, 97, 74, 147 }, { 168, 97, 204, 147 } },   -- pixel rects x0, y0, x1, y1
            -- pane pixels: near white (252, 255, 255); frame wood (165, 134, 107)
            maskLum = 200, maskSat = 40,           -- pane = luminance > maskLum and max-min < maskSat
        },
    },
}
