# v_mysql

Shared MySQL layer for the FreeV server. It owns the one database connection
and every persistent system in the mod goes through it — accounts, account
data, owned vehicles, and anything added later. There is **no localhost ↔ host
mirror sync**: both servers read and write the same tables.

## Setup

1. `cp config.example.lua config.lua` and fill in `MYSQL_CONFIG`
   (host / port / database / username / password). **`config.lua` is
   git-ignored** – it holds the credentials; everything else in the folder is
   versioned.
2. Create the tables: run [`../../main.sql`](../../main.sql) against that
   database (`mysql ... < main.sql`, or paste into phpMyAdmin / Adminer).
   `database.sql` in this folder is just the `accounts` slice of the same
   schema.
3. `v_mysql` has `download_priority_group 1000`, so the resource loader starts
   it before everything else. `v_accounts` `<include>`s it.

### Running without a database

Set `MYSQL_ENABLE_SYNC = false` in `config.lua` (the default in
`config.example.lua`). Then v_mysql **never connects** and every helper degrades
gracefully: `getAccData` returns `nil`, `setAccData` returns `false`, the
query/exec helpers are no-ops. Nothing persists — and nobody can log in
(v_accounts can't read the `accounts` table), so this is only for a throwaway
test server.

## Parts

### `core/mysql.lua` — connection wrapper

A thin wrapper around `dbConnect("mysql", ...)`. Connects on start, verifies
with a round-trip `SELECT 1`, pings every 30 s and reconnects on failure.

Exports (server):

| Export | Purpose |
| --- | --- |
| `mysqlIsConnected()` | `true` once the round-trip check has passed |
| `mysqlQuery(callback, sql, ...)` | Async SELECT; `callback(result, numRows)` or `callback(false, err)`. Callback style is only reliable **inside this resource**. |
| `mysqlQuerySync(sql, ...)` | **Blocking** SELECT. Returns the result table (maybe empty) or `false`. Safe cross-resource. Use for small, latency-tolerant lookups only — it stalls the server thread for the round trip. |
| `mysqlInsert(sql, ...)` | **Blocking** INSERT. Returns the new `AUTO_INCREMENT` id (`LAST_INSERT_ID()`) or `false`. |
| `mysqlExec(sql, ...)` | INSERT/UPDATE/DELETE, fire-and-forget. |
| `mysqlEscape(value)` | Quote/escape one value. Prefer `?` placeholders. |

`?` placeholders in every helper are substituted and escaped from the varargs.
Custom event: `mysql:connected` (at `resourceRoot`) when the link comes up.

### `scripts/accdata.lua` — account data store

**The full replacement for MTA's `getAccountData` / `setAccountData`.** The mod
no longer uses the built-in account system at all. `who` is a **player element**
or an **account-name string** (both work, online or offline).

| Export | Purpose |
| --- | --- |
| `getAccData(who)` | `{ key = value, ... }` copy of everything stored for the account. |
| `getAccData(who, key)` | The single stored value, typed (`string` / `number` / `boolean`), or `nil`. |
| `setAccData(who, key, value)` | Upsert one key. `value = nil` removes it. → `true` when queued. |
| `setAccData(who, { key = value, ... })` | Merge several keys in **one** DB write — use this on bulk saves (e.g. v_accounts' `save_all`). |
| `flushAccData(name)` | Drop the cache entry for an account (v_accounts calls it right after creating a row). |

```lua
local money = exports.v_mysql:getAccData(player, "bank_money") or 0
exports.v_mysql:setAccData(player, "bank_money", money + 500)
```

Most keys live in the `account_data` column as a JSON object:

```json
{ "bank_money": { "v": "1500", "t": "int" },
  "skin":       { "v": "295",  "t": "int" } }
```

`t` is one of `string` / `int` / `float` / `boolean`, so a value comes back the
same type it went in.

Four keys are **promoted to real columns** so a website / tooling can edit them
directly — `email`, `display_name`, `admin_level`, `created_at`. `getAccData` /
`setAccData` map them transparently; callers never need to know which is which.

A per-account in-memory cache serves reads without a round trip. It is filled on
first access, updated on every `setAccData`, and dropped on `onPlayerQuit` (two
servers share the table and do not sync live, so a cached value could otherwise
go stale after the player leaves).

## The `accounts` table

| Column | Written by |
| --- | --- |
| `account_name` | v_accounts on register (unique key, the identity) |
| `password` | v_accounts (bcrypt hash — `passwordHash` / `passwordVerify`) |
| `email` | `setAccData(who, "email", …)` |
| `display_name` | `setAccData(who, "display_name", …)` — defaults to the account name |
| `admin_level` | `setAccData(who, "admin_level", n)` (v_admin) |
| `account_data` | `setAccData` (everything else, JSON) |
| `created_at` / `updated_at` | first insert / every write |

## Dependency direction

`v_accounts` `<include>`s `v_mysql`. `v_mysql` includes nothing — it is the
lowest layer.
