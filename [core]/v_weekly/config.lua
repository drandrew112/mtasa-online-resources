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

    -- Discord weekly update (server/discord.lua): an embed through v_discordmanager
    -- when a new week starts. Webhook ids are keys of v_discordmanager/webhooks.json.
    DISCORD_WEBHOOK      = "weekly",   -- "" = no automatic post
    DISCORD_INSTANCE_ID  = 2,          -- only this v_main server instance posts automatically
    DISCORD_POST_WINDOW  = 6 * 3600,   -- s after the week start; a server started later does not post that week
    DISCORD_COLOR        = 0x0096FF,
    DISCORD_MENTION      = "",         -- text above the embed, e.g. "@everyone" or "<@&roleId>" ("" = none)
    DISCORD_FOOTER       = "",         -- "" = the server name
    DISCORD_THUMBNAIL    = "",         -- image URL ("" = none)
    DISCORD_TEST_WEBHOOK = "weekly",   -- /weeklydiscord sends here
    DISCORD_ADMIN_LEVEL  = 3,          -- /weeklydiscord: Admin and above

    -- the default week when nothing was ever configured
    DEFAULT_TIMETRIAL = 5,
}
