# med_web – San Andreas EMS website

Website of the ambulance service, built on **web_api**. A public landing page and the staff pages
of med_erm as sub-pages. English only.

| page | HTTP | source | sign-in |
| --- | --- | --- | --- |
| landing page | `/med_web/` | `web/index.html` | – |
| dispatcher console | `/med_web/dispatch.html` | `web/dispatch.html` | dispatcher code (med_erm `data/dispatchers.json`) |
| unit tablet | `/med_web/tablet.html` | `web/tablet.html` | game account, member of a signed-in unit |
| ERM admin | `/med_web/admin.html` | `web/admin.html` | game account, admin level ≥ med_erm `Config.ADMIN_LEVEL` |

In game the site is `ems-dispatch.eu` in ui_browser (category Services). It opens the landing page;
its links lead to the other pages through web_api's loader (`web/js/common.js`: `MedWeb.pageUrl`).

## Layout

```
med_web/
├─ meta.xml
├─ index.html dispatch.html tablet.html admin.html   HTTP entries: MedWeb.render("<page>")
├─ server/
│  ├─ pages.lua            page builder (web_api renderPage) + in-game site registration
│  └─ api.lua              http="true" exports: medWebPublic + the erm* calls forwarded to med_erm
└─ web/
   ├─ *.html               page sources (also the in-game pages)
   ├─ css/home.css         landing page
   ├─ css/erm.css          dispatcher / tablet / admin
   ├─ js/common.js         links between the pages (HTTP and in game)
   ├─ js/home.js           landing page: live figures, hospital map
   ├─ js/api.js            ERM facade over OSA (token, helpers, status texts)
   ├─ js/map.js chat.js dispatch.js   dispatcher console
   ├─ js/tablet.js         unit tablet
   ├─ js/admin.js          ERM admin
   └─ sounds/tablet_alert.mp3
```

## API

Only the `http="true"` exports of `meta.xml` can be called by the pages (`POST /med_web/call/<fn>`, in game
relayed by web_api).

- `medWebPublic()` – landing page: units on duty (by status), active task count, hospitals
  (name, position, bays) from med_hospitals. Anonymous figures only, cached for 3 s.
- `erm*` – forwarded unchanged to `exports.med_erm:webCall(callerId, fn, ...)`; the logic and the
  sessions are in med_erm (see its README). `callerId` = `web_api:getCallerId(hostname)` (HTTP
  address or `player:<serial>`), med_erm uses it for the login throttles. med_erm not running ->
  `{ ok = false, error = "The dispatch system (med_erm) is not running." }`.

## HTTP access

No MTA login: guests need HTTP in the **Default** ACL (`acl.xml`, `<acl name="Default">`):

```xml
<right name="general.http" access="true"></right>
```

then `reloadacl`. The pages appear on web_manager automatically (`index.html` is the default page).

## Dispatcher console

- **Tasks**: `Not assigned` → `Prioritized` (select a task and press **P1–P4**, or right-click →
  Priority) → `Assigned` (drag the task onto a unit in the list or on the map, or right-click →
  Assign unit). A unit can hold one task, a task several units. **+ New** / right-click on the map
  creates a task. Closed tab = recent history.
- **Map**: v_radar bigmap. Tasks = dots, units = callsign labels in their status colour. Hover =
  details, right-click = the list actions. Wheel zoom, drag to pan, double-click a list entry to
  centre it.
- **Chat**: Broadcast (all units), per unit, per task. Crew replies arrive in the unit's thread.

Task -> unit dragging is pointer-event based, because MTA's offscreen CEF has no HTML5 drag & drop.
The session token lives in page memory only (a reload asks for the code again).
