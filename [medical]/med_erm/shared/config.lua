if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- Emergency Response Manager - shared configuration

Config = {}

-- Key that opens/closes the unit tablet.
Config.TABLET_KEY = "j"

-- Vehicle models the tablet can be opened in while NOT signed in.
-- 416 = Mercedes Sprinter (HU), 456 = Mission Row Ambulance, 563 = Raindance (air ambulance for HELI units).
Config.TABLET_VEHICLES = {
    [416] = true,
    [456] = true,
    [487] = true,
    [563] = true,
    [598] = true,
    [582] = true,
    [600] = true,
}

-- Unit types selectable on the sign-in screen.
Config.UNIT_TYPES = { "SOLO", "DOC", "BLS", "ALS", "HELI" }

-- Radius (metres) in which other players can be added to a crew.
Config.ADD_MEMBER_RADIUS = 10

-- Scene radius (metres). Within it the radar objective of the task is removed
-- and the unit switches to On Scene automatically (only at its own task).
Config.ARRIVE_RADIUS = 30

-- Distance (metres) from the scene after which a unit that reached it counts as
-- departed: the crew gets a radar objective to the nearest hospital (med_hospitals),
-- removed when the unit gets the Handover status. Coming back within ARRIVE_RADIUS
-- sets On Scene again and removes it until the next departure.
Config.HOSPITAL_DEPART_RADIUS = 50

-- Speed (km/h) above which Start Response is switched on automatically when the
-- driver of a unit with an active case drives off (to the scene, or away from it).
Config.RESPONSE_AUTO_SPEED = 5

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
    available = { label = L.text("med_erm.config.available"), color = { 46, 160, 67 } },   -- green
    enroute   = { label = L.text("med_erm.config.en_route"),  color = { 218, 54, 51 } },   -- red
    onscene   = { label = L.text("med_erm.config.on_scene"),  color = { 56, 132, 244 } },  -- blue
    handover  = { label = L.text("med_erm.config.handover"),  color = { 230, 190, 40 } },  -- yellow
}

Config.PRIORITY_COLORS = {
    [1] = { 229, 72, 77 },
    [2] = { 247, 107, 21 },
    [3] = { 255, 197, 61 },
    [4] = { 62, 155, 255 },
}

-- Shift-end payment (server/payment.lua): paid via work_core's payWork() export
-- when a unit signs out, one itemised line per task it worked (u.closedTasks),
-- split evenly among everyone who was ever part of the shift (u.roster). Needs
-- work_core running; WORK_ID only has to resolve a name/colour for the receipt.
Config.PAY = {
    WORK_ID = "ems",
    -- base money per minute spent on the task, by closedTasks outcome.
    -- "default" covers any outcome not listed here; base = perMinute = 0
    -- credits the task (it still counts on the unit's Home page) without
    -- paying anything for it.
    RATES = {
        handover        = { base = 1500, perMinute = 120 },  -- full hospital handover
        released        = { base = 600,   perMinute = 60  },  -- taken off the case by dispatch
        left            = { base = 600,   perMinute = 30  },  -- handed to another unit
        ["task closed"] = { base = 600,   perMinute = 30  },  -- case closed while still on it
        ["shift ended"] = { base = 300,   perMinute = 30  },  -- shift ended mid-case, no payout
        default         = { base = 300,   perMinute = 30  },
    },
}
end)
