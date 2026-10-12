# v_locals – nyelvi fordító (lokalizáció) – DESIGN

Állapot: **3. fázis kész** (2026-10-12; 1. fázis: 10., 2. fázis: 11., 3. fázis: 12. fejezet). Minden szöveget megjelenítő resource a v_locals-on keresztül ír ki; a magyar nyelv a következő, külön engedélyhez kötött lépés.
Dátum: 2026-10-12. Szerző: DrAndrew112 (meta author).

Ez a dokumentum rögzíti a teljes tervet: a 0. fázisban felmért kiinduló állapotot,
a talált problémákat, az architektúrát, a DX-méretezést, a teljesítményt, a 2. fázis
automatizálását, a 3. fázis menetét, valamint a felhasználó által a terv átnézése
után kért módosításokat (lásd **0. fejezet**, ezek mindenhol felülírják az
eredeti javaslatot).

---

## 0. A felhasználó döntései (kötelező érvényű)

| # | Döntés |
|---|---|
| D1 | A **med_scenemanager** későbbi fázisban kap fordítást, **saját rendszerrel**. Most nem nyúlunk hozzá. Az ERM címek és leírások később **csak kliens oldalon feloldott kulcsok** lesznek; a jelenet-JSON-okba külön `locals` bejegyzés kerül. Ezt **most nem csináljuk meg**, de a v_locals-nak támogatnia kell a kliensen feloldott kulcsokat (4.5). |
| D2 | A **medsys Lifepak 15** kijelzője (`[medical]/medsys/client/lifepak.lua`) **kivétel**: könnyen érthető elem, a fordítás megtörné a valósághűséget. |
| D3 | Ahol a megjelenített szöveg egyben kulcs vagy logikai érték, ott **a működést kell átírni** azonosító alapúra. A tervezés a 6. fejezetben található. |
| D4 | A szerver fix szöveges értesítéseit **szerver oldali exporttal** fordítjuk. Az export a szöveg ID-je mellett a **játékost** is megkapja, és a játékosnak beállított nyelven adja vissza a szöveget (4.6). |
| D5 | **Kivételek, nem fordítjuk:** achievement nevek és leírások, jobmanager játéknevek (és leírások), med_scene szövegek. |
| D6 | A képkockánkénti `dxGetTextWidth`/wrap helyett a **med_erm jó mintáit** (`Gfx.fit`, `Gfx.wrap`) visszük tovább, és **módosítjuk** azokat a resource-okat, amelyek most rosszul csinálják. **Minden megjelenítésnek UTF-8 biztosnak kell lennie** (5. fejezet). |
| D7 | Az `upper` problémát **saját, UTF-8-at támogató exporttal** oldjuk meg (5.6). |
| D8 | A GTA-fontoknál jellemzően kivételek vagy számok vannak, ezeket általában nem kell fordítani. **Listázni kell, melyiket igen** (5.7). |
| D9 | A **Discordot nem fordítjuk** (v_discordmanager): globálisan ugyanúgy kell működnie. |
| D10 | A **v_modmenu**, a **claude-mcp** és a **[tiktok]** resource-ok nem kapnak fordítást. |
| D11 | Az **avi_controller** scope-ját nem szabad lefordítani: mindig angol, **az ATC login panel is**. |
| D12 | A nyelvválasztó helye: **pause menu → Settings → Display → „Language” choice mező** (4.8). |
| D13 | Lehetnek **csak a kliens által feloldott kulcsok** (később a med_scenemanager ERM szövegei). A mechanizmus kell, a scene-integráció még nem. |
| D14 | A **tesztparancsokat nem fordítjuk**, a szövegeiket **egyáltalán nem tároljuk** a katalógusban. |
| D15 | Az **`outputChatBox`-okon nem változtatunk**: a szövegük le lesz fordítva, de a működés (hogy egyáltalán chatre megy-e) a resource döntése marad. |
| D16 | A szerver lib függvénye **`L.forPlayer`** (nem `L.for`): a `for` foglalt szó a Luában, `L.for(...)` szintaxishiba lenne. |
| D18 | **Közös kulcsok (`common.*`) elfogadva:** Loading..., Back, Cancel, Save, Send, Confirm, Edit, Name, Level, Players, Played time, Race, Deathmatch, Job, Get ready, „{time_left\|1f} s”. Ezek minden resource-ban a `common.*` kulcsot használják. |
| D19 | **Aviation jóváhagyva:** csak az `avi_core` ATC-pozíció marker promptja és a jogosultsági hibaüzenetek fordulnak. A scope-tükrök (avi_monitors), az ATC-adatok és -értesítések, valamint a `/avinav` és `/avitraffic` admin-szerkesztők angolok maradnak. |
| D20 | **„WASTED” és „GO” angol marad** (magyarul is így használatos). A GTA-fontos szövegek közül így egyik sem fordul. |
| D21 | **Az időfutam-nevek (`v_timetrial`) kivételek**, mint a jobmanager játéknevek. |
| D17 | **ACL (ideiglenes):** a szerver oldali `loadstring` alapból tiltott. A felhasználó a `Default` ACL-ben engedélyezte (`function.loadstring`) és lefuttatta a `reloadacl`-t. Egy teljesen új ACL később, **külön sessionben** készül, és a README-be is bekerül. A szerver oldali import addig is a terv szerint működik; ACL-jog nélkül a `translate(player, key, params)` export a tartalék út. |

Általános alapelvek (a feladat kiírásából):

- Az alapértelmezett nyelv az **angol**. A magyar később jön, előbb az angolnak kell működnie.
- A lokalizáció **nem változtathatja meg indokolatlanul** a játékmenetet, az üzleti logikát és a meglévő UI működést.
- A **fordítási kulcsok stabilak**, a belső azonosítók és technikai értékek **nyelvfüggetlenek** maradnak.
- Csak a **felhasználó által látott** szöveget lokalizáljuk. Nem lokalizáljuk a debug üzeneteket, fájlneveket, eventneveket, adatbázis-azonosítókat és protokollértékeket.
- Nem lokalizáljuk az avi_web dokumentumokat, a ui_browser weboldalait és az egyéb HTML oldalakat.
- A DX-méretezési problémákat (`dxGetTextWidth` stb.) kezelni kell.
- A szövegekben változók is lehetnek, akár a szöveg közepén.
- Exportok kellenek: nyelv beállítása és lekérdezése játékosonként, szöveglekérdezés stb.
- A `dxDrawText` és az exporthívások miatt a játékos nem veszíthet érezhető FPS-t.

---

## 1. Kiinduló állapot (0. fázis felmérése)

| Mérőszám | Érték |
|---|---|
| Resource-ok (tiktok, dgs és old nélkül) | kb. 100 |
| Saját Lua kód (ai_land_traffic / v_radar / claude-mcp generált adatai nélkül) | kb. 130 ezer sor, 665 fájl |
| `dxDrawText` / `dxGetTextWidth` / `dxGetFontHeight` | 98 / 53 / 22 fájlban |
| `exports.ui_core:addNotification` hívás | 45 |
| `setAlert` / `setBanner` / `setInfobox` / `drawSubtitle` / `drawLoadingText` | 23 |
| Szerver→kliens notify események, resource-onként saját `notify()` helperrel | kb. 32 resource |
| `outputChatBox` (a v_chat `showChat(false)` miatt a játékos nem látja) | 56 fájl |
| Szövegjelölt literálok (zajos prototípus-becslés) | kb. 8000, ebből kb. 5700 egyedi |
| Ugyanaz a szöveg több resource-ban | 364 eset (`Cancel`, `Save`, `Loading...`, `Unknown`, `Vehicle`, `XP`, `SUCCESS`/`FAILED` …) |
| med_scenemanager jelenet-JSON-ok | 1936 fájl, 508 egyedi cím, 1907 egyedi leírás, kb. 68 ezer szó (D1 miatt most kimarad) |
| DGS szöveg | v_accounts login/register (`dgsCreateButton`/`CheckBox` feliratok) |
| GUI (`guiCreate*`) | parachute, realdriveby, v_admin report, v_minres (v_modmenu kivétel) |

A legtöbb szöveget tartalmazó resource-ok (prototípus szerint): medsys, med_erm,
v_jobcreator, v_admin, v_jobmanager, v_socialpanel, work_ems, ui_browser (keret),
v_introduce, rw_core, medsys_effects, ui_pause, rw_customtracks, v_customs, ui_inac,
v_radar, ui_phone, med_bag, work_core, rw_timetable, v_weekly.

Meglévő infrastruktúra, amire építünk:

- **ui_core** exportok: `addNotification(title, text, silent)`, `setAlert`, `setBanner`, `setInfobox`, `drawSubtitle`, `drawLoadingText`, `openTextInput`, `showMoney`. A notification a hozzáadáskor egyszer tördel (`wrapText` a `notifications.lua`-ban), ez jó minta.
- **ui_inac** `createTempMenu(config)`: csak adatot kap (label/desc/title/value). A kiválasztott elemet `value` alapján adja vissza, nem label alapján.
- **ui_pause** `SETTINGS_TREE` (`c_pausemenu.lua` kb. 174. sor) `choice` típussal, és a `PAUSE_SETTINGS` / accData mentés (`settings_shared.lua`, `s_settings.lua`).
- **v_mysql** `getAccData`/`setAccData` (accData), **v_accounts** `onPlayerLoaded`.
- **v_main** `<include>` alapú topologikus indítási sorrend: aki `<include resource="v_locals"/>`-t tesz a meta-ba, az a v_locals után indul.
- **med_erm** `client/gfx.lua`: `Gfx.fit` (utf8 ellipsis) és `Gfx.wrap` (utf8 szó- és karaktertörés). Ez a referencia minta.
- **medsys** `client/panel.lua:413`: kisebb fontra vált, ha a felirat nem fér ki.
- **Python + lupa (Lua 5.1)**: szintaxisellenőrzés és stubolt unit tesztek.
- **claude-mcp**: élő restart, debug log, probe.

---

## 2. Azonosított problémák

1. **Vegyes nyelvű forráskód.** Magyar szöveg van a kódban, például:
   - `v_levelsys/server.lua:116-175` („Elérted a … szintet!”, „Ehhez nincs jogod!”, „Használat: /givexp …”),
   - `shader_colors/c_api.lua:139-153`,
   - `rw_core/server/depot.lua:177,181`, `log.lua:388-408`, `role.lua:67,81`,
   - `rw_customtracks` (kb. 26 db), `v_playedtime` („Játékidő”), `v_radar`, `v_arenawar/c_gamemanager.lua:16`, `shader_markers/client.lua:241-244`.

   Az angol alapnyelvhez ezek angol forrásszöveget kapnak. Az eredeti magyar szöveg a `hu` seedbe kerül.
2. **A megjelenített szöveg logikai érték** (D3, a megoldás a 6. fejezetben):
   - `v_jobmanager/core/client/ui.lua:231-234, 320, 360`: `action == "Start Game"` / `"Invite Player"`.
   - `med_erm/shared/config.lua`: `Config.PAY.RATES["task closed"]`, `["shift ended"]` (a kimenetel-kód angol mondat), és `Config.STATUS[*].label`.
   - `v_jobmanager/mode_race/server.lua:96`: a szerver a `"GO"` szöveget küldi a countdown eseményben, a kliens kiírja.
   - `v_joinquit/joinquit.lua:18-19`: MTA quit reason összehasonlítás. Ez protokollérték, maradhat; csak a kimenetét fordítjuk.
3. **A szerver kész szöveget küld** (`rw_core/server/consist.lua:249` „Your train was removed (" .. reason .. ")”, `v_admin/server/core.lua:15-20` alert `root`-nak, `v_weekly/server/panel.lua:75` „Login bonus: …”, stb.). Játékosonkénti nyelvnél ezt játékosonként kell feloldani (D4).
4. **Közös, több néző által látott adatok szövegként tárolva:** med_erm task title (most D1 miatt marad), `Config.STATUS` label, elementData-ban tárolt feliratok. Ezek helyett ID-t tárolunk, és megjelenítéskor oldjuk fel.
5. **Saját wrap/ellipsis szinte minden UI-ban, eltérő minőséggel** (D6):
   - `v_socialpanel/c_ui.lua:263` `ellipsis()`: `#str`/`str:sub` bájtalapú, az ő/ű betűket kettévágja.
   - `v_socialpanel/c_ui.lua:225` `para()`: **minden képkockán** szavanként `dxGetTextWidth`, valamint a 721. sor (chatbuborék).
   - `ui_core/client/notifications.lua` `UI:drawLoading`: képkockánként `dxGetTextWidth`.
   - `ui_inac/client/render.lua:28` `wrapText` és `v_admin/client/panel/core.lua:124` `AP.wrap`: render közben tördelnek.
   - Jó minta: `med_erm/client/gfx.lua` `Gfx.fit`/`Gfx.wrap` (utf8), `v_admin` core.lua:209 (`utf8.sub`), `medsys` panel.lua:413 (font-fallback).
6. **Ugyanaz a literál mérve és rajzolva, két helyen:** `v_introduce/client/rules.lua:129` (`"I have read and accept the rules"`), `v_socialpanel/c_ui.lua:299` (`"SOCIAL PANEL"`). Ha csak az egyik fordul, elcsúszik a méret.
7. **GTA-fontok** (`pricedown`, `bankgothic`, `beckett`) nem tudnak ő/ű-t. A `:upper()` 110 helyen szerepel, és UTF-8 ékezeten nem működik (`v_introduce/client/draw.lua:145` `big:upper()`, `avi_core/client/marker.lua:67` stb.).
8. **Exporthívás a render-ciklusban:** `ui_inac/client/render.lua:2` `ui = function(v) return uicore:ui(v) end`. Ez mutatja, miért nem lehet a fordítás képkockánkénti export.

---

## 3. Hatókör

### 3.1 Lokalizáljuk

- minden DX szöveget (`dxDrawText`, render targetbe rajzolt feliratokat, 3D címkéket, világbeli kijelzőket: állomások, falitáblák),
- a ui_core notification, alert, banner, infobox, subtitle, loading és text input címek/placeholderek szövegét,
- a ui_inac fő- és temp menüit, a ui_interactobject menüit, a ui_pause-t, a ui_phone-t és a ui_download-ot,
- a v_accounts login/register DGS feliratait,
- a szerverről érkező értesítéseket (D4 szerint),
- a kick/ban indokokat és a v_admin panelt,
- az `outputChatBox` szövegeket (D15: csak a szöveget, a működést nem),
- a hosszú szövegfájlokat (`v_introduce/rules.txt` → `locales/en/files/v_introduce/rules.txt`),
- a ui_browser **kereteit** (`core/browser.lua`, cím- és fülsáv) és a `dealership.lua`/`server.lua` notify üzeneteit (ezek nem weboldal-tartalmak),
- az achievement értesítések **keretét** (pl. „Achievement unlocked”), de **nem** az achievement nevét és leírását (D5),
- a jobmanager UI **keretét** (lobby, akciók, eredményképernyő), de **nem** a játékok nevét és leírását (D5).

### 3.2 Nem lokalizáljuk

**Teljes resource kivételek:**
- `[tiktok]/*`, `v_modmenu`, `[devtools]/claude-mcp` (D10),
- `[aviation]/avi_web`, `[web]/web_manager`,
- `[aviation]/avi_controller`: a scope és az ATC login panel is mindig angol (D11),
- `[core]/v_discordmanager` (D9),
- `[medical]/med_scenemanager`: későbbi, saját rendszer (D1).

**Részleges kivételek:**
- `medsys/client/lifepak.lua` (Lifepak 15, D2), és a hozzá tartozó kijelzőtartalom (az `ecg.lua` csak görbét rajzol),
- ui_browser `sites/*`, `.vhtml`, `core/markup.lua` által renderelt oldaltartalom; web_api HTML oldalak (`server/page.lua`); med_erm webes diszpécserkonzol (`server/webapp.lua`, `http.lua`); rw_core webtérkép (sunline-rail.sa),
- achievement nevek és leírások (`v_achievements/config.lua` `ACH.LIST[*].name/desc`), jobmanager játéknevek és leírások (`games/*.json`, community játékok), med_scene szövegek (D5),
- tesztparancsok és kimeneteik: `/medtest` (`medsys/*/test.lua`), `/medfx` (`medsys_effects/*/test.lua`), az mg_* `server.lua` teszt `outputChatBox`-ai, `v_introduce` kamera-debug (`runner.lua:226`), `v_arenawar/shared.lua` debug kiírásai. Ezeket a katalógusban sem tároljuk (D14),
- debug kimenetek: `outputDebugString`, `outputServerLog`, `outputConsole`, `iprint`, `print`, `error`, ui_core `uiLog`,
- technikai értékek: eventnevek, elementData/accData kulcsok, DB-azonosítók, fájlnevek, protokollértékek (MTA quit reason, ICAO kódok, frekvenciák),
- játékosok által írt tartalom: chat, privát üzenet, crew név/tag, v_jobcreator pályák, a telefonon begépelt ERM leírás,
- tulajdonnevek: városok és zónák (`getZoneName`), NPC/telefonos kontaktnevek, kórház-, állomás-, repülőtérnevek, járműmodell-nevek (`veh_manager/models.json`), rádióadók, hívójelek, márkanevek („FreeV”, „FREE V”, „Sunline Rail”).

**Javasolt kivételek, a 2. fázisban megerősítendők** (az avi_controller kivétel logikája alapján):
- `avi_monitors`: az ATC falikijelzők a scope tükrei, ezért javasolt kivétel,
- az `avi_*` resource-ok ATC-szakmai notify-jai (`avi:notify` ATC/NAV/TRAFFIC/WIND),
- az `avi_core` marker prompt (`"Press %s · ATC position"`) viszont nem-ATC játékosnak is látszik, ezért javasolt fordítani.

---

## 4. Architektúra

### 4.1 Fájlstruktúra

```
[core]/v_locals/
  meta.xml                   <include resource="v_mysql"/>; exportok; <file> a katalógusokra
  DESIGN.md                  ez a fájl
  shared/lib.lua             a fogyasztó resource-okba injektált könyvtár forrása
  shared/template.lua        {param} sablon-parser + fordított sablon cache
  shared/formats.lua         nyelvenkénti formázók: money, number, int, decimal, dist, time, plural szabály
  shared/utf8x.lua           UTF-8 upper/lower (később HU kis/nagy tábla), biztonságos sub/len
  server/catalog.lua         JSON betöltés, validálás, fallback lánc
  server/players.lua         játékosnyelv, accData "locale.language", események
  server/exports.lua
  client/catalog.lua         csak az aktív nyelv + en betöltése
  client/state.lua           bejelentkezés előtti nyelv: privát kliens fájl (@settings.xml)
  client/debug.lua           /locdebug: keys | pseudo | overflow
  client/exports.lua
  locales/languages.json     [{code, name, nativeName, fallback, pluralRule, enabled}]
  locales/en/common.json     közös szavak (common.cancel, common.save, common.error …)
  locales/en/<namespace>.json   egy fájl resource-onként (lapos kulcs → szöveg)
  locales/en/files/<resource>/<file>   hosszú szövegek (pl. v_introduce/rules.txt)
  locales/hu.seed/           a forrásban talált magyar szövegek (nincs a meta-ban, csak a későbbi HU kiindulása)
  tools/locales.py           2. fázis eszköz (scan / report / build / lint), nincs a meta-ban
  tools/ignore.json          kézi kivételek
  tests/                     lupa unit tesztek (sablon, plural, utf8, golden)
```

A katalógusok **központilag** a v_locals-ban vannak: a fordító egy helyen dolgozik,
a namespace-ek közötti duplikáció látszik, a magyar hozzáadása csak a v_locals-t érinti.

### 4.2 Kulcsok és stabilitás

- Formátum: `^[a-z0-9_]+(\.[a-z0-9_]+)+$`. Az első szegmens a **namespace**: a resource neve vagy `common`.
  Példák: `ui_pause.settings.display.language.label`, `med_erm.status.enroute`, `common.cancel`.
- A kulcs **szemantikus**, nem az angol szöveg hash-e. A szöveg javítása nem változtatja meg a kulcsot.
- Egy kiadott kulcsot **nem nevezünk át és nem használunk újra más jelentéssel**. Elavult kulcs: `locales/deprecated.json`.
- Adatvezérelt kulcs a meglévő stabil ID-ből jön (pl. státusz-ID, setting-ID). A D5 kivételek nem kapnak kulcsot.
- A kulcs soha nem kerül DB-be vagy elementData-ba megjelenítendő szöveg helyett, ha ugyanez egy technikai ID-vel is megoldható. Az ID-t tároljuk, és megjelenítéskor `namespace.<csoport>.<id>` kulcsra képezzük le.

### 4.3 Katalógus formátum

`locales/<lang>/<namespace>.json`: lapos objektum, kulcs → szöveg.

```json
{
  "ui_pause.tab.settings": "SETTINGS",
  "work_core.paid": "You were paid {amount|money} for {work}.",
  "v_stats.unit.km.one": "{count} km",
  "v_stats.unit.km.other": "{count} km"
}
```

- Többsoros szöveg: `\n`. Színkód: `#RRGGBB`, a szövegben megengedett.
- A katalógus **nem tartalmaz** tesztparancs-szöveget (D14) és kivételes szöveget (3.2).
- A hosszú szöveg külön fájl: `L.file("v_introduce/rules.txt")` az aktív nyelv mappájából olvas, fallbackje az `en`.

### 4.4 Változók, többes szám, formázás

- **Névvel jelölt helyőrző:** `{name}`, akár a szöveg közepén. A szórend nyelvenként eltérhet, ezért nem pozicionális `%s`.
- **Típusos helyőrző:** `{x|money}`, `{x|int}`, `{x|1f}` (tizedesek száma), `{x|pct}`, `{x|dist}`, `{x|time}` (mm:ss / hh:mm:ss), `{x|upper}`.
  - Az angol `money` **pontosan** a mostani kimenetet adja: `€1,234` (ugyanaz, mint a ui_inac `render.lua` `money()` függvénye).
  - Az angol `int`/`time` a meglévő `%02d:%02d` és hasonló formákkal egyezik.
- **Escape:** `{{` és `}}`.
- **Hiányzó paraméter:** a `{name}` látható marad, és kulcsonként egyszer figyelmeztetés kerül a debug logba (`outputDebugString`, csak debug módban).
- **Egymásba ágyazott üzenet:** egy paraméter lehet üzenetobjektum, pl. `{ status = L.msg("med_erm.status.enroute") }`.
- **Többes szám:** a `count` paraméter alapján `.one`/`.other` alkulcs, a nyelv plural szabálya szerint (EN: `n == 1` → one; HU később: mindig `other`, mert számnév után egyes szám áll). Ha nincs alkulcs, a sima kulcsot használja.
- **Színkód-konzisztencia:** a validátor ellenőrzi, hogy minden nyelvben ugyanannyi `#RRGGBB` és ugyanazok a helyőrzők szerepelnek.

### 4.5 Kliensen feloldott kulcsok (üzenetobjektum) – D13

```lua
{ t = "namespace.key", p = { name = "…", status = { t = "med_erm.status.enroute" } } }
```

- A címzett kliens a **saját nyelvén** oldja fel. Ez kell az olyan adathoz, amelyet több néző lát, és később is újrarenderelődik (pl. a később jövő med_scenemanager ERM címek a JSON `locals` bejegyzésből – **most nem készül el**).
- A ui_core megjelenítő exportjai (`addNotification`, `setAlert`, `setBanner`, `setInfobox`, `drawSubtitle`, `drawLoadingText`, `openTextInput` címe/placeholdere) és a ui_inac `createTempMenu` `title/label/desc` mezői **stringet vagy üzenetobjektumot** is elfogadnak. A sima string változatlanul átmegy, így a régi hívók nem törnek el.
- Ugyanígy a resource-ok saját kliens notify-kezelői is elfogadják mindkettőt (`L.resolve(x)`).

### 4.6 Szerver oldali fordítás játékosnak – D4

A fix szöveges szerverértesítéseknél a szerver a **játékost és a szöveg ID-jét** adja
át a fordítónak, és az a játékos beállított nyelvén adja vissza a kész stringet:

```lua
-- export (bármely szerver resource-ból)
local text = exports.v_locals:translate(player, "rw_core.train_removed", { reason = L.msg("rw_core.reason.idle") })
triggerClientEvent(player, "rw:notify", resourceRoot, text, false)   -- a meglévő notify esemény változatlan

-- ugyanez az injektált libbel (export nélkül, lokális katalógusból)
notify(player, L.forPlayer(player, "rw_core.train_removed", { reason = L.msg("rw_core.reason.idle") }))
```

- A meglévő `notify(player, title, text)` helperek **szignatúrája és eseménye nem változik**, csak a hívási helyen a literál helyett `L.forPlayer(player, key, p)` szerepel. A kliens oldali kezelő ugyanazt kapja, mint eddig: kész stringet.
- **Broadcast** (`triggerClientEvent(root, …)`, pl. `v_admin/server/core.lua:20`): játékosonkénti ciklus `L.forPlayer(p, …)`-vel, **vagy** kliensen feloldott üzenetobjektum (4.5). A választás resource-onként a 3. fázisban dől el; az alapértelmezés a játékosonkénti szerveres fordítás.
- `outputChatBox(…, player)`, `kickPlayer` indok, ban üzenet: `L.forPlayer(player, …)` (D15: a hívás maga marad).
- Ha a játékos már látja a szerveren feloldott szöveget és közben nyelvet vált, az a szöveg nem fordul újra. Ez elfogadott, mert rövid életű értesítésekről van szó.

### 4.7 Az injektált könyvtár (lib)

A fogyasztó resource egyszer, betöltéskor hívja meg:

```lua
loadstring(exports.v_locals:import())()   -- létrehozza a resource-lokális `L` táblát
```

**Kliens API:**

| Függvény | Leírás |
|---|---|
| `L(key, params)` | fordított string az aktív nyelven |
| `L.msg(key, params)` | üzenetobjektum (4.5) |
| `L.resolve(msgOrString)` | stringet változatlanul visszaad, üzenetobjektumot felold |
| `L.has(key)`, `L.lang()` | kulcs létezése, aktív nyelv |
| `L.onChange(fn)` | callback nyelvváltáskor (cache-ek, render targetek, nyitott menük újraépítése) |
| `L.bind(tbl)` | `{ field = "key", … }` tábla, amely nyelvváltáskor automatikusan újratöltődik (statikus feliratok) |
| `L.file(path)` | hosszú szövegfájl az aktív nyelven |
| `L.upper(s)`, `L.lower(s)`, `L.len(s)`, `L.sub(s,i,j)` | UTF-8 biztos szövegműveletek (5.6) |
| `L.width(text, scale, font, colorCoded)` | cache-elt szövegszélesség (5.2) |
| `L.fit(text, w, scale, font)` | UTF-8 ellipsis (med_erm `Gfx.fit` alapján) |
| `L.fitScale(text, w, scale, font, minScale)` | zsugorítás, utána ellipsis (medsys panel.lua:413 minta) |
| `L.wrap(text, w, scale, font)` | cache-elt UTF-8 tördelés (med_erm `Gfx.wrap` alapján) |
| `L.money(n)`, `L.num(n)`, `L.time(s)` | formázók az aktív nyelven |

**Szerver API:** `L.forPlayer(player, key, params)`, `L.msg`, `L.lang(player)`, `L.money(n, player)` stb.

**Működés:**
- A lib egy namespace első használatakor **egyszer** kéri le a katalógusát (`exports.v_locals:getCatalog(lang, ns)`), és a saját resource-ában tárolja. Utána egy fordítás lokális táblaindexelés, **export nélkül**.
- Nyelvváltáskor (`v_locals:onClientLanguageChange`) újratölti az érintett namespace-eket, frissíti a `bind` táblákat, üríti a cache-eket, majd meghívja az `onChange` callbackeket.
- Ha a v_locals újraindul, a már lemásolt katalógusok megmaradnak a fogyasztóban. A v_locals `onClientResourceStart`-jára a lib újra szinkronizál.
- **Fallback lánc:** aktív nyelv → `en` → a kulcs maga (debug módban `[missing:key]`). Hiányzó kulcsnál kulcsonként egyszer figyelmeztetés.

### 4.8 Nyelv tárolása, választása, váltása

- **Szerver:** accData `"locale.language"` a v_mysql-en keresztül. **Nem elementData**, mert más klienseknek nincs rá szükségük, és fölösleges broadcastot okozna. A szerver memóriában `player → lang` cache-t tart.
- **Bejelentkezés előtt** (v_accounts login/register, ui_download): a kliens a privát `@settings.xml` fájlból olvassa a legutóbbi nyelvet, alapértéke `en`. Az `onPlayerLoaded` után a fiókban tárolt érték győz, és a kliens fájl frissül.
- **Vendég** (nincs belépve): a választás csak a munkamenetre és a kliens fájlba szól.
- **Választó (D12):** `ui_pause/c_pausemenu.lua` `SETTINGS_TREE` → `display` kategória → új elem:
  ```lua
  { id = "language", label = <L key>, type = "choice",
    options = function() return exports.v_locals:getLanguages() end,   -- {value, label}
    get = function() return exports.v_locals:getLanguage() end,
    set = function(v) exports.v_locals:setLanguage(v) end }
  ```
  - A mentést a **v_locals végzi**. Az `id` **nem** kerül a `PAUSE_SETTINGS`-be, így nincs kettős tárolás.
  - A choice opciók a nyelvek saját nevükön jelennek meg (`nativeName`, pl. „English”, „Magyar”).
  - Az `options` export csak a menü megnyitásakor és lapozáskor hívódik, nem minden képkockán. Szükség esetén a ui_pause cache-eli.
- **Események:**
  - kliens: `v_locals:onClientLanguageChange(newLang, oldLang)` (root),
  - szerver: `onPlayerLanguageChange(newLang, oldLang)` (source = player).

### 4.9 Exportok

**Kliens:**

| Export | Leírás |
|---|---|
| `import()` | a lib forrása |
| `getLanguage()` / `setLanguage(lang)` | aktív nyelv; a beállítás a szerverre is felmegy (ha be van lépve) |
| `getLanguages()` | `{ {value, label}, … }` az engedélyezett nyelvekről |
| `translate(key, params)` | alkalmi, lassú út (nem render-ciklusba) |
| `resolve(msgOrString)` | üzenetobjektum feloldása |
| `getCatalog(lang, ns)` | a lib használja |
| `hasKey(key)` | kulcs létezése |
| `utf8Upper(s)` / `utf8Lower(s)` | D7 (render-ciklusban a lib lokális `L.upper`-ét kell használni) |

**Szerver:**

| Export | Leírás |
|---|---|
| `import()` | a lib forrása |
| `getPlayerLanguage(player)` / `setPlayerLanguage(player, lang)` | játékosonkénti nyelv |
| `getLanguages()` | engedélyezett nyelvek |
| `translate(playerOrLang, key, params)` | D4: a játékos nyelvén visszaadott string |
| `resolve(player, msg)` | üzenetobjektum feloldása egy játékosnak |
| `utf8Upper(s)` / `utf8Lower(s)` | D7 |
| `getMissingKeys()` | debug: futás közben hiányzónak talált kulcsok |
| `reloadCatalogs()` | admin: katalógusok újratöltése |

**Parancsok:**
- `/language <code>` (később, ha több nyelv van),
- admin (`admin_level` küszöbbel): `/locdebug off|keys|pseudo|overflow`, `/locreload`, `/locbench`.

Ezek fejlesztői parancsok, a kimenetük **nem** kerül a katalógusba (D14).

---

## 5. DX-méretezés és UTF-8 (D6, D7, D8)

### 5.1 Egységes szabály

Minden megjelenítés UTF-8 biztos. Megjelenített szövegen tilos a `#str`, a `string.len`,
a `str:sub` és a `string.upper/lower`. Helyettük: `L.len`, `L.sub`, `L.upper`, `L.lower`
(vagy az MTA `utf8.*`). A 2. fázis riportja ezeket a helyeket külön listázza.

### 5.2 Cache-elt mérés

- `L.width(text, scale, font, colorCoded)`: memoizált, kulcsa `tostring(font)|scale|cc|text`, legfeljebb kb. 2000 bejegyzés (megteléskor ürül).
- Nyelvváltáskor és felbontásváltáskor (`onClientScreenSizeChange`/újraindítás) ürül.

### 5.3 Elrendezési szabályok (a med_erm jó mintái továbbvive)

| Szabály | Mikor | Megvalósítás |
|---|---|---|
| `auto` | a doboz a szöveghez nőhet (notification magasság, tab, badge, gomb) | `L.width` + padding (ez a meglévő jó minta) |
| `fitScale` | fix doboz, rövid felirat | `L.fitScale(text, w, scale, font, 0.8)`, alatta ellipsis |
| `fit` | fix doboz, listaelem/név | `L.fit` (utf8 ellipsis, a `Gfx.fit` alapján) |
| `wrap` | bekezdés, leírás | `L.wrap` (cache-elt; csak szöveg/szélesség/nyelv változáskor számol) |
| `clip` | végső eset | `dxDrawText(... clip=true)` |

### 5.4 Javítandó resource-ok (D6)

A 2. fázis teljes listát ad. A már ismert helyek:

- `v_socialpanel/c_ui.lua:225` `para()` képkockánkénti tördelés → `L.wrap` cache.
- `v_socialpanel/c_ui.lua:263` bájtalapú `ellipsis()` → `L.fit`.
- `v_socialpanel/c_ui.lua:721` chatbuborék tördelés → `L.wrap`, üzenetenként egyszer.
- `ui_core/client/notifications.lua` `UI:drawLoading` → a szélességet csak szövegváltozáskor számolja.
- `ui_inac/client/render.lua:28` `wrapText` (desc) → `L.wrap`.
- `v_admin/client/panel/core.lua:124` `AP.wrap` → `L.wrap`.
- `v_introduce/client/draw.lua:54` → `L.wrap`.
- `v_introduce/client/rules.lua:129` és `v_socialpanel/c_ui.lua:299`: a mért és a rajzolt szöveg ugyanabból a feloldott változóból jöjjön.
- Minden `onClientRender`-en belüli `dxGetTextWidth`, amelynek bemenete nem változik képkockánként: a 2. fázis `render_measure.md` riportja listázza.

### 5.5 Ellenőrző eszközök

- **`/locdebug pseudo`:** minden szöveget kb. 35%-kal megnyújt és ékezetekkel tölt fel (`[Šéttîñĝš ~~~]`). Megmutatja a túllógást, a nem lokalizált szöveget (az nem kerül zárójelbe) és a glifhiányt.
- **`/locdebug keys`:** a kulcsokat jeleníti meg.
- **`/locdebug overflow`:** csak debug módban a lib a fogyasztó resource **saját környezetében** becsomagolja a `dxDrawText`-et. Ha clip/wordBreak nélkül a mért szélesség nagyobb, mint `right-left`, egyszer naplózza a resource-ot, a szöveget/kulcsot és a túllógást. Kikapcsolva nulla a költsége, mert az eredeti függvény marad.

### 5.6 UTF-8 upper/lower (D7)

- `shared/utf8x.lua`: ASCII + Latin-1/Latin Extended-A leképezés (benne `á é í ó ö ő ú ü ű` ↔ `Á É Í Ó Ö Ő Ú Ü Ű`), cache-elve.
- Export: `utf8Upper(s)`/`utf8Lower(s)` (kliens + szerver). A lib ugyanezt a kódot lokálisan tartalmazza (`L.upper`), hogy render-ciklusban ne legyen exporthívás.
- A 3. fázisban a **megjelenített** szövegeken lévő `:upper()` hívásokat cseréljük. A technikai `:upper()` (ICAO kód, jogosultságnév, parancsargumentum) **marad**.

### 5.7 GTA-fontok (D8) – előzetes lista

Jellemzően kivételek vagy számok. A 2. fázis véglegesíti a listát.

| Hely | Font | Tartalom | Fordítandó? |
|---|---|---|---|
| `v_spawnmanager/client.lua:62` | pricedown | `"WASTED"` | **igen, jelölt** (GTA-ikon; a döntés a 2. fázisban; ha fordul, Roboto fallback kell ékezethez) |
| `v_jobmanager/core/client/ui.lua:284` | pricedown | countdown: `3, 2, 1` számok és a szervertől jövő `"GO"` | számok nem; **`"GO"` igen, jelölt** (a szerver kódot küld, a kliens kulcsra képez, lásd 6.3) |
| `ui_inac/client/render.lua:85` | pricedown | `"FREE V"` fejléc | nem (márka) |
| `ui_pause/c_pausemenu.lua:1047` | pricedown (`FONT.logo`) | `"FreeV"` | nem (márka) |
| `v_socialpanel/c_ui.lua:294` | pricedown | `"FreeV"` | nem (márka) |
| `ui_core/client/yoverlay.lua:92-93, 132-137` | pricedown | szintszám, pénzösszeg | nem (szám) |
| `ui_core/client/yoverlay.lua:94` | arial | `xp/next_xp` | nem (szám) |
| `v_introduce/client/draw.lua:40` | bankgothic **csak fallback** (elsődleges RobotoB) | címek | igen, de RobotoB-vel; a fallback glifhiánya csak hibás fontbetöltésnél jön elő |
| `v_radar/radar/sourceC.lua:494` | „pricedown” néven Roboto.ttf | radar feliratok | a font valójában Roboto, ékezetképes |
| `ui_download/client.lua:65` | pricedown | kikommentezett `"Free V"` | nem (nem fut) |
| `realdriveby/utils/textlib.lua` | általános lib | a hívó dönti el | a 2. fázis ellenőrzi |

### 5.8 Egyéb fontok

- A Roboto/RobotoB (sok példányban), illetve a `default`/`default-bold` (Tahoma) ékezetképes.
- Az `EuroScope.ttf` csak az avi_controllerben van, ami kivétel.
- `gtaFont.ttf`, `hand.ttf` (v_radar): a 2. fázisban ellenőrizzük, mire használja a resource.

---

## 6. Ahol a megjelenített szöveg kulcs vagy logika (D3) – a működés átírása

Cél: a logika **csak nyelvfüggetlen ID-ken** dolgozik. A felirat megjelenítéskor jön kulcsból.

### 6.1 Minták

1. **Akciólista felirat alapú azonosítással.** A `{ "Start Game", "Invite Player" }` helyett:
   ```lua
   { { id = "start",  label = "v_jobmanager.lobby.start" },
     { id = "invite", label = "v_jobmanager.lobby.invite" } }
   if action.id == "start" then …
   ```
   Helyek: `v_jobmanager/core/client/ui.lua:231-234, 320, 360`. A gomb kiemelése (`bg = …`) és a help szöveg is `id` alapján dől el.
2. **Kimenetel- és státuszkódok.** Ha a kód tárolt vagy perzisztált (DB, closedTasks, history), **az értéke nem változik**, mert ID-ként befagyasztjuk. Csak egy leképező tábla kerül mellé:
   ```lua
   Config.OUTCOME_LABEL = { handover = "med_erm.outcome.handover", ["task closed"] = "med_erm.outcome.task_closed", … }
   Config.STATUS.enroute = { label = "med_erm.status.enroute", color = … }   -- a label kulcs, megjelenítéskor L()
   ```
   A belső kódok átnevezése (pl. `"task closed"` → `task_closed`) **csak** migrációval és külön döntéssel történhet.
3. **A szerver megjelenítendő technikai értéket küld** (pl. `"GO"`, `reason` stringek). A kliens kód→kulcs leképezést kap (`COUNTDOWN = { GO = "v_jobmanager.countdown.go" }`). Ismeretlen kódnál a nyers érték jelenik meg, így a viselkedés nem romlik.
4. **elementData megjelenítendő szöveggel.** Szöveg helyett ID-t tárolunk, a néző oldja fel. Ha egy elementData értéket más resource vagy a DB is olvas, a 2. fázis riportja jelzi, és a döntés ID-migrációval együtt születik.
5. **Choice/option listák:** `{ value = <id>, label = <kulcs vagy kész string> }`. A mentés és az összehasonlítás csak `value` alapján történik (a ui_pause choice már így működik; a `shader_colors:getColorPresets()` felirat-visszaadását ellenőrizni kell).
6. **Protokollérték-összehasonlítás** (pl. `v_joinquit/joinquit.lua:18-19` MTA quit reason): **marad**, csak a kiírt szöveg fordul.
7. **ui_inac temp menük:** már `value` alapján adják vissza a kiválasztást. Ott csak a label/desc/title fordul, a logikához nem kell nyúlni.

### 6.2 Felderítés (2. fázis, `logic_strings.md`)

- `==`/`~=` összehasonlítás nagybetűs, szóközt tartalmazó literállal,
- táblakulcs szóközzel (`["task closed"]`),
- elementData/accData írása szóközt tartalmazó, nagybetűs értékkel,
- `triggerClientEvent` paraméterként küldött literál, amelyet a kliens `dxDrawText`-tel kiír.

### 6.3 Biztosíték

Minden átírt helyhez lupa unit teszt vagy élő ellenőrzés tartozik: ugyanaz a bemenet ugyanazt az akciót váltja ki, mint az átírás előtt.

---

## 7. Teljesítmény

| Út | Költség |
|---|---|
| Statikus felirat (`L.bind`, előre feloldva) | 0 képkockánként; nyelvváltáskor egyszer |
| `L(key)` paraméter nélkül | 1–2 lokális táblaindexelés |
| `L(key, params)` | előre fordított sablon (a parse csak egyszer fut); a költség a mostani `..`/`string.format`-hoz hasonló |
| `L.width` / `L.wrap` / `L.fit` | cache találatnál egy táblaindexelés |
| Export | csak betöltéskor (namespace-enként egyszer), nyelvváltáskor és alkalmi szerverhívásnál |

- **Szabály:** paraméteres szöveget akkor formázunk, amikor az állapot változik, nem minden képkockán. A minden képkockán változó számlálóknál a sablon cache elég.
- **Tilos:** exporthívás az `onClientRender`-ben fordítás vagy upper céljából.
- **Mérés (1. fázis):** `/locbench`: 10 ezer lookup, formázás, mérés és upper; ms/képkocka a debug logba (claude-mcp `get_debug_log`). Cél: tipikus UI képkockán **< 0,1 ms** többletköltség.
- **Mérés (3. fázis):** előtte/utána FPS-összevetés a legnehezebb UI-okon (ui_pause, medsys panel, v_socialpanel, v_admin panel). A képkockánkénti mérések megszüntetésével néhány UI-nál nyereség várható.
- **Memória:** resource-onként csak a használt namespace-ek másolata él. Egy ötezer szöveges nyelv kb. 0,3–0,5 MB; a kliens csak az aktív nyelvet és az `en`-t tölti be.
- **Letöltés:** a katalógusok `<file>`-ként kerülnek a kliensre; az MTA cache-eli őket, változás nélkül nem töltődnek le újra.

---

## 8. Fázisok

### 1. fázis – a v_locals felépítése (még szövegimport nélkül) – KÉSZ, lásd 10. fejezet

1. A 4.1 szerinti struktúra, `meta.xml` (author `DrAndrew112`), `<include resource="v_mysql"/>`.
2. Katalógusbetöltő, validátor, fallback lánc, `languages.json` (csak `en` engedélyezve).
3. Sablonmotor (névvel jelölt és típusos helyőrzők, escape, nested, plural), EN formázók, a `€1,234` pontosan.
4. utf8x (upper/lower/len/sub) és az exportok.
5. Injektált lib (kliens + szerver), `bind`, `onChange`, mérés/fit/fitScale/wrap cache.
6. Nyelvtárolás (accData, privát kliens fájl), események, exportok, admin parancsok.
7. Debug mód: keys / pseudo / overflow, `/locbench`.
8. Lupa unit tesztek (sablon, plural, utf8, fallback), élő teszt a claude-mcp-n egy minta `common` katalógussal.
9. A ui_pause „Language” choice csak a 3. fázisban kerül be (ui_pause módosítás).

### 2. fázis – szövegek gyűjtése, rendezése, duplikációk

Eszköz: `tools/locales.py` (Python; a lupa szintaxisellenőrzést is ad).

1. **`scan`**
   - Valódi Lua tokenizáló (kommentek, long stringek), ezen kívül `.txt` fájlok, és a nem kivételes JSON/XML adatok.
   - Minden literálhoz a **nyelő** kontextusa: `dxDrawText` 1. argumentum, ui_core exportok, `createTempMenu`/`registerMenu` mezők (`label`/`desc`/`title`), `text=`/`hint=`/`placeholder=`, resource-onkénti `notify()` helperek, `triggerClientEvent(... notify/alert/toast ...)`, `outputChatBox`, `dgsCreate*`, `guiCreate*`, `kickPlayer`/ban indok.
   - Kimenet: `inventory.json`/`.csv` ezekkel a mezőkkel: resource, fájl, sor, nyelő, eredeti szöveg, dinamikus-e, javasolt sablon, nyelvtipp (HU/EN), javasolt kulcs, oldal (kliens/szerver), állapot (`translate` / `ignore` / `review`).
2. **Szűrés**
   - Technikai regexek (eventnév `ns:event`, fájlút, Lua minta, hex szín, igazítás/font név, snake_case ID),
   - debug-nyelők,
   - a 3.2 kivételek (teljes resource, fájl, mező: pl. `ACH.LIST[*].name/desc`, `lifepak.lua`, `test.lua`),
   - `tools/ignore.json` (fájl:sor, minta, resource).
   - A tesztparancsok szövegei **még az inventoryba sem** kerülnek be szövegként, csak darabszámként a riportba (D14).
3. **Dinamikus szövegek**
   - `"a " .. x .. " b"` → `"a {x} b"`, a paraméter neve a változónévből jön.
   - `("%d/%d"):format(a, b)` → `"{a}/{b}"`, a formátum típusos helyőrzőként (`{a|int}`).
   - Mindkettő `review` állapotot kap.
4. **Duplikációk**
   - pontos egyezés (normalizált whitespace),
   - kis-/nagybetű variáns (`Cancel`/`CANCEL`): egy kulcs + `L.upper` megjelenítéskor,
   - közel-duplikátum (hasonlósági arány > 0.9, vagy csak írásjelben tér el),
   - `common.*` javaslat: legalább 3 resource és azonos nyelőtípus kell. **Nincs automatikus összevonás**: az azonos szövegnek lehet más a jelentése („Open” mint ige vagy mint állapot), ezért a riport alapján kézzel döntünk.
5. **Riportok** (`tools/out/`):
   - `duplicates.md`,
   - `hungarian_in_source.md` (ezek angol szöveget kapnak, a magyar a `hu.seed`-be megy),
   - `dynamic.md`,
   - `logic_strings.md` (6.2),
   - `utf8_unsafe.md` (5.1),
   - `render_measure.md` (5.4),
   - `gta_fonts.md` (5.7 véglegesítése),
   - `exceptions.md` (mi maradt ki és miért),
   - resource-onkénti lefedettség.
6. **`build`:** a jóváhagyott tételekből `locales/en/<ns>.json` és `locales/hu.seed/<ns>.json`.
7. **`lint`** (a 3. fázistól folyamatosan):
   - új beégetett literál egy nyelőben,
   - hiányzó vagy nem használt kulcs,
   - helyőrző- vagy színkód-eltérés a nyelvek között,
   - érvénytelen kulcsformátum,
   - ugyanaz a szöveg két kulcson,
   - kivételes resource-ban használt `L(`.

### 3. fázis – implementáció minden szöveget megjelenítő resource-ban (a kivételek nélkül)

**Sorrend:**
1. **Keretrendszerek:** ui_core (msg-elfogadás, `drawLoading` fix), ui_inac, ui_interactobject, ui_pause (+ Display → Language choice), ui_phone, ui_download.
2. **Első kontaktus:** v_accounts (DGS feliratok, bejelentkezés előtti nyelv), v_introduce (`rules.txt` → `locales/en/files`).
3. **HUD és social:** v_radar, v_nametags, v_chat (csak a keret), v_socialpanel (+ UTF-8/wrap javítás), v_levelsys, v_bank, v_stats, v_achievements (csak keret, D5), v_weekly, v_admin, v_joinquit, v_spawnmanager, v_playedtime.
4. **Work:** work_core, work_ems (+ tutorial), work_traindriver, work_atc.
5. **Medical:** medsys (a Lifepak nélkül, D2), med_bag, med_erm (DX tablet + unit label; webkonzol nélkül), med_hospitals, med_stretcher, medsys_effects, medsys_events, mg_airway, mg_arrows, mg_cpr, mg_intravenous, mg_splinting (a tesztkimenetek nélkül).
6. **Railways:** rw_core, rw_signals, rw_timetable, rw_loco, rw_passengers, rw_customtracks, rw_auto, rw_crossings, rw_trainhorn.
7. **Minigames:** v_jobmanager (először a 6.1 akció-ID refaktor; a játéknevek nem fordulnak), v_jobcreator (a felhasználói tartalom nem fordul), v_timetrial, v_arenawar.
8. **Vehicles:** v_customs, v_ownveh, v_els, v_radio, v_headlights.
9. **World, grafika és egyebek:** world_* (interiors, clothes-shop, elevators, ferriswheel, cablecars), v_shop_robbery, shader_colors / shader_markers / shader_detail / shader_dynamic_sky / dynamic_lighting üzenetek, map_int_sacontrol falitáblák (render target újraépítés `onChange`-re), ai_land_traffic notify, parachute, realdriveby, v_minres, ui_browser kerete és notify-jai.
10. **Aviation:** csak a 3.2-ben javasolt, nem kivételes részek, a 2. fázis megerősítése után (az avi_controller sosem).

**Resource-onkénti lépések:**
1. `<include resource="v_locals"/>` a meta-ba, a lib importja (kliens és/vagy szerver).
2. Literál → kulcs csere az inventory alapján; a statikus feliratok `L.bind`-ba.
3. A szerver notify-k hívási helyén `L.forPlayer(player, key, p)` (D4); a helper és az esemény változatlan.
4. Logikai szövegek ID-re cserélése (6. fejezet).
5. Az egyedi wrap/fit/ellipsis helyett `L.*`; a megjelenített `:upper()` helyett `L.upper`; a bájtalapú string-műveletek helyett utf8.
6. Render targetek és cache-ek újraépítése `L.onChange`-re.
7. Ellenőrzés:
   - lupa szintaxisellenőrzés,
   - **golden teszt**: minden kulcs a mintaparaméterekkel **bájtra pontosan** az eredeti angol szöveget adja; kivétel a tudatosan angolra fordított magyar szöveg,
   - `lint` = 0 hiba,
   - élő ellenőrzés a claude-mcp-n: restart, debug log, 0 hiányzó kulcs, overflow-riport pseudo módban,
   - képernyőkép csak ott, ahol elkerülhetetlen.
8. **Commit resource-onként**, így egyenként visszaállítható.

### Későbbi fázisok (most nem)

- **Magyar nyelv:** `locales/hu/` a `hu.seed`-ből indulva, a HU plural szabály, a HU formázók (pénz, szám), a választóban a „Magyar”, a pseudo módban talált túllógások javítása.
- **med_scenemanager saját rendszer (D1, D13):** a jelenet-JSON-ban `locals` bejegyzés; a task a jelenet azonosítóját és a kulcsot hordozza; a feloldás csak kliens oldalon, üzenetobjektummal (4.5) történik.

---

## 9. Kockázatok és ellenintézkedések

| Kockázat | Ellenintézkedés |
|---|---|
| Egy fordítás logikát tör | 6. fejezet: ID-alapú logika, `logic_strings.md`, tesztek |
| Az angol szöveg észrevétlenül megváltozik | golden teszt bájtpontos összevetéssel |
| FPS-csökkenés | lokális lib, cache, render közben nincs export, `/locbench`, FPS-összevetés |
| Túllógás vagy glifhiány (később HU) | pseudo mód, overflow-detektor, `fitScale`/`fit`/`wrap`, GTA-font lista |
| Kulcsok elcsúszása vagy átnevezése | szemantikus, befagyasztott kulcsok, `deprecated.json`, `lint` |
| A v_locals nem fut | `<include>` sorrend; a lib a már lemásolt katalógussal tovább működik |
| Perzisztált kód átnevezése adatvesztéssel | a perzisztált kód befagyasztva, csak leképező tábla; átnevezés csak migrációval |
| A szerver ACL újra tiltja a `loadstring`-et (új ACL, D17) | a szerver oldali import ilyenkor nem töltődik be; tartalék: `exports.v_locals:translate(player, key, params)`; az új ACL-ben a fogyasztó resource-oknak meg kell kapniuk a `function.loadstring` jogot |

---

## 10. Az 1. fázis megvalósítása (2026-10-12)

### 10.1 Fájlok

| Fájl | Szerep |
|---|---|
| `meta.xml` | include: v_mysql; a lib fájlok kliensen `<file>` (az importhoz), szerveren `<script>` (a saját példányhoz); a katalógusok `<file>`-ként |
| `config.lua` | `LOC`: alapnyelv, accData kulcs, privát kliens fájl, admin szint (3), cache-limit, debug módok, `/locbench` szintetikus szövegei (nem katalógus) |
| `shared/catalog.lua` | `languages.json` + lusta namespace-betöltés, kulcs/érték szűrés, `getFile` fallback lánccal |
| `shared/loader.lua` | `import(name)`: a lib forrásának összefűzése; `LOCALS_INTERNAL` backend; a kliens saját példánya `loadstring`-gel |
| `lib/utf8x.lua` | `len`/`sub` (MTA `utf8.*`, ha van), `upper`/`lower` saját táblával: Latin-1, Latin Extended-A (ő/ű), görög, cirill; cache |
| `lib/template.lua` | `{name}`, `{name\|fmt}`, `{{ }}`, egyszer fordított sablonok cache-ben, `placeholders()` a validátornak |
| `lib/formats.lua` | `money` (bájtra azonos a ui_inac `money()`-jével, 2000 véletlen értéken tesztelve), `num`, `int` (= `%d`), `Nf`, `pct`, `time`, `dist`, `upper`/`lower`; plural szabályok: `one_other`, `other` |
| `lib/core.lua` | motor: store / negatív cache / fallback lánc / plural (a nyelven belül előbb a saját alapkulcs, csak utána a következő nyelv) / pseudo / hiányzó kulcs egyszeri jelentése |
| `lib/client.lua` | kliens `L` API, DX segédek, `bind`, `onChange`, debug módok, nyelvváltás- és újraindulás-események |
| `lib/server.lua` | szerver `L` API (`L.forPlayer` …); fogyasztóban export backend + játékosnyelv-cache az `onPlayerLanguageChange` eseménnyel |
| `server/players.lua` | nyelv játékosonként, `clientHello` / `requestLanguage` / `onPlayerLoaded`, accData mentés |
| `server/validate.lua` | indításkori és `/locreload`-kori validáció a szervernaplóba |
| `server/commands.lua` | `/locdebug`, `/locreload`, `/locbench`, `/locmissing` (admin_level ≥ 3, kimenet: F8 konzol + szervernapló) |
| `server/exports.lua`, `client/exports.lua` | exportok (4.9) |
| `server/ready.lua` | a szerver saját példányának publikálása (`L`) + validáció; az utolsó szerver script |
| `client/state.lua` | aktív nyelv, `@language.txt`, `applyLanguage` |
| `client/debug.lua` | debug mód, hiányzó kulcsok listája, kliens benchmark |
| `locales/languages.json` | `en` (bekapcsolva), `hu` (kikapcsolva, plural `other`, fallback `en`) |
| `locales/en/common.json` | üres; a szövegek a 2. fázisban kerülnek be |
| `tests/run.py`, `tests/test_lib.lua` | lupa (Lua 5.1): az összes fájl szintaxisa + 101 unit teszt |

### 10.2 Használat a fogyasztó resource-okban

```lua
-- kliens ÉS szerver, egyszer, betöltéskor (a meta-ban: <include resource="v_locals"/>)
loadstring(exports.v_locals:import())()

-- kliens
local TXT = L.bind{ title = "ui_pause.title", hint = { "ui_pause.hint", { key = "ESC" } } }
dxDrawText(L.fit(TXT.title, w, 1, font), ...)
L.onChange(function() rebuildRenderTarget() end)

-- szerver (D4)
notify(player, L.forPlayer(player, "rw_core.train_removed", { reason = L.msg("rw_core.reason.idle") }))
-- ACL-jog nélkül ugyanez: exports.v_locals:translate(player, key, params)
```

- Az `import(name)` más globális nevet is adhat, ha a resource-ban az `L` foglalt.
- A 3. fázisban átnevezendő helyi `local L` változók, mert elfednék a globális `L`-t: `med_erm/client/admin/panel.lua`, `v_jobcreator/client/menus.lua`, `client/tools.lua`, `server/sanitize.lua`, `rw_core/client/trainlabel.lua`, `rw_core/server/log.lua`, `ai_land_traffic/server/sim.lua` (ez utóbbi függvényen belüli lokális, nem zavar).

### 10.3 Élő eredmények

- A szerver tisztán indul: `catalogs: 2 languages (en,hu), 1 namespace files, 0 text files, 0 keys, 0 warnings`.
- A kliens és a szerver oldali import is működik (a claude-mcp környezetéből kipróbálva): paraméterek, plural, nested, UTF-8 `upper`/`fit`/`fitScale`/`wrap` valódi fontokkal, pseudo mód, a kikapcsolt `hu` visszautasítása, accData mentés (`locale.language = en`).
- `/locbench`:

  | Mérés | Kliens | Szerver |
  |---|---|---|
  | statikus `L()` / `L.forPlayer` | 0,50 µs | 1,02 µs |
  | 2 paraméter (benne `money`) | 5,10 µs | 6,55 µs |
  | plural | 2,14 µs | 3,18 µs |
  | `L.upper` UTF-8 (cache) | 0,25 µs | 0,30 µs |
  | export `translate` | 7,2 µs | 13,8 µs |
  | nyers `dxGetTextWidth` | 11 µs | – |
  | `L.width` (cache) | 0,20 µs | – |
  | szavanként mérő régi wrap (1 bekezdés) | 457 µs | – |
  | `L.wrap` / `L.fit` (cache) | 0,25 / 0,20 µs | – |

  Következtetés: a statikus szöveg és a cache-elt mérés elhanyagolható. A paraméteres szövegeket állapotváltozáskor kell formázni, nem minden képkockán (7. fejezet). A régi wrapek lecserélése a 3. fázisban önmagában FPS-nyereség.

### 10.4 Eltérések a 4. fejezettől

- A szerveren a v_locals saját példánya `<script>`-ként fut (nem `loadstring`), így a v_locals független az ACL-től. A fogyasztók szerver oldali importja az ACL `function.loadstring` jogától függ (D17).
- A `/locdebug` mód kliensenként él, nem mentődik.
- A `getLanguages()` `{ value, label }` listát ad, közvetlenül a ui_pause `choice` típusához.

---

## 11. A 2. fázis eredménye (2026-10-12)

### 11.1 Eszköz: `tools/locales.py`

| Parancs | Mit csinál |
|---|---|
| `python tools/locales.py scan` | Lua lexer + kontextuselemzés minden resource-ra, kimenet: `tools/out/inventory.json/.csv` + riportok |
| `python tools/locales.py build` | katalógusok az inventoryból: `locales/en/<ns>.json`, `locales/hu.seed/<ns>.json`, `locales/en/files/…`, a `meta.xml` `<file>` listája, `tools/keys.lock.json` |
| `python tools/locales.py all` | scan + build |
| `python tools/locales.py lint` | katalógusellenőrzés + a kódban használt kulcsok + (3. fázistól) a migrált resource-okban maradt beégetett szövegek |

**Kézzel szerkesztett bemenetek (`tools/`):**
- `config.json`: kizárások, UI-nyelők, mezőnevek, technikai minták.
- `decisions.json`: tételenkénti, szövegenkénti és szabályalapú döntések, valamint a `common.*` összevonások.
- `hu_to_en.json`: a forrásban talált magyar szövegek angol forrásszövege.

A `tools/out/` generált, ezért gitignore-os.

**Felismerés:**
- **Nyelők:**
  - DX/DGS/GUI hívások, ui_core exportok, `outputChatBox`, `kickPlayer`/`banPlayer`,
  - notify-eseményekkel küldött argumentumok,
  - UI-nevű helperek (camelCase szavakból: `adminAlert`, `commandFeedback`, `drawSection` …),
  - UI-mezők (`label`, `title`, `desc`, `text`, `hint` …), UI-listák, UI-változók, `return` üzenetek.
- **Dinamikus szövegek:** `a .. b .. c` összefűzés, `("…"):format()`, `string.format()`, valamint `cond and "A" or "B"` és zárójeles csoportok.
- **Sablonná alakítás:** `{param}` és `{param|int}`, `{param|Nf}` formában.
- **Kiszűrve:**
  - debug-nyelők, tesztparancsok (`addCommandHandler("…test…")` hatóköre, D14),
  - technikai minták (eventnevek, utak, Lua minták, SQL, fontnevek, színkódok, azonosítók),
  - **titokszerű tokenek** és vezérlőkarakteres bináris adat.

### 11.2 Számok

| | |
|---|---|
| Talált tétel | 4004 |
| Fordítandó | 3471 tétel → **3053 egyedi kulcs, 69 namespace** (a namespace-en belüli ismétlések egy kulcsot kapnak; 67 tétel a 16 `common.*` kulcsot használja, D18) |
| Kihagyott (döntés alapján) | 533 |
| Átnézendő | 0 |
| Dinamikus (sablonos) | 606 |
| A szövegben `%s`/`%d` (később `:format`) | 20 |
| Renderből elért fordítandó szöveg | 493 |
| Magyar a forrásban | 81 tétel / 61 egyedi szöveg → `hu_to_en.json` (angol forrás), az eredeti a `locales/hu.seed/` alá (9 namespace) |
| Hosszú szövegfájl | `v_introduce/rules.txt` → `locales/en/files/v_introduce/rules.txt` |

A legnagyobb katalógusok: medsys 319, v_jobcreator 317, v_admin 257, med_erm 228, v_socialpanel 183, work_ems 147, v_introduce 137, rw_core 95.

**Ellenőrzések:**
- `lint`: 0 hiba, 0 figyelmeztetés.
- Mind a 3092 érték átment a Lua sablonmotoron; a sima szövegek bájtra azonosak.
- Élőben: a v_locals indításkor 69 namespace-t, 3053 kulcsot validált, 0 figyelmeztetéssel (a D18–D21 utáni újraépítés). Kliens és szerver oldali lookup egyaránt működik (pl. `v_levelsys.server.you_reached_level` → „You reached level 12!”).

### 11.3 Kulcsok

- **Formátum:** `<namespace>.<terület>.<slug>`.
  - A namespace a resource neve (`-` → `_`, kisbetűs).
  - A terület a fájlnév (a `c_`/`s_` előtag és a semmitmondó `client`/`server`/`main` nevek nélkül).
  - A slug az angol szöveg első szavaiból képzett azonosító.
- **Stabilitás:** a `tools/keys.lock.json` rögzíti a `namespace|szöveg → kulcs` párokat. Egy kiadott kulcs újragenerálásnál sem változik; új szöveg új kulcsot kap.
- **Sima szöveg:** a `{` és `}` escape-elve kerül a katalógusba (`{{`, `}}`). Így a resource-ok saját jelölései, például a v_introduce `{key:hudinfo}` jelölése, bájtra pontosan megmaradnak.

### 11.4 Fontosabb döntések (`tools/decisions.json`)

- **Kihagyva:**
  - naplók: `adminLog`, `railLog`, `rlog`, `mysqlLog`, a v_main updater-konzolja,
  - generált tartalom: shader-forrás, JSON és SQL építése, SVG és oldal-markup,
  - wrapper-előtagok (`"[SLR] " .. text`); maguk a szövegek a hívási helyeken fordulnak,
  - belső okkódok, például `"task closed"`, `"shift ended"`, `"the network train is gone"`; ezek logikai értékek, lásd 11.5,
  - Lifepak-üzenetek (`setMonitorMessage`, D2), gyógyszernevek, `mg/dL`, a BR 232 műszer-mértékegységei,
  - parancsszintaxisok, rangcímkék a nametagben,
  - tulajdonnevek: városok, állomások, rádióadók, NPC-k (Julia, Markus), márkák (FreeV, Sunline Rail, Binco, SA Control, BR 232, „Open SE”),
  - a ui_browser webtartalma (site-registry, hibaoldalak; 3.2),
  - a szerverböngészőben látszó játékmód- és térképnév (globális, mint a D9).
- **Kizárt fájlok és resource-ok:**
  - minden 3.2 / D1–D17 kivétel,
  - a v_achievements `config.lua` és a registry validációja,
  - az mg_* `server.lua` teszt-harness,
  - az rw_customtracks debug-overlayje, network-fájlja és validátora,
  - a **`v_mysql/config.lua`** (hitelesítési adat; a szkenner nem olvassa, a fájl gitignore-os),
  - a v_mysql naplói.
- **Aviation (AVI-CONFIRM javaslat, 11.6):**
  - fordítandó: az `avi_core` ATC-pozíció marker promptja és a jogosultsági hibaüzenetek,
  - minden más angol marad: az avi_monitors scope-tükrök, az ATC-adatok, a `/avinav` és `/avitraffic` admin-szerkesztők, az ATC-értesítések (WIND/NAV/TRAFFIC).

### 11.5 Riportok (`tools/out/`) – a 3. fázis munkalistái

| Riport | Tartalom |
|---|---|
| `report_coverage.md` | resource-onkénti lefedettség |
| `report_duplicates.md` | 20 `common.*`-jelölt (3+ resource), ~90 kétresource-os egyezés, kis/nagybetű variánsok |
| `report_hungarian.md` | magyar szövegek a forrásban |
| `report_dynamic.md` | 606 sablon a javasolt paraméternevekkel |
| `report_logic.md` | ~70 szövegként használt logikai érték (D3). A 3. fázisban átírandók: `v_jobmanager ui.lua` „Start Game”/„Invite Player”; `medsys glucometer.lua:192` („Measuring...” összehasonlítás); `v_socialpanel c_ui.lua:57` (a HELP_TABS felirata a tartalomtábla kulcsa); `med_erm config.lua` „task closed”/„shift ended”; `rw_core log.lua` „no route”/„end of track”. Protokollérték, marad: v_joinquit quit reason, getVehicleType, HTTP fejlécek |
| `report_utf8.md` | 59 megjelenített szövegen futó `upper`/`lower`, 4 `sub`, 9 `#hossz` (D6/D7) |
| `report_render_measure.md` | 127 `dxGetTextWidth`, ebből 77 renderből; a legtöbb: work_core 13, rw_core 10, v_socialpanel 6, v_jobmanager 6, med_erm 5 |
| `report_gta_fonts.md` | GTA-fontos szövegek (D8, 11.6) |
| `report_exceptions.md` | a kizárások és a kézzel eldöntendő adatfájlok (hospitals, airports, lights, stock_interiors, models, vehcolor, dispatchers) |

**Megjegyzések a 3. fázishoz:**
- A v_radar HUD-szerkesztő elemneveit (`boundingBoxes.name`, magyarról angolra) a resource JSON-ba menti. Ellenőrizni kell, hogy a betöltés nem név alapján párosít-e.
- A `shader_colors` és az `rw_core` paraméterként átadott magyar értékei (`"BE"`/`"KI"`, `"lett"`/`"megszűnt"`, `"minden"`) a hívási helyen kapnak kulcsot.

### 11.6 Nyitott kérdések (a 3. fázis előtt) – LEZÁRVA: D18 (common), D19 (aviation), D20 (WASTED/GO angol), D21 (időfutam-nevek kivételek)

1. **`common.*` összevonás:** a riport 20 jelöltje közül melyek kerüljenek a `common` namespace-be? Javaslat: Loading..., Back, Cancel, Save, Send, Confirm, Edit, Name, Level, Players, Played time, Race, Deathmatch, Job, Get ready, „{time_left|1f} s”.
2. **Aviation (AVI-CONFIRM):** jóváhagyod a 11.4 szerinti felosztást?
3. **GTA-fontok (D8):** fordítandó jelölt a v_spawnmanager **„WASTED”** és a v_jobmanager countdown **„GO”** (a szerver kódként küldi, a kliens képezi le kulcsra). A márkák („FreeV”, „FREE V”) és a számok maradnak.
4. **Időfutam-nevek** (`v_timetrial` „Las Venturas Highway Run” stb.): a jobmanager játéknevek mintájára kivétel legyen? Jelenleg fordítandóként szerepelnek.


---

## 12. A 3. fázis eredménye (2026-10-12)

### 12.1 Mi készült el

- **Lefedettség:** minden szöveget megjelenítő resource átállt; a kivételek a 3.2 és D1–D21 szerint maradtak ki.
  - `tools/locales.py scan`: **0** beégetett, fordítandó szöveg maradt.
  - `lint`: 0 hiba, 0 figyelmeztetés.
  - A katalógus **3104 angol kulcs, 68 namespace**, a megjelenő szöveg a régivel bájtra azonos. Kivétel a forrásban talált magyar szövegek angol változata, ezek a `locales/hu.seed/` alá kerültek.
- **Commitok:** a `localization` branchen, blokkonként.
  1. v_locals bővítés + codemod
  2. UI-keretrendszerek
  3. v_accounts / v_introduce
  4. HUD / social / core
  5. Work
  6. Medical
  7. Railways
  8. Minigames / vehicles / world / grafika / egyéb
  9. Maradék magyar szövegek
- **Élő ellenőrzés:** minden blokk után `/restartallresource` és a szerver-, illetve kliensnapló átnézése. A végén csak a korábbról meglévő hibák maradtak: v_jobcreator→v_jobmanager indítási sorrend, `acc:requestPanel` / DGSI időzítés újraindításkor.

### 12.2 Hogyan használják a resource-ok

- **Betöltés:** minden migrált script első sora:
  ```lua
  if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
  ```
  Emellett a meta.xml első scriptje `locals.lua` (ugyanez az import), és kap `<include resource="v_locals" />` sort. Az őrsor azért kell, mert ha egy include-olt resource meta.xml-je megváltozik, az MTA csak szerver-újraindítás után olvassa újra. Az őrsor nélkül a `locals.lua` ilyenkor nem futna le.
- **Kliens:** `L("kulcs", { param = érték })` szöveget ad.
- **Szerver:** `L.msg("kulcs", params)` üzenetobjektumot ad. A játékos nyelvére a küldéskor oldódik fel (D4).
- **Shared (közös konfig) scriptek:** `L.text(...)`, ami kliensen szöveg, szerveren üzenet.
- **Formátumsztringek:** a `%d`/`%s`-t tartalmazó, később `:format()`-tal kiegészített szövegek mindig sima `L()`-t kapnak.

### 12.3 A v_locals szerver lib biztonsági hálója (importáló resource-okban)

| Helyzet | Viselkedés |
|---|---|
| `triggerClientEvent` / `triggerLatentClientEvent` / `outputChatBox` / `kickPlayer` üzenettel | címzettenként, a játékos nyelvén feloldva (D4) |
| `..`, `tostring`, string-metódus (`:upper()` …), `<` / `<=` | alapnyelvű szöveg, nincs hiba (UTF-8-biztos upper/lower) |
| `string.format("%s")`, `table.concat` | alapnyelvű szöveg |
| `dbExec`, `dbQuery`, `setElementData`, `toJSON`, nem-v_locals resource exportja (pl. v_mysql) | alapnyelvű szöveg (tárolt / közös adat) |
| export argumentuma vagy visszatérési értéke egy másik v_locals-resource-ból | a metatábla visszaáll (`L.adopt`), az üzenet tovább működik |
| export hívója nem használja a v_locals-t (med_scenemanager, claude-mcp …) | a visszatérési értékek alapnyelvű szövegek |
| a v_locals-t használó resource-ok jelzése | resource-gyökér elementData `v_locals.consumer` (nem szinkronizált) |

A kliens oldalon nincs ilyen csomagolás: a kliens kódja szöveget kap. A ui_core exportjai és a ui_inac temp menüje az üzenetobjektumot is elfogadja (4.5).

### 12.4 Kézi átírások (D3, D6, D7) – a fontosabbak

- **Azonosító-alapú logika, kulcsból jövő felirattal:**
  - ui_pause: statisztika-kategóriák, jobs-nézetek, ON/OFF;
  - v_socialpanel: súgófülek;
  - v_jobmanager: lobby-akciók;
  - med_erm: tablet-címkék és a kifizetés kimenetel-szavai;
  - mg_airway: nehézségi szint;
  - v_stats: a mértékegység kód marad (`km`/`s`, a ui_pause összehasonlítja);
  - glucometer: a lokalizált „Measuring...” elutasítást hasonlítja össze.
- **UTF-8:**
  - v_chat és v_socialpanel: beviteli mező hossza és törlése (`L.len`/`L.sub`), a korábbi bájtalapú törlés elrontotta az ő/ű betűt;
  - v_socialpanel `ellipsis` → `L.fit`;
  - a megjelenített `:upper()` → `L.upper`.
- **Mérés:** minden v_locals-klienstől a `dxGetTextWidth` → gyorsítótárazott `L.width`.
  - v_socialpanel súgó és chatbuborék, ui_core loading/timer → `L.wrap`;
  - med_erm `Gfx.fit`/`Gfx.wrap` → `L.fit`/`L.wrap`.
- **Nyelvválasztó:** Settings → Display → Language (D12).
- **v_introduce szabályzat:** `L.file("v_introduce/rules.txt")`, a resource saját `rules.txt`-je a tartalék.
- **Helyi `L` változók átnevezve:** ui_core textInput (`lay`), med_erm admin panel (`lst`), rw_core trainlabel / log, rw_signals, rw_passengers scenery, v_jobcreator (`LIM`), world_clothes-shop label.

### 12.5 Fejlesztői munkafolyamat új szövegekhez

1. A kódba vagy rögtön `L("namespace.terület.kulcs")` kerül, a kulcs pedig a `tools/decisions.json` `add` részébe, **vagy** a resource-ba angol literál kerül, és utána `python tools/locales.py apply <resource>` (ez a kulcsot is legenerálja).
2. `python tools/locales.py residue <resource>`: az esetleg kimaradt, UI-gyanús literálok.
3. `python tools/locales.py all && python tools/locales.py lint`, a szintaxisra `python tools/locales.py check <resource>`.
4. A `tools/keys.lock.json` tartja a kulcsokat stabilan; a build a kódban már használt kulcsokat megtartja.

### 12.6 Ismert korlátok és teendők a magyar nyelv előtt

- **Nyelvváltás futás közben:** a betöltéskor összerakott statikus táblák nem frissülnek azonnal, csak újracsatlakozás vagy resource-újraindítás után. Ilyenek a menü- és konfigfeliratok, a ui_inac főmenü és a SETTINGS_TREE. A dinamikus szövegek, a `L.bind`-del kötött táblák és az `L.onChange` callbackek azonnal frissülnek. Teendő a magyar előtt: az érintett resource-ok `L.onChange`-re építsék újra a tábláikat, vagy a választó jelezze, hogy újracsatlakozás kell.
- **Alapnyelvű tartalék:** szerver oldali szövegösszefűzés (`"x" .. msg`) és tárolt adat az alapnyelven marad.
- **Tárolt adat:** a némítás alapértelmezett oka (`mute_reason` elementData) angol.
- **Kimaradt magyar seedek:** az `add`-ban felülírt, ékezet nélküli magyar szövegekhez nincs `hu.seed` bejegyzés: Uj uzenet, BE/KI, Vasutas jog, az rw_customtracks admin-parancsai.
- **MTA meta-gyorsítótár:** a v_locals, ui_core, ui_inac, ui_interactobject, ui_browser, rw_customtracks meta.xml-je csak a **szerverfolyamat újraindítása** után töltődik be teljesen. Működés közben az őrsor pótolja.

---

## 13. A magyar fordítás (2026-10-12)

- `locales/hu/<ns>.json`: mind a 68 katalógus + `locales/hu/files/v_introduce/rules.txt`, kulcsra pontosan az `en` párja (3126 kulcs). A `languages.json`-ban a `hu` **be van kapcsolva** (plural: `other`, fallback: `en`), a `meta.xml` felsorolja a fájlokat (a `tools/locales.py build` ezentúl a meglévő `locales/hu` fájlokat is beírja).
- **Szójegyzék / meghagyott kifejezések:** `Job` = Job, `Jobs` = Jobok (a versenyek / deathmatchek), a work_core „work” = *munka*; `Model LOD`, `Ped LOD`, `Vehicle LOD`, `Color Grading` marad; `lobby`, `crew`, `tag`, `nametag`, `blip`, `marker`, `spawn pont`, `checkpoint` bevett játékszavak; gyógyszernevek (Ketamine, Fentanyl …), `SpO2`, `NIBP`, `BPM`, `SIFA`, `ATP`, rangok (Admin, Mod, SuperAdmin …), állomás- és márkanevek változatlanok.
- **Lifepak kivétel (D2):** a medsys ritmusnevek (`normal_sinus_rhythm`, `asystole`, `ventricular_fibrillation` … 8 kulcs) angolok maradnak, mert a Lifepak kijelzőn jelennek meg.
- **ERM állapotok:** Szabad / Úton / Helyszínen / Átadás; `Start Response` = *Kivonulás indítása* (a med_hospitals és a work_ems oktatóprogram ugyanezeket a szavakat használja).
- **Az angol szövegbe égetett töredékek javítva** (a magyarnak nem volt hova fordulnia): `world_interiors` Enter/Exit, `v_weekly` day/week (`v_weekly.period.*`), `rw_loco` / `rw_passengers` / `rw_timetable` left/right (`*.side.left|right`), `rw_loco` „Dep.” és „completed”, `v_socialpanel` szabályok 1-4., `mg_airway` „mistake(s)” és `med_erm` „result(s)” (plural kulcsok `.one` / `.other`), `medsys` neuro vizsgálat (`{side}` paraméter, `side_left|right|cap_*`; a „Pupils” felismerés kulcs alapú lett).
- **Ismert határ:** GTA-fontok (pricedown, bankgothic) nem tudnak ő/ű-t (D8/D20: „WASTED”, „GO” angol). Játékban nem tesztelt: a hosszabb magyar szövegek túlnyúlását `/locdebug overflow` móddal kell végigjárni.
