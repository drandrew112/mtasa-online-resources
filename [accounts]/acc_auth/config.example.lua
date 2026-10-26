-- acc_auth configuration (SERVER ONLY - meta.xml type="server", never downloaded by clients).
-- Copy to config.lua. config.lua is gitignored.

AUTH = {
    LOGIN_MIN_INTERVAL    = 1000,       -- ms between two login attempts of one player
    LOGIN_FAIL_WINDOW     = 60,         -- s
    LOGIN_MAX_FAILS       = { serial = 5, ip = 15 }, -- ip is higher: shared/NAT addresses
    LOGIN_LOCK            = 60,         -- s, first lockout (doubles every time)
    LOGIN_LOCK_MAX        = 15 * 60,    -- s
    LOGIN_TIMEOUT         = 15000,      -- ms, give up on a lost DB answer
    ONLINE_CHECK          = true,       -- refuse a login while the account is online on another server instance
    ONLINE_TABLE          = "online_players", -- kept by v_admin (server/instance.lua) on every instance
    ONLINE_STALE          = 120,        -- s: rows not refreshed for this long = crashed server, ignored
    REGISTER_MIN_INTERVAL = 3000,       -- ms between two registration attempts of one player
    REGISTER_TIMEOUT      = 15000,      -- ms
    POOL_SIZE             = 2,          -- reserved `accounts` rows per server instance (0-2, server/pool.lua): no id gaps
    PASSWORD_MIN          = 5,
    EMAIL_MAX             = 254,
    EMAIL_MIN_INTERVAL    = 2000,       -- ms between two email changes of one player
}

-- Forgotten password: the server makes a code and sends it by email through
-- v_mail (the Brevo API key lives in v_mail/config.lua).
RECOVERY = {
    TABLE            = "password_resets",
    CODE_LENGTH      = 6,
    CODE_CHARS       = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", -- no 0/O, 1/I
    CODE_TTL         = 15 * 60,  -- s
    ADMIN_CODE_TTL   = 24 * 3600, -- s; a code an admin mailed (v_admin Accounts page); 24 h when missing
    MAX_ATTEMPTS     = 5,        -- wrong codes before the code is dropped
    SERIAL_INTERVAL  = 60,       -- s between two code requests of one machine
    SERIAL_PER_HOUR  = 5,
    ACCOUNT_PER_HOUR = 5,
}
