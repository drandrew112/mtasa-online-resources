# mg_fast

FAST / eFAST ultrasound (HK-K20 / HK-K21). Hold the left mouse button to put the probe on the torso, move it into a window (dashed circle), tilt it with the mouse wheel until the live picture clears, keep it there for 3 s. Windows: RUQ, LUQ, pelvis, subxiphoid (eFAST: + both lungs). Windows not read in time are "na" (not evaluable). The pos / neg result comes from options.positives.

One of the hospital minigames (`med_hospitals` ER treatments, work_hospital Minigames tab). The frame
(panel, countdown, timer, result, placing the player next to the patient, synced animation, server
sanity check) is the shared kit in `kit/`: an identical copy in mg_suture (master), mg_irrigation,
mg_cast, mg_reduction, mg_blooddraw, mg_fast, mg_chestdrain and mg_ecg. Change it in `mg_suture/kit/`
and copy it to the others.

## Server exports

```lua
local id = exports.mg_fast:startFastGame(player, ped, options) -- session id or false
exports.mg_fast:stopFastGame(player)      -- fires onFastGameFinish with reason "cancelled"
exports.mg_fast:isFastGameActive(player)
```

- `ped` - optional patient: the player is placed next to it (standing at a stretcher / bed, kneeling
  at a patient on the ground; `options.stand` forces it) and the animation is synced
- `options` - { efast = false, positives = { ruq = true, luq = false, pelvis, cardiac, lung_r, lung_l }, time = 50 (efast 70), passPercent = 75, stand = nil }

Result:

```lua
addEventHandler("onFastGameFinish", root, function(success, percent, reason, sessionId, details)
    -- source = player; percent 0-100
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details: windows = { ruq = "pos" | "neg" | "na", ... }, evaluated, total
end)
```

## Client exports

Local-only game (practice), the server is not involved:

```lua
exports.mg_fast:startFastGame(ped, options)
exports.mg_fast:stopFastGame()
exports.mg_fast:isFastGameActive()
addEventHandler("onClientFastGameFinish", localPlayer, function(success, percent, reason, sessionId, details) end)
```

## Test

`/fasttest [0]` spawns a lying test ped in front of you and starts the game (`0`: without a ped).
