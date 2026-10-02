-- Stretcher tunables. Offsets are { x, y, z, rx, ry, rz } in the parent's local space
-- (x = right, y = forward, z = up). Model 2146's long side lies along its own y axis, so an rz of
-- 0 keeps it lengthwise to the ambulance / the medic.

STRETCHER = {
    VEHICLE_MODELS = {             -- ambulances that carry a stretcher
        [416] = true,              -- Mercedes Sprinter (HU)
        [456] = true,              -- Mission Row Ambulance
    },
    OBJECT_MODEL = 2146,           -- hospital trolley

    -- Size: every client scales the model so its longest side is TARGET_LENGTH metres
    -- (a lying adult + a bit). FALLBACK_SCALE is used if the bounding box cannot be read.
    TARGET_LENGTH = 2.1,
    FALLBACK_SCALE = 1.0,

    -- Path in / out of the ambulance (vehicle-local offsets). Taking out runs
    -- STOW -> EDGE (slide to the rear doors) -> OUT (down, behind the vehicle); loading runs it backwards.
    STOW_OFFSET = { 0, -1.6, 0.0, 0, 0, 0 },   -- inside the cargo area: the take-out slide starts here
    -- While stowed the (invisible) object is parked at the rear doors so its menu is there. Every
    -- client moves it onto the model's real rear doors (door dummies / bounding box, client/stretcher.lua);
    -- this y is only the server-side estimate (used for its range check) and the fallback.
    STOWED_MENU_POINT = { 0, -3.7, 0.0, 0, 0, 0 },
    EDGE_OFFSET = { 0, -3.7, 0.0 },            -- at the rear doors, still at floor height
    OUT_OFFSET = { 0, -4.7, -0.55 },           -- on the ground behind the vehicle
    -- Per-model shift along the vehicle's y axis (negative = further back), applied to
    -- STOW / EDGE / OUT_OFFSET, STOWED_MENU_POINT, REAR_POINT and LOAD_ZONE_CENTER
    MODEL_Y_SHIFT = {
        [456] = -0.8,              -- Mission Row Ambulance
    },
    DOOR_TIME = 600,               -- ms, the rear doors open / close
    ALIGN_TIME = 500,              -- ms, loading: the stretcher lines up behind the vehicle
    SLIDE_TIME = 1200,             -- ms, STOW <-> EDGE
    LOWER_TIME = 700,              -- ms, EDGE <-> OUT
    REAR_DOORS = { 4, 5 },         -- rear left / rear right door
    FREEZE_VEHICLE = true,         -- the ambulance cannot drive away during the animation

    -- Where the medic stands to take the stretcher out / how close it must be to be loaded
    REAR_POINT = { 0, -4.0, 0 },   -- vehicle-local, behind the rear doors
    REAR_RANGE = 2.5,              -- medic within this of REAR_POINT (take out)

    -- Load zone: a narrow rectangle on the ground behind the ambulance. The stretcher can only be
    -- loaded while its centre is inside it and it points into the ambulance (its yaw within
    -- LOAD_ZONE_MAX_ANGLE of the stowed yaw). While pushing, the pusher sees it:
    -- white = outside, orange = inside but turned wrong, green = can be loaded.
    LOAD_ZONE_CENTER = { 0, -4.7 },  -- vehicle-local x, y (MODEL_Y_SHIFT applies)
    LOAD_ZONE_WIDTH = 1.2,           -- metres, across the vehicle (x)
    LOAD_ZONE_LENGTH = 2.4,          -- metres, along the vehicle (y)
    LOAD_ZONE_HEIGHT = 3.0,          -- max height difference to the vehicle origin
    LOAD_ZONE_MAX_ANGLE = 30,        -- degrees, max yaw difference to the stowed direction
    LOAD_ZONE_COLOR = { 255, 255, 255 },
    LOAD_ZONE_ANGLE_COLOR = { 255, 150, 40 },
    LOAD_ZONE_OK_COLOR = { 60, 220, 90 },
    LOAD_ZONE_FILL_ALPHA = 60,
    LOAD_ZONE_LINE_ALPHA = 220,

    -- Pushing: attached in front of the medic, no collisions. The medic moves with GTA's own
    -- movement (forced to walk speed unless sprinting, synced natively). A looped setPedAnimation walk cannot be used:
    -- its root motion is drawn forward and snaps back on every loop. PUSH_IDLE_ANIM is played locally
    -- on every client while the pusher stands still.
    PUSH_OFFSET = { 0, 1.5, -0.55, 0, 0, 0 },
    PED_HEIGHT = 1.0,              -- a standing ped's origin above its feet
    PUSH_IDLE_ANIM = { "CARRY", "crry_prtial" },  -- standing, arms forward
    PUSH_LOCKED_CONTROLS = { "jump", "crouch", "fire", "aim_weapon", "enter_exit",
        "enter_passenger", "next_weapon", "previous_weapon" },

    -- On the ground (after releasing)
    DROP_DISTANCE = 1.4,           -- metres in front of the medic
    GROUND_Z = 0.45,               -- object origin above the ground
    GROUND_ROT_Z = 0,              -- yaw relative to the medic's heading (= PUSH_OFFSET[6])

    -- Patient
    -- The lying animation draws the body ~1 m below the ped's origin, so z = mattress height + ~1.
    -- rz turns the body lengthwise on the stretcher (use 180 to swap the head and feet end).
    -- MTA does not rotate attached peds with their parent: every client keeps the patient's
    -- heading at stretcher yaw + rz (client/stretcher.lua).
    PATIENT_OFFSET = { 0, 0, 1.5, 0, 0, 180 },
    -- { block, name, loop }: lying on the back. A non-looped one keeps its last frame.
    PATIENT_ANIM = { "BEACH", "Lay_Bac_Loop", true },
    DOWN_ANIM = { "PED", "KO_shot_front" },   -- after unloading an unconscious patient (= medical_system)
    PATIENT_RANGE = 3.0,           -- metres around the stretcher: who can be selected as patient
    SELECT_MAX_DISTANCE = 6.0,     -- the selection ends if the medic walks this far from the stretcher
    REAR_SEATS = { 2, 3 },         -- ambulance seats the patient is warped into

    -- Menu (on the stretcher object; while stowed it is reached at the rear of the ambulance)
    MENU_RANGE = 2.5,
    STOWED_MENU_RANGE = 3.0,       -- from the stowed stretcher inside the vehicle
    SELF_DATA_KEY = nil,           -- e.g. "isMedic": only players with this element data see the menu

    SCAN_INTERVAL = 3000,          -- ms, fallback scan for ambulances the hooks missed
}

-- Element data (synced, read by the client and other resources)
STRETCHER_DATA = {
    STATE = "stretcher.state",     -- on the object: "stowed" | "moving" | "ground" | "pushing"
    VEHICLE = "stretcher.vehicle", -- on the object: its ambulance
    PATIENT = "stretcher.patient", -- on the object: the ped lying on it
    ON = "stretcher.on",           -- on the patient: the stretcher they lie on
    PUSHING = "stretcher.pushing", -- on the medic: the stretcher they push
    LOCKED = "stretcher.locked",   -- on the patient: the ambulance they are locked into
}
