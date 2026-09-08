# v_ownveh

Per-account **personal vehicles**. Owns one SQLite database, `vehicles.db`, that
holds every player-owned vehicle and everything about it except health. Other
resources (a dealership, a sell menu, the phone's *MyVeh* app) drive it through
the exports – this resource never touches money.

## What is stored

One row per vehicle in `vehicles.db` → table `vehicles`:

| Column | Notes |
| --- | --- |
| `id` | Auto-increment. The vehicle's permanent id, used by every export. |
| `account_name` | Owner. |
| `model` | Vehicle model id. |
| `colors` | `"r,g,b,r,g,b,…"` – every value `getVehicleColor(veh, true)` returns. |
| `paintjob` | `getVehiclePaintjob`. |
| `upgrades` | `"id,id,id"` – `getVehicleUpgrades`. |
| `handling` | JSON, **only** the properties that differ from the model's stock handling. |
| `plate` | Number plate text. |
| `isDestroyed` | `0/1`. When `1` the vehicle **cannot be summoned** until it is unlocked. |
| `created_at` / `updated_at` | Unix timestamps. |

**Health is never saved.** A wrecked vehicle instead gets `isDestroyed = 1`.

For fast lookups the owner's account data carries the id list:

```lua
getAccountData(account, "owned_vehicle_ids")  -- "1,2,3"
```

v_ownveh rebuilds this string on every `giveVehicle` / `deleteVehicle`.

## Exports (server)

All exports return `false, "<errorCode>"` on failure.

| Export | Purpose |
| --- | --- |
| `giveVehicle(who, model [, data])` | Register a new vehicle. `who` = player or account-name. `data` (optional) = `{ colors, paintjob, upgrades, handling, plate }` in the stored/serialised form. → `id`. **No money is deducted** – the calling script does that. |
| `deleteVehicle(id)` | Sale or plain delete. Row is removed; if the vehicle is currently summoned it is despawned too. → `true`. |
| `spawnOwnedVehicle(player, id)` | Summon the vehicle (placement rules below), apply its stored state, attach a blip. → `vehicle`. Errors: `not_owner`, `destroyed`, `already_spawned`, `no_free_spawnpoint`, … |
| `storeVehicle(id)` | Save the summoned vehicle's live state and remove it from the world. Refused while occupied. → `true`. |
| `setVehicleDestroyed(id, bool)` | Set/clear `isDestroyed`. `setVehicleDestroyed(id, false)` is the **unlock**. → `true`. |
| `getOwnedVehicles(who)` | `{ { id, model, plate, isDestroyed, spawned }, … }`. |
| `getVehicleData(id)` | Raw stored row (with `account_name`). |
| `isVehicleSpawned(id)` | The live `vehicle` element if summoned, else `false`. |
| `getModelName(model)` | Display name for a model id. A `models.lua` override (`Vehicles.modelNames[id]`) wins, otherwise `getVehicleNameFromModel`. → `string`. |
| `getSpawnedVehicleId(who)` | Id of the vehicle the owner currently has summoned, or `nil`. |
| `storePersonalVehicle(who)` | Store whatever the player has summoned (wrapper around `storeVehicle`). → `true`. Errors: `not_spawned`, `occupied`. |

### Example – a dealership buying a car

```lua
if exports.v_bank:takeBankMoney(player, price) ~= true then
    -- tell the player they can't afford it
    return
end
local id = exports.v_ownveh:giveVehicle(player, model, { plate = "FREE V" })
```

## Summoning: spawn points and blips

`spawnpoints.lua` holds four hand-maintained lists – `land`, `boats`,
`helicopters`, `airplanes` – each entry `{x, y, z, rx, ry, rz}`. A model's list
is chosen from `getVehicleType()`.

`spawnOwnedVehicle` sorts the matching list by distance to the player and picks
the first point with **no vehicle within `spawnpointClearDist`** (config).

* **boats / helicopters / airplanes** – if every point is taken it fails with
  `no_free_spawnpoint`.
* **land** – if the nearest free land point is farther than
  `landDirectSpawnDistance` (config, default 150), or none is free, the vehicle
  is spawned **right at the player and they are put in the driver seat** – so
  no blip is created (it appears if they later get out).

**Only one owned vehicle may be summoned at a time.** A second
`spawnOwnedVehicle` while one is out fails with `already_spawned`; the caller
should `storeVehicle` the current one first.

A summoned vehicle left on a spawn point gets a radar blip. It is tagged for
v_radar (`isFarVisibility` + a `tooltipText` of `blip.tooltip`) so it pins to the
minimap edge when the car is off-screen and shows a hover label on the pause
bigmap. The blip is **hidden** while the owner is in the driver seat, **shown**
again when they get out, and **removed for good** when the vehicle explodes
(which also sets `isDestroyed = 1` and cleans up the wreck after
`wreckCleanupDelay`).

### Collecting spawn points – `/vehspawn` and `/showvehspawns`

Both admin only (`admin_level` ≥ `spawnpointAdminLevel`, default 1). Each point
gets a `checkpoint` marker **and an attached radar blip** (tinted the category
colour), **visible only to the admin who ran the command**.

* **`/vehspawn`** – sit in a vehicle and type it. The position + rotation is
  appended to `vehiclespawnpoints.txt` as `{x, y, z, rx, ry, rz}, -- category`,
  and a white checkpoint marker is dropped on the spot. Move the lines into the
  right list in `spawnpoints.lua` by hand.
* **`/showvehspawns`** – toggles checkpoint markers on **every point already in
  `spawnpoints.lua`**, colour-coded per category (`land` green, `boats` blue,
  `helicopters` yellow, `airplanes` red – see `Vehicles.config.marker.colors`).
  Type it again to hide them.

Both marker sets are cleared when the admin disconnects. Until real points are
added every list holds a single placeholder `{0, 0, 3, 0, 0, 0}`.

## Persistence timing

A summoned vehicle's state is written back to the database:

* every `autosaveInterval` ms (config),
* on `storeVehicle`,
* on the owner's quit (empty vehicles are also despawned),
* on resource stop.

## Files

| File | Role |
| --- | --- |
| `config.lua` | Tunables (`Vehicles.config`). |
| `spawnpoints.lua` | Hand-maintained spawn point lists (`Vehicles.spawnpoints`). |
| `models.lua` | Custom model-name overrides for `getModelName` (`Vehicles.modelNames`). |
| `db.lua` | SQLite connection, schema, row CRUD (`OwnVeh.db*`). |
| `state.lua` | Vehicle state capture/apply, model→category, spawn point picking. |
| `server.lua` | Runtime tracking, blips, lifecycle, the exports. |
| `commands.lua` | `/vehspawn`, `/showvehspawns` (admin, marker helpers). |

`vehicles.db` (+ its journal files) and `vehiclespawnpoints.txt` are
git-ignored; `spawnpoints.lua` is versioned.
