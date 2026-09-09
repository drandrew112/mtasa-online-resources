# v_admin

MTA:SA resource for admin commands, an admin jail and a server-side ID manager.

Messages are shown through the **`ui_core` Alert element**
(`exports.ui_core:setAlert`) because chat is disabled on the server
(`showChat(false)`). Every player-facing message is **English**.

**Alert rules:**

* Alerts **never** include the admin's **rank** (`getAdminTag`), only their
  **name** (`getPlayerName`).
* The admin and the target get **separate** messages with different wording:
  * target: `Muted by <admin> (<minutes> min) for <reason>`
  * admin: `You muted <player> (<minutes> min) for <reason>`
* Admin actions (`/ajail`, `/ajailout`, `/ban`, `/unban`, `/mute`, teleport,
  vehicle, `/heal`) are **not** broadcast to the whole server — only the admin and
  the target see them. The exception is `/af`, the admin announcement, which is
  intentionally sent to everyone.

---

## File structure

```
v_admin/
├── meta.xml
├── config.lua              – shared configuration (ranks, permission levels, jail coordinates, event names)
│                             ADMIN.perms / ADMIN.titles / ADMIN.jail / ADMIN.events / ADMIN.report
│
├── server/
│   ├── core.lua            – admin data load/sync + shared helper functions
│   ├── id_manager.lua      – unique, reused player IDs ("ID" element data) + /myid
│   ├── announce.lua        – /af, /adminannounce
│   ├── admin_manage.lua    – /setadminlevel, hidden command
│   ├── report.lua          – /report, /reports (report system)
│   ├── teleport.lua        – /goto, /gethere
│   ├── vehicle.lua         – /fixveh, /flipveh, /getout
│   ├── jail.lua            – /ajail, /ajailout + jail timers, escape checks
│   ├── ban.lua             – /ban, /unban (account ban → v_accounts)
│   ├── mute.lua            – /mute (chat mute → v_chat)
│   └── misc.lua            – /fly (gate), /heal, /money, /getid, /listacc
│
└── client/
    ├── hud.lua             – Alert receiver, admin jail HUD
    ├── report.lua          – report UI (DGS): player panel + admin report manager
    └── noclip.lua          – noclip movement, /flyspd, N key
```

Dependencies: **`dgs`** (report UI), **`ui_core`** (Alert), **`v_accounts`**
(`/ban`, `/unban`), **`v_chat`** (`/mute`), **`v_mysql`** (`admin_level` + admin
jail data in the shared `accounts` table).

---

## Shared helper functions (`server/core.lua`)

| Function | Description |
|---|---|
| `adminAlert(target, text [, r, g, b, duration])` | Alert to one player / a table (`ui_core`). Colour/duration optional, the text may contain `#RRGGBB`. |
| `adminBroadcast(text [, r, g, b, duration])` | Same, to every player. |
| `adminInfo` | Backwards-compatible alias for `adminAlert`. |
| `denyAccess(player, minLevel)` | Uniform "no permission" message. |
| `getAdminLevel(player)` → number | Admin level as a number (guest/unknown = `0`). **Always reads from account data**, not the element-data mirror. |
| `hasAdminLevel(player, minLevel)` → bool | Whether the player has at least `minLevel`. Every admin command goes through this. |
| `getAdminTag(player)` → string | Coloured rank label for the level (e.g. `[MOD]`). |
| `getPlayerFromId(id)` → player/false | Find a player by `"ID"` element data. |
| `resolveTarget(player, idArg)` → player/false | As above, but also sends an error message. |
| `syncAdminData(player)` | Write the account's admin data onto the player element. |

`server/jail.lua`: `setPlayerInAJ(player, state, minutes)` – toggle jail on/off.

---

## Admin levels (`config.lua` → `ADMIN.titles`)

| Level | Rank |
|:---:|---|
| 0 | Player (not an admin) |
| 1 | Trial Mod |
| 2 | Mod |
| 3 | Admin |
| 4 | SuperAdmin |
| 5 | Dev |
| 6 | Owner |

An admin **only has a level** (no admin name, no admin duty). `ADMIN.maxLevel = 6`.

---

## Commands

| Command | Min. level | Description |
|---|:---:|---|
| `/af <message>` · `/adminannounce` | 2 | Admin announcement to the whole server. |
| `/setadminlevel <ID> <0-6>` | 4 | Set a target's admin level (only below your own; owner is the exception). |
| `/report` | – | Player report panel (DGS). One open report per player at a time. Calls an admin, chat, close, shows who claimed it. |
| `/reports` | 1 | Admin report manager (DGS). List of active reports, claim, chat, teleport to the player, close. |
| `/goto <ID>` | 1 | Teleport to that player (interior/dimension too). |
| `/gethere <ID>` | 1 | Bring that player to you (with their vehicle). |
| `/fixveh [ID]` | 2 | Repair a vehicle (yours without an ID). |
| `/flipveh [ID]` | 2 | Flip a vehicle back over. |
| `/getout <ID>` | 2 | Remove that player from their vehicle. |
| `/heal <ID>` | 1 | Restore that player's health and armour. |
| `/fly` · **N key** | 2 | NoClip mode on/off. |
| `/flyspd <0.1-20>` | – | NoClip speed (client). |
| `/ajail <ID> <minutes> <reason>` | 2 | Admin jail. |
| `/ajailout <ID>` | 2 | Release from the admin jail. |
| `/ban <account> <reason>` | 2 | Account ban (never expires). Also stores the serial for an online player. |
| `/unban <account>` | 2 | Lift an account ban. |
| `/mute <ID> <minutes> <reason>` | 2 | Chat mute. No `/unmute` – it expires on its own. |
| `/money` | 4 | Test money (+$2000). |
| `/getid <name>` | – | A player's ID from a name (fragment). |
| `/myid` | – | Your own ID. |
| `/listacc` | 5 | Every account, to the server log. |
| `/ichbintulajandris [level]` | – | **Hidden** – set your own admin level (defaults to 6). |

The minimum levels are set in one place: `config.lua` → `ADMIN.perms`.

### Resource control (in the `v_main` resource)

Resource start/stop/restart commands are **not here** but in `v_main`, because in
the ACL only `v_main` has `startResource` / `stopResource` / `restartResource`
rights (`acl.xml` → `<group name="Admin">`). Same access as
`/restartallresource`: server console **or** a logged-in player with
`admin_level >= 5` (see `v_main/commandAuth.lua`); no user ACL group needed.

| Command | Min. level | Description |
|---|:---:|---|
| `/startresource <name>` · `/startres` | 5 | Start a resource. |
| `/stopresource <name>` · `/stopres` | 5 | Stop a resource (protected: `v_main`, `v_mysql`, `v_accounts`, `v_admin`). |
| `/restartresource <name>` · `/restartres` | 5 | Restart a resource (same protected list). |
| `/restartallresource` | 5 | Restart every resource in dependency order. |

---

## Report system (`server/report.lua` + `client/report.lua`)

The old `/pm` and `/pmv` are **gone**. Instead:

* **`/report`** – player-side DGS panel.
  * No open report → type the problem, "Call an admin" → the report is created,
    every online report-admin gets an Alert + a sound ping.
  * A player can have **only one** open report at a time.
  * Open report → chat, a status line ("Waiting for an admin to respond..." /
    "Claimed by: `<name>`"), a "Close report" button. The player only sees
    **their own** report.
* **`/reports`** – admin-side DGS manager (min. `ADMIN.perms.reports`).
  * List on the left, two tab buttons side by side at the top: **`Active cases`**
    and **`Logs`** (the active tab highlighted).
    * *Active cases* – every active report (ID, player, status/claimer).
    * *Logs* – the saved logs of closed reports (date, player, admin); select a
      row to read the chat back (read-only, with timestamps).
  * The selected report is on the right: chat, **Claim**, **Teleport** (to the
    player), **Close** (asks for confirmation). Writing into an unclaimed report
    claims it automatically. On the *Logs* tab the chat / `Claim` / `Teleport` /
    `Close` / `Send` controls are hidden (a log is a read-only history).
  * Several admins can watch at once; everyone sees who claimed it.
* **Both the player and an admin** can close a report (the button is two-step:
  first click "Confirm?", second closes). When the reporter leaves, the report
  closes automatically.
* Buttons are handled by a **custom hit test** (`onClientClick` + the button's
  current screen rectangle) because DGS's own click events (`onDgsMouseClick*`)
  fired on the wrong element (the title bar / window background triggered
  buttons). A button only fires when both the press **and** the release are
  inside its rectangle and the button is visible + enabled. In the list the
  selected row "sticks": clicking empty space does not lose the open report/log.

### Log files (`report_logs/`)

Every closed report goes to the `report_logs/` folder, **one JSON per chat**
(without colour codes), `report_logs/<YYYY-MM-DD>-<PlayerName>.json`:

```json
{
  "info": { "player": "PlayerName", "adminClaimed": "AdminName" },
  "messages": [
    { "sender": "PlayerName", "text": "Hi!", "time": "14:03" },
    { "sender": "AdminName",  "text": "How can i help today?", "time": "14:05" }
  ]
}
```

`report_logs/index.json` holds the list (the `/reports` "Logs" view reads it;
server-side a single log is read back by its file name). System messages are
recorded with `sender = "SYSTEM"`.

### UI behaviour

* The panels have a **fixed minimum size** (they do not collapse on a small
  monitor) and are **movable** (drag by the title bar).
* The red **X** top-right only hides the panel (it does not close the report);
  **ESC** too.
* **Right mouse button**: hides the cursor → the character can move; another
  right click → cursor back.
* While a panel is open, `reportPanelOpen` element data = `true`, and the pause
  menu, INAC menu (M), phone, social panel do **not** open, and chat `T` does
  **not** work. (`ui_pause`, `ui_inac`, `ui_phone`, `v_socialpanel`, `v_chat`
  check this key in their `otherPanelOpen` / `blocked` guard.)
* The chat is colour-coded (`#RRGGBB`): the log is a bottom-aligned, wrapped,
  clipped DGS label (the DGS *memo* does not colour-code its body text).

**Active** report state lives only in memory (lost on a server restart);
**closed** reports are saved to `report_logs/`. Configuration:
`config.lua` → `ADMIN.report` (min/max length, chat history limit, `logDir`) and
`ADMIN.events.report*` (event names).

---

## Ban and mute

* **`/ban` / `/unban`** → the `v_accounts` exports:
  `banAccount(account_name, reason, admin_name)` and
  `unbanAccount(account_name)` (**not** `banPlayer` / `unbanPlayer` — those are
  MTA built-in function names and can't be used as export names).
  The ban is **account-based** (no account, no login), and if the player is
  online their **serial is also saved** to `bans.xml` (so they can't return from
  the same machine with a new account). There is **no temporary ban** — the
  release attribute is `Never` for an active ban, `1` after it is lifted. A
  banned player stays connected but frozen behind the ban panel (login is
  rejected too).
* **`/mute`** → the `v_chat` export: `mutePlayer(player, minutes, reason, admin_name)`.
  While muted, chat messages are dropped and a `ui_core` Alert shows instead:
  "You are muted! Time left: …". On mute the target gets "Muted by `<admin>`
  (`<minutes>` min) for `<reason>`", the admin gets "You muted `<player>`
  (`<minutes>` min) for `<reason>`". On expiry: "Your mute has expired…". The
  mute **survives a relog** (account data), there is **no `/unmute`** — it
  expires on its own.

---

## Element data keys (other resources can read them too)

| Key | Side | Contents |
|---|---|---|
| `ID` | server | unique player ID (number) |
| `admin_level` | server | admin level (number) |
| `adminjail` | server | whether jailed (bool) |
| `adminjail_remTime` | server | minutes remaining |
| `adminjail_admin` / `adminjail_indok` | server | jailing admin / reason |
| `banned` | server (`v_accounts`) | whether banned (bool) |
| `banned_date` / `banned_admin` / `banned_reason` / `banned_account` | server (`v_accounts`) | ban details |
| `mute_until` | server (`v_chat`) | mute end (epoch); `mute_reason` / `mute_admin` |
