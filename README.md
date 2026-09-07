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
> mechanics may change over time. There is no version number either, because the
> pack evolves continuously.

## Resource structure

Resources are organised into category folders (`[...]`). `listres.py` generates
the load list from this structure (the `[tiktok]` group is skipped – it is not
part of the base mod).

| Folder | Contents |
| --- | --- |
| `[core]` | Base systems: accounts/login, admin, bank, level system, spawn and join handling, modloader, gamemode name (`v_main`). |
| `[ui]` | User interface: the UI framework (`ui_core`), pause menu, virtual browser, download screen, interaction menu, radar/map, the DGS GUI library. |
| `[player_interaction]` | Player-to-player interaction: chat, nametags, phone, social panel. |
| `[minigames]` | Jobs and minigames: job manager, arena war, time trial. |
| `[vehicles]` | Vehicle features: ELS lights, headlights, car radio. |
| `[world]` | World elements: real time, store robbery, cable cars, elevators, ferris wheel. |
| `[graphics]` | Visual enhancements: shaders, dynamic lighting/sky, draw distance, road surfaces, grass. |
| `[audio]` | Audio replacements (weapon sounds, train horn). |
| `[maps]` | Map and object data. |
| `[npc]`, `[rpg]` | Groups reserved for later expansion. |
| `v_modmenu` | F1 free-roam / test menu (for development). |

By convention most resource names start with the `v_` prefix. The UI resources
`<include>` `ui_core` and draw to the screen through its client exports
(notifications, alert, banner, HUD sizes).

## Main panels

Every larger surface sets `elementData` flags (e.g. `browserOpen`,
`socialPanelOpen`, `phoneOpen`, `interactionMenuOpen`), and the other panels
watch these so they will not open on top of an already-open surface.

- **Account / login (`v_accounts`)** – a login/register panel on connect; this
  owns the player's account data, which the other systems also read and write.
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
  contacts, browser, settings). Other resources (e.g. the job manager) push
  lobby invites through the phone.
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
  panel.

## Minigames and content

- **Job manager (`v_jobmanager`)** – jobs and lobbies (race and deathmatch
  modes), with invites and a scoreboard.
- **Arena war (`v_arenawar`)**, **time trial (`v_timetrial`)** – standalone
  minigames.
- **World interactions** – store robbery, cable cars, elevators, ferris wheel,
  real-time clock and weather.

## Developer notes

- Where a resource has its own detailed docs, they live in its `README.md` /
  `readme.xml` (e.g. `[ui]/ui_browser`, `[core]/v_bank`).
- Runtime-generated files that hold personal data (bans, crews, messages,
  models) are `.gitignore`d, as is the `[tiktok]` integration. - [mtasa-tiktok-integration](https://github.com/drandrew112/mtasa-tiktok-integration)
- `listres.py` generates the `<resource ... />` lines for the server's
  `mtaserver.conf`.
