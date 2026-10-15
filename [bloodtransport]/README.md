# Blood transport

Blood products, lab samples and urgent medicine are carried between the blood supply centers and the
hospitals by players. Plan, decisions and mockups: [DESIGN.md](DESIGN.md), `docs/mockups/`.
Request: `Blood transporter prompt.txt`.

| resource | what |
|---|---|
| `bt_core` | the transporter right (`bt.right`), the 7 institutions and their v_inventory ports, `getConfig()` |
| `bt_items` | cargo items, the blood box of the ambulances (take / put back through an interact menu at the rear, no trunk panel), per-player port rules, pickup / delivery detection |
| `bt_stock` | stock of centers and hospitals (`data/stock.json`), hospital consumption, hourly refill, resupply requests |
| `bt_dispatch` | services (shifts), tasks, assignment, handover, pay, the panel (F6), `/btadmin`, SQLite `data/bloodtransport.db` |
| `bt_web` | web page: home, live map with the stock, admin. HTTP `/bt_web/` and ui_browser `blood-transport.eu` |
| `[work]/work_bloodtransport` | the work on work_core: duty marker, `BT-` ambulances (model 415), gives the right |

Start order follows the `<include>`s: v_locals, v_inventory, work_core → bt_core → bt_items → bt_stock → bt_dispatch → bt_web.

## Playing it

1. Duty marker (blip 14) → work duty (gives the right) → vehicle marker → `BT-xxxx` ambulance.
2. In the vehicle press `F6` → **Sign on**. The unit id is the plate.
3. Tasks arrive as notifications and in the panel. Get out, use the interact menu at the rear of the ambulance to take the blood box into a hand.
4. Stand in the port marker of the pickup institution, `E`: move the TAKE items into the box (task becomes *transit*).
   Put the box back into the trunk before getting in (v_inventory rule).
5. At the destination port put the DELIVER items on the port (task becomes *delivered*).
6. End the service from the panel (anywhere). Pay: €2000 base (needs ≥1 delivery) + €2500 per delivery − €1500 per cargo still on the way.

Panel (bottom right, only with the right): small view = state + tasks in transit; `F6` = big view with sign on/off,
*wind down* (no new tasks), route button (one v_radar objective), ▲▼ order, hand over (waiting tasks, a unit ≤ 6 m away accepts within 20 s).

The service ends (all tasks cancelled, cargo and box contents deleted, pay calculated) when: the player ends it, the work duty ends,
the vehicle is destroyed / deleted, the player dies. (Quitting the server ends it without pay.)

## Config

* `bt_core/config.lua`: `REQUIRE_RIGHT` (`false` = everybody is a transporter, for testing), `ADMIN_LEVEL`, blood groups and their weights,
  products, institutions with the port positions.
* `bt_stock/config.lua`: capacities, refill (60 min, never above 90 %), consumption, resupply thresholds, batch sizes.
* `bt_dispatch/config.lua`: pay, task limits, random generator weights, handover range / timeout.
* `work_bloodtransport/shared/config.lua`: skins, plate prefix, duty / vehicle markers and spawn points.

## Admin

`/btadmin` in game (admin level `ADMIN_LEVEL`, 2): shifts and tasks, search, filters, details, the task ids of each shift.
The same in the browser: `http://<server>:<httpport>/bt_web/` → Admin (v_accounts login).

## Exports (server)

* `bt_core`: `getConfig`, `hasRight`, `setRight`, `getInstitutions`, `getInstitution`, `getPortId`, `getInstitutionByPort`
* `bt_stock`: `getStock`, `getAllStock`, `allocate`, `release`, `canFulfill`, `taskClosed`
* `bt_dispatch`: `createTask` (resupply only from bt_stock), `requestSupply`, `getTask`, `getPlayerTasks`, `getDutyCount`,
  `isPlayerInService`, `getPublicState`, `getCompletedCount`, `adminQuery`, `generateTask` (test helper)
* `bt_items`: `spawnCargo`, `destroyCargo`, `refreshPlayer`, `clearBox`, `getBox`, `getCargoItem`
* `work_bloodtransport`: `isPlayerBloodTransporter`, `getBloodTransportPlayers`, `getBloodTransportWorkId`

Events: `onBtCoreStart`, `onBtPortsReady`, `onBtItemsStart`, `onBtStockStart`, `onBtShiftStart` / `onBtShiftEnd` (shift id, reason), `onBtTaskChanged` (task id, status).

## Texts

English and Hungarian in v_locals (`bt_core`, `bt_items`, `bt_dispatch`, `work_bloodtransport`, item names in `v_inventory`); the web page is English only.
Client texts load after `onClientLoadingStarted` (v_accounts gate). Catalog files are listed in `v_locals/meta.xml`:
**v_locals has to be restarted once** so clients receive the new catalogs. `tools/loc_bt.py` / `tools/loc_work.py` regenerate the catalog entries.

## Tests

`python tests/run.py` (lupa, Lua 5.1): compiles every Lua file, tests the stock model and dispatch logic, and runs the dispatch core
with stubbed MTA functions (services, balancing, wind down, handover, pay, supply splitting). The in-game UI, the port window rules
and the web page are **untested in game**.
