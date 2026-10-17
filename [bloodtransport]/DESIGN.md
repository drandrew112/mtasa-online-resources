# Vérszállító rendszer – felmérés és terv

Állapot: **megvalósítva 2026-10-15** (szerveroldal élőben indul, a logika lupa-teszttel ellenőrzött; a játékbeli UI, a porta-ablak és a weboldal játékban még nincs kipróbálva). Használat: README.md. A kérés: `Blood transporter prompt.txt`.
A képernyőtervek: `docs/mockups/01..07_*.png` (újragenerálás: `python docs/mockups/make_mockups.py`).

---

## 0. Döntések (2026-10-15)

| # | Kérdés | Döntés |
|---|---|---|
| D1 | Csomagtartó → doboz → porta → doboz → csomagtartó kör | Kötelező (v_inventory K7). |
| D2 | Sürgős gyógyszer | Külön `bt_urgent_medicine` item, a `drug` ikonnal, `sample` kategóriával; a gyógyszer fajtája nincs megnevezve; ritka feladat. |
| D3 | Feladatgenerálás | Célszám = 2 × szolgálatban lévők, egyénenként max. 4, 60–150 s-onként új feladat (config). |
| D4 | Fogyasztás | Kórházi vonalanként 90–240 s / 1 egység, vércsoport-gyakorisággal súlyozva, küszöb 40 %. |
| D5 | Vércsoportok | Minden vércsoport külön vonal (0−, 0+, A−, A+, B−, B+, AB−, AB+), nincs egyszerűsítés. |
| D6 | Hiányzó központi készlet | Több központ között több feladatra osztjuk, ha így összejön a mennyiség; különben a feladat nem jön létre. |
| D7 | Megszakadt szolgálat | Halálnál / jármű elvesztésénél is jár a fizetés a leírt számítással. |
| D8 | Lemondott feladat készlete | WAITING: egységek vissza a központba; TRANSIT: elvész. |
| D9 | Visszatétel a forrásportára | **Tiltott.** (A 3. fejezet 6. pontja és a porta-szabályok ennek megfelelően: forrásportán `allowIn` mindig üres.) |
| D10 | Szolgálatba lépés | Csak a saját munkajárműben. |
| D11 | Skinek | Javaslat: 70, 17, 98, 150 (a work_core választóban ellenőrizzük). |
| D12 | J | F6 helyett J (kézre áll). A med_erm tabletje is J, de az csak szolgálatban lévő mentősnek nyílik. |
| D13 | Becsült kereset a panelen | Marad (a végső válasz szerint). |

---

## 1. Felmérés – mi van már meg

| Terület | Állapot | Következmény a tervre |
|---|---|---|
| `[bloodtransport]` | Csak a prompt van benne. | Itt jön létre a 5 resource; a `work_bloodtransport` a `[work]`-be kerül. |
| **v_inventory** | Ma készült, szerver oldala élőben tesztelt, a **UI játékban még nem**. Van `createPort`, `setPortVisibleTo`, `setPortRules` (játékosonként `allowIn/allowOut` uid/def lista), `setPortSuggestions` (TAKE/DELIVER jelölés + banner), `createTrunk` (`dataKey`), `onPortItemMoved`, `onInventoryItemMove` (megszakítható). Kész a `bt_blood_box` (konténer, 10 kg, `accepts`: blood, sample, tool) és a `blood` / `sample` kategória. **Vérkészítmény item még nincs.** | A dobozt, a portát és a csomagtartót nem kell megírni, csak használni. Új itemeket a `shared/items.lua`-ba + `v_locals/locales/en,hu/v_inventory.json`-ba kell felvenni (a v_inventory csak ismert itemet hoz létre). |
| **v_inventory szabályai, amik a vérszállítót érintik** | Kézben tárggyal tilos járműbe szállni (K7). A konténerbe csak egyszerű tárgy mehet (doboz a dobozba nem). Azonos itemek csak akkor halmozódnak, ha nincs `meta`-juk. A porta nyitása `E`-vel, kézben/háton lévő konténerrel. | Játékmenet: autó csomagtartó → doboz kézbe → porta → vissza a csomagtartóba → beszállás. A feladatonkénti item `meta`-val nem olvad össze más feladatéval (jó). A porta ablakában a többiek tételei is látszanak (zárolva) – ezt élőben kell megnézni, a v_inventory nem tud játékosonkénti láthatóságot. |
| **v_locals** | A mintát a v_inventory/work_ems adja: `locals.lua` az első script (`loadstring(exports.v_locals:import())()`), `L.config(function() … end)` a szöveges konfigra, kliens szövegek csak `onClientLoadingStarted` után (vagy ha `loaded=true`), utána `exports.v_accounts:resourceReady()`. Szerveren `L.forPlayer(player, key, params)`, kliensen `L.msg` üzenetobjektum (a ui_core és a ui_inac elfogadja). Katalógus: `locales/<lang>/<namespace>.json`, és **minden fájlt fel kell venni a v_locals `meta.xml`-be** (az ma módosított állapotban van, csak sorokat fűzök hozzá). | Új namespace-ek: `bt_core`, `bt_stock`, `bt_dispatch`, `bt_items`, `work_bloodtransport` + a `v_inventory` bővítése, mind `en` + `hu`. Kivétel (v_locals D-döntések): intézménynevek (tulajdonnév) és a weboldalak (angol). |
| **medsys** | Átnéztem a szöveg-/L-integrációját és a kapcsolódási pontjait: a vérszállítónak **nincs rá szüksége** (a vitális szimuláció és a kórházi átadás külön világ). | A prompt szerint a vérszállító független a `[medical]`-tól és a `med_hospitals`-tól: nem használunk belőle semmit, a kórházak saját listán vannak (`bt_core`). |
| **work_core** | `registerWork`, `createDutyMarker(blip)`, `createDutyVehicleMarker(platePrefix, spawns)`, `payWork(tételes nyugta)`, `getPlayerWorkVehicle`, események: `onPlayerWorkDutyStart/End`, `onWorkVehicleSpawn`. Az felrobbant/törölt munkajárművet maga eltávolítja. A work_ems a minta. | `work_bloodtransport` ~100 sor, a work_ems mintájára. A szolgálat (bt) és a work duty külön marad. |
| **med_erm** (admin minta) | `/ermadmin` dx panel (`client/admin/panel.lua`, `detail.lua`), `server/admin.lua` (`AdminHandlers`, SQLite `data/erm.db`, lapozott lekérdezések), webes admin (`webadmin.lua`: `v_accounts:httpLogin`, token, szintellenőrzés minden hívásnál, 5 hiba/perc korlát). | A `/btadmin` és a webes admin ennek a mintája, az auto-dispatch kapcsoló nélkül. |
| **web_api / ui_browser** | `registerApp({ site, category = "services" })` ugyanazt az oldalt adja HTTP-n és játékbeli oldalként. Csak a `meta.xml`-ben `http="true"` exportok hívhatók. Térkép: `OSA.Map` a v_radar bigmap-jével. A „Provided by OpenSanAndreas” felirat automatikus. | `bt_web` egy oldal, 3 nézet (Home / Map / Admin), cím: `blood-transport.eu`. |
| **v_radar** | Szerver export: `addObjective(player, x, y, z, label)`, `removeObjective`, `clearObjectives`. | Az „Útvonal” gomb ezt használja, játékosonként egyetlen aktív célponttal. |
| **ui_core** | `addNotification` elfogad üzenetobjektumot. | Új feladat értesítés. |
| **J** | A `med_erm` EMS tabletje használja. | Nem ütközik: a tablet csak szolgálatban lévő mentősnek nyílik, és a 415-ös vérszállító autóban hint sem jön; a billentyű a `panel.lua` elején állítható. |

---

## 2. Architektúra

```
[bloodtransport]/
  bt_core       intézmények (7 db), jog, portamarkerek (v_inventory), közös config, exportok
  bt_items      itemek, csomagtartó + doboz, porta-szabályok, felvétel/leadás észlelése
  bt_stock      készlet (data/stock.json), fogyasztás, feltöltés, kórházi utánpótlás kérése
  bt_dispatch   szolgálat, feladatok, kiosztás, átadás, fizetés, panel, /btadmin, MySQL (v_mysql)
  bt_web        weboldal (Home / Map / Admin), web_api app
[work]/work_bloodtransport   work duty, járműpontok, jog adása
```

Indítási sorrend (`<include>`): v_locals, v_mysql, work_core, v_inventory → bt_core → bt_items → bt_stock → bt_dispatch → bt_web;
`work_bloodtransport` a work_core-ra és a bt_core-ra épül. A bt_stock ↔ bt_dispatch kölcsönös hívás **futásidejű export** (nincs `include` kör, a `work_ems` mintájára `isRunning` védelemmel).

### 2.1 bt_core
* `BT.REQUIRE_RIGHT` (alap: `true`; tesztelésre `false`: mindenki vérszállítónak számít). A jog = `elementData "bt.right"`. A `false` módban a bt_core mindenkinek beállítja.
* Intézmények (config, angol tulajdonnév): 3 vérellátó (LS, LV, SF) + 4 kórház (All Saints, Country General, LV General, SF Medical Center), a megadott porta-koordinátákkal. Minden intézményhez egy `v_inventory:createPort`, láthatósága `dataKey = "bt.right"`.
* Exportok: `hasRight`, `setRight`, `getInstitutions`, `getInstitution`, `getPortId`, `getInstitutionByPort`.
* Megjegyzés: a promptban szereplő „különböző vérszállító rendszerhez tartozó interact object” alatt a csomagtartó menüt értem (v_inventory `ui_interactobject`, ugyanazzal a `bt.right` kulccsal). Más interact object nem készül.

### 2.2 bt_items
Új itemek (v_inventory): `bt_ffp`, `bt_rbc`, `bt_platelets` (kategória `blood`), `bt_lab_sample`, `bt_urgent_medicine` (kategória `sample`, mert a doboz a `drug`-ot nem fogadja). **Egy feladat = egy item** (`amount` = egység), `meta = { task, group, display = { honnan, hová, vércsoport } }` – a HUD és az ablak ezt mutatja.
* Mértékek (javaslat): vér-egység 0,5 kg (≈450 ml), labormintacső 0,05 kg, sürgős gyógyszer 0,3 kg → a 10 kg-os dobozba ~20 egység fér, egy feladat max. 8 egység.
* **Jármű**: az `onWorkVehicleSpawn` után (415, `BT-` rendszám) saját interact menü a jármű hátulján (nincs v_inventory trunk panel, a doboz `vehicle` tárolásban van, kivétel/betétel: `Vérdoboz kivétele` / `betétele`) + egy `bt_blood_box`, a doboz `access = bt.right`. A doboz uid-ja a szolgálathoz van kötve.
* **Porta-szabályok** (`setPortRules` + `setPortSuggestions`, minden feladat- vagy szolgálatváltozásnál újraszámolva): forrásportán `allowOut` = a játékos *felvételre váró* feladatainak itemei (TAKE), `allowIn` = semmi (visszatétel tiltott, D9); célportán `allowIn` = a dobozban lévő, **ide szóló** itemek (DELIVER), `allowOut` = a labormintákat (kórház → vérellátó) a felvételnél.
* Eseményfordítás: `onPortItemMoved(port, player, uid, "out"/"in")` → `bt_dispatch:onPickedUp / onDelivered`. Szerveroldali `onInventoryItemMove` védőháló: más játékos feladatának itemét nem lehet a saját dobozba tenni akkor sem, ha a UI hibázna.
* Takarítás: lemondott feladatnál az item törlése a portáról/dobozból; szolgálat megszakadásakor a doboz tartalma (`clearContainer`) és a játékosnak szánt portás tételek.

### 2.3 bt_stock (`data/stock.json`, gitignore, automatikus létrehozás)
Készlet: intézmény × termék (FFP / RBC / trombocita) × 8 vércsoport, egységben. Ha a fájl hiányzik, a script az alapértékekből létrehozza.
* **Kórház**: kis kapacitás, csak fogyaszt, **csak ha van szolgálatban vérszállító**. A küszöb alatt (config: 40 %) utánpótlást kér a `bt_dispatch`-től (csak kórházi utánpótlás típus; ha nincs szolgálatban senki, a dispatch elutasítja).
* **Vérellátó**: nagy kapacitás. A készlet **a feladat létrehozásakor** csökken (foglalás, az item a központ portájára kerül). **60 percenként** feltöltés: vonalanként a kapacitás 10–35 %-a, de sosem lépheti át a kapacitás 90 %-át (nem lesz 100 %). Szolgálat nélkül is nő.
* **Döntés a feladat létrehozásakor**: elég van az elsődleges központban? Ha nem, a többi központ (legközelebbi / legtöbb készletű) → ha egyetlen központban sincs elég, a feladat **létrejötte előtt törlődik**. (Részleges teljesítés: lásd a kérdéseket.)
* **Érkezéskor** (`receive`): kórházi utánpótlás → hozzáadódik a kórház készletéhez; minden más típus → az item azonnal eltűnik (felhasználva).
* A „sürgősség” (kék lámpás) a központ készletéből jön: ha a központ vonala 25 % alatt van, az utánpótlás sürgős, kisebb csomagokban (több, apróbb út).
* Exportok: `getStock`, `getAllStock` (web), `reserve`, `release`, `receive`, `findSource(product, group, units, preferInst)`, `canFulfill`.

### 2.4 bt_dispatch
**Szolgálat (shift)** – külön a work duty-tól:
* Belépés: a játékos a **saját munkajárművében ül** (work_core `getPlayerWorkVehicle`, 415, `BT-` rendszám). Egység-azonosító = rendszám, pozíció = a jármű pozíciója.
* Kilépés bárhol a panelről. A szolgálat megszakad: work duty leadás (`onPlayerWorkDutyEnd`), jármű törlése/megsemmisülése, a játékos halála. Megszakításkor/kilépéskor minden feladat `CANCELLED`, a doboz tartalma és a rá váró portás tételek törlődnek, kiszámolódik a fizetés.
* „Felkészülés a végére” (wind down): nem kap új feladatot, a meglévőket befejezheti; visszakapcsolható.

**Feladat**: `id`, típus, sürgősség (rutin / sürgős), termék, vércsoport, egység, felvételi és leadási intézmény, státusz, szolgálat, időbélyegek, forrás.
Típusok: kórházi utánpótlás (csak bt_stock kérheti), sürgős vér, előre tervezett műtéti vér, laborminta (csak kórház → vérellátó), sürgős gyógyszer (kórház → kórház).
Státusz: `WAITING` → `TRANSIT` → `DELIVERED` / `CANCELLED` (automatikus: porta → doboz = felvétel, doboz → célporta = átadás). A leadott feladat 5 mp-en belül eltűnik a panelről.

**Kiosztás**: ha nincs szolgálatban senki → nincs feladat, a külső kérést elutasítja. Az új feladat a legkevésbé terhelt (a legkevesebb nyitott feladatú) vérszállítóé. A nyitott feladatok célszáma a szolgálatban lévők számával arányos (config: 2 × létszám, egyénenként max. 4). A beépített típusokat egy generátor hozza létre (config-ban hangolható gyakorisággal), az utánpótlást a bt_stock.
**Átadás két játékos között**: csak `WAITING`, csak ha a két egység ≤ 5 m-re van; a másik 20 mp-ig fogadhatja; elfogadáskor a feladat átkerül a másik listájára (a porta-szabályok újraszámolódnak, az útvonal törlődik), a `bt_tasks.shifts` / `bt_shifts.tasks` naplózza.
**Sorrend**: a játékos mozgathatja a `WAITING` feladatokat; a `TRANSIT` mindig legfelül. A sorrend szerveren tárolt, a szerver érvényesíti.
**Útvonal**: egyszerre egy v_radar objective játékosonként; státusz szerint a felvételi vagy a leadási pont; státuszváltáskor automatikusan frissül/törlődik.

**Fizetés** (a szolgálat végén, `work_core:payWork`, tételes nyugta, `workId = "bloodtransport"`): alapbér €2000 (csak ha ≥1 `DELIVERED`), +€2500 / átadott, −€1500 / szállítás közben (TRANSIT) lévő, fel nem vett: nulla. A végösszeg ≤ 0 → nem fizet, de a nyugta látszik (work_core szabály).

**Adatbázis** a közös MySQL (v_mysql exportok, séma: `bt_dispatch/database.sql`, `main.sql`), két tábla: `bt_tasks` (feladatok; `log` = státusztörténet, `shifts` = kinek jutott, mikor, átadva-e) és `bt_shifts` (szolgálatok; `tasks` = a kiadott feladat-ID-k, `task_count`). A naplóoszlopok hozzáfűzős JSON-sorok. Az SQLite-ot (2026-10-17) teljesen elvetettük, a régi adatot nem vittük át. Minden elemnek `id`-ja van, a státuszok folyamatosan frissülnek.

**Kliens panel** (jobb alsó sarok): kis nézet (01. kép) és nagy nézet J-re (02. kép) kurzorral; csak a joggal rendelkezőknek.
**Admin**: `/btadmin` (dx panel a `/ermadmin` mintájára, 04. kép), szint: `BT.ADMIN_LEVEL = 2`; a lekérdezések közösek a webes adminnal.

### 2.5 bt_web (angol, nincs v_locals)
* HTTP (`/bt_web/`) és ui_browser (`blood-transport.eu`, Services).
* **Home**: bemutatás, „How do I become a blood transporter?”, statisztika (szolgálatban lévők, aktív feladatok, összes elvégzett – exportból a bt_dispatch-től) – 05. kép.
* **Map**: v_radar bigmap, egységek (hover: sofőr + feladatlista), intézmények (hover: rövid info), bal oldalt a szolgálatban lévők listája (csak olvasható), jobb oldalt a készletek (központok / kórházak fül) – 06. kép.
* **Admin**: v_accounts `httpLogin` + admin ≥ 2, token, szint újraellenőrzés, hibakorlát; ugyanaz, mint a `/btadmin` – 07. kép. Nincs auto-dispatch kapcsoló.
* A publikus végpontok (home, map, készlet) 2 s-os szerveroldali gyorsítótárat kapnak.

### 2.6 work_bloodtransport
`registerWork("bloodtransport")`, néhány véletlen skin (a work_core választóval), duty blip 14, járműpont: 415, `BT-` + számjegyek, a megadott 3 város duty/vehicle markerekkel és spawn pontokkal. Duty kezdetén `bt_core:setRight(player, true)`, leadáskor elveszi. A koordináták a promptból kerülnek a configba, MCP-vel nem ellenőrzöm őket.

---

## 3. Játékmenet

1. Duty marker → work duty (jog megkapva) → járműpont: `BT-xxxx` mentőautó.
2. Beszállás, J → **Sign on** → szolgálatban. Új feladatok értesítésként és a panelen érkeznek.
3. Kiszállás, csomagtartó (interact menü) → doboz kézbe → a forrásporta markerében `E` → a **TAKE** jelölt tételek a dobozba (→ `TRANSIT`).
4. Doboz vissza a csomagtartóba, beszállás, az útvonal gombbal célpont.
5. A célportán **DELIVER** jelölt tételek a portára (→ `DELIVERED`, 5 mp múlva eltűnik). Utánpótlásnál a kórház készlete nő; másnál az item eltűnik.
6. A felvett tétel visszatétele a forrásportára tiltott (D9); a feladatot a szolgálat megszakításával lehet lemondani.

---

## 4. Végrehajtási lépések (jóváhagyás után)

| # | Lépés | Ellenőrzés |
|---|---|---|
| 0 | v_inventory: új itemek + `v_inventory.json` (en, hu); v_locals meta bővítése az új namespace fájlokkal | `python tests/run.py`, JSON lint |
| 1 | `bt_core` + `work_bloodtransport` (jog, 7 porta, duty/jármű pontok) | indítás hibamentes, exportok (claude-mcp) |
| 2 | `bt_items` (csomagtartó + doboz, porta-szabályok, események) | szerveroldali export-tesztek |
| 3 | `bt_dispatch` mag: DB, szolgálat, feladatok, kiosztás, átadás, fizetés (UI nélkül) | lupa unit tesztek (kiosztás, fizetés, státuszgép), élő export-teszt |
| 4 | `bt_stock` + a dispatch-összekötés | lupa tesztek (fogyasztás, feltöltés, forrásválasztás), `stock.json` |
| 5 | kliens panel (kis/nagy), útvonal, értesítések, átadás UI | játékban a felhasználó próbálja |
| 6 | `/btadmin` dx panel | játékban |
| 7 | `bt_web` (Home / Map / Admin) + ui_browser oldal | böngészőben + játékban |
| 8 | `hu` fordítások átnézése, README + DESIGN-ok, `.gitignore` (`stock.json`, `*.db`) | `/locdebug pseudo` |

A játékos felé látható részeket (5–7) csak hiányos tesztelhetem; a UI-ra nincs automata ellenőrzés, ezeket jelölöm „untested”-ként, ahogy a többi resource-nál.

---

## 5. Nyitott kérdések

Nincs; a döntések a 0. fejezetben. Hátra van a végrehajtási engedély.

---

## 6. Megvalósítás – eltérések és megjegyzések (2026-10-15)

* A v_inventory restartja (vagy bt_items restart) után minden áru elvész: a nyitott feladatok `items_reset` okkal törlődnek.
* Szerver újraindulás után a megmaradt nyitott feladatokat és szolgálatokat a bt_dispatch lezárja (`restart`); a WAITING feladatok lefoglalt egységei visszakerülnek a központba.
* Kilépő játékos szolgálata fizetés nélkül ér véget (nincs kinek a nyugtát mutatni).
* Kórházi utánpótlásnál részleges teljesítés megengedett (ami van, azt viszi), a többi vér-feladat mindent-vagy-semmit.
* A feladat egység-határa 8; egy 10 kg-os doboz kb. 20 egységet bír, a porta súlyhatára akadályozza a túlterhelést.
* Egy áru nem osztható szét (a v_inventory részmozgatása elveszítené a `meta`-t), a bt_items ezt megtiltja.
* Más játékos dobozába nem lehet árut tenni, és csak a saját feladatot lehet kivenni a portáról (v_inventory szabály + `onInventoryItemMove` védőháló).
* A v_locals új katalógusfájljai miatt a v_locals-t egyszer újra kell indítani, hogy a kliensek megkapják őket.
