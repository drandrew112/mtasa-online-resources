-- v_news configuration (shared).

NEWS = {
    COMMAND      = "news",  -- unused since v_admin 3.0 (v_admin ADMIN.pageCommands)
    ADMIN_LEVEL  = 5,      -- unused since v_admin 3.0 (v_admin ADMIN.perms.news)
    TABLE        = "news",
    TITLE_MAX    = 120,    -- characters
    BODY_MAX     = 4000,   -- characters
    DUE_CHECK    = 60000,  -- ms; how often scheduled articles are checked for becoming public
}
