# [business] – organizations

Player-founded organizations (companies) with their own interiors, a company account,
the OrgOS computer, temporary associates and activities. Built 2026-10-22 from the plan
artifact (v2 + the user's decisions). **Not tested in game yet.**

| Resource | What it does |
| --- | --- |
| `biz_core` | Companies, company account (clean + dirty) and ledger, property catalog, buying/selling, selling the organization, temporary associates, the online tick (upkeep, activity ticks), registry/top list cache, notifications, stats, admin API |
| `biz_int` | Own interior system (independent of `world_interiors`): entrances, one private inside per unit (dimension `30000 + unit id`), access control, owner-only blips, computer + props per inside, `/bizpos` |
| `biz_pc` | OrgOS – the computer of offices and properties (full-screen `web_api` page). Office: Overview, Finance, Properties (buy), Settings. Site (only that site): weed farm = Overview / Supply / Stock / Sales / Upgrades / Sell property, casino = Overview / Laundering / Sell property |
| `biz_web` | `sabusinessregistry.eu` (in-game browser only): register, move headquarters, registry search, top organizations |
| `biz_weed` | Weed farm activity (illegal, supply/deliver): supply → product in online time, bought supply, Capacity / Staff upgrades, HUD |
| `biz_casino` | Casino activity (legal, passive): one result per online hour, events, money laundering queue |
| `biz_missions` | Supply steal (guards, van or crate) and product delivery (40 units per van, +1 van per online associate, 30 min, 50% enemy chance, hijacking, visible shipment, disconnect = half back) |

Extended: `ui_core` (stat tracker `progress` bar), `ui_inac` (My organization on top of the main
menu), `ui_phone` (Organization app), `ai_land_traffic` (scripted `pursuit` + `engageScriptedVehicle`),
`v_inventory` (`biz_supply_crate` item), `v_weekly` (Business sale multipliers), `v_stats` (Business
category), `v_achievements` (12 achievements), `v_admin` (Organizations page in game + web, account
tile, Weekly → Business tab), `acc_menu` / `ui_pause` (Business stat category).

## Rules (user decisions)

- One organization per player. Registration 50 000 € + the office, paid from the player's bank.
  Everything after that is paid by the company account.
- **Online only:** production, casino, laundering and upkeep run only while the founder is online
  (biz_core ticks per online minute; every counter is in online seconds). The casino works per hour.
- Upkeep every 2 online hours for every property and the office; unpaid → paused until the account covers it.
- Deposit from the founder's bank is allowed. Dirty money can be withdrawn (logged in accData
  `biz_dirty_withdrawn` for later consequences) or laundered through a casino (40 000 € / casino hour, 12%).
- Temporary associates: founder + max 3, memory only; the membership ends on leave / disconnect / removal
  and when the founder disconnects. An associate may own an organization of his own.
- Selling the organization ends it: full balance + 60% of properties, upgrades and stock.
- Delivery payout: founder → company 100%; associate → 80% his bank / 20% company; stranger → 60% his bank.
- Weekly Business bonus: sale multipliers for supply/deliver activities only (not the casino).
- Every business event is a ui_core notification (no e-mail).

## Images

`biz_core/img/buildings/<building>.jpg` (one photo per `BIZ.BUILDINGS` key, 1280x720) and
`biz_core/img/upgrades/<activity>_<upgrade>.jpg` (800x500), client files used by biz_pc and biz_web
as `/biz_core/img/...`. New building photo: take it with `/takeapic free`, name the PNG after the
building key and run `python tools/compress_photos.py`. Upgrade pictures: `tools/draw_upgrades.py`
(SVG, saved as JPEG). A missing picture leaves an empty dark frame.

## Data (MySQL, self-created)

`biz_companies`, `biz_units`, `biz_ledger` (biz_core), `biz_weed`, `biz_casino_state`,
`biz_casino_hours`, `biz_missions` (log). Balances are changed with deltas only, so several
instances add up; loaded companies re-read their balance every 60 s.

## To check in game (positions are estimates)

- Entrances marked "approx" in `biz_core/shared/properties.lua` (Downtown Plaza, SF Financial,
  Redsands Tower, Castillo del Diablo farm) come from verified ground spots, not doors.
- Computer / spawn positions of every template (`biz_int/shared/config.lua`, "verify"), the weed
  plant grid and staff peds inside Warehouse 2. Fix them standing in place:
  `/bizpos <template> <spawn|exit|computer>` or `/bizpos building <id>` (admin level 5,
  saved to `biz_int/data/positions.json`).
- Mission spots and buyers (`biz_missions/shared/config.lua`), the crate item model/offsets
  (`v_inventory`), the pursuit behaviour on the road.

## Tests

`python biz_core/tests/run.py` (lupa): money order, sale payout, laundering, associates limit and
disconnects, sale split and multipliers, upkeep pause/resume, names.

## Error codes of the founder actions

`not_logged_in`, `unavailable`, `has_company`, `name_short`, `name_long`, `name_invalid`,
`name_taken`, `name_same`, `rename_cooldown`, `bad_office`, `not_enough_money`, `no_company`,
`already_owned`, `use_move_hq`, `unknown_property`, `unknown_unit`, `cannot_sell_hq`,
`activity_offline`, `bad_amount`, `confirm_mismatch`.
