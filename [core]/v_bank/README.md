# v_bank — bank manager

Server-side bank account manager. `bank_money` lives on the player element data
at runtime and is mirrored into the shared `accounts` table
(`exports.v_mysql:getAccData` / `setAccData`), so it survives reconnects and
resource restarts. **Cash** is GTA's own money and is only moved by the built-in
`takePlayerMoney` / `givePlayerMoney`.

Depends on `v_mysql` (`<include resource="v_mysql" />`).

## Persistence

| Event | Action |
| --- | --- |
| `onPlayerLoaded`, `onResourceStart` | account → element data load (first login: 0) |
| `onPlayerQuit`, `onResourceStop` | element data → account save |
| every 5 minutes | save every logged-in player |
| every export that modifies the balance | immediate save of that player |

For a player who is not logged in, `bank_money` only exists at runtime and is
never saved.

## Server exports

```lua
local bank = exports.v_bank
```

### `takeBankMoney(player, amount)`
Removes money from the bank account.
- `true` — success
- `"not_enough_money"` — not enough money on the account
- `"player_not_found"` — invalid player element or `amount`

### `giveBankMoney(player, amount)`
Adds money to the bank account.
- `true` — success
- `"player_not_found"` — invalid player element or `amount`

### `depositMoney(player, amount)`
Takes cash and adds it to the account.
- `true` — success
- `"not_enough_cash"` — not enough cash
- `"player_not_found"` — invalid player element or `amount`

### `withdrawMoney(player, amount)`
Takes money from the account and hands it over as cash.
- `true` — success
- `"not_enough_money"` — not enough money on the account
- `"player_not_found"` — invalid player element or `amount`

> **Deviation from the spec:** `withdrawMoney` checks the bank balance, so its
> insufficient-funds error is `"not_enough_money"` (consistent with
> `takeBankMoney`), not `"not_enough_cash"`. If you need the `"not_enough_cash"`
> string instead, it is a one-line change in `server.lua`.

Every export rounds `amount` to a positive integer; `0` or a negative value
returns `"player_not_found"` (invalid input).

### `playPickupMoneySound([player])`
Plays the "pickup money" sound.

- **Server export:** `exports.v_bank:playPickupMoneySound(player)` — plays for the
  given player. Without `player` it plays for everyone. Returns `true` or
  `"player_not_found"`.
- **Client export:** `exports.v_bank:playPickupMoneySound()` — plays for the local
  player, returns the sound element (or `false`).

### `createMoneyPickup(x, y, z, money [, player])` — server
Creates a money bag pickup (model `1550`). When a player walks into it: they get
`money` cash, the pickup sound plays for them, `ui_core:showMoney("add", money)`
runs on their client, and the pickup is destroyed.

- `money` — positive integer
- `player` — optional; when given, only that player can collect it; `nil` = anyone
- Returns: the pickup element, or `false` (invalid arguments)

## Client event

`v_bank:playPickupMoneySound` (triggered by the server) plays the sound on the
client; when it carries a `money` argument it also calls
`exports.ui_core:showMoney("add", money)`.
