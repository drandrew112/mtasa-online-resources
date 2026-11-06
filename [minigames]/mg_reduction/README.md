# mg_reduction

Closed fracture reduction (HK-S08). Hold the left mouse button and drag: down = traction, sideways = lateral shift; the mouse wheel turns the fragment, only under traction (>= 3 mm). Aligned (< 3 degrees, < 2 mm) under traction for 1 s = reduced. Every movement hurts: the pain meter fills fast without analgesia; when full the patient jerks and the fragment slips back (attempts).

One of the hospital minigames (`med_hospitals` ER treatments, work_hospital Minigames tab). The frame
(panel, countdown, timer, result, placing the player next to the patient, synced animation, server
sanity check) is the shared kit in `kit/`: an identical copy in mg_suture (master), mg_irrigation,
mg_cast, mg_reduction, mg_blooddraw, mg_fast, mg_chestdrain and mg_ecg. Change it in `mg_suture/kit/`
and copy it to the others.

## Server exports

```lua
local id = exports.mg_reduction:startReductionGame(player, ped, options) -- session id or false
exports.mg_reduction:stopReductionGame(player)      -- fires onReductionGameFinish with reason "cancelled"
exports.mg_reduction:isReductionGameActive(player)
```

- `ped` - optional patient: the player is placed next to it (standing at a stretcher / bed, kneeling
  at a patient on the ground; `options.stand` forces it) and the animation is synced
- `options` - { part = "" (label), analgesia = false, time = 60, passPercent = 50, stand = nil }

Result:

```lua
addEventHandler("onReductionGameFinish", root, function(success, percent, reason, sessionId, details)
    -- source = player; percent 0-100
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details: reduced (bool), angle, shift (mm, at the end), attempts
end)
```

## Client exports

Local-only game (practice), the server is not involved:

```lua
exports.mg_reduction:startReductionGame(ped, options)
exports.mg_reduction:stopReductionGame()
exports.mg_reduction:isReductionGameActive()
addEventHandler("onClientReductionGameFinish", localPlayer, function(success, percent, reason, sessionId, details) end)
```

## Test

`/reductiontest [0]` spawns a lying test ped in front of you and starts the game (`0`: without a ped).
