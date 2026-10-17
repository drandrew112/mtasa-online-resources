# Control Lock API — design

Status: **design only, not implemented** (2026-10-17). Owner resource: `ui_core`.
Related: ISSUES.md PERF-05 (D4: wp_manager re-disables controls every frame), the skipped
parachute skydiving handler (B3).

## 1. Problem

GTA controls (`fire`, `next_weapon`, `forwards`, `enter_exit`, …) are one global on/off state per
player. Today about 36 resources switch them directly, client side (`toggleControl`,
`toggleAllControls`, `exports.ui_core:toggleMoveControls`) and server side
(`toggleControl(player, …)`, `toggleAllControls(player, …)`, `toggleMoveControls_s`). The
**last call wins**. Nobody knows who else holds a control, so:

| Conflict | Example |
|---|---|
| Re-enabling someone else's lock | `toggleAllControls(true, …)` when a panel closes (v_weekly, v_mapcam, clothes shop, avi_controller scope, v_jobcreator freecam) frees the carry lock of v_inventory, the phone lock, a minigame lock, … |
| Fighting every frame | wp_manager switches `next_weapon` / `previous_weapon` / `fire` off **every frame** because others (v_inventory, parachute) switch them back on. parachute/skydiving_cl.lua toggles the same two controls from its own render handler. |
| Guessing the other owner | the tutorial cards (work_atc / work_bloodtransport / work_ems) re-enable `fire` / `aim_weapon` only "if not carryingEquipment()": they hard-code v_inventory's rule. wp_manager does the same with `handsBusy()`. |
| Client vs server | v_inventory (server, carry lock), med_bag, medsys treatment, v_mysql connguard and v_accounts lock from the server; the client side of other resources unlocks the same controls. |
| Restart leftovers | a resource that stops while it holds a lock leaves the control off (some have their own `onClientResourceStop` cleanup, many do not). |

The per-frame workarounds cost FPS (PERF-05), and the conflicts produce "stuck" or "unlocked too
early" control bugs that depend on the order things happen in.

## 2. Goals

1. A control is **enabled only when nobody holds a lock on it**. Owners never re-enable a control
   directly; they release *their* lock.
2. Locks are **owned** (resource + id) and are dropped automatically when the owner stops.
3. **No per-frame work.** The manager calls `toggleControl` only when the combined state of a
   control changes.
4. One API on the client and one on the server; both end in the same per-player table on the
   client.
5. A gradual migration: the legacy calls keep working while resources move over.
6. Debuggable: who holds what, from a command.

Non-goals: analog/ped control states (`setPedControlState`, `setPedAnalogControlState`), key
binds (`bindKey`), cursor ownership and `guiSetInputMode` — separate topics (a cursor owner API
would follow the same pattern later).

## 3. Concepts

- **Lock**: `{ owner = "<resource>:<id>", controls = { [name] = true } }`. `id` is chosen by the
  caller (`"phone"`, `"carry"`, `"minigame"`), unique within the caller resource. Locking the same
  id again **replaces** that lock's control set (so a resource can widen / narrow its lock without
  unlocking first).
- **Holders of a control**: `holders[control] = { [owner] = true }`. Enabled ⇔ the set is empty.
- **Groups** (shared config, `ui_core/shared/controls.lua`): names that expand to a control list,
  so callers stop copying lists.

  | Group | Controls |
  |---|---|
  | `move` | forwards, backwards, left, right, jump, sprint, walk, crouch, look_behind, change_camera |
  | `weapon` | fire, aim_weapon, next_weapon, previous_weapon, action |
  | `weapon_switch` | next_weapon, previous_weapon |
  | `vehicle` | accelerate, brake_reverse, steer_forward, steer_back, vehicle_left, vehicle_right, handbrake, horn, vehicle_fire, vehicle_secondary_fire |
  | `group` | group_control_forwards, group_control_back |
  | `enter_exit` | enter_exit |
  | `ui_move` | what `toggleMoveControls` switches today (move + weapon + group + enter_exit + vehicle) |
  | `all_gta` | every GTA control (the `toggleAllControls(false, true, false)` case) |
  | `all` | GTA + MTA controls (`toggleAllControls(false)`) |

- **Except**: a lock may be "everything in these groups except …" (v_introduce: everything locked
  but the scene's permitted controls).

## 4. Client API (exports.ui_core, client)

```lua
-- lock (or replace) the caller's lock `id`
-- controls: list of control and/or group names; opts: { except = { ... }, releaseOnKeyUp = bool }
lockControls(id, controls, opts)          --> true | false, err

unlockControls(id)                        --> true (unknown id: true, no-op)
unlockAllControls()                       --> drops every lock of the caller resource

isControlLocked(control)                  --> bool
getControlHolders(control)                --> { "v_inventory:carry", "server:med_bag:restock", ... }
getControlLocks()                         --> { [owner] = { controls... } }   (debug / admin panel)
```

The caller is `sourceResource` (resolved inside ui_core), so a resource cannot release another
resource's lock.

### releaseOnKeyUp

ui_core already re-enables `enter_exit` only after the key is released (a menu closed with Enter/F
would otherwise trigger an exit). This becomes a per-control behaviour of the manager: when the
last holder of a control with `releaseOnKeyUp` goes, the manager waits until none of the control's
bound keys is down (`getBoundKeys` + `getKeyState`) before switching it on — implemented with a
short `onClientKey` listener (key up), not a render handler. Default on for `enter_exit` and `fire`.

## 5. Server API (exports.ui_core, server)

```lua
lockPlayerControls(player, id, controls, opts)   --> true | false
unlockPlayerControls(player, id)                 --> true
unlockAllPlayerControls(player)                  --> drops every lock of the caller resource on that player
getPlayerControlLocks(player)                    --> { [owner] = { controls... } }
```

The server keeps `serverLocks[player][owner] = lock` (owner = `"server:<resource>:<id>"`) and sends
every change to that client (`ui_core:ctl:set` / `ui_core:ctl:unset`, latent not needed — tiny
payloads). The client merges them into the same `holders` table. On the client's ui_core start
(join, reconnect, ui_core restart) the client asks for the full list (`ui_core:ctl:sync`), so a
lock never depends on event order at join.

The server **does not** call `toggleControl(player, …)` itself any more for managed controls: the
client applies the merged result. (Server-side checks that must not trust the client — e.g. "may
this player fire" — stay server-side logic, as today.)

## 6. Client manager (internals)

```
holders[control] = { [owner] = true }    -- owner = "<res>:<id>" or "server:<res>:<id>"
locks[owner]     = { controls = set, opts }
applied[control] = true | false          -- what we last passed to toggleControl
```

`apply(control)`:
1. `want = next(holders[control]) == nil` (enabled when nobody holds it).
2. If `want == applied[control]` → nothing.
3. If `want` and the control has `releaseOnKeyUp` and a bound key is down → mark pending, return.
4. `toggleControl(control, want)`; `applied[control] = want`.

`lockControls` / `unlockControls` update `locks` and `holders` and call `apply` only for the
controls whose holder set changed. Cost: O(controls in the lock), only when something locks or
unlocks.

Cleanup:
- `onClientResourceStop` (root): drop every lock whose owner starts with that resource name.
- Server player locks are dropped by the server on `onResourceStop` of the owner and sent as
  unset; `onPlayerQuit` clears the player's table.
- ui_core stop: re-enable everything it disabled (`applied == false` → `toggleControl(c, true)`).
- ui_core start: event `onClientControlLockReady` (and server `onControlLockReady`), so owners
  that hold a lock re-apply it (same pattern as `onProximityReady`).

### Legacy writes (during the migration)

Unmigrated code still calls `toggleControl` directly and can re-enable a locked control. The
manager does **not** poll every frame for that. Instead:
- the legacy ui_core exports (`toggleMoveControls`, `toggleMoveControls_s`) become wrappers over
  locks right away (section 8, phase 1), which removes most legacy writes in one step;
- `reconcile()` re-applies every locked control once (`isControlEnabled` → `toggleControl(c,
  false)`); it runs after a lock change, on `onClientResourceStart` of any resource (a starting
  resource is the usual source of a stray `toggleControl(..., true)`), on spawn, and from a slow
  timer (1 s) **only while at least one lock exists** and only until the migration is finished.
  Remove the timer in the last phase.

## 7. toggleAllControls mapping

| Today | With the API |
|---|---|
| `toggleAllControls(false, true, false)` (panel open: GTA controls off, MTA on) | `lockControls("panel", { "all_gta" })` |
| `toggleAllControls(true, true, false)` (panel closed) | `unlockControls("panel")` |
| `toggleAllControls(localPlayer, false, true, false)` (loading screen) | `lockControls("loading", { "all_gta" })` |
| `toggleAllControls(localPlayer, not banned)` | `lockControls("banned", { "all" })` / unlock |
| server `toggleAllControls(player, false, true, false)` (v_mysql guard, v_accounts) | `lockPlayerControls(player, "guard", { "all_gta" })` |
| v_introduce `toggleControl(c, permitted[c])` | `lockControls("intro", { "all_gta" }, { except = permitted })` |

## 8. Migration plan

Phase 1 — **ui_core core + legacy wrappers** (no behaviour change for callers)
- `ui_core/shared/controls.lua` (groups), `client/controls.lua` (manager), `server/controls.lua`
  (player locks + sync), exports, `/ctllocks` debug command (admin level from v_admin).
- `toggleMoveControls(v)` → `v == false` ⇒ `lockControls("legacy_move", { "ui_move" })` owned by the
  **calling** resource, `v == true` ⇒ `unlockControls("legacy_move")`. Same for
  `toggleMoveControls_s(player, v)`. The `enter_exit` key-up logic moves into the manager.
  Covers v_accounts, v_admin, v_jobmanager, v_chat, ui_browser, ui_inac, ui_pause, v_customs.

Phase 2 — **the conflicts behind PERF-05**
- wp_manager: `lockControls("switch", { "weapon_switch" })` once at start; `fire` lock only while
  the held weapon is empty (`lockControls("empty", { "fire" })` / unlock). **Delete the
  per-frame handler** (main.lua:79) and `handsBusy()`.
- v_inventory (server/slots.lua `syncControls`): `lockPlayerControls(player, "carry", want)` —
  replaces the had/want diff; the tutorial cards drop `carryingEquipment()`.
- parachute/skydiving_cl.lua: lock `weapon_switch` while skydiving, unlock on stop/death; then gate
  its render handler like the other B items (event: weapon 46 / skydiving state).
- tutorial cards (3): `lockControls("card", { "fire", "action", "aim_weapon" })` while the cursor is
  over the card.

Phase 3 — **panels and minigames** (mechanical)
avi_controller scope, v_weekly, v_mapcam, world_clothes-shop, v_jobcreator freecam, ui_phone,
med_erm tablet, med_stretcher push/select, mg_airway / mg_cpr / mg_intravenous / mg_splinting,
ui_interactobject (weapon-switch suppression), v_els editor, v_introduce, medsys_effects,
ui_core textInput.

Phase 4 — **server side**
v_accounts (server.lua), v_mysql connguard, med_bag interaction, medsys treatment, v_inventory
(phase 2). Then remove the reconcile timer and add a check to the Lua test runner that fails on
new direct `toggleControl` / `toggleAllControls` calls outside ui_core.

Each phase is a separate change set, testable alone.

## 9. Edge cases

- **Death / respawn**: GTA keeps the control states; the manager re-applies on `onClientPlayerSpawn`
  (cheap: only locked controls).
- **Same control, client and server owner**: both are holders; it is enabled only when both release.
- **Lock replaced with fewer controls**: the dropped controls are re-evaluated (may become enabled).
- **Owner restarts while holding a lock**: stop drops the lock; on start the owner locks again
  from its own state.
- **ui_core restarts**: every lock is lost; ui_core stop re-enables what it disabled, owners re-lock
  on `onClientControlLockReady` / `onControlLockReady`. Owners must keep their own "I want a lock"
  state (they already have it: `WindowOpen`, `state.open`, …).
- **Key held while unlocking** (`releaseOnKeyUp`): see section 4.
- **Invalid names**: unknown control or group → `false, "unknown control"` and a debug warning;
  nothing changes.
- **Cross-resource calls cost**: lock/unlock happen on state changes only (open/close, pick up,
  start/stop), never per frame, so the export overhead does not matter.

## 10. Testing

- Unit (lupa, MTA stubs, see the Lua test runner memory): holder sets, replace, except, group
  expansion, owner stop cleanup, releaseOnKeyUp pending/flush, server merge + sync order.
- In-game checklist per phase:
  1. open the phone while carrying an item → close it → the carry lock (fire/aim) is still on;
  2. wp_manager: weapon switch stays off with the inventory window open/closed, no per-frame
     handler in `getPerformanceStats("Lua timing")`;
  3. close a menu with Enter → no vehicle exit;
  4. restart v_inventory / wp_manager / ui_core while locks are held → nothing stays stuck;
  5. reconnect during a server-side lock (v_mysql guard) → still locked after join.
- `/ctllocks` shows the expected owners at every step.

## 11. Open questions

1. Should `fire` always use `releaseOnKeyUp` (a click closing a panel would otherwise shoot)?
   Proposal: yes for `fire` and `enter_exit`, opt-in for the rest.
2. Priority / "force enable" (e.g. an admin freeze override): not needed now — keep the rule
   "enabled only when nobody holds it".
3. Cursor ownership (`showCursor`) has the same last-writer-wins problem; a `cursorLock` API with
   the same structure could follow after phase 2.
