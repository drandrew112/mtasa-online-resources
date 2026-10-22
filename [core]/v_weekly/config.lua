-- v_weekly :: shared config

WEEKLY = {
    -- unused since v_admin 3.0 (the Weekly page uses v_admin ADMIN.perms.weekly)
    ADMIN_LEVEL = 4,

    -- a week runs from this weekday/hour (UTC) to the next.
    -- weekday: 0 = Sunday ... 2 = Tuesday ... 6 = Saturday
    WEEK_DAY  = 2,
    WEEK_HOUR = 10,

    -- how many upcoming weeks the admin menu lists (0 = current week)
    ADMIN_WEEKS = 5,

    -- account-data key holding the week_start of the last panel the player saw
    SEEN_KEY = "weekly_seen",

    -- delay after onPlayerLoaded before the panel opens (ms)
    PANEL_DELAY = 3000,

    -- how often the schedule timer checks for a new week (ms)
    CHECK_INTERVAL = 30000,

    -- how often the weekly_schedule table is re-read, so edits made on another
    -- server instance (or in the database) reach this one (ms)
    SYNC_INTERVAL = 30000,

    -- weeks of history kept in weekly_schedule (older rows are deleted)
    KEEP_WEEKS = 26,

    -- allowed Job / Work money / XP multipliers (1 = no bonus)
    MULTIPLIERS = { 1, 2, 3 },

    -- login bonus is paid once per "day" (UTC calendar day) or once per "week"
    LOGIN_BONUS_PERIOD = "day",
    LOGIN_MAX_MONEY    = 300000, 
    LOGIN_MAX_XP       = 100000,
    LOGIN_KEY          = "weekly_login", -- accData: id of the last period paid

    -- the default week when nothing was ever configured
    DEFAULT_TIMETRIAL = 5,
}
