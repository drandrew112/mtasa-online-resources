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
