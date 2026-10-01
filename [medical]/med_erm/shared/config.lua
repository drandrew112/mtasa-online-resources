-- Emergency Response Manager - shared configuration

Config = {}

-- Key that opens/closes the unit tablet.
Config.TABLET_KEY = "j"

-- Vehicle models the tablet can be opened in while NOT signed in.
-- 416 = Ambulance, 563 = Raindance (air ambulance for HELI units).
Config.TABLET_VEHICLES = {
    [416] = true,
    [563] = true,
}

-- Unit types selectable on the sign-in screen.
Config.UNIT_TYPES = { "SOLO", "DOC", "BLS", "ALS", "HELI" }

-- Radius (metres) in which other players can be added to a crew.
Config.ADD_MEMBER_RADIUS = 10

-- Scene radius (metres). Within it the radar objective of the task is removed
-- and the unit switches to On Scene automatically (only at its own task).
Config.ARRIVE_RADIUS = 30

-- Speed (km/h) above which the driver of a unit with an active case, not yet
-- on scene, is warned when Start Response is off.
Config.RESPONSE_WARN_SPEED = 15

-- Minimum admin_level (v_mysql account data) for /ermadmin.
Config.ADMIN_LEVEL = 1

-- Hospital handover duration; afterwards the server frees the unit.
Config.HANDOVER_TIME = 30000

-- Chat history kept in memory (messages are not persisted).
Config.MAX_MESSAGES = 500

-- Closed tasks shown on the dispatcher page.
Config.RECENT_CLOSED = 30

-- Unit statuses.
Config.STATUS = {
    available = { label = "Available", color = { 46, 160, 67 } },   -- green
    enroute   = { label = "En Route",  color = { 218, 54, 51 } },   -- red
    onscene   = { label = "On Scene",  color = { 56, 132, 244 } },  -- blue
    handover  = { label = "Handover",  color = { 230, 190, 40 } },  -- yellow
}

Config.PRIORITY_COLORS = {
    [1] = { 229, 72, 77 },
    [2] = { 247, 107, 21 },
    [3] = { 255, 197, 61 },
    [4] = { 62, 155, 255 },
}
