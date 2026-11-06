# mg_suture

Wound suturing (HK-S04 / HK-S05). Press the left mouse button on one wound edge, drag the needle across and release on the other edge. The dashed circles show the ideal bites of the next stitch. Scored: bite depth (3-6 mm), the same depth on both sides, a straight crossing, even spacing along the wound. `tremor` shakes the scene (no local anaesthesia).

One of the hospital minigames (`med_hospitals` ER treatments, work_hospital Minigames tab). The frame
(panel, countdown, timer, result, placing the player next to the patient, synced animation, server
sanity check) is the shared kit in `kit/`: an identical copy in mg_suture (master), mg_irrigation,
mg_cast, mg_reduction, mg_blooddraw, mg_fast, mg_chestdrain and mg_ecg. Change it in `mg_suture/kit/`
and copy it to the others.

## Server exports

```lua
local id = exports.mg_suture:startSutureGame(player, ped, options) -- session id or false
exports.mg_suture:stopSutureGame(player)      -- fires onSutureGameFinish with reason "cancelled"
exports.mg_suture:isSutureGameActive(player)
```

- `ped` - optional patient: the player is placed next to it (standing at a stretcher / bed, kneeling
  at a patient on the ground; `options.stand` forces it) and the animation is synced
- `options` - { length = 4 (cm), stitches = length / 6.5 mm (3-10), part = "" (label), time = 45, passPercent = 60, tremor = 0-1, stand = nil }

Result:

```lua
addEventHandler("onSutureGameFinish", root, function(success, percent, reason, sessionId, details)
    -- source = player; percent 0-100
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details: stitches, placed, misses, depth (0-100), spacing (0-100), angle (0-100)
end)
```

## Client exports

Local-only game (practice), the server is not involved:

```lua
exports.mg_suture:startSutureGame(ped, options)
exports.mg_suture:stopSutureGame()
exports.mg_suture:isSutureGameActive()
addEventHandler("onClientSutureGameFinish", localPlayer, function(success, percent, reason, sessionId, details) end)
```

## Test

`/suturetest [0]` spawns a lying test ped in front of you and starts the game (`0`: without a ped).
