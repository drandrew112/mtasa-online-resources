# v_gangwar

Gang wars: an armed player who comes near a gang territory reserves it. When the player enters the red zone, the
gang members spawn. These are ai_peds scripted peds, and they attack every player. When the last one dies, the
starter gets the base reward. Every kill pays the killer at once, whether the killer is the starter or a helper.

## Storage

The data lives in the MySQL table `gangwars`, accessed through v_mysql. The schema and the column notes are in
`database.sql`, which is also part of the repo-root `main.sql`. The resource creates the table on start if it is
missing (an older table gets the `isRunning` column added). Every row is cached in `GangWars.list`. Every minute
only `last_run` and `isRunning` are read back, for servers that share the database.

`isRunning`: `0` = startable, `1` = a run is in progress on one of the servers sharing the database, so it cannot be
started anywhere else. A reservation starts only after `UPDATE ... SET isRunning = 1 WHERE id = ? AND isRunning = 0`
changed the row, so two servers can never both get it. The flag goes back to `0` when the run closes (finished,
aborted, starter quit) and on resource stop. Test runs never touch it. If a server crashes during a run, the flag
stays `1`: the editor shows "Running on another server" and offers "Clear running flag".

Each gang war has a schedule:

- `days`: `"1234567"`, where 1 is Monday.
- `hour_from` / `hour_to`: server time, `[from, to)`. `0-24` means all day; `22-4` wraps past midnight.
- `last_run`: the unix time of the last completed run. A **global 3-day cooldown** (`GW.COOLDOWN`) runs from it.
  Aborted runs do not set it.

## Life cycle (`server/runtime.lua`)

| State | How it gets there |
|---|---|
| (idle) | No run. It can be reserved if it is enabled, has attackers, the cooldown is over, and it is inside its day and hour window. |
| `reserved` | An armed player (a firearm with ammo, per wp_manager) came within `trigger_radius`. v_radar shows the red `zone_radius` circle to that player only. Nobody else can take it. |
| `active` | The starter entered `zone_radius`. The attackers spawn into the ai_peds group `gw_<gang>`, which is hostile to `player`. |
| `running` | The first kill, by anyone. The "Gang war / Started" banner shows and the clock starts. |
| `cleanup` | The run finished or was aborted. The peds and bodies are removed one at a time, each only when no player camera sees it (`ai_peds:isPointSeenByPlayers`). The gang war stays unavailable until every ped is gone. |

A run finishes when every attacker is dead. The "Completed" banner shows, `last_run` is set to now, and the starter
gets `reward_money` and `reward_xp`. A summary notification follows.

A run is aborted when any of these happens:

- The starter goes beyond `release_radius`. This is not checked while the starter is dead; death alone never ends a
  reservation.
- The starter leaves the server.
- The reservation expires: the starter did not enter the zone within 5 minutes.
- An admin stops the run, saves the gang war, or deletes it.
- Something other than a kill removes a living attacker, for example ai_peds stopping. No rewards are paid.

Each kill pays `GW.KILL_MONEY` (1500) and `GW.KILL_XP` (500) to the killing player.

The HUD uses ui_core stat rows in the bottom-right corner: Time, Enemies left and Enemies killed. The starter sees
them anywhere inside the release radius. Other players see them within `zone_radius × 1.2`.

## Editor: `/gangwareditor` (admin_level >= 5)

You edit on foot, and every position is taken from your own ped. **R** opens the menu (it returns to the page you left). The menu is built from
ui_inac temp menus, one menu per page.

The editor moves you into a private dimension (`GW.EDITOR_DIMENSION` + slot, 46001+). The preview peds and the
peds of a test run are created there, so nobody else sees them. New or re-centred gang wars get the dimension you
opened the editor in. Closing the editor ends your test run and puts you back where you started. After a respawn
you go back into the private dimension.

- **List.** For each gang war you can edit, teleport, start a test run, stop the current run, reset the cooldown or
  delete it. A test run has no time, cooldown or weapon check, pays no rewards and does not set `last_run`. It
  runs in your private editor dimension.
- **Gang war page.** Name, gang, enabled, move the centre here, the 3 radii, base money and XP, days, hours,
  attackers, and save.
- **Attacker page.**
  - Skin, weapon (id or name; 0 = fists), ammo, health, armour, accuracy, aggro radius.
  - Task: guard or patrol.
  - Patrol route recording. Walk the route and press **1** to add a point, **2** to undo, **3** to finish.
  - Wait time, speed.
  - Move here, duplicate, delete.
- **Attacker interact menu** (ui_interactobject, **X** next to a ghost ped, within 6 m):
  - Drag: the ped follows your aim (max 30 m). **1** or left click puts it down, **2** or right click cancels,
    the mouse wheel rotates it.
  - Duplicate: the copy (no patrol route) is dragged at once. Cancelling removes it.
  - Skin: previous / next, gang presets, or a typed ID.
  - Edit (opens the attacker page), delete.
- **Preview.**
  - Ghost peds stand at the attacker spots.
  - Circles: zone in red, trigger in yellow, release in grey.
  - Patrol lines.
  - The red circle on your radar.

The server sanitizes everything on save (`server/sanitize.lua`): numbers are clamped, at most 40 attackers and 20
patrol points per attacker are kept, and `zone <= trigger < release` is enforced. Saving a gang war stops its
current run.

Settings: `shared/config.lua`. Texts: v_locals `v_gangwar.json` (en + hu).

## Dependencies

- Included: v_locals, v_mysql, ai_peds, ui_core, ui_inac, ui_interactobject.
- Soft, called at use time: v_radar (zone circle), wp_manager (armed check; without it the GTA weapon slots are
  checked), v_levelsys (XP), v_accounts (editor name).
