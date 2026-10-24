# gov_railways — the railway as a public service

Part of `[government]` (see gov_core README). /gov page **Railways** (category Public services).

- **Operator** (setting `rail.operator`, minister / admin only): the state company or private
  company that runs the railway, or nobody (default). Its members — everyone with bank access to
  the company's account — open /gov (they get only this page, role "sector") and edit the
  timetable (gov_core sector `railways`).
- **Routes**: the fixed lines of rw_timetable (stops, minutes between them, start stations).
- **Timetable**: the rows of the MySQL table `rw_timetable`. A row = line + stretch (from / to)
  + departures (interval: first .. last every N min; or one single train, optionally with its own
  number) + days of the week (+ optionally one date). Add, edit, pause / resume, delete. The rows
  are checked by rw_timetable (`checkScheduleRow`), written here, then `reloadTimetable()`.
- **Departures**: the trains of today .. +6 days as they will run, per line.

The current timetable (= the seed of the table): `[railways]/rw_timetable/TIMETABLE.md`.
Changes are logged in gov_log: `rail.row.create / update / toggle / delete`, `rail.operator`.

| Export | |
| --- | --- |
| `getRailOperator()` | `"none"` \| `"state:<code>"` \| `"company:<id>"` |
