# v_mysql

Shared MySQL layer for the FreeV server. Its job is to keep the **localhost dev
server** and the **hosted server** working off one database so account data does
not diverge between them.

## Setup

1. `cp config.example.lua config.lua` and fill in `MYSQL_CONFIG`
   (host / port / database / username / password). **`config.lua` is
   git-ignored** – it holds the credentials; everything else in the folder is
   versioned.
2. Create the table: run [`database.sql`](database.sql) against that database
   (`mysql ... < database.sql`, or paste into phpMyAdmin / Adminer).
3. Make sure `v_mysql` is in `mtaserver.conf` **after** `v_accounts`
   (`<resource src="v_mysql" startup="1" protected="0" />`).

### Running without the sync

Set `MYSQL_ENABLE_SYNC = false` in `config.lua` (it is the default in
`config.example.lua`). Then v_mysql **never connects to any database**:

* on login it immediately reports `accountdata` ready, so v_accounts loads and
  spawns the player with no delay;
* `updateAccountData()` is a no-op.

So a server that does not need the localhost ↔ host sync can keep this resource
installed and simply leave the switch off – nothing else has to change.

## Parts

### `core/mysql.lua` — connection wrapper

A thin async wrapper around `dbConnect("mysql", ...)`. Connects on start, verifies
with a round-trip `SELECT 1`, pings every 30 s and reconnects on failure.

Exports (server):

| Export | Purpose |
| --- | --- |
| `mysqlIsConnected()` | `true` once the round-trip check has passed |
| `mysqlQuery(callback, sql, ...)` | SELECT; `callback(result, numRows)` or `callback(false, err)`. `?` placeholders are escaped from `...`. Callback style is only reliable **inside this resource**. |
| `mysqlExec(sql, ...)` | INSERT/UPDATE/DELETE, fire-and-forget. `?` placeholders escaped. |
| `mysqlEscape(value)` | Quote/escape one value. Prefer `?` placeholders. |

Custom event: `mysql:connected` (at `resourceRoot`) when the link comes up.

### `scripts/accountdata.lua` — account data sync

Mirrors every player's MTA account data 1:1 into `global_account_data`.

* **On login** (`onPlayerLogin`): the row is fetched, decoded and written back
  into the account with `setAccountData()`, then v_accounts is told the
  `accountdata` loading step is finished
  (`exports.v_accounts:loadingComplete`). Every save is logged to the console.
* **Push** — export `updateAccountData(player)` upserts the player's whole
  current account-data snapshot. v_accounts' save system calls it on every
  periodic autosave, logout, quit and resource stop.

Stored `account_data` column format (JSON):

```json
[
  {"key":"money-BETA","value":"1500","valueType":"int"},
  {"key":"x","value":"1685.68","valueType":"float"},
  {"key":"skin","value":"295","valueType":"int"}
]
```

`valueType` is one of `string` / `int` / `float` / `boolean`.

## The `onPlayerLoaded` event (in v_accounts)

Because the account-data sync is **asynchronous**, anything that reads a
player's account data must not do it on `onPlayerLogin` (that fires *before* the
DB round trip). v_accounts instead fires a custom server event once the player
is fully ready – account data synced, saved state restored, player spawned:

```lua
addEvent("onPlayerLoaded")               -- every consuming resource needs this
addEventHandler("onPlayerLoaded", root, function(account)
    local player = source
    -- getAccountData(account, ...) is now the synced value
end)
```

`source` = the player, argument 1 = the account. This replaces every
`onPlayerLogin` handler in the other resources (v_bank, v_levelsys,
v_playedtime, v_admin, v_chat, v_socialpanel, ui_pause, ui_phone). Resource
restarts with players already online are still handled by each resource's own
`onResourceStart` loop.

When `MYSQL_ENABLE_SYNC = false`, `onPlayerLoaded` still fires – just with no
delay, right after login.

## Dependency direction

`v_mysql` `<include>`s `v_accounts` so it starts after it. `v_accounts` must
**not** include `v_mysql` back — it calls these exports defensively
(`getResourceState` guard) so it keeps working when `v_mysql` is absent.
