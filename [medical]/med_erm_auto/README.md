# med_erm_auto – ERM Auto Dispatch

Automatic dispatcher for `med_erm`. While enabled it:

1. **Prioritizes** every open task that has no priority yet: `meta.priority`
   (1-4 or `"P1"`..`"P4"`, set by the creating resource – later
   `med_generator`), otherwise **P1**. Priorities already set by a dispatcher
   are left alone.
2. **Assigns** the **nearest free unit** (status Available, no task) to every
   waiting task (prioritized, no unit). With more tasks than free units the
   queue is ordered by priority (P1 first), then by age (older first); the
   rest waits until a unit becomes free (handover finished, released, signed in).

Everything goes through med_erm's exports, so the web console, the tablets and
the database behave exactly as with a human dispatcher (the crew gets the
usual "New case assigned" notification). Dispatchers can still act manually
while it runs. A released task (unit unassigned) is dispatched again.

A pass runs 250 ms after any relevant med_erm event (task created / updated /
priority changed / unassigned, unit sign-in / status change / handover
complete) plus every 5 s as a fallback. Assignments are written to the server log.

## On / off

- `/ermadmin` → **Auto dispatch: ON/OFF** button in the header (med_erm).
- The web dispatcher console (HTTP and in-game ems-dispatch.eu) shows a green
  **AUTO DISPATCH** badge in the top bar while it is on.
- The state is kept in the resource setting `enabled` (survives restarts,
  default off).

## Exports (server)

```lua
exports.med_erm_auto:getAutoDispatch()               -- -> bool
exports.med_erm_auto:setAutoDispatch(enabled [, by]) -- -> true; by = name for the log
```

Event on med_erm_auto's root: `onErmAutoDispatchChange (enabled, by)`.

## Task meta (for task generators)

```lua
exports.med_erm:createTask("Cardiac arrest", "...", x, y, z, "Caller", nil, { priority = 2 })
```

Passing `priority` as createTask's own argument also works – the task is then
already prioritized and only gets a unit.
