# med_bag – design

Portable EMS equipment for every ambulance: a **medical bag** and a **monitor / defibrillator**.

Goal: a medic can still *examine* a patient with bare hands, but every *intervention* needs the
equipment next to the patient. The bag holds the consumables (medicines, IV kits, oxygen), which
run out and are restocked at a hospital. Both items live in the ambulance, are taken out and put
back at the side door, and can be carried together (bag in the left hand, monitor in the right).

Status: implemented 2026-10-09 (phases 1-7); offsets and the side points need in-game tuning.
The work_ems tutorial teaches the equipment (phase 7, see work_ems/tutorial/README.md). Author in meta.xml: `DrAndrew112`.

---

## 1. Rules (from the request)

| # | Rule |
|---|---|
| R1 | Without equipment the medic can examine (pulse, bleeding, skin, breathing line) and use **Neuro exam**, **Request transport** and **CPR** only (CPR needs no bag, decided 2026-10-09). Every other action is locked. |
| R2 | The bag holds the medicines. Medicines, IV kits and oxygen can run out. |
| R3 | Restocking happens at a hospital. |
| R4 | The bag and the monitor are taken out of / put back into the ambulance. |
| R5 | The monitor/defibrillator is an item too. One medic may carry both at once (one in each hand). |
| R6 | Equipment works only within `X` metres of the patient. |
| R7 | Both items are reached at the ambulance side door, under **one** ui_interactobject menu. The position is tuned by the user (config). |
| R8 | Every ambulance has exactly one bag and one monitor. Duplication must be impossible. |
| R9 | The unit is warned if it leaves the bag or the monitor at the scene. |
| R10 | Bag model: `11738` (not in MTA, see 7.1). Monitor: a plain PC monitor model with a static DX-drawn screen, easy to delete when the custom models arrive. |

---

## 2. Concepts

### 2.1 Kit

A **kit** belongs to one ambulance (vehicle element) and holds two **items**:

```lua
Kit = {
    vehicle  = <vehicle>,
    anchor   = <object>,           -- invisible menu anchor at the side door (one menu, R7)
    menuId   = "s12",
    items = {
        bag     = Item,
        monitor = Item,
    },
}

Item = {
    id       = "bag:A-1234",       -- stable identity (kind + plate), never cloned
    kind     = "bag" | "monitor",
    kit      = Kit,                -- home vehicle; can only be stowed back into it
    state    = "stowed" | "carried" | "ground",
    object   = <object> | nil,     -- exists ONLY while out of the vehicle
    carrier  = <player> | nil,     -- state == "carried"
    lastHolder = <player>,         -- for the left-behind warning when no unit is known
    leftTick = nil,                -- first tick it was detected as "left behind" (§8)
    stock    = Stock,              -- bag only (§5)
}
```

### 2.2 Item state machine

```
              take (side-door menu)               put down (H)
   STOWED  ───────────────────────►  CARRIED  ─────────────────────►  GROUND
     ▲   ◄───────────────────────       │  ▲  ◄─────────────────────    │
     │      put back (side-door menu,   │  │     pick up (item menu)    │
     │      or entering own ambulance)  │  │                            │
     │                                                                  │
     └──────────────── abandoned timeout / admin reset (§8.3) ──────────┘
```

* `stowed`: no world object. The item exists only as server data.
* `carried`: no server object; every client hangs a local object from the carrier's hand (7.2).
* `ground`: an object on the ground with its own ui_interactobject menu (**Pick up**).
* `stretcher`: a server object on the side of its own ambulance's stretcher (section 16).

### 2.3 Why duplication is impossible (R8)

* Only the server creates items. There is exactly one `Item` per `kind` per kit, created when the
  kit is created; there is no "spawn item" path anywhere else.
* An item's world object is created on leaving `stowed` and destroyed on returning to it. Taking
  out an item that is not `stowed` is refused, so the object can never exist twice.
* Stowing checks `item.kit == kit` (an item only goes back into its own ambulance). A foreign bag
  at the wrong ambulance gets: *"This bag belongs to A-1234"*.
* A player carries at most one item of each kind (`carriedBy[player] = { bag = item, monitor = item }`).
* The kit is destroyed with the vehicle. A re-created ambulance (work_core respawn) gets a new kit
  with fresh ids; the old kit's out-of-vehicle objects are destroyed at the same time.

---

## 3. Ambulance discovery

Same approach as `med_stretcher` (MTA has no server `onVehicleCreate`):

* `addDebugHook("postFunction", requestScan, { "createVehicle", "setElementModel" })` (needs the
  `addDebugHook` ACL right, already granted for med_stretcher), plus a 5 s fallback scan timer.
* `BAG.VEHICLE_MODELS = { [416] = true, [456] = true }`.
* `onElementDestroy` / `onVehicleExplode` on the vehicle → destroy the kit (and its loose objects;
  the carriers' hands are emptied).
* Like med_stretcher, the first scan is deferred by 500 ms after `onResourceStart` (ui_interactobject
  early-sync note).

---

## 4. Interaction

### 4.1 Side-door menu (one menu per ambulance, R7)

An invisible anchor object (`BAG.ANCHOR_MODEL`, a small prop, alpha 0, collisions off) is attached
to the ambulance at `BAG.SIDE_POINT[model]` (vehicle-local `{ x, y, z }`, **positioned by the user**;
`/bagpos` prints the player's offset relative to the nearest ambulance to help). The menu is
registered on the anchor, not on the vehicle, so it appears exactly at the side door and does not
collide with the stretcher menu at the rear.

```
[X] Ambulance equipment  (A-1234)
 1  Take medical bag            (disabled when not in the vehicle)
 2  Take monitor / defibrillator
 3  Take both
 4  Put medical bag back        (disabled when the bag is in the vehicle)
 5  Put monitor back
 6  Put everything back
 7  Restock bag                 (only while the ambulance stands in a hospital bay, §5.3)
 8  Check contents              (chat/notification summary of the stock)
```

* `selfDataKey = "medic.role"` → only medics see it (same rule as medsys / med_stretcher with
  `REQUIRE_MEDIC_ROLE`).
* `range = 1.8`, `lineOfSight = true`, `allowInVehicle = false`.
* The item labels are refreshed with `setInteractMenuItems` on every state change, e.g.
  `"Put medical bag back"` becomes disabled with the desc `"In the vehicle"`. The server
  re-validates everything in `onInteractMenuSelect` anyway (the label is only a hint):
  * **Take**: item is `stowed`; the player has no item of that kind; player is a medic; not in a vehicle;
  * **Put back**: the player carries the item **or** the item lies on the ground within 2 m of the
    side point; `item.kit == kit`.
* A short take/put-back animation (`BAG.TAKE_ANIM`, ~600 ms, e.g. `"CARRY", "liftup"` /
  `"CARRY", "putdwn"`) and optionally the side door opening (`BAG.SIDE_DOOR[model]`, nil = no door).

### 4.2 Ground items

An item on the ground gets its own menu (`title = "Medical bag (A-1234)"`):
`1 Pick up`. Anyone with the medic role may pick up any kit's items, so a crew member can
collect what a colleague left. Picking up a second bag while holding one is refused.

### 4.3 Putting down

`H` (`BAG.DROP_KEY`, not G: G is "enter as passenger", bound client side, sent to the server) puts the carried items down in front of
the player: the bag at the left, the monitor at the right (`BAG.DROP_OFFSETS`), on the ground
(`processLineOfSight` / `getGroundPosition` on the client, z validated by the server against the
player's z ± 2 m).

**Auto put-down**: when a medsys procedure starts while the medic holds items, they are put down
beside the patient automatically (`BAG.AUTO_DROP_ON_TREAT = true`), so the minigame/animation
never shows a bag glued to a CPR hand. Holding them is still enough for the range check (§6.1).

### 4.4 Vehicles

* Entering **its own** ambulance (any seat) with carried items → they are stowed automatically.
* Entering any other vehicle while carrying → cancelled (`onVehicleStartEnter`) with
  *"Put the equipment down or back first"*.
* Warp into a vehicle by script (e.g. med_stretcher loading, tutorial teleports) → items are put
  down where the player stood (never silently stowed into a foreign vehicle).

### 4.5 Carrier leaves

`onPlayerQuit`, `onPlayerWasted`, `onPlayerMedicChange(false)` (off duty), dimension/interior
change → the items are put down where the player stood and become `ground` (the left-behind
warning then handles them, §8).

---

## 5. Consumables (bag only, R2/R3)

### 5.1 Stock

```lua
BAG.STOCK = {
    drugs = {                      -- MEDIC_DRUGS ids → doses in a full bag
        ketamine = 2, rocuronium = 2, fentanyl = 3, epinephrine = 5, captopril = 3,
        nitroglycerin = 3, glucose = 2, glucose_gel = 2, insulin = 1, naloxone = 2,
        salbutamol = 2, midazolam = 2,
    },
    ivKits   = 4,                  -- one per IV *attempt* (a failed cannulation wastes it)
    oxygen   = 100,                -- percent of one cylinder
    -- later, if wanted: bandages, splints, glucose strips (all optional: nil = unlimited)
}
BAG.OXYGEN_DRAIN = 100 / 900       -- %/s per active mask: a full cylinder lasts 15 min of mask time
BAG.OXYGEN_LOW   = 20              -- % warning threshold
```

* A drug **not listed** in `BAG.STOCK.drugs` is unlimited (new medsys drugs work immediately).
* Stock is per bag, server-side only, sent to the client with the panel snapshot.
* Not persisted: a new ambulance (new kit) starts full. Persistence is a later option (§12).

### 5.2 When something is consumed

| Action | Check (before start) | Consumed |
|---|---|---|
| Medication | `drugs[id] > 0` | when `apply` succeeds (the dose was given) |
| IV access | `ivKits > 0` | when the minigame **starts** (attempt) |
| O2 mask on | `oxygen > 0` | drains every second while the mask is on (see below) |
| Glucometer / bandage / splint / airway | bag in range | nothing (unlimited for now) |

Oxygen: see 6.3 (mask or intubation, drained every second until the transport begins).

### 5.3 Restocking at the hospital

* **Restock bag** in the side-door menu is enabled while
  `exports.med_hospitals:getVehicleHospitalBay(vehicle)` returns a bay (the ambulance is parked in
  a hospital bay; that function already exists). The bag must be stowed in the ambulance.
* 6 s progress bar (`BAG.RESTOCK_TIME`), the medic stands still; leaving / moving cancels it.
* Free for now; `BAG.RESTOCK_PRICE` (nil) can later charge the unit via v_bank.
* Optional later: a *supply point* per hospital in `hospitals.json` (`"supply": {x,y,z}`), for
  restocking a bag carried in by hand. Not needed for the first version.
* Low-stock hint: when any counted item drops to ≤ 25 % / 0, the carrier and the crew get a
  one-time notification (*"Medical bag: Adrenalin is out"*).

---

## 6. medsys integration

medsys must keep working without med_bag (tests, other servers). Everything goes through
`medsys/server/equipment.lua`; when `MEDIC.REQUIRE_EQUIPMENT` is false **or med_bag is not running,
medsys asks for no equipment at all** (decided). Tutorial patients (`setTutorialPatient`) are exempt
unless marked with `useEquipment` (the work_ems tutorial patient is); `/medtest` patients are **not** exempt (so the bag can
be tested with them).

### 6.1 Range rule (R6)

An item **serves** a patient when it is out of the ambulance (carried or on the ground), in the same
dimension + interior, and within `BAG.USE_RANGE` (**4.0 m**, 3D) of the patient. A carried item's
position is the carrier's. The medic's own carried item is preferred, then the nearest one.
(medsys never treats a patient sitting in a vehicle, so stowed items never serve.)

### 6.2 Requirements (`MEDIC_EQUIPMENT`, medsys `shared/config.lua`)

```lua
MEDIC_EQUIPMENT = {
    bandage = { item = "bag" },  splint = { item = "bag" },  airway = { item = "bag" },
    iv = { item = "bag", stock = "ivKits" },
    oxygen = { item = "bag", stock = "oxygen" },      -- taking the mask OFF needs nothing
    medication = { item = "bag" },                    -- + per-drug stock
    glucometer = { item = "bag" },
    monitor = { item = "monitor" },
}
-- not listed = no equipment: neuro exam, CPR (decided), transport
```

* **Panel** (`getAvailability`): an action whose item does not serve the patient is disabled with
  *"Needs the medical bag"* / *"Needs the monitor"*; an empty stock gives *"Out of IV kits"* /
  *"Oxygen cylinder empty"*. The snapshot carries `equipment = { bag, monitor, stock }`
  (stock = the sum of every serving bag): header chips `O2 64%` / BAG / MONITOR, `x3` on every drug
  card (0 = disabled, "Out of stock"), `IV access (3)`, the monitor button's reason on hover.
  The panel is rebuilt every simulation tick (1 s), so equipment arriving / leaving shows within 1 s.
* **Start** (`startTreatment`): the same check again (the panel can be stale), incl. the chosen drug.
  Then `med_bag:onTreatmentStart` puts the medic's carried items down beside the patient
  (`BAG.AUTO_DROP_ON_TREAT`), and an IV attempt consumes one IV kit.
* **Success** (`finishTreatment`): medication consumes one dose from a serving bag that has it;
  the oxygen mask on -> `startPatientOxygen`, off -> `stopPatientOxygen`; monitor attached ->
  `linkPatientMonitor`.
* **Glucometer** reading: the bag must serve the patient.

### 6.3 Oxygen and monitor link (med_bag 1 s tick, `server/stock.lua`)

* Oxygen is used **continuously** by a patient with the **mask on or intubated** (the session starts
  when the intubation succeeds): at the scene, on the stretcher, in the ambulance (from the stowed bag)
  and at the handover. It drains `BAG.OXYGEN_DRAIN` %/s from the bag feeding it. If that bag is
  farther than `BAG.CONNECT_RANGE` (6 m) or runs empty, another bag with oxygen within 6 m takes over;
  otherwise med_bag calls `medsys:removePatientEquipment(patient, "oxygen", msg)`: the mask comes off
  (*"Oxygen cylinder empty - mask removed"*). An intubated patient keeps the tube, but **the tube has
  no effect without oxygen** (user's rule): medsys `state.noOxygen` -> `isVentilated` is false, so the
  SpO2 follows the injuries / resting limit, a paralysed patient desaturates, the breathing is no longer
  "Ventilated", no ROSC airway bonus; the panel shows *"Airway: tube, NO OXYGEN"*. The session keeps
  looking for oxygen: as soon as a bag has some (brought back, restocked, another bag),
  `restorePatientEquipment` makes the tube work again (*"Oxygen connected"*).
  noOxygen only counts while med_bag runs, and a med_bag (re)start clears it on every patient.
* Monitor: one monitor - one patient. Beyond `BAG.CONNECT_RANGE` (6 m) or lost with the ambulance ->
  `removePatientEquipment(patient, "monitor", "Monitor disconnected - attach it again")`.
  Attaching it to a second patient disconnects the first.
* Positions come from the top of the attachment chain (`rootPosition`): a patient lying on a pushed
  stretcher and an item on its side are both measured at the pusher (server positions of attached
  elements are not reliable).
* Sessions are dropped when medsys says the mask / tube / monitor is gone (`getMedicalState`).

### 6.4 Stretcher

See section 16: the equipment rides on the side of its own ambulance's stretcher.

---

## 7. Visuals

### 7.1 Models

The SA-MP ids (11738 *MedicCase*, 19787 *LCDTV1*) **do not exist in MTA** (verified live:
`createObject` -> "Invalid model id"). Placeholders until the custom models:

| Item | Model | Notes |
|---|---|---|
| Bag | `1210` *briefcase* | 0.50 x 0.07 x 0.37 m, origin off-centre |
| Monitor | `2190` *PC_1* at scale 0.55 | ~0.30 m, origin off-centre; screen texture `CJ_TV_SCREEN` (to verify) |
| Anchor | `1598`, alpha 0 | Only the menu anchor at the side door. |

### 7.2 Carrying (R5)

* Server: a carried item has **no** server object; the carrier gets the `medbag.hands` element data
  (`{ bag = model, monitor = model }`).
* Client (every client, streamed-in carriers only): creates a local object per carried item and in
  `onClientPedsProcessed` hangs it from the hand bone (`getPedBonePosition`, left hand `35` = bag,
  right hand `25` = monitor). The offset is in the **carrier's** frame (x right, y forward, z up,
  rz added to the heading), so the item hangs upright and follows the walk; the offsets also
  compensate the models' off-centre origins.
* No carry animation is forced. Jump / fire / aim / weapon switch are disabled while carrying
  (`BAG.CARRY_LOCKED_CONTROLS`).

### 7.2b HUD

* **Carry HUD** (right side, while carrying): the items in the hands (L = bag, R = monitor), the
  carried bag's IV kits and oxygen (from `medbag.hands`), and the put-down key.
* **Check contents** opens a window (right side, 15 s or until the player walks 6 m away): IV kits,
  oxygen, every medicine `left/full` coloured by level. (The server's v_chat hides the default
  chat, so nothing of med_bag uses `outputChatBox`.)
* Ground item menus have `lineOfSight = false`: ui_interactobject checks the sight line to the
  element origin, and the monitor model's origin lies under the ground.

### 7.3 Static monitor screen (R10)

`client/screen.lua` + `fx/screen.fx`, self-contained:

* At start: one `dxCreateRenderTarget(512, 256)` drawn **once** with dxDraw* calls (a Lifepak-like
  frame: HR 78 green, a flat ECG trace, SpO2 98 cyan, NIBP 122/78, battery and the "LIFEPAK 15"
  label) and applied to every monitor object via `engineApplyShaderToWorldTexture(shader,
  BAG.MONITOR_SCREEN_TEXTURE, object)`.
* Redrawn only on `onClientRestore` (render targets are lost on minimise). One render target for
  all monitors: ~0.5 MB VRAM total. No per-frame drawing, no live data (user's request).
* `BAG.MONITOR_SCREEN_TEXTURE` names the model's screen texture. `/bagscreen` (client) puts the
  picture on the next texture of the model and names it, to find the right one by eye.
* **Removal**: delete `client/screen.lua` and `fx/screen.fx` from meta.xml, or set
  `BAG.STATIC_SCREEN = false`. Nothing else references them.

### 7.4 Range feedback

While the examination panel is open, the panel header shows two small icons (bag / monitor):
white = in range, grey = missing. Disabled buttons already carry the reason text (§6.2).

---

## 8. Left-behind warning (R9)

### 8.1 Detection (server, every `BAG.WATCH_INTERVAL` = 2 s, items not `stowed` only)

An item is **left behind** when all of these are true:

1. its state is `ground` (carried items have someone with them), and
2. its home ambulance is farther than `BAG.LEFT_DISTANCE` (**60 m**) from it, **or** the ambulance is
   moving faster than 15 km/h and farther than `BAG.LEFT_MOVING_DISTANCE` (**20 m**), and
3. no medic stands within 10 m of it.

Rule 2b catches "drove away from the scene" immediately instead of after 60 m.

### 8.2 Warning

Recipients: the ERM unit of the ambulance (`exports.med_erm:getVehicleUnit(vehicle)` → its members),
falling back to the ambulance's occupants + `item.lastHolder`.

* First detection: a UI notification + a short beep, e.g. *"Equipment left at the scene: medical
  bag, monitor"* (English UI), and a red blip on the left item (visible only to the recipients,
  `createBlipAttachedTo(…, visibleTo)`). No automatic waypoint (Q6).
* Repeats every `BAG.WARN_REPEAT` = 45 s while it is still left behind.
* The ambulance's driver also gets a one-time warning when they **start driving** while an item is
  on the ground > 20 m away (the most common case, caught before 60 m).
* In a hospital bay (`getVehicleHospitalBay`) an ambulance with items out shows *"EQUIPMENT MISSING"*
  over its side door (anchor element data `medbag.missing`, drawn by med_bag) and the crew is notified (Q7).
  med_hospitals is not changed (occupied bays have no label of their own).

### 8.3 Abandoned items

After `BAG.ABANDON_TIME` (**10 min**) as left-behind, the item is "recovered by dispatch": the
object is destroyed, the item returns to `stowed` **with an empty stock** (bag) – it must be
restocked at a hospital. The crew gets a notification. No fine for now (decided); the empty stock
is the only penalty.

The ambulance being destroyed / respawned destroys its kit and every loose item of it (§3).

---

## 9. Other resources

| Resource | Change |
|---|---|
| **medsys** | `server/equipment.lua` (adapter), `MEDIC_EQUIPMENT` + `MEDIC.REQUIRE_EQUIPMENT` / `EQUIPMENT_RESOURCE`, checks in `getAvailability` / `startTreatment` / glucometer, consumption hooks, exports `removePatientEquipment` + `getDrugNames`, panel: chips, doses, O2 %, IV count. |
| **med_stretcher** | Fires the five stretcher events (section 16). |
| **med_hospitals** | None (the existing `getVehicleHospitalBay` is used). |
| **work_ems tutorial** | Equipment step (contents, take, put down, pick up), equipment on the stretcher, restock in the tutorial bay. Its patient is a tutorial patient with `useEquipment`; med_hospitals `getVehicleHospitalBay` also knows the tutorial bays. |
| **med_scenemanager / med_erm_auto** | None. |

---

## 10. Files

```
med_bag/
  meta.xml                 author="DrAndrew112"
  DESIGN.md
  README.md                (after implementation)
  shared/config.lua        BAG.* tunables (§12)
  shared/util.lua          offsets, matrix helpers
  server/kits.lua          ambulance discovery, kit/item creation + destruction
  server/items.lua         state machine: take / put back / put down / pick up, carriers
  server/interaction.lua   side-door + ground menus (ui_interactobject), restock, /bagpos, /bagreset
  server/stock.lua         serving items, stock, consumption, oxygen drain, monitor links
  server/watch.lua         left-behind detection, warnings, blips, abandon, equipment missing
  server/exports.lua       §6.1 exports + getVehicleKit / getPlayerItems / admin reset
  client/carry.lua         local hand objects, put-down key, ground snap
  client/screen.lua        static monitor screen (removable, §7.3)
  client/hud.lua           notifications (ui_core if available), restock bar, equipment missing label
  fx/screen.fx             texture replace shader (removable)
```

### Events

| Event | Side | Args |
|---|---|---|
| `onMedicalEquipmentChange` | server | source = the ambulance, `itemId, kind, oldState, newState` |

### Exports (server)

```lua
-- medsys
getEquipmentNear(patient [, medic])       -> { bag = id|false, monitor = id|false, stock = {...}|nil }
findStockItem(patient, medic, category [, key]) -> id | false
consumeStock(id, category [, key, amount]) -> bool
startPatientOxygen(patient, medic) / stopPatientOxygen(patient)
linkPatientMonitor(patient, medic) / unlinkPatientMonitor(patient)
onTreatmentStart(medic, patient)          -- auto put-down
-- others
getVehicleKit(vehicle)                    -> { bag = id, monitor = id } | false
getItemInfo(id)                           -> { kind, state, vehicle, carrier, x, y, z, linkedTo } | false
getPlayerItems(player)                    -> { bag = id|nil, monitor = id|nil }
getItemStock(id) / restockItem(id) / returnItem(id)
```

Admin (account `admin_level` > 3, via v_mysql): `/bagpos` prints the player's offset from the nearest
ambulance (for `BAG.SIDE_POINT`), `/bagreset` returns the nearest ambulance's items (stock kept).

---

## 11. Replacing the models later

1. Put the new DFF/TXD through v_modloader (or `engineRequestModel` in med_bag).
2. Change `BAG.MODELS.bag.id` / `BAG.MODELS.monitor.id`, re-tune `hand` / `ground`
   offsets and `scale`.
3. If the custom monitor has its own screen texture, set `BAG.STATIC_SCREEN = false` and remove
   `client/screen.lua` + `fx/screen.fx` from meta.xml.

---

## 12. Config

All tunables are in `shared/config.lua` (`BAG`), commented there: models + offsets, side point per
model, ranges, stock, oxygen drain, restock time, left-behind distances / times, blip, static screen.

---

## 13. Edge cases

| Case | Behaviour |
|---|---|
| Two medics click **Take bag** in the same frame | Server is single-threaded: the first wins, the second gets *"Already taken"*. |
| Carrier dies / quits / goes off duty | Items dropped where they stood → `ground` → left-behind watch. |
| Ambulance explodes while items are out | Kit destroyed; loose items destroyed, carriers' hands emptied, crew notified. |
| Ambulance respawned by work_core | Old kit gone (vehicle destroyed), new full kit. |
| Medic enters own ambulance holding items | Auto-stow. |
| Item put down in water / falls through the map | Client ground check fails → server falls back to the player's feet; an item below z −50 or in water returns to `stowed` (stock kept). |
| Different dimension (tutorial) | Items keep the carrier's dimension; the kit of a tutorial ambulance works in its private dimension. |
| med_bag restarts | All kits recreated full (new item ids); medsys asks for no equipment meanwhile. Oxygen / monitor sessions are forgotten (the mask / monitor stay on). |
| medsys restarts | med_bag unaffected; oxygen drains stop (no masks). |
| Monitor attached, then someone picks it up and walks away | Link breaks at 6 m → *"Monitor disconnected"*. |
| Two patients, one monitor | Attaching to the second detaches the first. |

---

## 14. Implementation phases

1. **Kits + items**: discovery, anchor + side-door menu, take/put back, ground items, put-down key,
   uniqueness. Test with `/bagpos` and the claude-mcp probe (exports + logs, minimal screenshots).
2. **Carrying**: hand objects, offsets, locked controls, vehicle enter rules, carrier leave.
3. **medsys gating**: adapter, `equipment` fields, availability/start checks, panel icons,
   `MEDIC.REQUIRE_EQUIPMENT` switch, monitor link.
4. **Stock**: counts, consumption hooks, oxygen drain, medication grid doses, restock in bays.
5. **Left-behind watch**: detection, warnings, blips, abandon.
6. **Static monitor screen** (removable module).
7. **work_ems tutorial** step + README.

---

## 15. Decisions (all answered 2026-10-09)

| # | Question | Decision |
|---|---|---|
| Q1 | Should CPR need the bag? | **Decided: no**, CPR is hands only. |
| Q2 | Glucometer, bandage, splint: unlimited, or counted like drugs? | **Decided: unlimited** for now (config-ready). |
| Q3 | May a medic stow *another* ambulance's item? | **Decided: no**, only its own. |
| Q4 | med_bag not running: what does medsys require? | **Decided: no equipment** (old behaviour). |
| Q5 | Restock cost? | **Decided: free.** |
| Q6 | Left-behind: add a v_radar waypoint to the item automatically? | **Decided: blip only.** |
| Q7 | Show *"Equipment missing"* in the hospital bay label? | **Decided: yes.** |
| Q8 | Abandoned item: fine the unit? | **Decided: no fine** for now; empty stock is the penalty. |

---

## 16. Patient flow with the stretcher (v2, implemented 2026-10-09)

Replaces the first version. The user's new rules:
* **No equipment hangs at a medic's side while pushing**: it is fixed to the side of the stretcher.
* **Oxygen is consumed continuously**, also in the ambulance (no pause for transport / handover).
* **The side door always gives out what is in the ambulance**, whatever the stretcher does.
* This revises "the stretcher has nothing to do with the equipment" (section 6.4): the equipment
  may now ride on the stretcher's side; the stretcher itself is still the patient's bed.

### 16.1 Item states (one more)

```
                 take (side door)                 put down (H)
   STOWED  ─────────────────────────►  CARRIED  ──────────────►  GROUND
     │  ▲                                │  ▲                        │
     │  │ stretcher loaded               │  │ take off (stretcher    │ put on (stretcher menu,
     │  │                    push start /│  │  menu)                 │  item within 2 m)
     │  │                    put on      ▼  │                        ▼
     │  └───────────────────────────── STRETCHER ◄─────────────────────┘
     │   taken out WITH a patient  (only items marked "aboard")
     └──────────────────────────────────►
```

* `stretcher`: a server object attached to the stretcher object's side (`BAG.STRETCHER_OFFSETS`:
  bag on the lower shelf, monitor on the side rail). It follows the stretcher everywhere (ground,
  pushed, sliding in / out) because it is attached to it.
* `stowed` gets a flag `aboard = stretcher object`: the item went into the ambulance **on** the
  stretcher.

### 16.2 When is an item on the stretcher

| Event | What happens to the items |
|---|---|
| A medic **starts pushing** while carrying items | They go onto the stretcher's side (both hands are on the handle). |
| Stretcher menu **Put bag / monitor on stretcher** (carried, or lying within 2 m) | onto the side. |
| Stretcher menu **Take bag / monitor** | off the side into the hands (any medic, also the pusher's colleague). |
| **Releasing** the stretcher | They stay on it (nothing jumps back into the hands). |
| **Loading** the stretcher into its ambulance | Items of **this** ambulance -> `stowed` + `aboard`. Other ambulances' items -> put down behind the vehicle (Q3), their crew is warned. |
| **Taking out** the stretcher **with a patient** (scene or hospital) | `aboard` items come out on it again: the equipment follows the patient's bed. |
| Taking out the stretcher **empty** | `aboard` is cleared, the items stay in the ambulance. |
| **Side door: Take** | Always works for a `stowed` item, `aboard` or not (clears `aboard`). An item that is out on a stretcher is not in the ambulance, so the side door shows it as "On the stretcher". |
| Stretcher destroyed / ambulance destroyed | items on it go to the ground / are lost with the kit. |

The stretcher menu is merged into med_stretcher's menu on the same object (ui_interactobject merges
menus of several resources on one element): an "Equipment" group, priority below the stretcher's.

### 16.3 Range and oxygen (continuous)

* An item **serves** a patient when: carried / on the ground / on a stretcher within `USE_RANGE`
  (4 m) - **or** `stowed` in the very ambulance the patient sits in.
* A connected item (the bag feeding the oxygen, the linked monitor) keeps working within
  `CONNECT_RANGE` (6 m) - a medic can walk beside the stretcher with the bag in hand.
* **Oxygen drains all the time while the mask / the tube is on**: at the scene, on the stretcher, in
  the ambulance (from the stowed bag), at the handover. The transport pause of section 6.3 is removed
  (medsys `isPatientInTransport` was removed).
* Loading keeps the oxygen on: the patient lies on the stretcher next to the items during the slide
  (they are attached to it), and at the end both are in the same ambulance (patient seated, items
  `stowed`), so the bag serves the patient the whole time. No phase logic is needed any more.
* Bag left outside while the patient is in the ambulance -> the normal rules: out of 6 m -> mask off /
  the tube has no effect, the monitor disconnects.

### 16.4 Handover

1. Taken out at the hospital with the patient: the `aboard` bag and monitor come out on the
   stretcher, the oxygen and the ECG stay connected while it is pushed to the handover marker.
2. Handover done (the ped disappears / a player patient is released): the sessions end, the items
   **stay on the stretcher**.
3. The crew loads the empty stretcher: the items go back into the ambulance (`stowed`, `aboard`
   cleared because there is no patient) -> **Restock** at the bay as usual.
4. If they push the stretcher away or leave it, the items on it count for the left-behind warning
   (position = the stretcher, the same rules as for items on the ground).

### 16.5 Visual / HUD

* Items on the stretcher are real server objects attached to it: everyone sees them; no hand objects.
* The carry HUD shows nothing for them; the stretcher's pusher sees a line "On the stretcher: bag,
  monitor" under the HUD while pushing.

### 16.6 Changes

| Resource | Change |
|---|---|
| **med_stretcher** | Events only: `onStretcherPushStart/Stop(player)`, `onStretcherLoadStart(player, vehicle, patient)`, `onStretcherLoaded(player, vehicle, patient)`, `onStretcherTakenOut(player, vehicle, patient)`; and the stretcher object is exported via the existing `getVehicleStretcher`. |
| **med_bag** | `stretcher` state + `aboard` flag, stretcher menu group, auto put-on at push start, load / take-out handling, serving rule for the patient inside the ambulance, oxygen without the transport pause, left-behind for stretcher items. |
| **medsys** | None. |

### 16.7 Decisions (2026-10-09)

| # | Question | Decision |
|---|---|---|
| S1 | Push start with items in the hands | They go onto the stretcher. |
| S2 | Other ambulances' items | A stretcher belongs to one ambulance: only that ambulance's items can go on it, no mixing. Foreign items in the pusher's hands are put down at push start. |
| S3 | After the handover | The items stay on the stretcher until it is loaded. |
| S4 | Stretcher taken out empty | The `aboard` items stay inside. |
| S5 | Connected range | 6 m (`BAG.CONNECT_RANGE`) for oxygen and monitor; a new action needs 4 m. |

Implementation: `server/stretcher.lua` (events, stretcher menu group, `medbag.onStretcher` data),
`putOnStretcher` / `stowItem(item, aboard)` in `server/kits.lua`, serving rules in `server/stock.lua`,
the pusher's "On the stretcher" HUD in `client/hud.lua`. med_stretcher only fires
`onStretcherPushStart/Stop`, `onStretcherTakeOut`, `onStretcherLoadStart`, `onStretcherLoaded`.
`BAG.STRETCHER_OFFSETS` are guesses: tune them in-game.
