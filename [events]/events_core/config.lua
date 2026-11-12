-- Shared config of events_core.
EVENTS = {
    WEEKLY_KEY  = "events",     -- v_weekly week value (custom.events = { [eventId] = true })
    ADMIN_LEVEL = 5,            -- account admin_level needed for /events (console always allowed)
    SYNC_DELAY  = 2000,         -- ms after a (re)start of v_weekly / v_modloader / maps_loader before the state is pushed again
}
