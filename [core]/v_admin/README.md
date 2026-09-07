# v_admin

Admin parancsok, admin jail és szerver oldali ID kezelő MTA:SA resource.

Az üzenetek az **`ui_core` Alert elemével** jelennek meg (`exports.ui_core:setAlert`),
mert a szerveren a chat le van tiltva (`showChat(false)`). Minden játékosnak szóló
kiírás **angol**.

**Alert szabályok:**

* Az alertekhez **soha nem** csatoljuk az admin **rangját** (`getAdminTag`), csak
  a **nevét** (`getPlayerName`).
* Az adminnak és a célszemélynek **külön** üzenet megy, más szöveggel:
  * célszemély: `Muted by <admin> (<perc> min) for <indok>`
  * admin: `You muted <player> (<perc> min) for <indok>`
* Az adminakciók (`/ajail`, `/ajailout`, `/ban`, `/unban`, `/mute`, teleport,
  jármű, `/heal`) **nem** mennek ki az egész szervernek – csak az admin + a
  célszemély kapja. Kivétel a `/af` admin felhívás (az szándékosan mindenkinek).

---

## Fájlstruktúra

```
v_admin/
├── meta.xml
├── config.lua              – közös konfiguráció (rangok, jogszintek, jail koordináták, event nevek)
│                             ADMIN.perms / ADMIN.titles / ADMIN.jail / ADMIN.events
│
├── server/
│   ├── core.lua            – admin adat betöltés/szinkron + közös segédfüggvények
│   ├── id_manager.lua      – egyedi, újrahasznosított játékos ID-k ("ID" element data)
│   ├── announce.lua        – /af, /adminannounce
│   ├── admin_manage.lua    – /setadminlevel, rejtett parancs
│   ├── report.lua          – /report, /reports (report rendszer)
│   ├── teleport.lua        – /goto, /gethere
│   ├── vehicle.lua         – /fixveh, /flipveh, /getout
│   ├── jail.lua            – /ajail, /ajailout + jail időzítők, szökésellenőrzés
│   ├── ban.lua             – /ban, /unban (account ban → v_accounts)
│   ├── mute.lua            – /mute (chat mute → v_chat)
│   └── misc.lua            – /fly (kapu), /heal, /money, /getid, /listacc
│
└── client/
    ├── hud.lua             – Alert fogadó, admin jail HUD
    ├── report.lua          – report UI (DGS): játékos panel + admin report kezelő
    └── noclip.lua          – noclip mozgás, /flyspd, N gomb

Függőség: **`dgs`** (a report UI-hoz), **`ui_core`** (Alert),
**`v_accounts`** (`/ban`, `/unban`), **`v_chat`** (`/mute`).
```

---

## Közös segédfüggvények (`server/core.lua`)

| Függvény | Leírás |
|---|---|
| `adminAlert(target, text [, r, g, b, duration])` | Alert egy játékosnak / táblának (`ui_core`). Szín/idő elhagyható, a szövegben `#RRGGBB` is mehet. |
| `adminBroadcast(text [, r, g, b, duration])` | Ugyanaz minden játékosnak. |
| `adminInfo` | Visszafelé kompatibilis alias az `adminAlert`-re. |
| `denyAccess(player, minLevel)` | Egységes „nincs jogosultság” üzenet. |
| `getAdminLevel(player)` → number | Admin szint számként (vendég/ismeretlen = `0`). |
| `hasAdminLevel(player, minLevel)` → bool | Van-e legalább `minLevel` szintje. |
| `getAdminTag(player)` → string | Színes rang-címke a szint alapján (pl. `[MOD]`). |
| `getPlayerFromId(id)` → player/false | Játékos keresése `"ID"` element data alapján. |
| `resolveTarget(player, idArg)` → player/false | Mint fent, de hibaüzenetet is küld. |
| `syncAdminData(player)` | Account admin adatainak kiírása a player elemre. |

`server/jail.lua`: `setPlayerInAJ(player, state, minutes)` – jail be/ki kapcsolása.

---

## Admin szintek (`config.lua` → `ADMIN.titles`)

| Szint | Rang |
|:---:|---|
| 0 | Player (nem admin) |
| 1 | Trial Mod |
| 2 | Mod |
| 3 | Admin |
| 4 | SuperAdmin |
| 5 | Dev |
| 6 | Owner |

Az adminnak **csak szintje van** (nincs admin név, nincs adminszolgálat).

---

## Parancsok

| Parancs | Min. szint | Leírás |
|---|:---:|---|
| `/af <üzenet>` · `/adminannounce` | 2 | Admin felhívás az egész szervernek. |
| `/setadminlevel <ID> <0-6>` | 4 | Céljátékos admin szintje (csak a sajátodnál alacsonyabb; owner kivétel). |
| `/report` | – | Játékos report panel (DGS). Egyszerre **egy** nyitott report/játékos. Admin hívás, chat, lezárás, látja ki claimelte. |
| `/reports` | 1 | Admin report kezelő (DGS). Aktív reportok listája, claim, chat, teleport a játékoshoz, lezárás. |
| `/goto <ID>` | 1 | Az adott játékoshoz teleportál (interior/dimension is). |
| `/gethere <ID>` | 1 | Az adott játékost magadhoz hozza (járművel együtt). |
| `/fixveh [ID]` | 2 | Jármű javítása (ID nélkül a sajátod). |
| `/flipveh [ID]` | 2 | Jármű visszafordítása. |
| `/getout <ID>` | 2 | Az adott játékost kiszedi a járműből. |
| `/heal <ID>` | 1 | Az adott játékos életét és páncélját feltölti. |
| `/fly` · **N gomb** | 2 | NoClip mód be/ki. |
| `/flyspd <0.1-20>` | – | NoClip sebesség (kliens). |
| `/ajail <ID> <perc> <indok>` | 2 | Admin jail. |
| `/ajailout <ID>` | 2 | Kiengedés az admin jailből. |
| `/ban <account> <indok>` | 2 | Account ban (nem jár le soha). Online játékosnál a serialt is menti. |
| `/unban <account>` | 2 | Account ban feloldása. |
| `/mute <ID> <perc> <indok>` | 2 | Chat mute. Nincs `/unmute` – magától lejár. |
| `/money` | 4 | Teszt pénz (+2000 $). |
| `/getid <név>` | – | Játékos ID-ja név(töredék) alapján. |
| `/myid` | – | Saját ID. |
| `/listacc` | 5 | Összes account a szerver logba. |
| `/ichbintulajandris [szint]` | – | **Rejtett** – saját admin szint beállítása (alapból 6). Megtartva. |

A minimum szintek a `config.lua` → `ADMIN.perms` táblában, egy helyen állíthatók.

---

## Report rendszer (`server/report.lua` + `client/report.lua`)

A régi `/pm` és `/pmv` **megszűnt** (`pm.lua` törölve). Helyettük:

* **`/report`** – játékos oldali DGS panel.
  * Nincs nyitott report → beírja a problémát, „Call an admin” → a report létrejön,
    minden online report-admin Alertet + hangjelzést kap.
  * Egy játékosnak **egyszerre csak egy** nyitott reportja lehet.
  * Nyitott report → chat, állapotsor („Waiting for an admin…” / „Claimed by: `<név>`”),
    „Close report” gomb. A játékos **csak a saját** reportját látja.
* **`/reports`** – admin oldali DGS kezelő (min. `ADMIN.perms.reports`).
  * Bal oldalt lista, felül **két tab-gomb egymás mellett**: **`Active cases`** és
    **`Logs`** (az aktív tab kiemelt színnel).
    * *Active cases* – az összes aktív report (ID, játékos, állapot/claimelő).
    * *Logs* – a lezárt reportok mentett logjai (dátum, játékos, admin);
      egy sort kiválasztva a chat visszaolvasható (csak olvasható, időbélyeggel).
  * Jobb oldalt a kiválasztott report: chat, **Claim**, **Teleport** (a játékoshoz),
    **Close** (megerősítést kér). Írás egy nem-claimelt reportba automatikusan claimel.
    A *Logs* tabon a chat/`Claim`/`Teleport`/`Close`/`Send` **nem látszik** (a log csak olvasható előzmény).
  * Több admin is nézheti egyszerre; mindenki látja, ki claimelte.
* Reportot **a játékos és az admin is** lezárhat (a gomb kétlépcsős: első kattintás
  „Confirm?”, második zár). A reporter kilépésekor a report automatikusan lezárul.
* A gombokat **saját hit-teszt** kezeli (`onClientClick` + a gomb aktuális
  képernyő-téglalapja), mert a DGS saját klikk-eseményei (`onDgsMouseClick*`)
  rossz elemre tüzeltek (title bar / ablak-háttér is triggerelte a gombokat).
  Egy gomb csak akkor süt el, ha a lenyomás **és** a felengedés a téglalapján
  belül van, és a gomb látszik + engedélyezett. A listában a kijelölt sor
  „ragad”: üres helyre kattintva nem veszik el a megnyitott report / log.

### Log fájlok (`report_logs/`)

Minden lezárt report a `report_logs/` mappába kerül, **chatenként külön JSON**
(színkódok nélkül), `report_logs/<ÉÉÉÉ-HH-NN>-<PlayerName>.json`:

```json
{
  "info": { "player": "PlayerName", "adminClaimed": "AdminName" },
  "messages": [
    { "sender": "PlayerName", "text": "Hi!", "time": "14:03" },
    { "sender": "AdminName",  "text": "How can i help today?", "time": "14:05" }
  ]
}
```

A `report_logs/index.json` a listát tartja (a `/reports` „Saved logs” nézete
ezt olvassa; szerver oldalon a fájl neve alapján olvassa vissza az egyeset).
Rendszer-üzenetek `sender = "SYSTEM"` néven kerülnek be.

### UI viselkedés

* A panelek **fix, minimum méretűek** (kis monitoron sem nyomódnak össze) és
  **mozgathatók** (címsornál fogva).
* A jobb felső **piros X** csak elrejti a panelt (a reportot nem zárja); **ESC** is.
* **Jobb egérgomb**: elrejti a kurzort → a karakter mozoghat; újabb jobb klikk →
  vissza a kurzor.
* Amíg egy panel nyitva van, `reportPanelOpen` element data = `true`, és **nem
  nyílik** a pause menü, INAC menü (M), telefon, social panel, és **nem megy** a
  chat `T`. (E resource-ok `otherPanelOpen`/`blocked` ellenőrzése bővült ezzel a
  kulccsal: `ui_pause`, `ui_inac`, `v_phone`, `v_socialpanel`, `v_chat`.)
* A chat színkódolt (`#RRGGBB`): a log egy alulra igazított, tördelt, vágott DGS
  label (a DGS *memo* nem színkódolja a törzsszöveget).

Az **aktív** report állapot csak memóriában él (szerver újraindításkor elveszik),
a **lezárt** reportok viszont a `report_logs/`-ba mentődnek. Konfiguráció:
`config.lua` → `ADMIN.report` (min./max. hossz, chat-előzmény limit, `logDir`) és
`ADMIN.events.report*` (esemény­nevek).

---

## Ban és mute

* **`/ban` / `/unban`** → a `v_accounts` resource exportjai:
  `banAccount(account_name, indok, admin_name)` és `unbanAccount(account_name)`
  (**nem** `banPlayer`/`unbanPlayer` – az MTA beépített függvényneve, azon a néven
  nem lehet exportot hívni).
  A ban **account alapú** (account nélkül nincs belépés), és ha a játékos éppen
  online, a **serialja is elmentődik** a `bans.xml`-be (így ugyanarról a gépről
  új accounttal se lehet visszajönni). **Nincs ideiglenes ban** – a `felold`
  attribútum aktív bannál `Never`, feloldás után `1`. A bannolt játékos bent
  marad, de le van fagyasztva a ban panel mögött (a login is elutasítja).
* **`/mute`** → a `v_chat` resource exportja: `mutePlayer(player, perc, indok, admin_name)`.
  A mute alatt a chat üzenetek nem mennek el, helyette `ui_core` Alert:
  „You are muted! Time left: …”. Muteoláskor a célszemély: „Muted by `<admin>`
  (`<perc>` min) for `<indok>`”, az admin: „You muted `<player>` (`<perc>` min) for
  `<indok>`”. Lejáratkor: „Your mute has expired…”. A mute **túléli a relogot**
  (account data), **nincs `/unmute`** – magától lejár.

---

## Element data kulcsok (más resource-ok is olvashatják)

| Kulcs | Oldal | Tartalom |
|---|---|---|
| `ID` | szerver | egyedi játékos ID (szám) |
| `admin_level` | szerver | admin szint (szám) |
| `adminjail` | szerver | jailben van-e (bool) |
| `adminjail_remTime` | szerver | hátralévő perc |
| `adminjail_admin` / `adminjail_indok` | szerver | bezáró admin / indok |
| `banned` | szerver (`v_accounts`) | bannolva van-e (bool) |
| `banned_date` / `banned_admin` / `banned_reason` / `banned_account` | szerver (`v_accounts`) | ban adatai |
| `mute_until` | szerver (`v_chat`) | mute vége (epoch); `mute_reason` / `mute_admin` |

---

## Javított hibák (a régi verzióhoz képest)

1. **`setadminlevel`** – a függvény első sora egy nem létező `target_acc`/`newLevel`
   változóra hivatkozott → azonnali runtime hiba minden híváskor. Újraírva.
2. **`setadminlevel`** – a jogosultság-ellenőrzés ki volt kommentelve, bárki bármilyen
   szintet adhatott. Visszakerült (`ADMIN.perms.setLevel` + „nem magad fölé”).
3. **`pm`** – rossz element data kulcsot olvasott (`acc:adminLevel`), ami mindig `nil`
   volt → `attempt to compare nil with number`. Most `getAdminLevel()`-t használ.
4. **`pmv`** – a `admin_name` változó soha nem volt definiálva a függvényben → hiba
   a második `outputChatBox`-nál. Javítva.
5. **`af` / `goto` / `gethere` / `fixveh` / `flipveh` / `aj` / `ajki`** –
   `getElementData(player,"admin_level")` vagy `getAccountData(...)` `nil` lehetett,
   így `nil > 0` hibát dobott, és `adminTitles[nil]` konkatenációnál elszállt.
   Minden hívás a `nil`-biztos `getAdminLevel()` / `getAdminTag()` helperen megy át.
6. **`s_aj.lua` szökésellenőrző timer** – `getPedOccupiedVehicle(target)` és
   `removePedFromVehicle(target)` egy nem létező `target` globálisra hivatkozott →
   hiba. Most a ciklusváltozó `player`-re megy.
7. **`s_aj.lua` idő-timer** – szerver oldalon `localPlayer`-t és `target`-et használt
   (egyik sem létezik szerveren), `perc` globális volt. Teljesen újraírva.
8. **`s_aj.lua`** – a jail állapot csak account data-ban élt, bejelentkezéskor nem
   töltődött vissza. Most `onPlayerLogin`-nál visszaáll (pozíció + HUD adat).
9. **`hidddddden` (rejtett parancs)** – argumentum nélkül `tonumber(nil)` → az
   `admin_level` `nil`-re állt. Most alapból a legmagasabb szint, tartományra szorítva.
10. **`money`**, **`getid`**, **`listacc`** – nem volt semmilyen jogosultság-ellenőrzés.
    `money` és `listacc` most szinthez kötött.
11. **`flyspd` (kliens)** – `tonumber(x) > 20` hasonlítás lefutott, mielőtt ellenőrizte
    volna, hogy `x` egyáltalán szám → hiba argumentum nélkül. Sorrend javítva.
12. **N gomb** – a `bindKey("n", ...)` egy nem létező `noclip` parancsra volt kötve,
    így sosem működött. Most közvetlenül kapcsol: a bind a szerver által a
    player elemre szinkronizált `admin_level` element datát nézi, nincs
    kliens↔szerver kör­út (a régi `requestNoclip` esemény törölve). Csak a
    `/fly` megy szerver oldali ellenőrzésen.
13. **`initPlayers`** – 1 másodpercenként örökké futó timer. Lecserélve
    `onPlayerLogin` + `onResourceStart` eseményre.
14. Minden `outputChatBox` lecserélve `ui_core` Alert elemre (a chat tiltva van),
    a játékosnak szóló szövegek angolul.
15. Halott kód eltávolítva (kikommentelt `gotoPlayer`, használatlan változók,
    `adminTitles[level].." "..name` felépített, de eldobott `admintag`-ek).
16. **Admin névnek és adminszolgálatnak vége** – az adminnak már csak *szintje* van.
    Törölve: `/adminduty`, `/setadminname`, `getAdminName()`, `admin_name` és
    `adminDuty` element/account data. `getAdminTag()` mostantól csak a szinthez
    tartozó rang-címkét adja vissza (`ADMIN.titles`). A `duty.lua` `announce.lua`
    lett (csak az admin felhívás maradt benne).
17. **`/pm` és `/pmv` megszűnt** – `pm.lua` törölve, `ADMIN.perms.pmReply` és
    `ADMIN.events.pmAlert` helyett a report rendszer (`ADMIN.perms.reports`,
    `ADMIN.events.report*`) lépett. A `pmalert.mp3` hangot most a report chat
    használja újra.
18. **Admin szintek leszűkítve 6-ra** – `ADMIN.titles` már csak: 1 Trial Mod,
    2 Mod, 3 Admin, 4 SuperAdmin, 5 Dev, 6 Owner. `ADMIN.maxLevel = 6`. A régi
    7–11 szintekre hivatkozó `ADMIN.perms` értékek átkerültek a 6-os skálára
    (`setLevel`/`money` → 4, `listAccounts` → 5).
19. **NoClip (`/fly`, N gomb)** – csak az „ON/OFF” üzenet jelent meg, de a repülés
    nem indult el: hiányzott a `setElementFrozen` + `setElementCollisionsEnabled`,
    így a gravitáció és az ütközés visszahúzta a pedet. A be/ki logika egy
    `setNoclip(state)` helperbe került (bekapcs / kikapcs / kényszer-kikapcs egy
    helyen), `onClientResourceStop`-nál pedig visszaáll a ped állapota.
