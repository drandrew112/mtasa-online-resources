# mg_intravenous

IV cannulation minigame. The screen shows the forearm from above (with a tourniquet and the vein
under the skin) and a cross-section along the needle. The procedure has three steps:

1. **Aim** – move the mouse to put the needle over the vein. The hand trembles a little, so the
   puncture point drifts. Press **LMB** to puncture the skin.
2. **Advance** – hold **LMB** to push the needle deeper (it starts slow, so short taps give finer
   control). When the tip enters the vein, blood appears in the flashback chamber. Release once the
   cannula tip is inside the vein too (≈1 mm deeper than the first flashback).
   Pushing through the back wall of the vein = *through*, reaching max depth without hitting it = *missed*.
3. **Withdraw** – hold **LMB** and drag the mouse **left** to pull the needle out. Only the silicone
   cannula stays in the vein. Pulling too fast raises the *cannula strain* bar; when it fills up the
   cannula comes out (*dislodged*).

The aim decides how thick the vein is in the cross-section (off-centre = thinner target). A mistake
costs an attempt; the game fails when all attempts are used or the time runs out. A successful game
also returns a 0–100 quality score (how centred, how well placed in depth, how gently withdrawn).

If a ped is passed, the player is placed next to it, controls are locked and a kneeling animation
loops for the whole game.

## Server exports

```lua
local id = exports.mg_intravenous:startIVGame(player, ped, options) -- session id or false
exports.mg_intravenous:stopIVGame(player)      -- fires onIVGameFinish with reason "cancelled"
exports.mg_intravenous:isIVGameActive(player)
```

- `ped` – optional ped/player being treated (`nil` = no positioning, no animation)
- `options` – optional `{ difficulty = 2, time = 45, attempts = 2, showDepth = true }`
  - `difficulty` 1–3: vein size, hand tremor, push speed and safe withdraw speed
  - `time` – seconds for the whole procedure (10–300), a 3 s countdown comes first
  - `attempts` – punctures allowed (1–5)
  - `showDepth = false` hides the vein in the cross-section, only the flashback tells you're in

Result:

```lua
addEventHandler("onIVGameFinish", root, function(success, attempts, quality, reason, sessionId)
    -- source = player
    -- attempts = punctures used, quality = 0-100 (0 on failure)
    -- reason: "completed" | "missed" | "through" | "dislodged" | "expired"
    --       | "cancelled" | "died" | "quit" | "timeout" | "invalid"
end)
```

The server plays the animation (synced to everyone), stops it when the game ends, and sanity
checks the client result (session id, reason, attempt count, quality range, play time).

## Client exports

Local-only game, the server is not involved (the animation is only visible to this client):

```lua
exports.mg_intravenous:startIVGame(ped, options)
exports.mg_intravenous:stopIVGame()
exports.mg_intravenous:isIVGameActive()

addEventHandler("onClientIVGameFinish", localPlayer, function(success, attempts, quality, reason, sessionId) end)
```

`onClientIVGameFinish` also fires for server-started games (with `sessionId` set).

## Config

`shared.lua` → `IV` (difficulty presets, vein depth range, needle angle/length, timings, animation,
placement offsets). `/ivtest [difficulty] [0]` spawns a lying test ped in front of you and starts the
game (pass `0` as the second argument to play without a ped). Enabled while `IV.TEST_COMMAND = true`
– turn it off in production.
