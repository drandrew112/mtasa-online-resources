# work_bloodtransport tutorial module

An optional walkthrough of the blood transport work in a private copy of the world, built like the
work_ems tutorial. Each session gets its own dimension, starting at `TUTORIAL.DIMENSION_BASE`.
It also teaches the basics of the inventory (v_inventory): hands and back, the inventory window,
ports. The v_introduce intro has no inventory module for this reason.

- **When:** the first time a player goes on duty as a blood transporter, a card offers the tutorial
  (Start / Skip). With `TUTORIAL.DEBUG = true` it is offered on every duty start. `/tutorial_bt`
  starts it at any time, and `/tutorial_bt skip` ends it. Completing or skipping it sets the
  account data `bt.tutorial = true` (v_mysql). Dying, quitting or an error does not set it.
- **Start conditions:** not in a real blood transport service, nothing in the hands.
- **During the tutorial:** the player keeps the transporter right (`bt.right`), or gets it for the
  tutorial only. v_accounts saves their original position (`save.position`), so a disconnect never
  saves the tutorial position. The tutorial vehicle cannot be damaged.

## The real flow, flagged as tutorial

The tutorial does not fake anything: the panel, the service, the task, the cargo, the box and the
ports are the real ones.
- bt_dispatch runs a **tutorial shift** (sign on works in the tutorial vehicle without the work
  duty) and one **tutorial task** (`TUTORIAL.TASK`). Both live only in memory: no SQLite row, no
  stock, no pay, no XP. They are not counted as a unit / open task, so the generator, the handover,
  bt_stock's consumption and the web page do not see them. At the end the receipt is only shown.
- bt_core makes **tutorial copies of the two ports** (pickup and destination) in the session's
  dimension, visible only to the player. The tutorial task carries their ids (`fromPort` / `toPort`).
- bt_items gives the tutorial vehicle a **blood box** (`addVehicleBox`), with the same take / put
  menu at the rear.

## Steps

1. **Panel.** In the vehicle in front of the blood bank (frozen): the small view, `J` big view,
   Sign on.
2. **Task.** The header and the tiles, the task arrives, the task row, Route, order and Hand over,
   close the big view.
3. **Blood box and inventory.** Get out, Take the blood box at the rear, the hands & back HUD
   (`H`, `I`, no entering a vehicle with something in the hands), `I` inventory window: slots,
   the box as a container, moving items, close.
4. **Pickup.** `E` in the bank's port: the window, the banner, drag the cargo (« TAKE) into the box.
   The task is in transit; close the window.
5. **On the road.** Put the box back, get in, drive to the hospital on the route (no teleport). The
   step ends within `TUTORIAL.ARRIVE_RANGE` of the destination port.
6. **Delivery.** Take the box, `E` in the hospital's port, drag the cargo (PUT IN ») onto the port,
   close the window, put the box back.
7. **End of service.** `J`, the pay rules (from `BTD.PAY`), the other task types, Wind down, when a
   service ends, End service.
8. **Done.** The receipt of the tutorial service (not paid) and a short summary. Finish takes the
   player back to where they started.

Signing off before step 7 starts the service part again from step 1 (the task is cancelled with the
shift). The card is on the left; while the inventory window is open it moves below the window
(`side = "bottom"`). Its buttons work while the cursor is visible: the big panel and the inventory
window show it themselves, a Next card without them shows it itself, and `F2` toggles it. Every card
has a "Skip tutorial" link (click twice).

## Files

| file | |
|---|---|
| `config.lua` | vehicle position, the task, arrive range, keys named in the texts, debug flag |
| `server/session.lua` | sessions, world elements, steps, command, duty start offer |
| `client/card.lua` | the DX card, the highlight and the cursor (copy of the work_ems card + bottom placement) |
| `client/steps.lua` | step texts, the client-driven sub-steps, panel / inventory layouts |

Texts: v_locals `work_bloodtransport.tut.*` (en + hu), written by `[bloodtransport]/tools/loc_tutorial.py`.

## Hooks it uses in other resources

- **bt_dispatch:** server `setTutorialVehicle`, `createTutorialTask`, `getPayRules`, `getTask`,
  `isPlayerInService`; the events `onBtTutorialShiftStart`, `onBtTutorialShiftEnd` (reason, total,
  receipt items) and `onBtTaskChanged`. Client `getPanelLayout` (small / big view, Sign on, End
  service, Wind down, stats, task rows with Route / Hand over / order).
- **bt_core:** `createTutorialPorts`, `destroyTutorialPorts`, `getInstitution`, `hasRight`, `setRight`.
- **bt_items:** `addVehicleBox`.
- **v_inventory:** server `isPlayerHandsFree`, `closeInventory`; client `getUiLayout` (window: slots,
  rows with item ids, banner, areas; the hands & back HUD) and the element data `inv.slots`.
- **v_accounts:** the server-only element data `save.position`.
