# mg_chestdrain

Chest drain (HK-R08). 1 click the safe triangle (5th intercostal space, mid-axillary line; the pectoralis / latissimus borders and the nipple line are drawn, the triangle is not), 2 hold on the site (local anaesthesia), 3 drag the incision just above the upper edge of the lower rib, 4 blunt dissection: click when the shrinking ring meets the target (5x), 5 hold and push the tube along the arrow, 6 SPACE: fixation + suction. Mistakes: wrong spot, cut under the upper rib (vessel), mistimed dissection, kinked tube.

One of the hospital minigames (`med_hospitals` ER treatments, work_hospital Minigames tab). The frame
(panel, countdown, timer, result, placing the player next to the patient, synced animation, server
sanity check) is the shared kit in `kit/`: an identical copy in mg_suture (master), mg_irrigation,
mg_cast, mg_reduction, mg_blooddraw, mg_fast, mg_chestdrain and mg_ecg. Change it in `mg_suture/kit/`
and copy it to the others.

## Server exports

```lua
local id = exports.mg_chestdrain:startChestDrainGame(player, ped, options) -- session id or false
exports.mg_chestdrain:stopChestDrainGame(player)      -- fires onChestDrainGameFinish with reason "cancelled"
exports.mg_chestdrain:isChestDrainGameActive(player)
```

- `ped` - optional patient: the player is placed next to it (standing at a stretcher / bed, kneeling
  at a patient on the ground; `options.stand` forces it) and the animation is synced
- `options` - { side = "right" | "left", time = 75, passPercent = 60, stand = nil }

Result:

```lua
addEventHandler("onChestDrainGameFinish", root, function(success, percent, reason, sessionId, details)
    -- source = player; percent 0-100
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details: wrongSpot, vessel, kink (bools), mistimed, steps (6 = all done)
end)
```

## Client exports

Local-only game (practice), the server is not involved:

```lua
exports.mg_chestdrain:startChestDrainGame(ped, options)
exports.mg_chestdrain:stopChestDrainGame()
exports.mg_chestdrain:isChestDrainGameActive()
addEventHandler("onClientChestDrainGameFinish", localPlayer, function(success, percent, reason, sessionId, details) end)
```

## Test

`/chestdraintest [0]` spawns a lying test ped in front of you and starts the game (`0`: without a ped).
