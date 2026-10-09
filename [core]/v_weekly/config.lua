-- v_weekly :: shared config

WEEKLY = {
    -- /weekly admin menu: account admin_level (v_mysql accData) must be >= this
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

    -- allowed Job money / XP multipliers (1 = no bonus)
    MULTIPLIERS = { 1, 2, 3 },

    -- login bonus is paid once per "day" (UTC calendar day) or once per "week"
    LOGIN_BONUS_PERIOD = "day",
    LOGIN_MAX_MONEY    = 1000000,
    LOGIN_MAX_XP       = 100000,
    LOGIN_KEY          = "weekly_login", -- accData: id of the last period paid

    -- the default week when nothing was ever configured
    DEFAULT_TIMETRIAL = 5,
}
