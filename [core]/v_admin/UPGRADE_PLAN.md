# v_admin 3.0 – frissítési terv (2026-10-21)

Állapot: **implementálva 2026-10-21** (szintaxis + offline füstpróbák rendben, játékban és élő weben még nem tesztelve). Mentett szűrők kész (accData admin_filters); a fiók lista pénz/játékidő oszlop nélkül, készpénz és bank külön a részletlapon.

## 1. Elrendezés

- A panel a képernyő **100%-át** foglalja el (`ADMIN.panel.size` megszűnik, a layout a `guiGetScreenSize()`-ból számol; `fontScale` marad).
- **Bal oldalsáv** (fix ~300 px @1080p): fejléc (név, rang, ID), alatta kategóriákba csoportosított menüpontok, jobb oldalon jelvények (online szám, nyitott reportok, mail sor). Lent: instance ID + UTC idő.
- Felső sáv: oldalcím + breadcrumb, globális számlálók, bezárás gomb.
- A tartalom oldalanként változik; a lista + részletek oldalaknál kétpaneles (lista balra, kiválasztott elem jobbra).
- Az oldalsávban **minden menüpont látszik**; amihez nincs jog, az halványan, lakattal jelenik meg (a „data is never hidden” szabály a menüpontokra is áll, csak a műveletek tiltottak). Kivétel: Mail/News szerkesztés tartalma látszik, a küldés/mentés gomb tiltott.

### Menüstruktúra (UI angol)

| Kategória | Oldal | Forrás | Jog |
|---|---|---|---|
| OVERVIEW | **Dashboard** *(új, javaslat)* | több resource | panel (1) |
| PLAYERS | **Online players** (eddig Players) | v_admin | 1 |
| | **Accounts** *(új)* | MySQL `accounts` + exportok | 1 megnéz / akciók szint szerint |
| | Reports | v_admin | 1 |
| | **Bans & mutes** *(új, javaslat)* | `bans` tábla, v_chat | 3 / 1 |
| SERVER | Server | v_admin | – |
| | **Resources** *(javaslat)* | v_main | 5 |
| | **Admin log** *(javaslat)* | új `admin_log` tábla | 1 megnéz |
| CONTENT | **Weekly** (← `/weekly`) | v_weekly | 4 |
| | **News** (← `/news`) | v_news | 5 |
| | **Mail** (← `/mail`) | v_mail | 5 |
| | **Achievements** (← `/ach`, javaslat) | v_achievements | config szerint |
| HELP | Commands | v_admin | – |

A keresett „még egy parancs” a **`/news`** (v_news, saját szerkesztő panel, admin 5). Ugyanebbe a körbe illik még a `/ach` (v_achievements), a `giveworkxp`/`setworklevel` (work_core) és a `givexp`/`resetlvl` (v_levelsys) – ezek az Accounts részletlapra kerülnének akcióként.

## 2. Új oldalak

### 2.1 Accounts
- Lista az összes fiókról, lapozva (50/oldal), rendezhető oszlopok: account, display name, admin, money, level, vehicles, playtime, last seen, status.
- **Szűrők**: szabad szöveg (account / display name / e-mail), admin szint, státusz (online / banned / muted / jailed), regisztráció dátuma, e-mail van-e, update mail feliratkozás, és egy „+ Filter” menü a számszerű változókra (money, level, XP, playtime, járműszám, work szint, achievement szám) `≥ / ≤ / =` operátorral. Aktív szűrők chipként; mentett szűrők (accData `admin_filters`).
- **Részletlap** fülei:
  - *Overview* – e-mail (maszkolva; teljes cím 5+), update mail, money, level/XP, work szintek, playtime, utolsó serial/IP, regisztráció, utolsó belépés, achievement szám.
  - *Stats* – v_stats kategóriái.
  - *Vehicles* – `vehicles` tábla: modell, rendszám, állapot (spawnolt / garázs / destroyed); akciók: restore, delete, give vehicle.
  - *Mails* – a `mails` tábla sorai erre az accountra (kind, subject, status, error), megnyitható szöveggel.
  - *Punishments* – bans (aktív + feloldott), mute, jail előzmények (az Admin logból).
  - *Inventory* – v_inventory tartalom (csak olvasás az első körben).
  - *Social* – barátok, crew (v_socialpanel).
  - *Notes* – admin megjegyzések az accounthoz (új accData kulcs vagy `admin_notes` tábla).
- Akciók (meglévő `admin*` függvények + újak): admin szint, money szerkesztés, mail küldése ennek az accountnak, ban/unban, unmute, work XP/szint, XP, achievement adás/elvétel, jelszó-visszaállító mail küldése; online esetén goto/spectate. Offline accountnál minden akció accData-n keresztül megy (`v_mysql:setAccData`).
- **Teljesítmény**: a szerver egyszerre tölti be az `accounts` táblát (async, `importAsync`), a JSON `account_data`-t egyszer parse-olja, és ~30 s-os cache-ben tartja; szűrés/rendezés Lua-ban a cache-en, a kliens csak az aktuális oldalt kapja meg. Online játékosoknál a cache helyett az élő accData az irányadó.
- Hiányzó adatok, amiket az v_accounts-nak menteni kell: `last_login`, `last_serial`, `last_ip`, `playtime` (ha még nincs).

### 2.2 Online players
- A régi Players fül átnevezve, ugyanazok a műveletek; új gomb: **Open account** → az Accounts oldal részletlapja nyílik meg erre az accountra.

### 2.3 Weekly (← `/weekly`)
- A v_weekly admin ablak tartalma (hetek listája + Jobs / Timetrial / Login bonus / News fülek) oldalba költözik. Szövegbevitel panelen belüli mezővel, nem ui_core overlay-jel.
- Előnézet: a heti panel megnyitása magamnak (`weekly:adminPreview` megfelelője).

### 2.4 News (← `/news`)
- Cikklista balra (megjelent / ütemezett / törölt), szerkesztő jobbra: cím, többsoros törzs, dátum + idő ütemezéshez, mentés / törlés.

### 2.5 Mail (← `/mail`)
- Al-fülek: **Compose** (címzettek + nyelvenkénti tárgy/szöveg, mint ma), **History** (csoportok → levelek → szöveg), **Queue** *(javaslat)*: függő/hibás levelek száma, napi limit állása, kézi újraküldés, **Updates**.
- **Updates fül**: következő heti update időpontja, legutóbbi futás eredménye, és **„Send test update to my e-mail”**: a teljes heti update levelet (v_news + v_weekly tartalom) elküldi az admin saját account e-mail címére, a választott nyelven. Nem csoportos, `kind = "test"`, nem számít a 300/24h limitbe, és instance-től függetlenül működik.
- Compose-ban is: „Send test to me” (a meglévő `test` mód).

### 2.6 Javasolt további oldalak
- **Dashboard**: online / max, nyitott reportok, aktív bannok, mail sor + napi limit, aktuális hét (multiplier, timetrial), legutóbbi admin akciók, nem futó fontos resource-ok.
- **Bans & mutes**: összes aktív és lejárt ban (`bans` tábla), szűrés account/serial/admin szerint, unban; aktív mute-ok és jailek.
- **Admin log**: minden admin akció naplózva (`admin_log`: ts, admin, forrás `game`/`web`, akció, cél account, paraméterek). Webes akcióknál különösen fontos. Szűrhető adminra/akcióra/célra.
- **Resources**: v_main start/stop/restart, `checkupdates` / `updateresources`, futó/álló állapot listája.

## 3. Architektúra

### 3.1 Kliens (játékon belüli)
- `client/panel/core.lua`: `AP.addTab` → `AP.addPage{ id, category, label, icon, perm, badge = fn, draw = fn, onOpen = fn }`; az oldalsávot a core rajzolja a kategória-sorrendből (`ADMIN.panel.categories`).
- Új widgetek a core-ba: táblázat (rendezhető fejléc, lapozás), szűrő-chip, fülsor, **többsoros szövegmező** (a v_mail/v_news `client/field.lua` alapján, egy közös példány a v_adminban).
- Új fájlok: `client/panel/dashboard.lua`, `accounts.lua`, `bans.lua`, `weekly.lua`, `news.lua`, `mail.lua`, `adminlog.lua`, `resources.lua`.
- A régi resource-panelek (v_weekly/client/admin.lua, v_mail/client/panel.lua, v_news/client/editor.lua) törlődnek; a `/weekly`, `/mail`, `/news` parancs megmarad és az admin panelt nyitja a megfelelő oldalon (mint a `/reports`).

### 3.2 Szerver
- Egy általános panel-hívás: `v_admin:panelCall (page, action, args)` → `server/pages/<page>.lua` kezelője, válasz `v_admin:panelReply`. Ugyanezt hívja a web (`adminWebCall(token, page, action, args)`), így minden oldal logikája egy helyen van (a mostani web actor mintára).
- Jogosultság: `ADMIN.perms` bővül (`accounts`, `accountEdit`, `weekly = 4`, `news = 5`, `mail = 5`, `mailTest = 5`, `resources = 5`, `adminLog = 1`). A cél-resource-ok saját `ADMIN_LEVEL` értéke helyett a v_admin ellenőriz, az exportok pedig csak a v_admintól (vagy saját resource-tól) fogadnak hívást (`sourceResource` ellenőrzés), és megkapják a cselekvő admin account nevét a naplózáshoz.
- Minden akció → `admin_log` sor.

### 3.3 Web panel
- `web/index.html` + `app.js`: ugyanaz az oldalsáv-szerkezet (bal oldali kategóriás lista, teljes szélesség), ugyanazok az oldalak. Az oldalak `adminWebCall`-on keresztül kapnak adatot; táblázat/szűrés/lapozás szerveroldali, mint játékban.
- A régi `adminWebState/Action/Report/Logs` megmarad átmenetileg, később `adminWebCall`-ba olvad.

## 4. Szükséges exportok

| Resource | Új export (szerver) | Megjegyzés |
|---|---|---|
| **v_weekly** | `adminOverview()`, `adminEdit(actor, action, ...)`, `adminPreview(player, weekOffset)` | a `server/admin.lua` eseménykezelőiből kiemelve; meglévő setterek maradnak |
| **v_news** | `newsAdminList()`, `newsSave(actor, id, title, body, publishAt)`, `newsDelete(actor, id)` | `server/editor.lua` logikája exportként |
| **v_mail** | `mailRecipients()`, `mailSendCircular(actor, names, texts, test)`, `mailHistoryGroups(page)`, `mailHistoryGroup(key)`, `mailHistoryMail(id)`, `mailsOfAccount(name, limit)`, `mailQueueInfo()`, `updatesInfo()`, `sendUpdateTest(actor, email, lang)`, `retryFailed(actor, ids)` | `sendUpdateTest`: `updates.lua` `content()`/`collect()` egy címzettre |
| **v_ownveh** | `getAccountVehicles(name)`, `adminRestoreVehicle(id)`, `adminDeleteVehicle(id)`, `adminGiveVehicle(name, model)` | |
| **v_stats** | `getAccountStats(name)` (offline accra is) | |
| **v_achievements** | `getAccountAchievements(name)`, `adminGrant/Revoke(actor, name, id)` | `/ach` logikája |
| **work_core** | `getAccountWorkLevels(name)`, `adminSetWorkLevel/GiveWorkXP(actor, name, work, n)` | |
| **v_levelsys** | `getAccountLevel(name)`, `adminGiveXP/ResetLevel` | |
| **v_inventory** | `getAccountInventorySummary(name)` | csak olvasás |
| **v_socialpanel** | `getAccountSocial(name)` (friends, crew) | |
| **v_accounts** | `listBans(filter, page)`, `getAccountBans(name)` | unban már van |
| **v_accounts** | `sendPasswordReset(name)`; `last_login/serial/ip` mentése belépéskor | |
| **v_main** | `listResources()`, `adminResourceAction(actor, name, action)` | a parancsok logikája exportként |

## 5. Ütemezés

1. Core átalakítás: teljes képernyő, oldalsáv + kategóriák, `addPage`, új widgetek, `panelCall`/`adminWebCall`, `admin_log`. A meglévő fülek átköltöztetése (Online players, Reports, Server, Commands).
2. Accounts (lista + szűrés + Overview/Vehicles/Mails/Punishments), Online players → Open account. v_accounts `last_*` mezők.
3. Weekly, News, Mail (+ update teszt) oldalak; régi panelek törlése, parancsok átirányítása.
4. Web panel ugyanezekkel az oldalakkal.
5. Javasolt extrák: Dashboard, Bans & mutes, Admin log oldal, Resources, Achievements, további részletfülek.

## 6. Nyitott kérdések

- A régi `/weekly`, `/mail`, `/news` saját paneljei teljesen megszűnjenek (javaslat), vagy maradjanak párhuzamosan?
- E-mail cím: teljes cím mindenkinek (a „semmit nem rejtünk” szabály szerint), vagy maszkolva 5-ös szint alatt?
- Offline account szerkesztése (money, admin szint) engedélyezett-e, és milyen szinttől?
