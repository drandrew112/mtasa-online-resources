# erm – Emergency Response Manager

EMS dispatch system: a **web dispatcher console** served by the MTA HTTP
server and a **dx tablet** for ambulance crews in game. All UI is English.

## Layout

```
erm/
├─ meta.xml
├─ shared/config.lua        keys, vehicles, unit types, statuses, timings
├─ server/
│  ├─ util.lua             time/text helpers, v_accounts wrappers
│  ├─ db.lua               SQLite (data/erm.db): tasks + shifts
│  ├─ tasks.lua            task lifecycle, priority, assignment, response log
│  ├─ units.lua            sign-in/out, crew, status + case flow, handover timer
│  ├─ chat.lua             broadcast / unit / task messages (memory only)
│  ├─ tablet.lua           client -> server events of the tablet
│  ├─ dispatchers.lua      dispatcher codes (data/dispatchers.json) + sessions
│  ├─ http.lua             web console API (http="true" exports)
│  ├─ webbridge.lua        same API for the in-game (ui_browser) console
│  ├─ admin.lua            /ermadmin permission + history queries
│  ├─ events.lua           server events for other resources (onErm...)
│  ├─ exports.lua          automation API (exports for other resources)
│  └─ main.lua             start / stop
├─ client/
│  ├─ gfx.lua              dx helpers (rounded rects, buttons, hit/scroll areas)
│  ├─ state.lua            unit state from the server, task objective (v_radar), notifications
│  ├─ tablet.lua           frame, header, hamburger menu, status column, input
│  ├─ pages/               login, home, case (Active Case), messages
│  ├─ webpage.lua          ems-dispatch.eu site in ui_browser + call bridge
│  ├─ admin/               /ermadmin panel (panel.lua lists, detail.lua views)
│  └─ fonts/               Roboto (copied from v_radar)
├─ web/                    dispatcher console (index.html, css/, js/, img/map.png)
└─ data/                   dispatchers.json (codes); erm.db is created here
```

## Web dispatcher console

`http://<server-ip>:<httpport>/erm/` (default port 22005). No MTA login is
used, but MTA only serves guests when the **Default** ACL allows HTTP at all
(`general.http` is `false` there by default -> 401 / login prompt). In
`acl.xml`, `<acl name="Default">`:

```xml
<right name="general.http" access="true"></right>
<right name="resource.erm.http" access="true"></right>
```

then `reloadacl` in the server console (or restart). This opens HTTP for
guests on every resource that has `<html>` files or `http="true"` exports –
currently only erm; add `resource.<name>.http = false` for any future one that
must stay private.

The page is served by `web/http.html` (default page, server-side template):
it sends `web/index.html` with `css/style.css` and `js/*.js` inlined. Those
files are client files too (for the in-game version) and MTA serves client
files on their own path as `application/octet-stream`, which browsers refuse
as a stylesheet – so they must not be linked directly over HTTP. Only the map
(`web/img/map.png`, `<base href="/erm/web/">`) is loaded separately.

**Dispatcher login**: the page shows only a login panel until a valid
dispatcher code is entered, and asks again after every reload (the session
token lives in page memory only; sessions expire after 10 min without
requests). Codes are in `data/dispatchers.json` (re-read on every login, no
restart needed):

```json
{ "dispatchers": [ { "code": "DRA112", "name": "DrAndres" } ] }
```

Codes are case-insensitive. The dispatcher appears as `Dispatcher <name>`
everywhere (chat sender, web-created task caller, close reason). 5 wrong codes
within a minute lock that client out for a minute.

- **Tasks**: `Not assigned` → `Prioritized` (select a task and press **P1–P4**,
  or right-click → Priority) → `Assigned` (drag the task onto a unit in the
  list or on the map, or right-click → Assign unit). A unit can hold one task,
  a task can hold several units; the assigned units are shown on the task.
  **+ New** / right-click on the map creates a task. Closed tab = recent history.
- **Map**: v_radar bigmap. Tasks = red dots, units = callsign labels in their
  status colour. Hover = details, right-click = the same actions as the lists.
  Wheel zoom, drag to pan, double-click a list entry to centre it.
- **Chat**: Broadcast (all units), per unit, per task (every unit assigned to
  the task gets it). Crew replies arrive in the unit's thread.

### In game: `ems-dispatch.eu` (ui_browser)

The same console is a website in the in-game virtual browser (`ui_browser`,
category **Services**, address `ems-dispatch.eu`) and behaves exactly like the
HTTP page (same login, map, drag & drop, right-click menus, chat). It is the
same `web/` page loaded as a local CEF page (`http://mta/erm/web/index.html`,
ui_browser's `web` site type). There is no HTTP in game, so `web/js/api.js`
detects `mta.triggerEvent` and sends the API calls through
`client/webpage.lua` -> `server/webbridge.lua`, which runs the same
`http.lua` functions. The map image comes from v_radar's client files there,
so only the small html/css/js files are downloaded by players.

Task -> unit dragging is mouse-event based (not HTML5 drag & drop), because
the offscreen CEF of MTA does not support native DnD.

## Admin panel (/ermadmin)

`/ermadmin` – admin_level >= `Config.ADMIN_LEVEL` (1), read from v_mysql
account data like v_admin does; every query re-checks it. Mouse-driven dx
panel (`client/admin/`):

- **Shifts** tab: all shifts, newest first, 14 per page, search (callsign,
  crew account, plate, type), filter All / On duty / Ended. A shift shows its
  unit, plate, start / end / duration, live status if still on duty, crew
  (account names) and every task the unit worked on during the shift with
  assign / release time and outcome (handover, released, task closed, shift
  ended, server restart).
- **Tasks** tab: every task independent of shifts, search (#id, title, zone,
  caller, unit, source), filter All / Open / Closed. A task shows priority,
  status, caller, source resource, position, timeline (created / prioritized /
  assigned / closed + reason), description, the units (shifts) that worked it,
  the lights & siren log with durations and the automation `meta`.
- Rows in one view open the other (shift -> task -> shift ...); **Back** or
  Backspace returns, the mouse wheel scrolls the details.

The shift <-> task relation is stored in the `shift_tasks` table (see below);
shifts from before it existed fall back to their `closed_tasks` list.

## Tablet (J)

Opens only inside an ambulance (`Config.TABLET_VEHICLES`: 416, 563) while not
signed in; after sign-in every crew member can open it anywhere.

- **Sign-in**: plate filled automatically, unit type (SOLO, DOC, BLS, ALS,
  HELI), crew list with Add (players within 10 m) / Remove. The opener is
  always in the crew. Optional **unit number** (1-999) gives the callsign
  `<TYPE>-<NN>` (e.g. 7 + ALS -> `ALS-07`); left empty, the server assigns the
  lowest free number.
- **Status** (pill in the header): Available (green), En Route (red),
  On Scene (blue), Handover (yellow). There are no manual status buttons.
- **Menu** (three lines, top right): Home, Active Case, Messages, End Shift.
- **Home**: shift time, active case + cases closed in this shift.
- The active case is placed on the radar with `v_radar`'s `addObjective`
  (yellow marker + automatic route), updated/removed with the task. It is
  removed once the player arrives (`Config.ARRIVE_RADIUS`, 30 m) or the unit
  is On Scene, and does not come back for that task.
- **On Scene is automatic**: once the unit's vehicle or a crew member is within
  `Config.ARRIVE_RADIUS` of the unit's own task, the server sets On Scene (stops
  the lights & siren log). Scenes of tasks assigned to other units never count.
- **Active Case**: Start Response / End Response / Leave Case / Close Case.
  Start sets En Route and starts the lights & siren log, End stops the log.
  Leave Case releases the unit (only while another unit stays on the case).
  Close Case asks for a reason (false call, broken scene, ...) and closes the
  task; the reason is stored as `<callsign>: <reason>`. The handover is
  started by the hospital (med_hospitals) and the task is closed once its last
  unit has handed over.
- **Start Response reminder**: the driver of a unit with an active case, not
  yet on scene, gets a notification when driving off (above
  `Config.RESPONSE_WARN_SPEED`, 15 km/h) without Start Response.
- **Messages**: two channels, *Dispatch* (the unit's thread with the
  dispatchers; broadcasts show up here) and *Case* (case chat: every unit on
  the active task + the dispatchers). Unread counts per channel.

## Database (data/erm.db)

- `tasks`: id, title, description, caller, position, zone, priority, status,
  units (callsigns ever assigned), response_log (unit + start/stop),
  created/prioritized/assigned/closed date-times, close_reason.
- `shifts`: id, callsign, unit_type, plate, members (account names),
  closed_tasks (task ids), started_at, ended_at.
- `shift_tasks`: shift_id, task_id, callsign, assigned_at, released_at,
  outcome – which shift worked which task and how it ended.
- `tasks` also has `source` (creating resource) and `meta` (JSON).

## Automation API (server exports)

ERM is meant to be the interface of an external scenario / automation
resource: it can create real situations, prioritise them, pick and assign
units and react to what the crews do. Everything goes through the same rules
as the web console (priority before assignment, one task per unit), is visible
live to the dispatcher, reaches the tablets and is logged in the DB.

Mutating exports return `true` / an id, or `false, "error"`.

```lua
-- tasks
local id = exports.erm:createTask(title, description, x, y [, z [, caller [, priority [, meta]]]])
exports.erm:updateTask(id, { title =, description =, caller =, x =, y =, z =, meta = })
exports.erm:setTaskPriority(id, 1..4)
exports.erm:assignUnit(id, unitId)
exports.erm:unassignUnit(id, unitId)
exports.erm:closeTask(id [, reason])
exports.erm:getTask(id)                    -- open or recently closed
exports.erm:getTasks([status [, source]])  -- open tasks, optional filters

-- units
exports.erm:getUnits()
exports.erm:getUnitData(unitIdOrPlayer)    -- incl. x, y, z, zone
exports.erm:getVehicleUnit(vehicle)        -- unit signed in with that vehicle
exports.erm:getFreeUnits([types])          -- no task + Available; types "ALS" or {"ALS","BLS"}
local unit, dist = exports.erm:getNearestFreeUnit(x, y [, z [, types]])
exports.erm:setUnitStatus(unitId, "available" | "enroute" | "onscene" | "handover" [, handoverMs])
exports.erm:unitCaseAction(unitId, "start" | "stop" | "onscene" | "handover")  -- tablet button rules
exports.erm:setHandoverTime(unitId, ms | false)  -- re-time a running handover
exports.erm:completeHandover(unitId)             -- finish it now

-- messages (shown as dispatch messages on the tablet and the web chat)
exports.erm:sendMessage("broadcast" | "unit" | "task", target, text [, from])
```

- `priority` in `createTask` creates the task already prioritised.
- `meta` is any table owned by the creator (e.g. `{ scenario = "car_crash",
  victims = 2 }`); stored as JSON in the DB, returned in `task.meta`.
  `task.source` is the creating resource's name ("" = web console), so
  `getTasks(nil, getResourceName(getThisResource()))` returns your own tasks.
- `z` = 0 / nil lets the tablet's radar objective find the ground.

Task: `id, title, description, caller, x, y, z, zone, priority (0 = none),
status, units = {{id, callsign, status}}, responseLog, createdAt, closedAt,
closedLabel, closeReason, unitLog, source, meta`.

Unit: `id, callsign, type, plate, status, statusLabel, task (0 = none),
taskTitle, responding, members, accounts, x, y, z, zone, startedAt,
handoverEnds, closedTasks`.

### Events

Triggered on erm's resourceRoot – listen with `addEventHandler(name, root, fn)`:

| Event | Arguments |
| --- | --- |
| `onErmTaskCreated` | taskId |
| `onErmTaskUpdated` | taskId |
| `onErmTaskPriorityChanged` | taskId, priority, oldPriority \| false |
| `onErmTaskAssigned` | taskId, unitId |
| `onErmTaskUnassigned` | taskId, unitId |
| `onErmTaskClosed` | taskId, reason |
| `onErmUnitSignIn` | unitId |
| `onErmUnitSignOut` | unitId, callsign, reason |
| `onErmUnitStatusChange` | unitId, status, oldStatus |
| `onErmUnitHandoverStart` | unitId, taskId \| false, durationMs – **cancellable** |
| `onErmUnitHandoverComplete` | unitId, taskId \| false |
| `onErmMessage` | messageId, channel, target, from, fromDispatch, text |

**Arrival**: `setUnitStatus(unitId, "onscene")` does what the automatic On
Scene does (stops the lights & siren log, marks the scene reached, removes the
radar objective).

**Handover under external control**: the handover starts from `setUnitStatus(unitId, "handover")`; `onErmUnitHandoverStart`
fires first. Call `cancelEvent()` in it to switch off the automatic 30 s
finish, run your marker / animation, then call `completeHandover(unitId)`
(or `setHandoverTime(unitId, ms)` to let ERM finish it after ms). The unit
status is set to `handover` right after the event, so call those exports
after the handler has returned (e.g. from your marker/animation callback).

```lua
addEventHandler("onErmUnitHandoverStart", root, function(unitId, taskId)
    cancelEvent()                        -- we run the handover
    startHandoverScene(unitId, function() -- your marker + animation
        exports.erm:completeHandover(unitId)
    end)
end)
```

Example – auto-dispatch the nearest ALS/BLS to every new situation:

```lua
local id = exports.erm:createTask("Traffic accident", "2 cars, 1 injured", x, y, z,
    "911 caller", 2, { scenario = "crash" })
local unit = exports.erm:getNearestFreeUnit(x, y, z, { "ALS", "BLS" })
if unit then exports.erm:assignUnit(id, unit.id) end

addEventHandler("onErmUnitStatusChange", root, function(unitId, status)
    if status == "onscene" then --[[ spawn patients, start the scene ]] end
end)
```

## Auto dispatch (med_erm_auto)

The optional `med_erm_auto` resource prioritizes tasks (meta.priority or P1)
and sends the nearest free unit automatically – see its README.
`server/autodispatch.lua` is the bridge: `/ermadmin` has an
**Auto dispatch: ON/OFF** switch in the header (N/A when med_erm_auto is not
running) and `ermGetState` returns `auto = { available, enabled }`, shown as
the **AUTO DISPATCH** badge in the web console's top bar (HTTP page and
in-game site – http.html inlines index.html, so both get it).

## Tablet tutorial mode (client, for the work_ems tutorial)

`startTabletTutorial()` / `stopTabletTutorial()` / `isTabletTutorial()`: in tutorial mode every
tablet request (`Tablet.send`) is answered locally with demo data: sign-in, Start/End Response
and messages. Server pushes are ignored. `setTabletTutorialCase(task)`,
`setTabletTutorialUnit(fields)` and `addTabletTutorialMessage(text [, channel])` drive the demo.
Each step is reported through `onClientErmTabletTutorial(action, ...)` (source = localPlayer).
Server export `removePlayerFromUnit(player [, reason])`.
