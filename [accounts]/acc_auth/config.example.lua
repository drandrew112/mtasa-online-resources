-- acc_auth configuration (SERVER ONLY - meta.xml type="server", never downloaded by clients).
-- Copy to config.lua and fill in BREVO_API_KEY. config.lua is gitignored (it holds the key).

AUTH = {
    LOGIN_MIN_INTERVAL    = 1000,       -- ms between two login attempts of one player
    LOGIN_FAIL_WINDOW     = 60,         -- s
    LOGIN_MAX_FAILS       = { serial = 5, ip = 15 }, -- ip is higher: shared/NAT addresses
    LOGIN_LOCK            = 60,         -- s, first lockout (doubles every time)
    LOGIN_LOCK_MAX        = 15 * 60,    -- s
    LOGIN_TIMEOUT         = 15000,      -- ms, give up on a lost DB answer
    REGISTER_MIN_INTERVAL = 3000,       -- ms between two registration attempts of one player
    REGISTER_TIMEOUT      = 15000,      -- ms
    PASSWORD_MIN          = 5,
    EMAIL_MAX             = 254,
    EMAIL_MIN_INTERVAL    = 2000,       -- ms between two email changes of one player
}

-- Forgotten password: the server makes a code and sends it straight through the
-- Brevo transactional email API. BREVO_API_KEY is a Brevo v3 API key
-- (Brevo > SMTP & API > API Keys, "xkeysib-..."), NOT the SMTP key.
-- SENDER_EMAIL must be a sender verified in Brevo.
RECOVERY = {
    BREVO_URL        = "https://api.brevo.com/v3/smtp/email",
    BREVO_API_KEY    = "CHANGE_ME",
    SENDER_EMAIL     = "noreply@freev-mtasa.online",
    SENDER_NAME      = "FreeV",
    TABLE            = "password_resets",
    CODE_LENGTH      = 6,
    CODE_CHARS       = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", -- no 0/O, 1/I
    CODE_TTL         = 15 * 60,  -- s
    MAX_ATTEMPTS     = 5,        -- wrong codes before the code is dropped
    SERIAL_INTERVAL  = 60,       -- s between two code requests of one machine
    SERIAL_PER_HOUR  = 5,
    ACCOUNT_PER_HOUR = 5,
    HTTP_TIMEOUT     = 10000,    -- ms
}
