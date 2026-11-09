# v_voiceclient_connector – voice radio gateway

The external voice client turns the player's speech into text and sends it here over MTA HTTP.
The connector checks the player, lets **ai_llm** pick one radio code of the player's work and runs
it through the work's resource exactly as the tablet / radio button would. The player always gets
a **ui_core subtitle** about the outcome.

```
voice client --HTTP--> voiceRadio(token, account, work, text)
   -> v_accounts token check, player online, work_core work on duty + supported
   -> ai_llm request (code list as context, response schema enum = allowed codes only)
   -> onAiLlmResponse
        RADIO code  -> exports.<resource>:radioCommand(player, id, args) -> "… - sent" / "… - failed: reason"
        Q_ code     -> question subtitle (the message was not specific enough)
        RAD_ERROR_  -> error subtitle
```

## HTTP API (for the voice client)

Every call: `POST http://<server>:<httpport>/<resource>/call/<function>`, body = JSON array of
the arguments, answer = JSON array with one object. Guests need `general.http` in the Default ACL
(like med_web).

1. Login (v_accounts): `webLogin(username, password, clientName)` ->
   `{ ok, token, account, displayName, expiresIn }`. `webCheck(token)`, `webLogout(token)`.
   The session ends after 12 h without calls (7 days at most), on a new password and on a ban.
2. Status: `voiceStatus(token)` -> `{ ok, account, online, work, onDuty, supported, ready, codes = { { id, label } } }`
3. Radio message: `voiceRadio(token, account, work, text)` ->
   `{ ok = true, requestId, status = "processing", work }` or `{ ok = false, error }`.
   `account` / `work` must match the token's account and the player's current work (`ems`, `police`).
   Empty `text` = no recognisable speech (subtitle, `error = "no_speech"`).
4. Result (optional polling, kept 2 min): `voiceResult(token, requestId)` ->
   `{ ok, status = "processing" | "done", kind = "success" | "failed" | "question" | "error", code, text, heard }`
5. Player state (web_api): `playerState(token)` -> position, rotation, vehicle, work, … (see web_api/server/players.lua)

Errors of voiceRadio: `unauthorized`, `flood`, `account_mismatch`, `offline`, `not_on_duty`,
`work_not_supported`, `work_mismatch`, `work_unavailable`, `no_speech`, `busy`, `cooldown`, `ai_offline`,
`ai_error` (+ `aiError`).

**AI errors**: when ai_llm fails (refused at once or later in `onAiLlmResponse`), the result is
`kind = "ai_error"`, `code = "RAD_ERROR_UNKNOWN"`, `aiError` = the ai_llm error kind, and the player
gets its own subtitle (`v_voiceclient_connector.ai.<kind>`): `overloaded` (429 / 503 / queue full),
`timeout`, `network`, `not_configured`, `auth`, `blocked`, `invalid_answer`, `cooldown`, `error`.

## Code database (server/codes.lua)

Per work: target resource, radio codes (id = the target's name id, description + example phrases
for the AI, `args.note = "required"` for free-text reasons), Q_ question codes with their subtitle
text. RAD_ERROR codes are common: `RAD_ERROR_NOT_FOUND` (no such request), `RAD_ERROR_UNPARSEABLE`
(not understandable), `RAD_ERROR_UNKNOWN` (anything else, also AI failures / invalid answers).

At start (and when a target resource starts) the connector asks the target's `getRadioCodes()`;
codes the target does not know are left out of the AI prompt.

| work | resource | codes |
|---|---|---|
| ems | med_erm (server/radio.lua) | BACKUP_AMBULANCE/BLS/ALS/DOC/HELI/SOLO, AGENCY_POLICE_SECURITY/TRAFFIC/VIOLENT/CRIME/DEATH/OTHER (+note) |
| police | police_system (existing radio messages) | STATUS_AVAILABLE/RESPONDING/BUSY/PURSUIT, CODE_4, REQUEST_BACKUP/AMBULANCE/TOW/TRANSPORT, QUERY_PERSON/VEHICLE |

A new work: add an entry to `Codes.WORKS`, give the work's resource `radioCommand(player, id, args)`
(-> true | false, errorText) and `getRadioCodes()` exports, add the Q_ texts to the locale files.

## Testing

`/voicetest <text>` (admin level 5): sends the text as if the voice client did (no token).
Server export `submitRadioText(player, text)` does the same for scripts.
