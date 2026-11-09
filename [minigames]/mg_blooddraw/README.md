# mg_blooddraw

Venous blood sampling (HK-L01). T = tourniquet, hold the left mouse button on the arm to palpate the vein, mouse wheel = needle angle (10-40 degrees), click on the vein, click a tube in the rack to attach it, hold SPACE to fill it to the mark, T to release the tourniquet. The rack shows the needed tubes in a random order: order of draw citrate, serum, heparin, EDTA, fluoride. Mistakes: hemolysis (tourniquet > 60 s or 2+ punctures), EDTA contamination (EDTA before a needed citrate / serum / heparin tube), underfilled citrate.

One of the hospital minigames (`med_hospitals` ER treatments, work_hospital Minigames tab). The frame
(panel, countdown, timer, result, placing the player next to the patient, synced animation, server
sanity check) is the shared kit in `kit/`: an identical copy in mg_suture (master), mg_irrigation,
mg_cast, mg_reduction, mg_blooddraw, mg_fast, mg_chestdrain and mg_ecg. Change it in `mg_suture/kit/`
and copy it to the others.

## Server exports

```lua
local id = exports.mg_blooddraw:startBloodDrawGame(player, ped, options) -- session id or false
exports.mg_blooddraw:stopBloodDrawGame(player)      -- fires onBloodDrawGameFinish with reason "cancelled"
exports.mg_blooddraw:isBloodDrawGameActive(player)
```

- `ped` - optional patient: the player is placed next to it (standing at a stretcher / bed, kneeling
  at a patient on the ground; `options.stand` forces it) and the animation is synced
- `options` - { tubes = { "citrate", "serum", "heparin", "edta", "fluoride" } (subset, default all), time = 60, passPercent = 60, stand = nil }

Result:

```lua
addEventHandler("onBloodDrawGameFinish", root, function(success, percent, reason, sessionId, details)
    -- source = player; percent 0-100
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details: hemolysis, edta, citrate (underfilled) (bools), attempts, tubes, filled, tourniquet (s)
end)
```

## Client exports

Local-only game (practice), the server is not involved:

```lua
exports.mg_blooddraw:startBloodDrawGame(ped, options)
exports.mg_blooddraw:stopBloodDrawGame()
exports.mg_blooddraw:isBloodDrawGameActive()
addEventHandler("onClientBloodDrawGameFinish", localPlayer, function(success, percent, reason, sessionId, details) end)
```

## Test

`/blooddrawtest [0]` spawns a lying test ped in front of you and starts the game (`0`: without a ped).
