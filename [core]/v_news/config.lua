-- v_news configuration (shared).

NEWS = {
    COMMAND      = "news",
    ADMIN_LEVEL  = 5,      -- accData admin_level needed for /news
    TABLE        = "news",
    TITLE_MAX    = 120,    -- characters
    BODY_MAX     = 4000,   -- characters
    DUE_CHECK    = 60000,  -- ms; how often scheduled articles are checked for becoming public
}
