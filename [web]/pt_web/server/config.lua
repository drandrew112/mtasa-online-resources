-- pt_web :: server/config.lua
-- Public transport website: every operator (rail now, buses later) behind one journey planner.

PT = {
    TITLE = "San Andreas Transit",
    SITE  = "sa-transit.sa",                 -- in-game ui_browser address (services category)

    -- Operators. `adapter` = a built-in provider (server/provider_*.lua). Any other entry is an
    -- external provider: a running resource that exports the protocol in README.md
    -- (ptGetStops, ptGetTrips, ptGetBoard, ptGetLines) - that is how the bus system plugs in.
    PROVIDERS = {
        { id = "rail", mode = "rail", adapter = "rail", name = "Sunline Rail", short = "SLR", color = "#ffb52e" },
        -- { id = "bus", mode = "bus", resource = "bus_core", name = "San Andreas Bus", short = "SAB", color = "#2fbf6b" },
    },
    -- modes announced on the website before they have an operator
    COMING_SOON = { { mode = "bus", name = "City and intercity buses" } },

    PLANNER = {
        TRANSFER_MIN = 60,      -- s: minimum time to change between two trips at the same stop
        WALK_MAX     = 300,     -- m: stops closer than this are connected by a footpath
        WALK_SPEED   = 1.3,     -- m/s
        WALK_BUFFER  = 30,      -- s added to every footpath
        LOOK_BACK    = 40 * 60, -- s: trips departing this long before the query (still running)
        HORIZON      = 3 * 3600,-- s: how far ahead journeys are searched
        RESULTS      = 5,       -- alternatives per search
        CACHE        = 5,       -- s: trip list cache
    },

    BOARD_ROWS = 12,
    LANG = "en",                -- texts of other resources (v_locals messages) are shown in this language
}
