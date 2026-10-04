-- rw_loco settings (server + client)

LOCO = {
    -- rolling stock type (rw_core RW.VEHICLES id) -> cab panel module + common modules.
    -- Every locomotive gets the timetable module and the vigilance device (sifa).
    TYPES = {
        -- cab: the game's own enter / exit is broken on this model, so the cab doors are
        -- ui_interactobject points (vehicle-local offsets, front cab = +y) and leaving puts
        -- the driver down beside the cab (platform side when known), exitLateral metres out.
        br232 = { panel = "br232", modules = { "timetable", "sifa" }, vmax = 120,
                  cab = { doors = { { x = -1.9, y = 7.2, z = 2.6 }, { x = 1.9, y = 7.2, z = 2.6 } }, exitLateral = 2.9 } },
    },
    CAB_DOOR_MODEL = 1319,     -- invisible, non-colliding anchor object for the door menus
    CAB_EXIT_MAX_SPEED = 3,    -- km/h: the driver can only leave a (nearly) standing train

    KEYS = {
        cursor    = "lctrl",   -- show / hide the mouse cursor for the cab panel
        timetable = "f6",      -- open / close the timetable panel
        sifa      = "space",   -- vigilance acknowledge (bindable command: rw_sifa)
    },

    ENGINE_CRANK_TIME = 3500,  -- ms from pressing START to a running engine
    LEAD_OFFSET = 10.6,        -- = RW.LEAD_OFFSET (train centre ahead of the game position)
    HALF_LENGTH = 11,          -- = RW.HALF_LENGTH

    -- Vigilance device (Sifa): while moving faster than MIN_SPEED the driver must press the
    -- acknowledge key every INTERVAL_MIN..INTERVAL_MAX seconds and whenever the signal in
    -- front changes its aspect. Lamp first, then the alarm sound, then an emergency stop.
    SIFA = {
        MIN_SPEED    = 5,      -- km/h
        INTERVAL_MIN = 25,     -- s
        INTERVAL_MAX = 40,
        LAMP_TIME    = 4,      -- s of silent warning lamp
        ALARM_TIME   = 4,      -- s of alarm before the brakes apply
        SOUND        = "sounds/sifa_alarm.wav",   -- temporary (medsys Lifepak alarm)
        VOLUME       = 0.45,
    },
    EMERGENCY_DECEL = 1.6,     -- m/s^2 of a forced stop (Sifa / signal passed at danger)
}
