# v_inventory

Item system: left / right hand and back slots, containers measured in kg, ports (storage markers),
trunks, items attached to elements or stored in vehicles, and one item UI. Nothing is saved: other
resources create every item through the exports (med_bag, later bt_items).

Full design (Hungarian): [DESIGN.md](DESIGN.md). UI mockups: `docs/mockups/`.

## Controls

| Key | What |
|---|---|
| `I` | own inventory window (ESC / I closes) |
| `H` | put down what is in the hands |
| `E` | open the storage while standing in a port marker (needs a container in a hand / on the back) |
| `X` menu | pick up / open an item on the ground, open a trunk |

In the window: drag & drop, double click = quick move, Shift = one piece of a stack, drag a held item
out of the window = put it down.

## Example

```lua
local inv = exports.v_inventory
local box = inv:createItem("bt_blood_box", {
    display = { { label = "From", value = "LS Blood Bank" }, { label = "To", value = "All Saints" } },
}, { type = "none" })
inv:giveItemToPlayer(player, box)

local port = inv:createPort({ x = 1172, y = -1323, z = 15, name = "All Saints", title = "Blood reception",
    dataKey = "work.id", dataValue = "bloodtransport" })
inv:setPortRules(port, player, { allowIn = { "bt_blood_box" }, allowOut = false })
inv:setPortSuggestions(port, player, { [box] = "in" }, "Deliver the box")
```

New item types go into `shared/items.lua` + `v_locals/locales/<lang>/v_inventory.json`.

## Tests

`python tests/run.py` (lupa, Lua 5.1).
