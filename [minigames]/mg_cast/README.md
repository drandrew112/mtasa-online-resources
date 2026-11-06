# mg_cast

Plaster cast (HK-S09 / HK-S10). The mouse (left / right) sets the overlap of the next turn (green: 40-60 %), SPACE rolls it on when the rhythm dot is in the window. Three layers. Off rhythm = wrinkle, overlap < 28 % = gap, > 70 % = tight; 3 tight turns = too tight, redo (success = false).

One of the hospital minigames (`med_hospitals` ER treatments, work_hospital Minigames tab). The frame
(panel, countdown, timer, result, placing the player next to the patient, synced animation, server
sanity check) is the shared kit in `kit/`: an identical copy in mg_suture (master), mg_irrigation,
mg_cast, mg_reduction, mg_blooddraw, mg_fast, mg_chestdrain and mg_ecg. Change it in `mg_suture/kit/`
and copy it to the others.

## Server exports

```lua
local id = exports.mg_cast:startCastGame(player, ped, options) -- session id or false
exports.mg_cast:stopCastGame(player)      -- fires onCastGameFinish with reason "cancelled"
exports.mg_cast:isCastGameActive(player)
```

- `ped` - optional patient: the player is placed next to it (standing at a stretcher / bed, kneeling
  at a patient on the ground; `options.stand` forces it) and the animation is synced
- `options` - { part = "" (label), speed = 1 (rhythm, 0.6-1.8), time = 60, passPercent = 65, stand = nil }

Result:

```lua
addEventHandler("onCastGameFinish", root, function(success, percent, reason, sessionId, details)
    -- source = player; percent 0-100
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details: turns, wrinkles, gaps, tight, layers
end)
```

## Client exports

Local-only game (practice), the server is not involved:

```lua
exports.mg_cast:startCastGame(ped, options)
exports.mg_cast:stopCastGame()
exports.mg_cast:isCastGameActive()
addEventHandler("onClientCastGameFinish", localPlayer, function(success, percent, reason, sessionId, details) end)
```

## Test

`/casttest [0]` spawns a lying test ped in front of you and starts the game (`0`: without a ped).
