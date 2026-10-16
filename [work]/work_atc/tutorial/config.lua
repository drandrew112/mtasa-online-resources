-- work_atc tutorial module - shared configuration. The texts of the steps are in client/steps.lua
-- (v_locals work_atc.tut.*). Positions: /workpos of work_core.

TUTORIAL = {
    -- true: the tutorial is offered on EVERY duty start, even when it was completed / skipped
    DEBUG = false,

    COMMAND = "tutorial_atc",          -- /tutorial_atc starts it, /tutorial_atc skip ends it
    ACC_KEY = "atc.tutorial",          -- v_mysql account data: true once completed or skipped
    DIMENSION_BASE = 44000,            -- every session gets its own dimension from here
    FADE_TIME = 1.2,                   -- seconds of a camera fade
    CURSOR_KEY = "F2",                 -- shows / hides the cursor for the tutorial card buttons
    POLL = 500,                        -- ms, server check of the tutorial aircraft

    -- The tower position of the tutorial (avi_controller tutorial login) and its airport. The SA
    -- Control building is next to San Fierro airport.
    POSITION = "SASF_TWR",
    AIRPORT = "SASF",

    -- The player starts here, in the SA Control operations room (interior 3, the session's dimension):
    -- the arrival point of the SA Control entrance (avi_core AVI.INTERIOR.entrance), a few metres from
    -- the San Fierro consoles. The tutorial console marker stands where the live San Fierro one does.
    START = { 215.20518, 199.86151, 1058.15942, 0, interior = 3 },

    -- The two tutorial aircraft of avi_traffic (spawnTutorialFlight); type and route are copied from
    -- a flight of the database. The departure waits gateWait s at the stand before it calls.
    DEPARTURE = { callsign = "TUT101", gateWait = 3 },
    ARRIVAL = { callsign = "TUT202" },
    ALERT_SQUAWK = "7700",             -- the alert demonstration (EMRG over the label)

    -- Keys named in the texts (avi_core AVI.MARKER_KEY)
    KEYS = { console = "E" },
}
