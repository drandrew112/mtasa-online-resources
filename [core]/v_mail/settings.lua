-- v_mail shared settings (the Brevo key is in the server-only config.lua).

MAILER = {
    COMMAND     = "mail",     -- unused since v_admin 3.0 (v_admin ADMIN.pageCommands)
    ADMIN_LEVEL = 5,          -- unused since v_admin 3.0 (v_admin ADMIN.perms.mail)
    SUBJECT_MAX = 150,        -- characters
    BODY_MAX    = 8000,       -- characters
    MAX_SELECTED = 5000,      -- account names one circular may list
    SIGNATURE   = "FreeV MTA:SA",
    TABLE       = "mails",    -- MySQL: every mail the server sent (or still has to send)
    HISTORY_PAGE  = 40,       -- /mail history: groups per page
    HISTORY_MAILS = 500,      -- /mail history: mails listed of one group
}

-- Weekly update mail (server/updates.lua): every Tuesday 11:00 UTC the news of
-- the last 7 days (v_news) + the running week (v_weekly) to every account with
-- an email, in its own language.
UPDATES = {
    INSTANCE_ID = 2,          -- only the v_main server instance with this id sends them
    WEEK_DAY    = 2,          -- 0 = Sunday ... 2 = Tuesday (UTC)
    HOUR        = 11,         -- UTC
    CATCH_UP    = 86400,      -- s: a run missed while the server was down is still made this long after
    NEWS_DAYS   = 7,          -- news of the last N days
    NEWS_MAX    = 10,         -- at most this many articles in one mail
    DAILY_LIMIT = 300,        -- update mails per 24 hours; the rest waits in the `mails` table
    CHECK_INTERVAL = 60000,   -- ms
    SETTING_KEY = "receiveUpdateMails", -- accData boolean, missing = true
}
