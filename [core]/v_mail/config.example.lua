-- v_mail configuration (SERVER ONLY - meta.xml type="server", never downloaded by clients).
-- Copy to config.lua and fill in BREVO_API_KEY. config.lua is gitignored (it holds the key).

-- Mails go straight through the Brevo transactional email API. BREVO_API_KEY is
-- a Brevo v3 API key (Brevo > SMTP & API > API Keys, "xkeysib-..."), NOT the SMTP key.
-- SENDER_EMAIL must be a sender verified in Brevo.
MAIL = {
    BREVO_URL     = "https://api.brevo.com/v3/smtp/email",
    BREVO_API_KEY = "CHANGE_ME",
    SENDER_EMAIL  = "noreply@freev-mtasa.online",
    SENDER_NAME   = "FreeV",
    HTTP_TIMEOUT  = 10000,  -- ms
    -- Every mail goes through one queue: one request every SEND_INTERVAL ms, at
    -- most MAX_IN_FLIGHT unanswered at a time. Single mails (password reset)
    -- jump ahead of a running circular.
    SEND_INTERVAL = 250,    -- ms
    MAX_IN_FLIGHT = 4,
    MAX_QUEUE     = 5000,   -- mails waiting; more is refused (a runaway caller must not burn the Brevo quota)
}
