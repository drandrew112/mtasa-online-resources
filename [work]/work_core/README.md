# work_core

The core of the work system. It stores **no works by default**. Every work, such as `work_ems`,
is a separate resource that registers itself through the exports. work_core handles the parts
that all works share:

- **registry**: works with an id, a name, a colour and their outfits (skins)
- **duty markers**: go on duty with an outfit selector, change outfit, go off duty
- **duty vehicle markers** (optional): request or return a work vehicle
- **one work at a time**: a player on duty in a work cannot go on duty in another
- **queries**: which players are doing a given work, so a work script can create elements that
  only those players see
- **work levels**: every work has its own level and XP per account (levels gate outfits and
  rights such as future `work_atc` positions)
- **payments**: `payWork()` pays an itemised amount into the player's bank account and shows a
  timed receipt; every work computes its own amounts, work_core only pays and displays

"Having a work" and "being on duty" mean the same thing here. A player has a work while on duty
in it, and has none after going off duty.

## Usage from a work resource

```lua
-- meta.xml:  <include resource="work_core" />

local function setup()
    exports.work_core:registerWork("ems", {
        name = "EMS",
        description = "Emergency Medical Services",
        color = { 220, 50, 50 },
        skins = { 274, 275, { model = 276, name = "Doctor" } },  -- at least one
    })

    exports.work_core:createDutyMarker("ems", 1172.5, -1323.4, 14.4, { blip = 22 })

    exports.work_core:createDutyVehicleMarker("ems", 1180.0, -1338.0, 12.6,
        { { model = 416, name = "Ambulance", plate = "EMS", color = { 255, 255, 255, 220, 50, 50 } } },
        { spawns = { { 1178.0, -1308.0, 14.0, 270 }, { 1178.0, -1314.0, 14.0, 270 } } })
end
addEventHandler("onResourceStart", resourceRoot, setup)
addEventHandler("onWorkCoreStart", root, setup)     -- after a work_core restart

addEventHandler("onPlayerWorkDutyStart", root, function(workId, skin)
    if workId ~= "ems" then return end
    -- source = the player
end)

-- Pay the player: each work computes its own amounts, work_core only deposits the total and
-- shows the itemised receipt.
exports.work_core:payWork(player, "ems", {
    { label = "Base pay",        amount = 150 },
    { label = "Distance bonus",  amount = 40 },
    { label = "Equipment fee",   amount = -20 },
}, "Call finished")
```

When the resource that registered a work stops, the work is unregistered automatically. Its
markers are destroyed, and everyone on duty in it goes off duty with reason `"unregistered"`.
Marker positions are at **ground level**. `/workpos` (admin level `WORK.ADMIN_LEVEL`) prints and
copies the position: on foot it gives the ground-level marker point, and in a vehicle it gives a
spawn point `{ x, y, z, rot }`.

## Server exports

| export | description |
|---|---|
| `registerWork(id, def)` → bool | `def`: `name`, `description`, `color {r,g,b}`, `skins` (model ids or `{ model, name }`). Registering again from the same resource updates the work. |
| `unregisterWork(id)` → bool | |
| `isWorkRegistered(id)`, `getWork(id)`, `getWorks()` | copies of the definitions (`resource` = owner) |
| `createDutyMarker(workId, x, y, z [, opts])` → marker | `opts`: `size`, `color {r,g,b[,a]}`, `interior`, `dimension`, `blip` (icon id; `false` or omitted = no blip), `blipDistance` |
| `createDutyVehicleMarker(workId, x, y, z, vehicles [, opts])` → marker | `vehicles`: model ids or `{ model, name, color = {setVehicleColor args}, plate, platePrefix, plateDigits, data = {elementData} }`. `platePrefix` (e.g. `"A-"`) gives every spawned vehicle a unique plate of the prefix and random digits (`plateDigits`, default: up to 8 characters); it overrides `plate`. `opts`: the duty marker opts plus `spawns` (one point or a list of `{x,y,z,rot}`; the first free one is used; the default is the marker itself), `rotation`, and `public` (by default only players on duty in the work see it) |
| `destroyWorkMarker(marker)`, `getWorkMarkers([workId])` | |
| `getPlayerWork(player)` → id \| false | |
| `isPlayerOnDuty(player [, workId])` → bool | |
| `getWorkPlayers(workId)` → { players } | |
| `getPlayerWorkSkin(player)` | |
| `setPlayerOnDuty(player, workId [, skin])` → bool, err | without a marker (the request event still runs) |
| `setPlayerOffDuty(player)` / `setPlayerWorkSkin(player, skin)` | |
| `setElementVisibleToWork(element, workId \| false)` | marker / blip / radar area visible **only to players on duty in the work**. It stays in sync as players go on and off duty, and new players do not see it. |
| `getPlayerWorkVehicle(player)`, `destroyPlayerWorkVehicle(player)` | |
| `getVehicleWork(vehicle)`, `getWorkVehicleOwner(vehicle)` | |
| `payWork(player, workId, items [, reason])` → `true, total` \| `false, err` | `items`: `{ { label, amount }, ... }`, shown on the receipt in this order. The positive total is deposited via `exports.v_bank:giveBankMoney` (fails if `v_bank` is not running); a total `<= 0` is not paid but the receipt is still shown. `reason`: optional text shown under the total. `workId` only needs to resolve a name/colour for the receipt — it does not have to be the player's current work. |

## Work levels

Each account has separate XP and a level for every work (levels start at 1). XP for level n+1 is
`levelXp + (n - 1) * levelStep` (defaults `WORK.LEVEL_BASE_XP` 500, `WORK.LEVEL_STEP_XP` 250, max
`WORK.MAX_LEVEL` 20). A work can override these in `registerWork`:

```lua
exports.work_core:registerWork("atc", {
    name = "ATC", skins = { 17, { model = 20, name = "Supervisor", level = 5 } },  -- outfit unlocks at level 5
    maxLevel = 10, levelXp = 400, levelStep = 200,
    levelNames = { [1] = "Trainee", [3] = "Ground", [6] = "Tower", [9] = "Approach" },
})
exports.work_core:giveWorkXp(player, "atc", 40)             -- after a job
if exports.work_core:hasWorkLevel(player, "atc", 6) then end  -- gate rights, e.g. in onPlayerWorkDutyRequest
```

Progress is saved as JSON in the account data key `work.levels` (v_mysql), loaded on
`onPlayerLoaded`. Only logged in players have progress. Admin commands (level `WORK.ADMIN_LEVEL`):
`/giveworkxp <player> <workId> <xp>`, `/setworklevel <player> <workId> <level>`.

| server export | description |
|---|---|
| `giveWorkXp(player, workId, amount)` → `true, level` \| `false, err` | positive amounts only; shows "+XP" and "Level up!" notifications |
| `getPlayerWorkLevel(player, workId)`, `getPlayerWorkXp(player, workId)` | level is 1 without progress |
| `hasWorkLevel(player, workId, level)` → bool | use this for rights |
| `getPlayerWorkLevelName(player, workId)` | name of the highest named level reached, or `false` |
| `getWorkLevelInfo(player, workId)` | `{ level, xp, from, to, maxLevel, name }` (`to` = false at max level) |
| `getWorkLevelXp(workId, level)` | total XP needed to reach a level |
| `setPlayerWorkXp(player, workId, xp)`, `setPlayerWorkLevel(player, workId, level)` | can lower; no notification |

Events: `onPlayerWorkXpGain (workId, amount, totalXp)`, `onPlayerWorkLevelChange (workId, newLevel, oldLevel)`.
Client: `getPlayerWorkLevel`, `getPlayerWorkXp`, `getPlayerWorkLevelName`, `hasWorkLevel` (read the
synced `work.levels` element data).

## Server events (source = player, unless noted otherwise)

| event | args |
|---|---|
| `onPlayerWorkDutyRequest` | `workId`. Cancellable: `cancelEvent(true, "reason")` refuses the request, and the player is shown the reason. |
| `onPlayerWorkDutyStart` | `workId, skin` |
| `onPlayerWorkSkinChange` | `workId, skin` |
| `onPlayerWorkDutyEnd` | `workId, reason`: `"player"`, `"script"`, `"quit"`, `"unregistered"` or `"shutdown"` |
| `onWorkVehicleSpawn` | source = the vehicle. Args: `player, workId, model`. Use it for liveries, sirens, or unit registration. |
| `onPlayerWorkPaid` | `workId, total, items, reason`. Fired after a successful `payWork()` (whether or not anything was actually transferred). |
| `onWorkCoreStart` | source = root. Fired when work_core starts, so work resources can register again. |

## Client exports and events

`getPlayerWork(player)`, `isPlayerOnDuty(player [, workId])`, `getWorkPlayers(workId)`,
`getWork(id)`, `getWorks()`, `getVehicleWork(vehicle)`. These read the synced `work.id` element
data. `onClientPlayerWorkChange(newWorkId | false, oldWorkId | false)`, where source = the player.

## Behaviour

- **Duty marker** (E): opens the outfit list as a ui_inac temp menu, and the hovered outfit is
  previewed on the player locally. Selecting an outfit puts the player on duty. While on duty,
  the menu offers *Change outfit* (when the work has more than one) and *Go off duty*. A player
  on duty in another work only gets a notification.
- Going on duty saves the civilian skin (`work.civilSkin`, server-only data). Going off duty, or
  quitting, restores it. `v_accounts` `save_all` saves this civilian skin, so the outfit is never
  saved as the player's skin. After a respawn the outfit is put back on.
- **Vehicle marker** (E): on foot, it shows the vehicle list. The player gets **one** work vehicle,
  and a new request replaces the old one, unless someone else is still in the old one. The driver
  of their own work vehicle can return it at the marker. Only players on duty in the work can
  drive a work vehicle, and passengers are not restricted. The vehicle is removed when its player
  goes off duty or quits, and `EXPLODED_CLEANUP` ms after it explodes.
- Every client request is validated by the server: the player is at the marker, the outfit or
  vehicle belongs to the work, and there is a cooldown. Clients cannot set the `work.*` element
  data; the server reverts any attempt.
- **Payment receipt**: itemised list + total, fades in, stays for `WORK.PAYMENT_DURATION` (a
  shrinking bar under the card shows the time left), then fades out on its own. Pressing ENTER
  skips straight to the next queued receipt. Only one is shown at a time; further `payWork()`
  calls for the same player queue up and show one after another.
- Settings are in `shared/config.lua`. UI text is in English.
