# MTA Online

This resource pack is the **MTA Online** mod – a full gamemode bundle for MTA:SA
that brings a **GTA Online-style experience** to the Multi Theft Auto platform.
Many of the surfaces (pause menu, phone, social panel, radar, virtual browser)
deliberately resemble GTA Online, but the systems behind them and the server
itself are a different thing entirely – this is its own platform, with its own
rules and content.

**MTA Online** is the base of the **FreeV** MTA server: the server runs on this
mod, and the additional server-specific extensions and content build on top of
it.

Who is it for? Mainly people who are **done with GTA Online** and want a fresh
experience in a familiar-but-different world.

> This README intentionally stays high level: the exact layout, keys and
> mechanics may change over time. The gamemode reports a version string (set in
> `[core]/v_main/server.lua`, e.g. `MTA Online v0.4.1 Beta`), but the pack
> itself evolves continuously – treat that string as a rough marker, not a
> release.

## Resource structure

Resources are organised into category folders (`[...]`). **The load list is no
longer hand-maintained.** `v_main` is the only resource that has to be started
by `mtaserver.conf`; on start it runs `loadResources.lua`, which:

1. scans every installed resource,
2. reads the `<include>` dependencies from each `meta.xml`,
3. sorts them into dependency (topological) order, and
4. starts the ones that are not already running.

Every step is logged to the server console. The `[tiktok]` group
(`ai_autoplayer`, `tiktok-live`) is skipped and started manually – it is not
part of the base mod. The old `listres.py` script has been removed.

| Folder | Contents |
| --- | --- |
| `[core]` | Base systems: gamemode script + resource loader + update checker (`v_main`), accounts/login (`v_accounts`), MySQL account-data sync (`v_mysql`), admin (`v_admin`), bank (`v_bank`), level system (`v_levelsys`), spawn/respawn (`v_spawnmanager`), join/quit handling (`v_joinquit`), played-time tracking (`v_playedtime`), Discord Rich Presence (`v_discordmanager`), modloader (`v_modloader`), plus gameplay scripts (`parachute`, `realdriveby`). |
| `[ui]` | User interface: the UI framework (`ui_core`), pause menu (`ui_pause`), phone (`ui_phone`), virtual browser (`ui_browser`), download screen (`ui_download`), interaction menu (`ui_inac`), radar/map (`v_radar`), the DGS GUI library (`dgs`). |
| `[player_interaction]` | Player-to-player interaction: chat (`v_chat`), nametags (`v_nametags`), social panel (`v_socialpanel`). |
| `[minigames]` | Jobs and minigames: job manager (`v_jobmanager`), arena war (`v_arenawar`), time trial (`v_timetrial`). |
| `[vehicles]` | Vehicle features: ELS lights, headlights, car radio. |
| `[world]` | World elements: real time/weather, store robbery, cable cars, elevators, ferris wheel. |
| `[graphics]` | Visual enhancements: detail/sky shaders, dynamic per-pixel lighting, draw distance, grass textures, look-direction sync. |
| `[audio]` | Audio replacements (HQ weapon sounds, train horn). |
| `[maps]` | Map and object data (interiors, stunt parks, garages, custom props). |
| `[npc]` | Group reserved for later expansion (currently empty). |
| `v_modmenu` | F1 free-roam / test menu (for development). |

By convention most resource names start with the `v_` prefix. The UI resources
`<include>` `ui_core` and draw to the screen through its client exports
(notifications, alert, banner, HUD sizes).

## `v_main` – gamemode core

`v_main` does three jobs:

- **Gamemode name / version** (`server.lua`) – sets the server's game type to
  `MTA Online v<version>`.
- **Resource loader** (`loadResources.lua`) – the dependency-ordered auto-start
  described above.
- **Update checker** (`updater.lua` + `lib/updater/`) – compares the local files
  against the public GitHub repo
  [`drandrew112/mtasa-online-resources`](https://github.com/drandrew112/mtasa-online-resources)
  and logs which files a `git pull` would change (outdated / missing). It **only
  reports** – it never downloads or modifies anything. Runs automatically ~5 s
  after start unless the `enableUpdateChecker` setting in `meta.xml` is `false`;
  the `checkupdates` console command runs it on demand. Runtime data and
  credentials (`[tiktok]`, `v_modloader`, `v_mysql`, `bans.xml`, crews/messages)
  are on its ignore list. Library:
  [fresholia/mtasa-git-resource-updater](https://github.com/fresholia/mtasa-git-resource-updater).

## Accounts, loading and account-data sync

- **Account / login (`v_accounts`)** – a login/register panel on connect; this
  owns the player's account data, which the other systems also read and write.
  After login it shows a **black loading screen** while the post-login providers
  finish, then spawns the player and fires the custom **`onPlayerLoaded`** event.
- **`onPlayerLoaded`** – because account data can be loaded **asynchronously**
  (see `v_mysql`), resources must **not** read account data on `onPlayerLogin`.
  Instead they listen for `onPlayerLoaded` (`source` = player, arg 1 = account),
  which fires once the player is fully ready – account data synced, saved state
  restored, spawned. Every consumer calls `addEvent("onPlayerLoaded")` itself, so
  handler order does not matter. When the MySQL sync is off, it still fires –
  just with no delay.
- **MySQL account-data sync (`v_mysql`)** – keeps a **localhost dev server** and
  the **hosted server** working off one external MySQL database so account data
  does not diverge. On login it pulls the player's row into the account with
  `setAccountData`; on every autosave / logout / quit it pushes the full
  snapshot back.
  - **Config:** copy `config.example.lua` → `config.lua` (git-ignored – it holds
    the DB credentials; everything else in the folder, including
    `config.example.lua` and `database.sql`, is versioned), fill in
    `MYSQL_CONFIG`, and run `database.sql` against the database.
  - **Master switch `MYSQL_ENABLE_SYNC`** (default `false`): when off, `v_mysql`
    **never connects to any database** – it reports `accountdata` ready
    instantly and `updateAccountData()` is a no-op. A server that does not need
    the sync can leave the resource installed and simply keep the switch off.
  - `v_mysql` `<include>`s `v_accounts` (starts after it); `v_accounts` calls
    `v_mysql`'s exports defensively, so it keeps working when `v_mysql` is
    absent. See [`[core]/v_mysql/README.md`](%5Bcore%5D/v_mysql/README.md).

## Main panels

Every larger surface sets `elementData` flags (e.g. `browserOpen`,
`socialPanelOpen`, `phoneOpen`, `interactionMenuOpen`), and the other panels
watch these so they will not open on top of an already-open surface.

- **HUD and notifications (`ui_core`)** – the shared framework: on-screen
  notifications, alert and banner messages, subtitles, loading text, timer,
  resolution-aware scaling. Other resources call into this instead of drawing
  directly.
- **Radar / map (`v_radar`)** – a GTA V-style minimap with GPS navigation and a
  full map.
- **Pause menu (`ui_pause`)** – the entry point for settings; settings are saved
  to the player's account. It will not open while another panel is active.
- **Social panel (`v_socialpanel`)** – `Home` / `Num 7`: friends, profiles,
  crews and messages. `Esc` closes it.
- **Phone (`ui_phone`)** – `B`: a modular, app-based phone (MyVeh, invites,
  contacts, browser, settings). Now lives under `[ui]` (moved out of
  `[player_interaction]`). Other resources (e.g. the job manager) push lobby
  invites through the phone.
- **Interaction menu (`ui_inac`)** – `M`: an arrow-key-driven, modular
  contextual menu (e.g. vehicle actions).
- **Virtual browser (`ui_browser`)** – a simple in-game "internet": websites are
  written in a custom, HTML-like `.vhtml` markup and tied together by a built-in
  search engine and categories (entertainment, finance, business, vehicles,
  property). The phone's Browser app and the `/browser` command both open it.
  It also shows a cash/bank HUD.
- **Bank (`v_bank`)** – a server-side bank account manager. Cash is GTA's own
  money; the bank balance (`bank_money`) persists on the account, and other
  resources (e.g. the browser's bank site) move money through its exports.
- **Chat (`v_chat`)** – a GTA Online-style chat (replacing the built-in MTA
  chat).
- **Admin (`v_admin`)** – admin commands, admin jail, an ID manager and a report
  panel. Permission checks read `admin_level` from account data.

## Minigames and content

- **Job manager (`v_jobmanager`)** – jobs and lobbies (race and deathmatch
  modes), with invites and a scoreboard.
- **Arena war (`v_arenawar`)**, **time trial (`v_timetrial`)** – standalone
  minigames.
- **World interactions** – store robbery, cable cars, elevators, ferris wheel,
  real-time clock and weather.
- **Gameplay scripts** – parachute / skydiving (`parachute`), real drive-bys
  (`realdriveby`).

## Developer notes

- Where a resource has its own detailed docs, they live in its `README.md` /
  `readme.xml` (e.g. `[ui]/ui_browser`, `[core]/v_bank`, `[core]/v_mysql`).
- Read account data on `onPlayerLoaded`, never on `onPlayerLogin` (see above).
- Runtime-generated files that hold personal data (bans, crews, messages,
  models) are `.gitignore`d, as is the `[tiktok]` integration
  ([mtasa-tiktok-integration](https://github.com/drandrew112/mtasa-tiktok-integration))
  and `v_mysql/config.lua`.
- There is no `mtaserver.conf` resource list to maintain – only make sure
  `v_main` itself is started. New resources are picked up automatically as long
  as their `meta.xml` `<include>` dependencies are correct.
