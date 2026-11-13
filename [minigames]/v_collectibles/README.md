# v_collectibles

Collectible items placed around the world. Every player only sees the items he has not collected yet.

## Lists

One JSON file per list: `data/lists/<id>.json` (`data/index.json` is the fallback list of ids when the server
has no `pathListDir`). The header says which object models the items may use:

```json
{
    "id": "hidden_packages",
    "name": "Hidden Packages",
    "models": [ 1276, 954 ],
    "event": false,
    "enabled": true,
    "spin": true,
    "reward": 2000,
    "nextId": 3,
    "items": [
        { "id": 1, "model": 1276, "x": 2495.1, "y": -1687.4, "z": 13.9, "rx": 0, "ry": 0, "rz": 90, "int": 0, "dim": 0 }
    ]
}
```

- `event: true` = the list is only active while an events_core event switches it on (see below).
- `reward` = cash (euro) for every picked-up item of the list, default 2000, 0 = none. Set per list in the editor (R > Reward), which also shows the total money available with the current item count (reward x items; also in the hint bar).
- `enabled: false` = nobody sees it (new lists start disabled, so a half-made list never reaches the players).
- Item ids are never reused: the collected state refers to them. Deleted items no longer count in `found/total`.
- Hand edits are fine; restart v_collectibles afterwards.

## Save / load

- The server loads every list on start.
- Collected items: MySQL `collectibles_found` (account, list_id, item_id, found_at), created on start
  (`database.sql`, also in the repo-root `main.sql`).
- After v_loading finished (`loaded` element data / `onPlayerLoaded`) and the client script runs, the player gets the
  ACTIVE lists with the items he has not collected. Any change (editor, event on/off) re-sends them to everyone.

## Pickup

The client creates the objects within 150 units (collisions off) and picks an item up closer than 3 units.
The server re-checks (8 units, same interior/dimension), saves it, and the client shows the ui_core banner:
title = list name, text = `found/total`.

Server events for other resources (source = player): `onPlayerCollectibleFound(listId, itemId, count, total)`,
`onPlayerCollectibleListCompleted(listId, total)`.

## ui_inac Collectibles menu

The client keeps the LOCAL element data `collectibles.lists` = `{ { id, name, event, count, total }, ... }` (active
lists only). `ui_inac/client/collectibles.lua` regenerates the rows below the fixed ones (stunt jumps, UFO parts)
whenever it changes: on join, on pickup, and when an event list is switched on or off.

## Event lists

`events_core:registerEvent(id, { ..., collectibles = { "list_id", ... } })`. events_core pushes
`setEventListEnabled(listId, on)` like the models / maps; a list must also have `"event": true` (the editor's
"Event list" switch), otherwise events_core logs a warning. Christmas: `events_xmas/config.lua` `collectibles = { }`.
Test: `/events xmas on` - the list appears in the world and in the ui_inac menu; `/events xmas auto` to go back.

## Editor: /collecteditor (admin_level >= 5)

- **R** menu: pick / create list, items (nearest first: teleport, delete), name, header models (add / remove),
  Enabled, Event list, Spinning objects, delete list, close.
- **F4** add item: the cursor appears and the object follows it on the world surface. Wheel = next / previous model of
  the header, Shift + wheel = rotate 15°, left click = place, Ctrl + left click = place and keep placing,
  right click / Backspace / F4 = cancel. The item gets your interior / dimension.
- Every change is written to the JSON file at once. While the editor is open the normal collectibles are hidden and
  nothing can be picked up; all items of the current list are shown with their `#id`.
