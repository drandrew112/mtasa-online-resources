-- v_voiceclient_connector / config.lua (server)

VC = VC or {}

VC.CONFIG = {
    -- longest accepted speech-to-text text (characters)
    MAX_TEXT = 400,
    -- one radio message per player at a time; minimum gap between two accepted messages (ms)
    PLAYER_COOLDOWN = 1500,
    -- HTTP calls of one address within 10 s (voiceRadio / voiceResult / voiceStatus)
    HTTP_FLOOD_MAX = 40,
    -- results kept for voiceResult polling (ms)
    RESULT_KEEP = 120000,

    -- AI (ai_llm)
    AI_TEMPERATURE = 0.0,
    AI_MAX_TOKENS = 120,

    -- subtitle durations (ms)
    SUB_HEARD = 3000,       -- the recognised text while the AI works
    SUB_RESULT = 4500,      -- success / failure / error
    SUB_QUESTION = 6500,    -- Q_ codes

    -- subtitle colours (colour codes)
    COLOR_TAG = "#7FD6FF",
    COLOR_OK = "#7CFF9A",
    COLOR_FAIL = "#FF7A7A",
    COLOR_QUESTION = "#FFD866",
    COLOR_TEXT = "#FFFFFF",

    DEBUG = false,
}

-- FreeV VoiceServer (real time radio over Cloudflare Realtime). This file is server only
-- (meta.xml type="server"): KEY is the VoiceServer's INTEGRATION_KEY and never goes to a client.
-- Every call is an OUTGOING HTTPS request (fetchRemote): no new port on the MTA server.
VC.VOICESERVER = {
    URL = "https://andrashevesy.eu/tools/freev_voiceserver",  -- base URL, no trailing slash
    KEY = "ada92f8f4a507fb74d36b5af5dfec776074cd58ee684d6c2b19cd5af6a68d2ec",  -- INTEGRATION_KEY of the VoiceServer .env
    SYNC_MS = 1000,                   -- player state push + active speaker pull
    TIMEOUT_MS = 5000,
    OFFLINE_AFTER = 3,                -- failed syncs in a row -> onVoiceServerOffline

    -- radio frequencies: whole numbers FREQ_MIN..FREQ_MAX; work on duty (work_core id) -> frequency
    FREQ_MIN = 100,
    FREQ_MAX = 499,
    FREQ = { ems = 140, police = 170 },
    UNIT_TAG = { ems = "EMS", police = "PD" },   -- callsign prefix ("EMS M-12")
    ASSIGN_MS = 2000,                 -- safety poll of the duty / unit state (events do the rest)

    SPEAKER_HOLD_MS = 2500,           -- the last speaker stays on the radar this long (old v_voice value)

    -- in-game listener: MTA CEF browser that plays the radio (listen only)
    CEF = {
        ENABLED = true,
        VOLUME = 1.0,
    },
}

VC.SYSTEM = [[
You are the radio code classifier of an emergency services roleplay game.
The input is the speech-to-text transcript of one radio message of a player (Hungarian or English,
may contain recognition errors). Map it to exactly ONE code of the code list.

Rules:
- You may ONLY answer with a code from the list (RADIO CODES, QUESTION CODES, ERROR CODES). Never invent a code.
- Pick a RADIO CODE only when the message clearly and completely asks for it.
- If the message is a request of this work but a needed detail is missing or ambiguous, pick the matching QUESTION CODE.
- If you find a problem, pick an ERROR CODE: RAD_ERROR_NOT_FOUND (a request with no matching code),
  RAD_ERROR_UNPARSEABLE (not understandable), RAD_ERROR_UNKNOWN (anything else).
- "note": only for codes marked [needs note]: the reason in the speaker's own words, short (max 120 characters). Otherwise an empty string.
- Answer with the JSON object only: {"code": "<CODE>", "note": "<text or empty>"}.
]]
