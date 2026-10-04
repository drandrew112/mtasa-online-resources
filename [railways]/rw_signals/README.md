# rw_signals

Block signalling of both lines (see `../README.md`). Stretches, boundaries, the LV
single-track stretches (`SIG.SINGLE`, entry signals on both lines at both ends, one train at
a time) and tunables are in `shared/config.lua`; signals are generated at start.

Server exports: `getSignalList()`, `getSignalAspects()` (`{ ["id"] = 0|1|2 }`),
`getSignal(id)`, `getSignalAhead(consistId) -> { id, name, aspect, distance }`.
Client exports: `getSignalAhead(track, headTp, dir) -> id, name, aspect, distance`,
`getSignalAspect(id)`.

Events: server `onRailSignalPassedAtDanger(consistId, signalId, name)` (source: lead),
client `onClientRailSignalChange(signalId, aspect, name)`.

Aspects: 0 red, 1 yellow, 2 green. Signal names: `M`/`S` (main / second track) + boundary
index + `W`/`E` (the direction it faces trains going to).
