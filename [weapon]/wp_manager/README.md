# wp_manager

Replaces GTA's own weapon handling. The server owns each player's weapons (`{ id, ammo, clip }`), and
the ped only ever holds the equipped one (GTA slots 0–10; slots 11–12, i.e. parachute, goggles and
detonator, are left alone). The selector UI is `wp_selector` (hold TAB).

- GTA's weapon switching (`next_weapon` / `previous_weapon`) is always off.
- A weapon with 0 ammo stays owned and can be drawn: GTA gets 1 fake bullet and `fire` is switched off.
  Thrown weapons (grenades, molotov, tear gas, satchel) are removed when the last one is used.
- R reloads a gun manually (when the magazine is not full and there is reserve ammo).
- The client reports the ammo of the equipped weapon every 250 ms. The server only accepts lower values.
- The hands rule with v_inventory (optional): no weapon while an item is in a hand, no item into a hand
  while a weapon is drawn (`onInventoryItemMove` is cancelled), a forced item puts the weapon away.
- A resource restart keeps everything (parked in the server-only element data `wp.backup`).

Persistence: v_accounts `savesys.lua` stores `getPlayerWeapons` as JSON in the accData key `weapons`,
and loads it with `setPlayerWeapons` (the old `weaponN` / `ammoN` keys are read once as a fallback).

## Server exports

| Export | |
|---|---|
| `getPlayerWeapons(player)` | the persistent weapons `{ {id, ammo, clip}, ... }`, or `false` before they were loaded |
| `setPlayerWeapons(player, list)` | replaces the persistent weapons. `list` = `{ {id=, ammo=, clip=} }`, `{ {id, ammo, clip} }` or `{ [id] = ammo }` |
| `isPlayerWeaponsLoaded(player)` | |
| `givePlayerWeapon(player, id, ammo, equip)` | adds a weapon, or adds ammo to an owned one |
| `takePlayerWeapon(player, id)` / `clearPlayerWeapons(player)` | |
| `getPlayerWeaponAmmo(player, id)` → `ammo, clip` | the active set |
| `setPlayerWeaponAmmo(player, id, ammo, clip)` | the active set |
| `getPlayerCurrentWeapon(player)` → id (0 = unarmed) | |
| `setPlayerCurrentWeapon(player, id)` → `true` \| `false, reasonKey` | |
| `setPlayerTempLoadout(player, list, equipId)` | a minigame loadout that hides the persistent weapons (Jobs, the job creator) |
| `clearPlayerTempLoadout(player)` / `hasPlayerTempLoadout(player)` | |
| `getWeaponCategory(id)` | `melee`, `shotguns`, `heavy`, `grenades`, `pistols`, `smg`, `mg`, `long` |

## Client exports

`getWeapons()`, `getCurrentWeapon()`, `isCurrentWeaponEmpty()`, `hasTempLoadout()`, `equipWeapon(id)`,
`getWeaponDefs()` → `categories, list`.

## Lent weapons (duty weapons)

`lendPlayerWeapon(player, id, ammo, equip)` lends a weapon for a work duty (work_police duty_weapons: 23 + 24).
The owner is the calling resource. A lent weapon is held like an own one, but it is **not the player's**:
`getPlayerWeapons(player)` (the save list) leaves it out, and an own weapon of the same id is parked meanwhile
(ammo bought for it goes to the parked copy). `returnLentWeapons(player [, owner|"*"])` /
`returnLentWeapon(player, id)` give it back; the owner resource stopping does it too.
`getPlayerWeapons(player, true)` = the held set with `lent = true`; `isPlayerWeaponLent`, `getPlayerLentWeapons`.
The client `getWeapons()` rows carry `lent`; wp_selector shows "Duty" next to the category.

## Stun gun (weapon 23)

`shared/stungun.lua` (WP.STUN). Weapon 23 never does damage (cancelled for players, peds, vehicles on every client;
medsys events / ai_peds ignore it). A hit within 10 units (shooter's client reports, server checks the shooter
holds 23 + distance) lays the victim down for 30 s: animation CRACK/crckdeth2, a player's weapon is holstered,
equip refused and movement controls off; an ai_peds ped gets `setAIPedStunned` (behaviour paused, threats
ignored). Element data `wp.stunned`, events `onElementStunned(shooter, ms)` / `onElementStunEnd`, exports
`stunElement(el, ms, by)`, `unstunElement`, `isElementStunned`. Not sold in wp_shop.

## Events

- `onPlayerWeaponEquip(newId, oldId)` (server, source = player, cancelable, 0 = unarmed)
- `onPlayerWeaponAmmoChange(id, ammo, clip)` (server, source = player)
- `onClientWeaponsChanged` (client, source = localPlayer)

## Tests

`python tests/run.py` (lupa, Lua 5.1, MTA stubbed).
