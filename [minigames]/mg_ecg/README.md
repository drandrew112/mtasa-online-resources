# mg_ecg

12-lead ECG electrode placement (HK-E01). Drag the ten electrodes from the tray onto the patient (front view: the patient's right is on the screen's left), then Record (button or ENTER). The preview draws lead I, II and V1-V6 live: swapped RA / LA = negative lead I, a misplaced V electrode = broken R progression. percent = correct electrodes x 10; success also needs RA / LA not swapped.

One of the hospital minigames (`med_hospitals` ER treatments, work_hospital Minigames tab). The frame
(panel, countdown, timer, result, placing the player next to the patient, synced animation, server
sanity check) is the shared kit in `kit/`: an identical copy in mg_suture (master), mg_irrigation,
mg_cast, mg_reduction, mg_blooddraw, mg_fast, mg_chestdrain and mg_ecg. Change it in `mg_suture/kit/`
and copy it to the others.

## Server exports

```lua
local id = exports.mg_ecg:startEcgGame(player, ped, options) -- session id or false
exports.mg_ecg:stopEcgGame(player)      -- fires onEcgGameFinish with reason "cancelled"
exports.mg_ecg:isEcgGameActive(player)
```

- `ped` - optional patient: the player is placed next to it (standing at a stretcher / bed, kneeling
  at a patient on the ground; `options.stand` forces it) and the animation is synced
- `options` - { time = 60, passPercent = 80, stand = nil, guide = false }
- `guide = true` (med_hospitals: Nurse / Resident): every target spot is drawn dashed with its label, and the
  spot of the electrode in hand pulses in its colour. Electrodes: radius 22 in the tray, 16 on the patient,
  bold labels with an outline (2026-11-06)

Result:

```lua
addEventHandler("onEcgGameFinish", root, function(success, percent, reason, sessionId, details)
    -- source = player; percent 0-100
    -- reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details: correct (0-10), swapRALA (bool), wrongLimb, wrongV, placed
end)
```

## Client exports

Local-only game (practice), the server is not involved:

```lua
exports.mg_ecg:startEcgGame(ped, options)
exports.mg_ecg:stopEcgGame()
exports.mg_ecg:isEcgGameActive()
addEventHandler("onClientEcgGameFinish", localPlayer, function(success, percent, reason, sessionId, details) end)
```

## Test

`/ecgtest [0]` spawns a lying test ped in front of you and starts the game (`0`: without a ped).
