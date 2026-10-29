# erm – Emergency Response Manager

EMS dispatch system: tasks, units, dispatcher sessions and a **dx tablet** for ambulance crews
in game. Its web pages (dispatcher console, web tablet, ERM admin) are in **med_web**, which calls
the web API of this resource. All UI is English.

## Layout

```
erm/
├─ meta.xml
├─ shared/config.lua        keys, vehicles, unit types, statuses, timings
├─ server/
│  ├─ util.lua             time/text helpers, v_accounts wrappers
│  ├─ db.lua               MySQL via v_mysql: med_tasks + med_shifts
│  ├─ tasks.lua            task lifecycle, priority, assignment, response log
│  ├─ units.lua            sign-in/out, crew, status + case flow, handover timer
│  ├─ chat.lua             broadcast / unit / task messages (memory only)
│  ├─ tablet.lua           client -> server events of the tablet
│  ├─ dispatchers.lua      dispatcher codes (data/dispatchers.json) + sessions
│  ├─ http.lua             web API entry (webCall) + dispatcher console functions
│  ├─ webtablet.lua        web tablet functions
│  ├─ webadmin.lua         web ERM admin functions
│  ├─ admin.lua            /ermadmin permission + history queries
│  ├─ events.lua           server events for other resources (onErm...)
│  ├─ exports.lua          automation API (exports for other resources)
│  └─ main.lua             start / stop
├─ client/
│  ├─ gfx.lua              dx helpers (rounded rects, buttons, hit/scroll areas)
│  ├─ state.lua            unit state from the server, task objective (v_radar), notifications
│  ├─ tablet.lua           frame, header, hamburger menu, status column, input
│  ├─ pages/               login, home, case (Active Case), messages
│  ├─ admin/               /ermadmin panel (panel.lua lists, detail.lua views)
│  └─ fonts/               Roboto (copied from v_radar)
└─ data/                   dispatchers.json (codes)
```

## Web pages (med_web)

The dispatcher console, the web tablet and the ERM admin are pages of the **med_web** resource
(`http://<server>:<httpport>/med_web/`, in game `ems-dispatch.eu`) - see its README for the pages,
the HTTP ACL and the in-game site. They reach this resource through one export:

```lua
exports.med_erm:webCall(callerId, fn, ...)   -- fn = one of the erm* web functions below
```

`callerId` (HTTP address or `player:<serial>`, from `web_api:getCallerId`) is what the login
throttles count (`Web.callerId()`). The functions take the session token as their first argument:

- dispatcher (`server/http.lua`): `ermLogin / Logout / GetState / SetPriority / Assign / Unassign /
  CloseTask / CreateTask / SendMessage`
- web tablet (`server/webtablet.lua`): `ermTabletLogin / Logout / State / CaseAction / LeaveCase /
  CloseCase / SendMessage / EndShift`
- ERM admin (`server/webadmin.lua`): `ermAdminLogin / Logout / Query / Auto / AutoSet`

**Dispatcher login**: codes are in `data/dispatchers.json` (re-read on every login, no restart
needed); sessions expire after 10 min without requests:

```json
{ "dispatchers": [ { "code": "DRA112", "name": "DrAndres" } ] }
```

Codes are case-insensitive. The dispatcher appears as `Dispatcher <name>`
everywhere (chat sender, web-created task caller, close reason). 5 wrong codes
within a minute lock that client out for a minute.

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

Opens only inside an ambulance (`Config.TABLET_VEHICLES`: 416, 456, 487, 563) while not
signed in; after sign-in every crew member can open it anywhere.

- **Sign-in**: plate filled automatically, unit type bound to the vehicle
  (`Config.UNIT_VEHICLE_TYPES`: Skoda 598 = SOLO/DOC, helicopter 487/563 = HELI,
  any other ambulance = BLS/ALS; checked on the server too), crew list with Add (players within 10 m) / Remove. The opener is
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
- **Transport to hospital** (server/hospitalroute.lua): once a unit that reached
  its scene is farther than `Config.HOSPITAL_DEPART_RADIUS` (50 m) from it, every
  crew member gets a radar objective to the nearest hospital (med_hospitals
  `getNearestHospital` + `setObjectiveToHospital(..., keep = true)`). It is removed
  when the unit gets the Handover status (ambulance bay) and is not set again for
  that case. Needs med_hospitals running; nothing happens without it.
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
- **Automatic Start Response**: when the driver of a unit with an active case
  drives off (above `Config.RESPONSE_AUTO_SPEED`, 15 km/h) without Start
  Response, the response is started automatically - once on the way to the
  scene and once when leaving it (beyond `Config.ARRIVE_RADIUS`). End Response
  still works by hand and is not overridden again on the same leg.
- **Messages**: two channels, *Dispatch* (the unit's thread with the
  dispatchers; broadcasts show up here) and *Case* (case chat: every unit on
  the active task + the dispatchers). Unread counts per channel.

## Shift-end payment (server/payment.lua)

When a unit signs out (End Shift, the last member leaving, or disbanding),
it is paid for every task credited to its shift (`u.closedTasks`, same list the
tablet's Home page counts): one itemised line per task, via `work_core`'s
`payWork()` export, so the receipt shows exactly why. Rates and the work id:
`Config.PAY` (shared/config.lua).

- The amount per task is `base + perMinute * minutesWorked`, rated by how the
  unit's work on it ended (`outcome`: `handover`, `left`, `task closed`,
  `released`, `shift ended`, ...). A full hospital handover pays the most;
  `shift ended` (signed out mid-case) is rated 0/0 by default - the task still
  counts on the Home page, but nothing is paid for it.
- The total is split evenly among everyone who was ever part of the shift's
  crew (sign-in roster), not just whoever is still in the unit at sign-out.
  Only accounts with a live player element (still connected under the same
  element - a reconnect does not count) actually receive their share; a
  disconnected one is skipped.
- Needs `work_core` running (soft dependency, same as every other optional
  integration here); without it nothing is paid, nothing else changes.

## Database (v_mysql: med_tasks, med_shifts)

Schema + JSON-line formats: `database.sql` (also in the repo-root `main.sql`); the
resource creates both tables on start. SQLite (`data/erm.db`) is no longer used.
If v_mysql is not connected yet, the start waits for `mysql:connected`.

- `med_tasks`: id, title, description, caller, position, zone, priority, status,
  units (callsigns ever assigned), response_log (unit + start/stop),
  created/prioritized/assigned/closed date-times, close_reason, source
  (creating resource), meta (JSON), shifts (JSON lines: shifts it was given to).
- `med_shifts`: id, server, callsign, unit_type, plate, members (account names),
  closed_tasks (task ids), started_at, ended_at, end_reason, task_count,
  tasks (JSON lines: which task, when, how it ended).
- **Callsign check on sign-in:** a shift with `ended_at IS NULL` holds its
  callsign on every server sharing the database. A number typed on the tablet
  that is taken -> the player gets "already on duty"; the automatic number
  counts up from 1 until it finds a free one. Without the database only the
  local units count.
- On start the server closes its own open shifts (`end_reason = 'restart'`).

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
the **AUTO DISPATCH** badge in the web console's top bar (med_web, HTTP and in game).

## Tablet tutorial mode (client, for the work_ems tutorial)

`startTabletTutorial()` / `stopTabletTutorial()` / `isTabletTutorial()`: in tutorial mode every
tablet request (`Tablet.send`) is answered locally with demo data: sign-in, Start/End Response
and messages. Server pushes are ignored. `setTabletTutorialCase(task)`,
`setTabletTutorialUnit(fields)` and `addTabletTutorialMessage(text [, channel])` drive the demo.
Each step is reported through `onClientErmTabletTutorial(action, ...)` (source = localPlayer).
Server export `removePlayerFromUnit(player [, reason])`.

## Web tablet (med_web `tablet.html`)

The web tablet signs in with the
game account (`exports.v_accounts:httpLogin(username, password)` - credential + ban check, no player
needed; failed attempts throttled per account in v_accounts and per client in `server/webtablet.lua`).

- Not a member of a unit (no online player on that account in a unit): "You are not a member of any
  ambulance unit." The page follows the unit live (sign in / out in game).
- Member: Home / Active Case / Messages like the in-game tablet (start / end response, leave, close with
  reason, dispatch + case chat, end shift). A separate instance from the in-game tablet - both work at once.
- Alerts: `Units.notify` also queues events (`WebTablet.push`); the page toasts them and plays
  the tablet alert sound for alert events (the sign-in click unlocks browser audio).
- Page: med_web `web/js/tablet.js`. English only.

## Web ERM Admin (med_web `admin.html`)

The in-game `/ermadmin` panel in the browser - shift and task history
(search, filters, paging), shift / task details with back navigation, and the auto dispatch (med_erm_auto)
switch. Login with the game account (`v_accounts:httpLogin`); the admin level (`Config.ADMIN_LEVEL`, 1) is
checked at login and re-checked every call (online player's account data, otherwise the `accounts` table).
Server: `server/webadmin.lua` (queries are the `AdminHandlers` of `server/admin.lua`); page: med_web `web/js/admin.js`.
