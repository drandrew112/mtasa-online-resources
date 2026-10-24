-- pt_tickets settings (server + client). See README.md.
-- Prices and who gets the ticket money are set on the /gov Transport page (v_gov setting
-- pt.<mode>); FALLBACK is used only while v_gov is not running.

PTT = {
    OFFER_TIME = 60,          -- s: an open ticket sale (panel) expires after this
    SALE_RANGE = 15,          -- m: walking this far from where the panel opened closes it

    FALLBACK = {              -- v_gov offline
        rail = { fare_km = 100, fare_min = 50, ic_supplement = 500 },
    },

    RAIL = {
        REQUIRED = true,      -- boarding a train needs a ticket (false = free travel as before)
        OPERATOR = "Sunline Rail",
        EJECT_DELAY = 8,      -- s after the doors opened at the ticket's last stop until the
                              -- passenger is put on the platform
        TICK = 1000,          -- ms: ticket / ride check
    },

    -- the DX panel: at most ~35 % of the screen width
    PANEL = {
        W = 0.30,             -- of the screen width
        MIN_W = 380,          -- px
        ROWS = 7,             -- destination rows visible at once (scrolls)
    },
}
