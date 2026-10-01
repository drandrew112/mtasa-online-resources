# ui_interactobject

3D world-space interaction menus attached to **objects, peds, players and vehicles**. Other
scripts register menus through exports and this resource handles everything else: finding nearby
targets, drawing, input, and (for server menus) validating the selection.

## Controls

| key | action |
|---|---|
| `Q` / `E` | switch focus between the nearby menus (left / right on screen) |
| `X` | open / close the focused menu |
| `1`-`9` (or numpad) | pick an option (opens a submenu if the item has one) |
| `0` | next page, if the menu has more than 9 options |
| `Backspace` | up one submenu level, or close |

Every nearby element with a menu gets a small dot above it. The focused element (the nearest one
by default) shows a `[X] Title` prompt. While the menu is open, a numbered panel hangs next to it.
If one element has menus from several resources (e.g. medical + stretcher), they merge into one
panel, grouped by menu title and ordered by `priority`.

Keys are in `shared/config.lua`. Q/E and the mouse wheel switch weapons on foot, so weapon
switching is blocked only while a menu is open or at least 2 menus are in range. Nothing shows while
the cursor is visible, the chat or console is open, the player is dead, or any `IO.BLOCKING_DATA`
panel flag is set (the same flags `ui_inac` uses).

## Architecture

```
shared/config.lua     IO tunables (keys, ranges, timings)
shared/util.lua       definition sanitising, path resolution, data filters
server/registry.lua   server menus, sync to clients, selection validation, server exports
client/registry.lua   local + synced menus in one table, client exports
client/scan.lua       nearby-target scan, focus, open/close
client/view.lua       what the open panel shows (merged root list / submenu, paging)
client/input.lua      key binds, selection dispatch
client/render.lua     markers, prompt, panel
```

## Menu definition

```lua
{
    title = "Patient",           -- prompt + panel title
    range = 3.0,                 -- metres (default IO.DEFAULT_RANGE, max IO.MAX_RANGE)
    priority = 10,               -- higher = listed first when an element has several menus
    offset = { 0, 0, 0.2 },      -- extra offset for the marker/panel anchor
    lineOfSight = true,          -- require a clear line to the target (default true)
    allowInVehicle = false,      -- usable from inside a vehicle (default false)
    enabled = true,
    dataKey = "medic.status",    -- only if the TARGET has this element data (truthy)...
    dataValue = nil,             -- ...or exactly this value, if set
    selfDataKey = "isMedic",     -- only if the LOCAL PLAYER has this element data (truthy)
    items = {
        { label = "Examine", value = "examine", desc = "Open the examination panel" },
        { label = "Put on stretcher", value = "stretcher", disabled = true },
        { label = "Treat", title = "Treatment", items = {   -- submenu
            { label = "Bandage", value = "bandage" },
            { label = "CPR", value = "cpr", closeOnSelect = false },
        } },
    },
}
```

- `value` must be serialisable (number, string, boolean, element, or a table of those). Functions
  cannot cross a resource boundary, so there are no callbacks: the result arrives as an event.
- `closeOnSelect` defaults to `true`.
- The anchor is above the head for peds/players and on top of the bounding box for everything else.

## Server exports (menus every / the listed players see)

```lua
local id = exports.ui_interactobject:addInteractMenu(element, def [, visibleTo])
local id = exports.ui_interactobject:addInteractTypeMenu("ped", def [, visibleTo])  -- every element of a type
exports.ui_interactobject:updateInteractMenu(id, { title = "...", items = {...} })  -- merges fields
exports.ui_interactobject:setInteractMenuItems(id, items)
exports.ui_interactobject:setInteractMenuEnabled(id, bool)
exports.ui_interactobject:setInteractMenuVisibleTo(id, visibleTo)  -- nil = everyone
exports.ui_interactobject:removeInteractMenu(id)
exports.ui_interactobject:isInteractMenu(id)
exports.ui_interactobject:closeInteractMenuFor(player)
```

`visibleTo` is `nil` (everyone), a player, or a table of players. The result:

```lua
addEventHandler("onInteractMenuSelect", root, function(menuId, value, target, path)
    -- source = the player who picked the option
end)
```

Before this fires, the server re-checks the menu, visibility, `enabled`, `dataKey`, `selfDataKey`,
distance (`range + IO.SERVER_RANGE_TOLERANCE`), dimension/interior, and that the item exists and is
not disabled. `value` comes from the server's own copy, not the client.

## Client exports (local-only menus)

Same `addInteractMenu(element, def)`, `addInteractTypeMenu`, `updateInteractMenu`,
`setInteractMenuItems`, `setInteractMenuEnabled`, `removeInteractMenu`, `isInteractMenu`, plus:

```lua
exports.ui_interactobject:isInteractMenuOpen()        -- bool
exports.ui_interactobject:getInteractTarget()         -- focused element or false, isOpen
exports.ui_interactobject:closeInteractMenu()
exports.ui_interactobject:setInteractionDisabled(bool) -- hide all menus while e.g. your panel runs
```

```lua
addEventHandler("onClientInteractMenuSelect", root, function(menuId, value, target, path) end) -- local menus only
addEventHandler("onClientInteractMenuOpen", root, function(target) end)
addEventHandler("onClientInteractMenuClose", root, function(target) end)
```

Client menus with ids starting `c` never reach the server. Server menus have ids starting `s`.

## Lifetime

- Menus bound to an element are removed when it is destroyed (or the player quits).
- Menus are removed when the resource that registered them stops, and so is its
  `setInteractionDisabled`.
- If `ui_interactobject` restarts, every registration is lost. Consumers should register again
  on `onResourceStart` / `onClientResourceStart` of `getResourceFromName("ui_interactobject")`.
- Add `<include resource="ui_interactobject" />` to the consumer's meta.xml.

## Example (server, medical + stretcher on the same patient)

```lua
local iobj = exports.ui_interactobject

local medicMenu = iobj:addInteractTypeMenu("ped", {
    title = "Patient", priority = 10, dataKey = "medic.status", selfDataKey = "isMedic",
    items = { { label = "Examine", value = "examine" } },
})

local stretcherMenu = iobj:addInteractMenu(stretcherObject, {
    title = "Stretcher", items = { { label = "Push", value = "push" }, { label = "Fold", value = "fold" } },
})

addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    if menuId == medicMenu and value == "examine" then
        -- open the examination for `source` on `target`
    end
end)
```
