# mg_cpr

CPR rhythm minigame. The player presses **SPACE** to do chest compressions and has to keep the
rate between **90–130 per minute** for the given number of seconds. Every press is judged by the
time since the previous one (GOOD / TOO FAST / TOO SLOW); long pauses count as missed
compressions. The game is won when the accuracy is **at least 70%**.

If a ped is passed, the player is placed next to it (facing it), movement controls are locked and
the `MEDIC/CPR` animation loops for the whole game. Without a ped there is no animation.

## Server exports

```lua
local id = exports.mg_cpr:startCPRGame(player, duration, ped, options) -- session id or false
exports.mg_cpr:stopCPRGame(player)      -- fires onCPRGameFinish with reason "cancelled"
exports.mg_cpr:isCPRGameActive(player)
```

- `duration` – seconds of compressions, default `30` (clamped to 5–300); a 3 s countdown comes first
- `ped` – optional ped/player being resuscitated (`nil` = no positioning, no animation)
- `options` – optional `{ minBPM = 90, maxBPM = 130, passPercent = 70, guide = true }`
  (`guide` = pulsing rhythm helper on the HUD)

Result:

```lua
addEventHandler("onCPRGameFinish", root, function(success, good, total, percent, reason, sessionId, avgBPM)
    -- source = player
    -- total = judged compressions + missed ones
    -- reason: "completed" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
end)
```

The server plays the animation (synced to everyone), stops it when the game ends, and sanity
checks the client result (session id, play time, plausible counts).

## Client exports

Local-only game, the server is not involved (the animation is only visible to this client):

```lua
exports.mg_cpr:startCPRGame(duration, ped, options)
exports.mg_cpr:stopCPRGame()
exports.mg_cpr:isCPRGameActive()

addEventHandler("onClientCPRGameFinish", localPlayer, function(success, good, total, percent, reason, sessionId, avgBPM) end)
```

`onClientCPRGameFinish` also fires for server-started games (with `sessionId` set).

## Config

`shared.lua` → `CPR` (BPM range, pass percent, key, countdown, animation, placement offsets).
`/cprtest [seconds] [0]` spawns a lying test ped in front of you and starts the game (pass `0` as
the second argument to play without a ped). Enabled while `CPR.TEST_COMMAND = true` – turn it off
in production.
