# ISSUES — FreeV resource audit

Audit date: **2026-10-17** · Scope: every resource under `resources/` (126 `meta.xml`) · Server config: `mods/deathmatch/mtaserver.conf`, `acl.xml`

This file is the working list for the fix-up. Every entry has a **Status** field. When you start
or finish an item, update the status in **both** the index table and the entry itself.

## How to use

**Status values**

| Status | Meaning |
|---|---|
| `OPEN` | Not started |
| `IN PROGRESS` | Someone is working on it |
| `FIXED` | Fixed. Add the date and commit, e.g. `FIXED 2026-10-20 (abc1234)` |
| `VERIFIED` | Fixed **and** tested in-game / on the live server |
| `WONTFIX` | Deliberately left as is. Add the reason |

**Severity**

| Severity | Meaning |
|---|---|
| **CRITICAL** | Server takeover, account takeover, or leaked secrets. Fix before anything else |
| **HIGH** | Exploitable by an ordinary player (economy, griefing, DoS), or real data loss |
| **MEDIUM** | Wrong behaviour or a noticeable cost that gets worse as the player count grows |
| **LOW** | Cosmetic, hygiene, or only theoretical |

**ID prefixes**

| Prefix | Section |
|---|---|
| `SEC-` | Security and exploits |
| `BUG-` | Functional bugs |
| `PERF-` | Optimization (kept separate, as requested) |
| `SCALE-` | Things that break or degrade with many players or with two servers |
| `MAINT-` | Maintenance and hygiene |

**Method, and what it does not cover.** The audit combined automated scans (every remote
`addEvent(...,true)` handler, `client` usage, element-data writes, render handlers, timers, SQL
calls, download sizes) with a manual read of the hot spots. Not every line of the ~150k
hand-written Lua lines was read. Not reviewed: `[ui]/dgs` (third-party), `[tiktok]/*` (git-ignored,
started manually), generated data files (`vehiclenodes.lua`, `nodes.lua`, …). Resources that
were written recently (medsys, med_*, wp_manager, v_inventory, bt_*, work_*) validated their
remote events well wherever they were spot-checked. Most problems are in shared infrastructure
(v_mysql, v_accounts, web_api, claude-mcp) and in older or legacy resources.

**Suggested fix order:** SEC-01 → SEC-02 → SEC-03 → SEC-04 → the other HIGH items → PERF-01/02 → the rest.

---

## Index

| ID | Severity | Title | Status |
|---|---|---|---|
| [SEC-01](#sec-01) | CRITICAL | Remote Lua execution: any player → web_api bridge → claude-mcp `dev/exec` | WONTFIX (not on the public server) |
| [SEC-02](#sec-02) | CRITICAL | Client-writable element data used as identity/authority (`accName`, `admin_level`, `adminjail`, `xp`…) | OPEN |
| [SEC-03](#sec-03) | CRITICAL | Discord webhook URL committed to the public repo + open relay event | OPEN |
| [SEC-04](#sec-04) | CRITICAL | v_modmenu (freeroam) `onServerCall` acts on arbitrary elements | FIXED 2026-10-17 (not committed yet) |
| [SEC-05](#sec-05) | HIGH | Chat sender spoofing, no length or flood limit (v_chat) | FIXED 2026-10-17 (not committed yet) |
| [SEC-06](#sec-06) | HIGH | Remote events act on a player passed by the client (arena, respawn, pause menu) | OPEN |
| [SEC-07](#sec-07) | HIGH | Any client can append unlimited text to a server file (`pos:saveToFile`) | FIXED 2026-10-17 (not committed yet) |
| [SEC-08](#sec-08) | HIGH | Time trial reward farm (gated by client-set `tt:active`) | FIXED 2026-10-17 (not committed yet) |
| [SEC-09](#sec-09) | HIGH | Pre-login DoS: login/register not rate limited, each try = 2 blocking remote queries + bcrypt | FIXED 2026-10-17 (not committed yet) |
| [SEC-10](#sec-10) | HIGH | Social panel events trigger blocking DB work with no rate limit (DoS) | OPEN |
| [SEC-11](#sec-11) | HIGH | Unrestricted vehicle spawner (`ui_inac:spawnVehicle`) | OPEN |
| [SEC-12](#sec-12) | HIGH | Debug/dev commands open to every player (`spawnfix`, `fixme`, `pos`, `fadetrue`…) | OPEN |
| [SEC-13](#sec-13) | MEDIUM | Shop robbery: no distance check, parallel robberies, orphaned 80 ms timers | OPEN |
| [SEC-14](#sec-14) | MEDIUM | Vehicle element data set directly by clients (sirens, radio, tuning, GPS) | OPEN |
| [SEC-15](#sec-15) | MEDIUM | Web session tokens built from `math.random` | OPEN |
| [SEC-16](#sec-16) | MEDIUM | Over-privileged ACL (claude-mcp Admin+runcode, v_chat Admin) | OPEN |
| [SEC-17](#sec-17) | MEDIUM | Synchronous bcrypt in `httpLogin`, throttled only per username | OPEN |
| [SEC-18](#sec-18) | LOW | Nametags show account login names to everyone | OPEN |
| [SEC-19](#sec-19) | LOW | Report log filename filter misses `\` (Lua 5.1 escape) | OPEN |
| [SEC-20](#sec-20) | LOW | Self-updater pulls code from GitHub `main` without pinning | OPEN |
| [BUG-01](#bug-01) | HIGH | Cross-server lost updates in account data (whole-blob writes) | OPEN |
| [BUG-02](#bug-02) | MEDIUM | v_mysql: writes silently lost during a DB outage; fragile `LAST_INSERT_ID` | OPEN |
| [BUG-03](#bug-03) | MEDIUM | v_arenawar disables interior sounds for everyone, every frame | OPEN |
| [BUG-04](#bug-04) | MEDIUM | v_arenawar `random()` reseeds every call and returns the wrong range | OPEN |
| [BUG-05](#bug-05) | MEDIUM | Bans are stored per server in `bans.xml` | OPEN |
| [BUG-06](#bug-06) | LOW | v_playedtime keeps a timer in synced element data | OPEN |
| [BUG-07](#bug-07) | LOW | v_chat bypasses `onPlayerChat`; webhook ignores Discord rate limits | OPEN |
| [BUG-08](#bug-08) | LOW | world_cablecars draws its cables always, map line uses hard-coded pixels | OPEN |
| [PERF-01](#perf-01) | HIGH | Blocking `dbPoll(-1)` queries to a **remote** MySQL host on the main thread | OPEN |
| [PERF-02](#perf-02) | HIGH | `setAccData` rewrites the whole account JSON blob on every key | OPEN |
| [PERF-03](#perf-03) | HIGH | ~400 MB mandatory client download (v_modloader alone 313 MB) | OPEN |
| [PERF-04](#perf-04) | MEDIUM | 4.7 MB `vehiclenodes.lua` duplicated 4×, shipped as client script (one with `cache="false"`) | OPEN |
| [PERF-05](#perf-05) | MEDIUM | ~100 always-attached `onClientRender`/`PreRender` handlers | OPEN |
| [PERF-06](#perf-06) | MEDIUM | Nametags do all-player loops, LOS rays and `setPlayerNametagShowing` every frame | OPEN |
| [PERF-07](#perf-07) | MEDIUM | Synced element data used for local UI state (`hideHUD`, `showChat`, …) | OPEN |
| [PERF-08](#perf-08) | MEDIUM | Shop robbery progress broadcast every 80 ms to all players | OPEN |
| [PERF-09](#perf-09) | MEDIUM | Many fast server ticks (100–250 ms) running even with nobody around | OPEN |
| [PERF-10](#perf-10) | LOW | accData `isOnline()` scans all players on every load | OPEN |
| [PERF-11](#perf-11) | LOW | v_socialpanel loads every message ever sent into memory | OPEN |
| [PERF-12](#perf-12) | LOW | v_radar walks all blips every frame | OPEN |
| [SCALE-01](#scale-01) | HIGH | Two-server setup: lots of state lives in local files / SQLite | OPEN |
| [SCALE-02](#scale-02) | MEDIUM | v_main autostarts everything (devtools, freeroam, editors) | OPEN |
| [SCALE-03](#scale-03) | MEDIUM | Global caps sized for few players (AI traffic, maxplayers 32) | OPEN |
| [SCALE-04](#scale-04) | MEDIUM | Client memory pressure from oversized TXD/DFF mods | OPEN |
| [SCALE-05](#scale-05) | LOW | Vehicle/player element data synced to the whole server, not just nearby players | OPEN |
| [MAINT-01](#maint-01) | LOW | ~25 copies of the "admin level" helper with inconsistent fallbacks | OPEN |
| [MAINT-02](#maint-02) | LOW | Leftover files (`*.old`, `v_customs/old/`) | OPEN |
| [MAINT-03](#maint-03) | LOW | Legacy code style: globals, mixed-language names, no `client` checks | OPEN |
| [MAINT-04](#maint-04) | LOW | No central list of protected element-data keys / server-owned state | OPEN |

---

## 1. Security and exploits

<a id="sec-01"></a>
### SEC-01 — Remote Lua execution: any player → web_api bridge → claude-mcp `dev/exec`
- **Severity:** CRITICAL
- **Status:** WONTFIX (not on the public server)
- **Resolution (2026-10-17):** claude-mcp does not run on the public server. It is git-ignored
  (`/[devtools]/claude-mcp/` in `.gitignore`), so the v_main updater never deploys it. The hole
  only exists on a dev server that runs claude-mcp **and** web_api. If claude-mcp is ever deployed
  somewhere players can join, do fixes 2 and 3 below first.
- **Location:**
  - `[web]/web_api/server/bridge.lua:88` (`invoke`), `:107` (`osa:web:call` remote event)
  - `[devtools]/claude-mcp/server/router.lua:10` (`allowedCaller`)
  - `[devtools]/claude-mcp/server/api/debug.lua:54` (`debug.exec`), `:145` (`debug.callExport`)
  - `[devtools]/claude-mcp/meta.xml:49` (`*allowExec = true`)
  - `[core]/v_main/loadResources.lua:16` (IGNORE list has no `claude-mcp`)
- **Problem:** `osa:web:call` lets any connected client call **any** `http="true"` export of
  **any** running resource. claude-mcp exports `dev` (= the `debug` category, which includes
  `exec`). `allowedCaller()` returns `true` when `hostname` is not a string, and an in-process
  `call()` from web_api has no HTTP `hostname`. So the localhost-only guard is skipped. v_main
  autostarts claude-mcp on the live server, and `acl.xml` puts it in the **Admin** and
  **runcode** groups.
- **Impact:** A client with a Lua injector can run arbitrary server-side Lua with Admin rights.
  That means full server takeover: ACL changes, reading `v_mysql` credentials from memory,
  deleting data.
- **Suggested fix:**
  1. Right away: do not run claude-mcp on the production server. Add it to the IGNORE list in
     `loadResources.lua` and set `*allowExec` to `false` by default.
  2. In claude-mcp `allowedCaller()`: reject in-process calls whose `sourceResource` is not
     explicitly allowed (at least reject `web_api`). Never treat "no hostname" as "trusted".
  3. In web_api: add an **allow-list** of apps the in-game bridge may call (pt_web, med_web,
     bt_web, avi_web, v_admin, web_api), configurable as a setting. Everything else gets
     "Unknown function".
- **Verify:** From a test client, `triggerServerEvent("osa:web:call", <web_api root>, 1, "claude-mcp", "status", "[]")` must fail.
- **Note:** The web_api bridge still lets players call **every** `http="true"` export of every
  running resource. That is fine for the web apps (they check their own tokens), but an app
  allow-list (fix 3) is still worth adding later.

<a id="sec-02"></a>
### SEC-02 — Client-writable element data used as identity and authority
- **Severity:** CRITICAL
- **Status:** OPEN
- **Location:**
  - `[core]/v_mysql/scripts/accdata.lua:93` (`resolveName` → `getElementData(player, "accName")`)
  - `[core]/v_accounts/server.lua:358` (`markLoggedIn` puts the identity into synced element data)
  - Every `getAdminLevel`/`isAdmin` (≈25 copies, see MAINT-01) → `getAccData(player, "admin_level")` → `accName`
  - Direct trust of `admin_level` element data: `[ai]/ai_land_traffic/server/main.lua:134`, plus the
    fallback branches in `avi_core/server/admin.lua:4`, `med_erm/server/admin.lua:7`,
    `v_els/server/editor.lua:5`, `rw_core/server/role.lua:53` (13 reads in total)
  - `[core]/v_admin/server/jail.lua:79`: the escape check is skipped when `adminjail` element data is false
  - `[core]/v_levelsys/server.lua:102`: `giveXp` reads `level`/`xp`/`next_xp` from element data
  - `mtaserver.conf`: `<elementdata_whitelisted>0`
- **Problem:** In MTA a client can call `setElementData` on its own player element (and on other
  elements) and the change is synced to the server, unless a server `onElementDataChange`
  handler reverts it. Only a few keys are protected (`save.position`, `bank_money`, `work.*`,
  plus some medsys/rw/wp keys). `accName`, `accID`, `isLogged`, `admin_level`, `adminjail*`,
  `level`, `xp`, `next_xp`, `loaded`, `adminDuty`, `admin_name` are not protected.
- **Impact:**
  - Setting `accName` to another account name makes **every** server system treat the cheater as
    that account: admin level (→ full admin), personal vehicles, bank, friends. And the next
    `save_all` writes the cheater's position/money/weapons **into the victim's account**.
  - Setting `adminjail = false` escapes the admin jail.
  - Setting `xp`/`level` to a huge value lets the next `giveXp` save it permanently.
- **Suggested fix:**
  1. v_accounts keeps a **server-side** table `player → accountName` and exports it, e.g.
     `getPlayerAccount(player)`. `v_mysql.resolveName` and every admin check use this, never
     element data.
  2. Add a central guard in v_accounts (or a new tiny resource): one `onElementDataChange`
     handler with a list of protected keys/prefixes. When `client` is set, revert the change and
     log/kick. See MAINT-04.
  3. `admin_level` checks: read from the server cache only. Drop the "element data" fallback branches.
  4. Look into MTA 1.6's element-data client-write protection (`elementdata_whitelisted` /
     per-key client change policy). Check the wiki for your server build before relying on it.
- **Verify:** On a test client, `setElementData(localPlayer, "accName", "<other>")` must be
  reverted immediately, and `getAdminLevel` must keep returning the real level.

<a id="sec-03"></a>
### SEC-03 — Discord webhook URL committed to the public repo, and an open relay event
- **Severity:** CRITICAL
- **Status:** OPEN
- **Location:** `[player_interaction]/v_chat/s_webhook.lua:1` (URL), `:3` (`chat:discord:sendWebhook` registered as a remote event)
- **Problem:** The full webhook URL (ID + token) is in git (commit `e79ed3e`). The repo is public:
  v_main's updater reads it anonymously from `raw.githubusercontent.com`. The event is also
  registered with `addEvent(..., true)` and never checks `client`, so any client can post any
  text to Discord, including `@everyone`.
- **Impact:** Anyone can spam or impersonate the server on Discord, or get the webhook (and so
  the channel) deleted for abuse.
- **Suggested fix:**
  1. **Rotate / delete the webhook in Discord now.** The old URL stays in git history.
  2. Keep the URL in a git-ignored config, or in a private `*` setting in meta.xml.
  3. Register the event as server-only (`addEvent(name)` without `true`), or call a local function.
  4. Send `allowed_mentions = { parse = {} }`, strip markdown/mentions, and queue messages (see BUG-07).

<a id="sec-04"></a>
### SEC-04 — v_modmenu (freeroam) `onServerCall` acts on arbitrary elements
- **Severity:** CRITICAL
- **Status:** FIXED 2026-10-17 (not committed yet)
- **Resolution (2026-10-17):** v_modmenu is not available on the public server. It is now
  git-ignored (`/v_modmenu/` in `.gitignore`), removed from the index with
  `git rm -r --cached v_modmenu` (the local files stay for dev use), and added to the v_main
  updater's `IGNORE_PREFIX` (`[core]/v_main/lib/repoSync.lua`) so `updateresources` never touches
  it. The code itself is unchanged: it must not be deployed where players can join.
- **Location:** `v_modmenu/fr_server.lua:30` (`g_RPCFunctions`), `:536` (`onServerCall` handler)
- **Problem:** This is the old freeroam RPC. The client names a whitelisted server function and
  passes **all** of its arguments, including the target element. `setElementPosition`,
  `setElementInterior`, `removePedFromVehicle`, `setVehicleColor`, `setVehicleRotation`,
  `fadeVehiclePassengersCamera` are allowed with no option check at all. Others (`killPed`,
  `setPedAnimation`, `giveMeWeapon`, `giveMeVehicles`, `setPedGravity`, `setTime`,
  `setWeather`…) are only behind global options. v_main autostarts the resource.
- **Impact:** Any player can teleport/kill/animate other players, move other players' vehicles,
  change time/weather for everyone, and get weapons that bypass `wp_manager` and the economy.
- **Suggested fix:** Remove v_modmenu from production (add it to the v_main IGNORE list). If it
  is needed, port the current upstream freeroam checks: the target must be `client` or
  `client`'s own vehicle. Remove weapon/vehicle/time/weather/stat functions that clash with
  wp_manager, v_ownveh and v_weekly.

<a id="sec-05"></a>
### SEC-05 — Chat sender spoofing, no length or flood limit
- **Severity:** HIGH
- **Status:** FIXED 2026-10-17 (not committed yet)
- **Resolution (2026-10-17):** `[player_interaction]/v_chat/s_chat.lua`:
  - The sender is always `client`. The client's first argument is ignored, and the player must be logged in.
  - The text is type-checked, invalid UTF-8 is dropped, `#RRGGBB` codes are stripped (repeatedly,
    so nesting does not get around it), control characters are removed, it is trimmed and capped
    at 45 characters, the same as the input box.
  - Flood limit: 3 messages / 5 s, then a 5 s cooldown with an alert
    (`v_chat.chat.slow_down`, en + hu in v_locals).
  - The Discord forward uses the real sender's name and the cleaned text.
  - **Restart needed:** v_locals (new string), v_chat. Not tested in-game yet.
  - Still open: the webhook itself (SEC-03).
- **Location:** `[player_interaction]/v_chat/s_chat.lua:1-15`, client side `c_chat.lua:106`
- **Problem:** The server broadcasts `sendMessageToAll(sender, text)` with the **client-supplied**
  `sender`. The mute check uses `client`, but the message is sent as `sender`. There is no
  server-side type/length check, no flood control, no colour-code filtering, and every message
  is also forwarded to Discord.
- **Impact:** Messages can be faked as an admin or any other player, the chat can be flooded,
  huge strings go out to every client, and Discord gets spammed.
- **Suggested fix:** Always use `client` as the sender. Validate `type(text)=="string"`, trim it,
  cap the length (e.g. 128 UTF-8 characters), strip or limit `#RRGGBB`. Add a per-player rate
  limit (e.g. 3 messages / 5 s, with a cooldown).

<a id="sec-06"></a>
### SEC-06 — Remote events act on a player passed by the client
- **Severity:** HIGH
- **Status:** OPEN
- **Location:**
  - `[minigames]/v_arenawar/s_playermanager.lua:53` (`enterArena(player)`), `:91` (`exitArena(player, code)`), `:225` (`continueGame(player)`)
  - `[ui]/ui_pause/s_pausemenu.lua:3` (`pausemenu_joinArenawar` uses `source`)
  - `[core]/v_spawnmanager/server.lua:81` (`respawnAfterWasted` uses `source`, no "is dead" check)
- **Problem:** The target player comes from the event argument or `source`, and either can be any element.
- **Impact:** Force any player into or out of the arena, respawn anyone at any time (instant heal,
  teleport out of jail/arena/interiors), grief players.
- **Suggested fix:** Use `client` only, and ignore the argument. `respawnAfterWasted`: only when
  `isPedDead(client)` and after the respawn delay. Arena: check that the player is actually in
  the arena state the action needs.

<a id="sec-07"></a>
### SEC-07 — Any client can append unlimited text to a server file
- **Severity:** HIGH
- **Status:** FIXED 2026-10-17 (not committed yet)
- **Resolution (2026-10-17):** The `pos:saveToFile` event is gone. `/pos` now only sends
  `pos:request`. The server (`[core]/v_spawnmanager/server.lua`) checks admin level ≥ 5 (from
  v_mysql accData), applies a 1 s cooldown, reads the position **itself**, appends it to
  `positions.txt`, and answers with `pos:saved`. The client then prints it, copies it to the
  clipboard and places the marker and blip. This also fixes the old typo `local marker createMarker(...)`
  that left the blip without a marker. Players below level 5 get no reaction.
  Not tested in-game yet. Note: the admin level check still goes through `accName` (SEC-02).
- **Location:** `[core]/v_spawnmanager/server.lua:106` (`pos:saveToFile`), `client.lua:69` (`/pos` for everyone)
- **Problem:** A remote event appends `text` to `positions.txt` with no permission check, no
  type/length check and no rate limit.
- **Impact:** Disk exhaustion on the host (the event can be fired in a loop with megabyte strings).
- **Suggested fix:** Delete the feature (it is a dev tool), or gate it to admin level ≥ 5, require
  `client`, cap the length, and rate limit it.

<a id="sec-08"></a>
### SEC-08 — Time trial reward farm
- **Severity:** HIGH
- **Status:** FIXED 2026-10-17 (not committed yet)
- **Resolution (2026-10-17):** The run is now tracked on the server only (`runs[player]` in `s_timetrial.lua`). The `tt:active` element data is not used anywhere any more.
  - E sends `tt:start`. The server starts a run only if the player is logged in, alive, driving
    a land vehicle **and inside the start marker** (`isElementWithinMarker`). It records the
    start tick and arms a timeout (trial time + 1.5 s grace), then answers with `tt:started`. The
    client then shows the countdown, which is display only.
  - At the finish marker the server pays only if a run exists, the time is not over, and the run
    is not faster than the straight-line distance at 85 m/s (≈306 km/h). Too-fast runs are
    rejected and logged. The reward is paid once, then the run is cleared.
  - Leaving the vehicle, dying, quitting, or the trial being switched (v_weekly) ends the run.
    The timeout sends `tt:finish false`.
  - `/tttest` uses the same path and still pays nothing.
  - Not tested in-game yet. A daily reward cap could still be added if farming by honest driving is a concern.
- **Location:** `[minigames]/v_timetrial/s_timetrial.lua:156` (pays `trial.reward`), `c_timetrial.lua:165` (client sets `tt:active`)
- **Problem:** The payout only checks `getElementData(source, "tt:active")`, which the **client**
  sets. There is no recorded start time, no minimum duration and no cooldown.
- **Impact:** Unlimited money: set `tt:active`, drive into the end marker, repeat.
- **Suggested fix:** The server records `startTick[player]` when the start marker is hit and the
  countdown ends. On finish it requires `startTick`, checks `elapsed >= minTime` (e.g. 70 % of
  the record), pays once, then clears the state. Optionally add a daily cap.

<a id="sec-09"></a>
### SEC-09 — Pre-login DoS: login/register not rate limited
- **Severity:** HIGH
- **Status:** FIXED 2026-10-17 (not committed yet)
- **Resolution (2026-10-17):**
  - **v_mysql:** new export `mysqlQueryAsync(eventName, requestId, sql, ...)` (`core/mysql.lua`,
    `meta.xml`). It is a non-blocking query for other resources, and the result comes back as an
    event on the caller's resource root (functions cannot be passed through exports). PERF-01 can reuse it.
  - **v_accounts `login_player`:** one async query (`fetchAccountAuthAsync` in `server/db.lua`:
    `SELECT id, account_name, password … LIMIT 1`) replaces the 2 blocking ones, then the async
    bcrypt verify runs as before.
  - Throttle: one attempt in flight per player, at least 1 s between attempts. Failed logins are
    counted per **serial** (5 in 60 s) and per **IP** (15 in 60 s, higher because of shared
    addresses). Hitting the limit locks the key for 60 s, and each further lockout doubles it
    (max 15 min). The message is `v_accounts.server.too_many_login_attempts` (en + hu). A
    successful login clears the serial counter, and a DB error does not count as a fail. A lost
    DB answer is dropped after 15 s.
  - Over-long username/password (> 64 / > 128) is rejected before any DB work.
  - **`register_player`:** one registration in flight per player (while bcrypt runs), at least
    3 s between attempts, password capped at 128. Its `accountNameExists` check is still a sync
    query (PERF-01).
  - **Deploy note:** the v_main updater skips `[core]/v_mysql/` (`IGNORE_PREFIX`), so copy
    v_mysql to the live server **by hand**, then restart v_mysql → v_accounts → v_locals.
    v_accounts needs the new v_mysql export.
  - Not tested in-game yet. `httpLogin` (web panels) is unchanged, see SEC-17.
- **Location:** `[core]/v_accounts/server.lua:368` (`login_player`), `:416` (`register_player`); `server/db.lua:25,48` (sync queries)
- **Problem:** Before logging in, a client can fire `login_player` as fast as it likes. Each call
  runs `accountNameExists` + `fetchAccountAuth` (2 blocking round trips to the remote MySQL)
  and then bcrypt. Only the HTTP login has a fail counter.
- **Impact:** One unauthenticated client can stall the main loop (lag or timeouts for everyone)
  and brute-force passwords in-game.
- **Suggested fix:** Per-serial and per-IP throttle (e.g. 5 tries / minute, then a growing
  lockout). Merge the two queries into one async `SELECT id, account_name, password … WHERE
  account_name = ?`. Ignore new attempts while one is still pending for the player.

<a id="sec-10"></a>
### SEC-10 — Social panel events trigger blocking DB work with no rate limit
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `[player_interaction]/v_socialpanel/server.lua:510` (`sp:search`), `:614` (`sp:msg:send`); `[core]/v_accounts/server/db.lua:36` (`getAllAccountNames`)
- **Problem:** `sp:search` runs `SELECT account_name FROM accounts` (every row) and then 2
  blocking `getAccData` queries per offline match. Every DM or crew message is a blocking
  `mysqlInsert` (2 round trips). There is no throttle.
- **Impact:** Any logged-in player can freeze the server by spamming search or messages. The cost
  grows with the number of registered accounts.
- **Suggested fix:** Rate limit per player (search: 1 / 2 s, messages: 5 / 10 s). Do the search
  in SQL: `WHERE account_name LIKE ? LIMIT n`, with columns for hours/minutes or a single
  query. Make the inserts async (`dbExec`, plus an async id lookup if needed). See PERF-01.

<a id="sec-11"></a>
### SEC-11 — Unrestricted vehicle spawner
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `[ui]/ui_inac/server/spawn.lua:16`
- **Problem:** Any model ID (Rhino, Hydra, Hunter…), anywhere, in any dimension or interior
  (arena, jail, job lobbies), with no cooldown. The old vehicle is destroyed even when other
  players are inside it.
- **Impact:** Griefing, bypassing the paid systems (dealership, v_ownveh, work vehicles),
  breaking minigames, spawn-spam load.
- **Suggested fix:** A model allow-list (or an admin level for military/air vehicles), a cooldown
  (e.g. 10 s), blocking when jailed, in a job/arena/interior or with dimension ≠ 0, and not
  destroying an occupied vehicle.

<a id="sec-12"></a>
### SEC-12 — Debug/dev commands open to every player
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `[core]/v_spawnmanager/server.lua:94` (`spawnfix` → `spawnPlayer` at 0,0,0), `:98` (`fixme` → dimension/interior 0), `:3` (`showrespawnpoints`); `client.lua:69` (`pos`); `[minigames]/v_arenawar/s_playermanager.lua:88-89` (`fadetrue`/`fadefalse`)
- **Problem:** No permission checks. (`/pos` was fixed in SEC-07, the rest is still open.)
- **Impact:** Instant full-health respawn and escape from arena/interiors/jobs. Together with
  SEC-02 also a jail escape. Free healing in fights.
- **Suggested fix:** Remove these, or gate them behind the admin level check. If players need a
  "stuck" command, give it a long cooldown and block it while jailed, dead, wanted, in a job or
  in the arena.

<a id="sec-13"></a>
### SEC-13 — Shop robbery: no distance check, parallel robberies, orphaned timers
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[world]/v_shop_robbery/s.lua:25` (`startRobbing`), `:44` (80 ms infinite timer), `:51`
- **Problem:** `startRobbing` does not check the distance to the NPC, whether the player is
  aiming or armed, the dimension, or whether the player is alive. `isRobbing` is client-writable
  (SEC-02): reset it and start again, and `robberies[player]` is overwritten while the old
  infinite 80 ms timer keeps running forever.
- **Impact:** Remote robberies, leaked timers (CPU), progress that speeds up.
- **Suggested fix:** Validate distance (< 5 m), the weapon, `client` and the dimension. Keep the
  robbery state in a server table only, kill any existing timer before creating a new one, and
  use a single timer with an end time instead of an 80 ms tick (see PERF-08).

<a id="sec-14"></a>
### SEC-14 — Vehicle element data set directly by clients
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[ui]/ui_inac/client/main.lua:104-194` (`sirenType`, bypasses the validated `siren:setData` in v_els), `[vehicles]/v_customs/client/preview.lua:99` (`tuning.lsdDoor`), `[ui]/v_radar/radar/sourceC.lua:1142` (`gpsDestination`), `[vehicles]/v_radio/s_radio.lua:1` (`radio:setStation` for **any** vehicle, any value, no `client` check)
- **Impact:** Players change other players' vehicle state (siren, radio stream, preview tuning
  that sticks). Values are not validated (e.g. an arbitrary radio "station" value).
- **Suggested fix:** Route every change through a validated server event (driver = `client`,
  value in an allow-list) and protect these keys with the SEC-02 guard. Use local element data
  (`false` as the 4th argument) for previews.

<a id="sec-15"></a>
### SEC-15 — Web session tokens built from `math.random`
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[core]/v_admin/server/web.lua:63`, `[medical]/med_erm/server/webadmin.lua:48`, `[medical]/med_erm/server/webtablet.lua:54`, `[bloodtransport]/bt_web/server/http.lua:86`
- **Problem:** `sha256(tick .. time .. account .. math.random() .. math.random())`. The inputs
  are mostly predictable and `math.random` is not a CSPRNG.
- **Impact:** An attacker who knows roughly when an admin logged in has a much smaller search
  space for the admin web session token.
- **Suggested fix:** Generate the entropy with `passwordHash(<anything>, "bcrypt")` (it uses a
  secure random salt) or with `generateKeyPair`, and hash that. Bind the token to the caller id
  (IP/serial), keep the expiry, and rotate the token on privilege changes. Put this in one
  shared helper in web_api.

<a id="sec-16"></a>
### SEC-16 — Over-privileged ACL
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `mods/deathmatch/acl.xml` (not in this repo): group `Admin` contains `resource.claude-mcp`, `resource.v_chat`, `resource.ui_pause`, `resource.web_api`…; group `runcode` contains `resource.claude-mcp`
- **Problem:** Resources get full Admin rights when they only need one or two (v_chat only needs
  `function.fetchRemote`, ui_pause needs `kickPlayer`). Any bug in them becomes an admin-level bug.
- **Suggested fix:** Give each resource its own ACL group with only the rights it needs. Take
  claude-mcp out of production (SEC-01).

<a id="sec-17"></a>
### SEC-17 — Synchronous bcrypt in `httpLogin`, throttled only per username
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[core]/v_accounts/server.lua:254-277` (`passwordVerify` without a callback, line 269)
- **Problem:** Each web login attempt blocks the main thread for a bcrypt verify (~50–150 ms)
  plus 2 sync queries. The fail counter is per **username**, so rotating usernames avoids it.
  v_admin/med_web/bt_web also count per caller id, but every attempt is still paid in full.
- **Suggested fix:** Use the async `passwordVerify` with a callback (the HTTP export then needs a
  pending/poll pattern, or a cheap rejection before bcrypt). Throttle per IP as well. Do the
  "too many fails" check before any DB or bcrypt work.

<a id="sec-18"></a>
### SEC-18 — Nametags show account login names to everyone
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[player_interaction]/v_nametags/sourceC.lua:84`
- **Problem:** The login name is public, which makes credential stuffing against the web panels
  (v_admin, ERM admin, BT admin) easier.
- **Suggested fix:** Show `display_name` (already in the `accounts` table), and keep login names private.

<a id="sec-19"></a>
### SEC-19 — Report log filename filter misses `\`
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[core]/v_admin/server/report.lua:480`
- **Problem:** In Lua 5.1, `"[/\]"` parses as `"[/]"` because `\]` is not a valid escape and
  loses the backslash. Only `..` blocking currently prevents traversal on Windows.
- **Suggested fix:** Use an allow-list pattern instead: `fileName:match("^[%w_%-%.]+%.json$")`.

<a id="sec-20"></a>
### SEC-20 — Self-updater pulls code from GitHub `main` without pinning
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[core]/v_main/lib/repoSync.lua`, `updateResources.lua`
- **Problem:** `updateresources` downloads whatever is on `main` and writes it into the resources.
  A compromised GitHub account or a bad push goes straight to the server. (It is gated by admin
  level 5 or the console, which is good.)
- **Suggested fix:** Update to a tag or commit SHA given on the command line, show the diff
  summary and ask for confirmation before writing, and keep a backup of the replaced files.

---

## 2. Functional bugs

<a id="bug-01"></a>
### BUG-01 — Cross-server lost updates in account data
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `[core]/v_mysql/scripts/accdata.lua:118` (`load`), `:138` (`persist`), `:186` (`setAccData`)
- **Problem:** Account data is one JSON blob per account, and each write sends the **whole** blob
  from the local cache. Accounts online on this server are cached. When server A writes to an
  account that is online on server B (friend request, crew change, admin edit, weekly reward),
  B's cache does not know about it, and B's next save overwrites A's change. The same happens
  between two resources on one server if a non-cached read-modify-write runs alongside a cached one.
- **Impact:** Lost friends/crew/admin changes and rewards, which look like "random rollbacks".
- **Suggested fix:** Write only what changed (`JSON_SET(account_data, '$.key', ?)` or a key/value
  table), and/or route writes for an online account to the server that owns it (a message over
  MySQL, or an `owner_server` + `updated_at` check, i.e. optimistic locking). Hot values (money,
  xp, level, playtime) should get their own columns.

<a id="bug-02"></a>
### BUG-02 — v_mysql: writes silently lost during an outage; fragile `LAST_INSERT_ID`
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[core]/v_mysql/core/mysql.lua:202` (`mysqlExec`), `:177-200` (`mysqlInsert`), `:69` (`verifyConnection` only every `MYSQL_PING_INTERVAL` = 30 s)
- **Problem:** `dbExec` returns `true` while the connection element exists, even when the server
  is unreachable, so up to 30 s of saves can be lost without an error. `mysqlInsert` runs a
  second `SELECT LAST_INSERT_ID()` query. With `autoreconnect=1` a reconnect in between returns
  0 or a wrong id. `dbPoll` already returns the insert id as its 3rd value.
- **Suggested fix:** Use `local res, affected, lastId = dbPoll(qh, -1)`. Detect failure through
  `dbExec`'s callback form (`dbQuery` + callback), and keep a small retry queue for failed
  writes so they are flushed on reconnect.

<a id="bug-03"></a>
### BUG-03 — v_arenawar disables interior sounds for everyone, every frame
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[minigames]/v_arenawar/shared.lua:22-24`
- **Problem:** `setInteriorSoundsEnabled(false)` runs in an always-on `onClientPreRender` for
  every player on the server, not only inside the arena.
- **Impact:** All interior ambient sounds (clubs, shops, casinos) are gone server-wide, plus a
  wasted call every frame.
- **Suggested fix:** Call it once when entering the arena, and `setInteriorSoundsEnabled(true)` when leaving.

<a id="bug-04"></a>
### BUG-04 — v_arenawar `random()` reseeds every call and returns the wrong range
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[minigames]/v_arenawar/shared.lua:28-38` (a global `random`, `table.random`)
- **Problem:** `math.randomseed(os.time()+u)` on every call gives poor, correlated values.
  `x + (math.random()*999999 % y)` returns `[x, x+y)`, not `[x, y]`. It is also a **global** in
  shared scope, so it shadows other `random` helpers in the resource.
- **Suggested fix:** Seed once at start and use `math.random(x, y)`. Make the helper `local`.

<a id="bug-05"></a>
### BUG-05 — Bans are stored per server in `bans.xml`
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[core]/v_accounts/server.lua:11` (`BANS_FILE = "bans.xml"`), `:54`
- **Problem:** The account system is shared through MySQL, but bans are a local XML file. A ban
  on server 1 does not apply on server 2.
- **Suggested fix:** Move bans into a `bans` table (account, serial, ip, until, reason, admin) and
  cache it with a short TTL.

<a id="bug-06"></a>
### BUG-06 — v_playedtime keeps a timer in synced element data
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[core]/v_playedtime/*.lua:38-40` (`setElementData(player, "Online.timer", setTimer(...))`)
- **Problem:** A timer userdata stored in synced element data is sent to every client (useless
  and noisy), and a client can overwrite it, which breaks `killTimer`. It also makes two
  `setAccData` calls per player per minute (PERF-02).
- **Suggested fix:** Keep the timers in a local `timers[player]` table, or better, use one
  global 60 s timer that walks the logged-in players and saves both values in one write.

<a id="bug-07"></a>
### BUG-07 — v_chat bypasses `onPlayerChat`; webhook ignores Discord rate limits
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[player_interaction]/v_chat/s_chat.lua`, `s_webhook.lua`
- **Problem:** Custom chat never fires `onPlayerChat`, so admin chat logs or other listeners do
  not see it. Every message is its own `fetchRemote`. A Discord webhook allows ~30 requests per
  minute, and any 429 is only logged.
- **Suggested fix:** Fire a custom server event (`onFreeVChat`) that others can hook and cancel.
  Batch webhook messages (one post every 2–3 s) and honour `retry_after`.

<a id="bug-08"></a>
### BUG-08 — world_cablecars draws its cables always; map line uses hard-coded pixels
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[world]/world_cablecars/client.lua:23-34`
- **Problem:** Two `dxDrawLine3D` calls every frame in any dimension or interior at any distance.
  The F11 map line is at fixed pixel coordinates (`225, 617`), so it is wrong on every
  resolution except one.
- **Suggested fix:** Draw only in dimension 0, interior 0, within ~1 km. Calculate the map line
  from world coordinates, or drop it.

---

## 3. Optimization

<a id="perf-01"></a>
### PERF-01 — Blocking `dbPoll(-1)` queries to a remote MySQL host on the main thread
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `[core]/v_mysql/core/mysql.lua:156` (`mysqlQuerySync`), `:177` (`mysqlInsert`). Callers: `v_accounts/server/db.lua`, `v_mysql/scripts/accdata.lua:118` (every read of an offline account), `v_socialpanel/db.lua`, `v_ownveh/db.lua`, `v_admin/server/panel.lua` and `web.lua`, `v_weekly/server/storage.lua`, `med_erm/server/webadmin.lua`, `bt_web/server/http.lua`
- **Problem:** The DB is on another host (`mysql8.srkhost.eu`). Every sync call freezes the
  **whole server**, all resources and all players, for a full network round trip (typically
  10–60 ms, much more under load). The connection guard (`connguard.lua`) exists precisely
  because this used to take the server down.
- **Impact:** Lag spikes that grow with player count and activity, desync, and timeouts when the DB is slow.
- **Suggested fix:**
  1. Use async `mysqlQuery(callback, …)` everywhere a player action triggers a query. A small
     coroutine helper (`local rows = DB.await(sql, …)` that yields until the callback) keeps the
     code readable.
  2. Load each account **once** at login (async), keep it cached, and never query on hot paths.
  3. Cache static lists (account names for search) with a TTL, or query with `LIMIT`.
  4. Long term, if both servers run on the same machine/datacenter, move the DB closer.

<a id="perf-02"></a>
### PERF-02 — `setAccData` rewrites the whole account JSON blob on every key
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `[core]/v_mysql/scripts/accdata.lua:138` (`persist`), `:186` (`setAccData`). Heavy callers: `v_levelsys/server.lua:82` (`saveLvl`, 3 writes), `v_playedtime` (2 writes/min/player), `v_accounts/savesys.lua` (periodic `save_all`), v_achievements, v_stats, v_socialpanel
- **Problem:** Each `setAccData(player, key, value)` re-encodes the full blob (inventory-sized
  JSON) and sends a full `INSERT … ON DUPLICATE KEY UPDATE` row. Callers write key by key.
- **Impact:** Write volume and CPU grow as players × keys × blob size. This is the biggest
  steady DB load.
- **Suggested fix:** Write-behind cache: `setAccData` only updates the cache and marks it dirty.
  Flush dirty accounts every 30–60 s, on quit and on resource stop (one write per account).
  Combine with BUG-01's partial updates. Offer `setAccData(player, { k1 = v1, k2 = v2 })` and
  use it in saveLvl and playedtime.

<a id="perf-03"></a>
### PERF-03 — ~400 MB mandatory client download
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `[core]/v_modloader` (313 MB: `vehicles/police_vg.txd` 63 MB, `skins/ballas3.txd` 56 MB, `streak.txd` 16 MB, `ambulan.txd` 15 MB, `streak.dff` 14 MB, `cheetah.dff` 13.6 MB, …), `[ui]/v_radar` 21.6 MB (`radar.png` 10.7 MB **and** `radar.jpg` 3.7 MB), `[core]/v_accounts` 10.8 MB (`audio/main_menu.mp3` 5.5 MB), `[vehicles]/v_els` 7.7 MB (WAV sirens), `[maps]/map_ls_busstation` 5.7 MB
- **Problem:** Every file in `<file>` without `download="false"` must be downloaded before the
  player can play. The TXDs are very likely uncompressed or 4K. A GTA vehicle needs around
  2–8 MB.
- **Impact:** First join takes many minutes, many players give up, the HTTP server is
  saturated when several join at once, and there are VRAM/streaming crashes (SCALE-04).
- **Suggested fix:**
  1. Recompress the textures (DXT1/DXT5, 1024–2048 px max) and simplify the DFFs. Target < 5 MB per model.
  2. Use `download="false"` with `downloadFile` on demand (after spawn, in the background) for
     mods that are not needed right away.
  3. v_radar: keep one map image (a 4096 px JPG/DXT is enough) and delete the other.
  4. Re-encode the audio: MP3/OGG ~96–128 kbps instead of WAV, or stream the menu music via URL.
  5. Set `<download_priority_group>` so the login screen loads first.

<a id="perf-04"></a>
### PERF-04 — 4.7 MB `vehiclenodes.lua` duplicated 4×, shipped as a client script
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[ui]/v_radar/radar/gps/vehiclenodes.lua` (client script), `[tiktok]/ai_autoplayer/shared/vehicle_nodes.lua` (client, `cache="false"` → downloaded again on **every** join), `[ai]/ai_land_traffic/data/source/vehiclenodes.lua`, `[devtools]/claude-mcp/assets/vehiclenodes.lua`
- **Problem:** A 307,772-line Lua table is downloaded, compiled and kept in memory per resource on
  each client (compiling a table that size costs a noticeable hitch at start).
- **Suggested fix:** Build it once into a compact binary/JSON data file (as ai_land_traffic
  already does with `data/runtime/geo.dat`), keep it in one resource, and let the others use
  its exports (path queries) instead of their own copies.

<a id="perf-05"></a>
### PERF-05 — ~100 always-attached `onClientRender`/`PreRender` handlers
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** Examples: `[world]/world_cablecars/client.lua:26,34`, `[minigames]/v_arenawar/shared.lua:22`, `c_hud.lua:42`, `c_interface.lua:209`, `[core]/v_spawnmanager/client.lua:23,66`, `[core]/parachute/*` (3), `[railways]/rw_customtracks/client/*` (7), `[railways]/rw_passengers/client/*` (7), `[minigames]/v_jobcreator/client/*` (6, active even when nobody is editing), `[minigames]/v_timetrial/c_timetrial.lua:139`, `[world]/v_shop_robbery/c.lua:71` (`processLineOfSight` per frame while aiming), `v_modmenu/fr_client.lua:1130`
- **Problem:** Every handler is called every frame, even when it returns early. The cost of the
  calls between VMs adds up. On low-end PCs this is several FPS.
- **Suggested fix:** Attach handlers only while they are needed (UI open, player nearby, minigame
  running) and remove them afterwards. Gate world drawing by distance and dimension. Merge
  small HUD widgets into ui_core's single render loop. Measure with the `performancebrowser`
  resource / `getPerformanceStats("Lua timing")`.

<a id="perf-06"></a>
### PERF-06 — Nametags do all-player loops, LOS rays and `setPlayerNametagShowing` every frame
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[player_interaction]/v_nametags/sourceC.lua:55-160`
- **Problem:** Every frame: `getElementsByType("player")` (all players, not just streamed ones),
  `setPlayerNametagShowing(p, false)` for each, a line-of-sight check for each nearby one,
  5–6 `getElementData` calls per player, then the same for all peds.
- **Impact:** Cost per frame grows as O(players + peds). At 50–100 players this is a real FPS loss.
- **Suggested fix:** `getElementsByType("player", root, true)` (streamed in only), cached and
  refreshed by a 250 ms timer. Call `setPlayerNametagShowing` once on join/stream-in. Cache
  the LOS result and element data per player at 5–10 Hz, and update the cache on
  `onClientElementDataChange` instead of reading every frame.

<a id="perf-07"></a>
### PERF-07 — Synced element data used for local UI state
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `hideHUD` (`v_accounts/client/state.lua:14`, `render.lua:7`, `loading.lua:23`, `v_introduce/client/lock.lua:81`, `v_spawnmanager/client.lua:26`, `v_jobmanager/core/client/ui.lua:69`, `scoreboard.lua:61`, `ui_download/client.lua:83`, `ui_pause/c_pausemenu.lua:339,360`, `v_radar/radar/sourceC.lua:1049,1060`), `showChat`, `paused`, `scoreboardOpen`, `interactionMenuOpen` (`ui_inac/client/input.lua:46`, `temp.lua:166`), `download_screen`, `toggleOwnNametag`, `valaszto`, `enableall`, `tt:active`, `parachuting`, `skydiving`, `isStream`…
- **Problem:** `setElementData` without `false` as the 4th argument sends the value to the server
  and then to **every** client. These keys only matter to the local client.
- **Impact:** Pointless traffic for each player × each UI toggle × every other player. Also
  "accidental" server trust (SEC-08).
- **Suggested fix:** Use `setElementData(localPlayer, key, value, false)`, or better, shared
  state through exports/events (e.g. `exports.ui_core:setHudHidden(reason, bool)` with
  reference counting so resources do not fight over `hideHUD`).

<a id="perf-08"></a>
### PERF-08 — Shop robbery progress broadcast every 80 ms to all players
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[world]/v_shop_robbery/s.lua:44,51-58`
- **Problem:** `robbingProgress` is synced element data updated 12.5 times per second, sent to the whole server.
- **Suggested fix:** Send `startTick` and `duration` once (an event to the robber, or local data).
  The client animates the bar, and the server ends the robbery with one `setTimer(duration)`.

<a id="perf-09"></a>
### PERF-09 — Many fast server ticks running even with nobody around
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** 100 ms: `ai_land_traffic` (`TICK`, plus a per-player state event in `server/sync.lua:86`), `rw_customtracks` (`SIM.TICK`), `rw_auto`. 250 ms: `avi_controller`, `med_hospitals` (`HOSP.TICK` used by 4 timers), `rw_crossings`, `rw_passengers/coaches.lua:302`, `mg_airway`. About 85 permanent server timers in total.
- **Problem:** Each one alone is fine. Together, with nothing to simulate, they add constant CPU
  load and jitter to the single server thread.
- **Suggested fix:** Profile with `performancebrowser`. Let systems sleep when no players are
  near or no entities are active (stop the timer, restart it on demand). Stagger timers so they
  do not all fire on the same tick. Put the 250 ms checks of one resource into one timer.

<a id="perf-10"></a>
### PERF-10 — accData `isOnline()` scans all players on every load
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[core]/v_mysql/scripts/accdata.lua:109`
- **Suggested fix:** Keep a `online[name] = player` map, updated on login and quit. This is also
  the natural home for SEC-02's server-side identity table.

<a id="perf-11"></a>
### PERF-11 — v_socialpanel loads every message ever sent into memory
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[player_interaction]/v_socialpanel/db.lua:115` (`SPDB.loadMessages`)
- **Problem:** Memory and start-up time grow without limit. `trimHistory` trims memory but not the DB.
- **Suggested fix:** Load threads on demand (last N per thread with `LIMIT`) and add a DB retention job (e.g. 90 days).

<a id="perf-12"></a>
### PERF-12 — v_radar walks all blips every frame
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `[ui]/v_radar/radar/sourceC.lua:688` (also `:973`, `:1378`)
- **Suggested fix:** Keep a blip list updated on `onClientElementStreamIn`/`Destroy` (or on blip
  create/destroy events) and skip blips outside the minimap radius early.

---

## 4. Scalability (many players / two servers)

<a id="scale-01"></a>
### SCALE-01 — Two-server setup: lots of state lives in local files or SQLite
- **Severity:** HIGH
- **Status:** OPEN
- **Location:** `v_accounts` `bans.xml` (BUG-05); `v_jobmanager/core/community.lua` (`index.json`, `<id>.json`); `v_admin/server/report.lua` (report logs); `rw_core/server/log.lua`; `med_erm/server/db.lua` (`data/erm.db` SQLite); `bt_dispatch/server/db.lua` (SQLite); `med_scenemanager/server/variety.lua`; `v_ownveh` `vehiclespawnpoints.txt`; `v_els/server/layouts.lua` (`lights.json`); `v_radar/savepositions.lua`
- **Problem:** v_mysql's comments say a second server shares the accounts. Everything above
  differs per server: community jobs, bans, reports, ERM history, stock.
- **Suggested fix:** Decide for each item: **global** (→ MySQL tables: bans, reports, community
  jobs, BT stock) or **per server** (fine as a file). Write the decision into each resource's
  DESIGN.md.

<a id="scale-02"></a>
### SCALE-02 — v_main autostarts everything
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[core]/v_main/loadResources.lua:16` (IGNORE only covers tiktok + web_manager)
- **Problem:** All 126 resources start, including `claude-mcp` (devtools), `v_modmenu`
  (freeroam), editors (`v_jobcreator`, `med_scenemanager` editor) and test-only code. Each one
  adds download size, render handlers, timers and attack surface.
- **Suggested fix:** Use an explicit production manifest (an allow-list), or put dev resources
  in a `[dev]` folder that the loader skips unless a `*devMode` setting is on.

<a id="scale-03"></a>
### SCALE-03 — Global caps sized for few players
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `mtaserver.conf` `<maxplayers>32`; `[ai]/ai_land_traffic/shared/config.lua:11-12` (`MAX_AGENTS = 140` for the whole server, `MAX_PER_PLAYER = 20`)
- **Problem:** With 7+ players spread across the map, the global agent cap is used up and areas
  stay empty. With more agents, the per-player 10 Hz state events grow as players × agents.
- **Suggested fix:** Size the budget dynamically (`min(cap, players × perPlayer)` with a per-area
  share). Send updates only to players whose view the agent is in (this is already partly done
  with camera reports), and send far agents at a lower rate. Plan load tests with bots
  (ai_autoplayer) before raising `maxplayers`.

<a id="scale-04"></a>
### SCALE-04 — Client memory pressure from oversized TXD/DFF mods
- **Severity:** MEDIUM
- **Status:** OPEN
- **Location:** `[core]/v_modloader` (see PERF-03)
- **Problem:** GTA:SA is a 32-bit process. A 63 MB TXD for one police car, when several are
  streamed in (police events, the ERM/EMS fleet), quickly exhausts streaming memory and VRAM,
  causing "out of memory" crashes and texture pop-in that get worse in crowded places.
- **Suggested fix:** As in PERF-03. Also only replace models that are actually used, and
  consider `engineSetModelLODDistance`/streaming limits for the custom models.

<a id="scale-05"></a>
### SCALE-05 — Vehicle/player element data synced to the whole server
- **Severity:** LOW
- **Status:** OPEN
- **Location:** v_els (`sirenState`, `mkjState`, `sirenType`…), rw_customtracks (`rwn.*`), v_customs (`tuning.*`), medsys/med_* keys
- **Problem:** Synced element data goes to every player, however far away they are.
- **Suggested fix:** For high-churn keys use MTA 1.6 `setElementData(el, key, value, "subscribe")`
  with `addElementDataSubscriber` for streamed-in players, or events sent only to nearby players.

---

## 5. Maintenance and hygiene

<a id="maint-01"></a>
### MAINT-01 — ~25 copies of the "admin level" helper with inconsistent fallbacks
- **Severity:** LOW
- **Status:** OPEN
- **Location:** e.g. `avi_core/server/admin.lua:4`, `med_erm/server/admin.lua:7`, `med_hospitals/server/exports.lua:112`, `rw_core/server/role.lua:53`, `v_els/server/editor.lua:5`, `v_ownveh/commands.lua:17`, `work_core/server/levels.lua:201`, `work_core/server/markers.lua:184`, `v_levelsys/server.lua:128`, `ai_land_traffic/server/main.lua:134`, `rw_customtracks/server/network.lua:15` (falls back to the ACL `command.kick`)
- **Problem:** Each copy falls back differently (element data, ACL, 0). Fixing SEC-02 needs every one of them changed.
- **Suggested fix:** One export, `exports.v_admin:getAdminLevel(player)` (backed by the server
  cache from SEC-02), and replace all the copies.

<a id="maint-02"></a>
### MAINT-02 — Leftover files
- **Severity:** LOW
- **Status:** OPEN
- **Location:** `v_modmenu/*.old` (3 files), `[core]/v_accounts/client.lua.old`, `[vehicles]/v_customs/old/` (11 Lua files with their own `meta.xml`), `[core]/v_spawnmanager/positions.txt` (runtime output)
- **Correction (2026-10-17):** `*.old` and `v_customs/old/` are already git-ignored, so this is only local clutter, not repo content.
- **Suggested fix:** Delete them, or move them to an `archive/` folder outside `resources/`.
  Git history keeps the old versions.

<a id="maint-03"></a>
### MAINT-03 — Legacy code style: globals, mixed-language names, no `client` checks
- **Severity:** LOW
- **Status:** OPEN
- **Location:** Mostly `v_arenawar`, `v_spawnmanager`, `v_chat`, `v_shop_robbery`, `v_playedtime`, `v_levelsys`, `world_cablecars`, `v_radar/client.lua` (`hudrajzol`, `dxHalal`, `actualizarJugadorOn`, `betolt`/`lement`, global `Wasted`, `sendMessageToAll`, `random`…)
- **Problem:** Globals collide across files of a resource, and the old patterns (`source`
  instead of `client`, synced element data as storage) keep creeping back.
- **Suggested fix:** When touching these files for the SEC/PERF fixes, make the functions
  `local`, use English names, and apply the remote-event checklist: `client` only, type checks,
  range checks, rate limit.

<a id="maint-04"></a>
### MAINT-04 — No central list of protected element-data keys / server-owned state
- **Severity:** LOW (it makes SEC-02 possible)
- **Status:** OPEN
- **Location:** The guards are scattered: `v_accounts/savesys.lua:172`, `v_bank/server.lua:119`, `work_core/server/duty.lua:193`, `medsys/server/treatment.lua:108`, `rw_core/server/role.lua:46`, `wp_manager/server/inventory.lua:29`, `bt_items/server/main.lua:299`, `v_inventory/server/ports.lua:57`, …
- **Suggested fix:** One small server resource (or a part of v_accounts) that owns the policy: an
  export `protectElementDataKey(key | prefix)` that resources call at start, and one
  `onElementDataChange` handler that reverts client writes and counts violations (kick after
  N). Document the rule in a CONTRIBUTING note: *the server never trusts element data a client
  could write.*

---

## Change log

| Date | Change |
|---|---|
| 2026-10-17 | Initial audit (this document) |
| 2026-10-17 | SEC-01 WONTFIX (not on the public server). SEC-04 untracked + ignored. SEC-05, SEC-07, SEC-08, SEC-09 fixed (uncommitted, not tested in-game) |
