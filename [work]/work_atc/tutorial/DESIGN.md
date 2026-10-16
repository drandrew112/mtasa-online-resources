# work_atc tutorial – terv (vázlat, jóváhagyásra vár)

Minta: `work_ems/tutorial` és `work_bloodtransport/tutorial` (ugyanaz a szerkezet: config /
server/session.lua / client/card.lua / client/steps.lua, v_locals szövegek, saját dimenzió,
`save.position`, Start / Skip ajánlat az első szolgálatkezdéskor, „Skip tutorial” link, `F2` kurzor).

Alapelv, ahogy a vérszállításnál: **nincs kamu**. Az igazi scope, az igazi menü, az igazi
avi_traffic szimuláció fut, csak a tutorial repülőgépei és a tutorial pozíció **meg vannak jelölve**,
és el vannak választva az élő forgalomtól.

## 1. Keret

| | |
|---|---|
| parancs | `/tutorial_atc`, `/tutorial_atc skip` |
| account flag | `atc.tutorial = true` (v_mysql), befejezés vagy kihagyás után |
| ajánlat | első `onPlayerWorkDutyStart("atc")`, vagy mindig `TUTORIAL.DEBUG = true` esetén |
| dimenzió | `DIMENSION_BASE = 44000` (42000 ems, 43000 bt **és** v_introduce – ez már most ütközik, 45000 jobcreator) |
| hely | SA Control épület belseje (int 3) a tutorial dimenzióban, a San Fierro konzol előtt |
| pozíció | `SASF_TWR` (a szint 1 = TWR jog; a reptér az épület mellett van) |
| indulási feltétel | bejelentkezett, él, **nincs bejelentkezve ATC pozícióra** |
| pénz / XP | nincs; a végén a tutorial pozíció nyugtáját csak megmutatjuk (mint a bt receipt) |
| vége | visszaáll az eredeti helyre (fade), halál / kilépés / hiba nem állítja be a flaget |

## 2. Lépések (9)

1. **Konzol.** A játékos az SA Control teremben áll. Egy tutorial ATC marker (csak neki látszik):
   `E` → a login ablak, amelyben csak a tutorial `SASF_TWR` van. Login → következő lépés.
2. **A scope.** Felső sáv, zoom (görgő) / mozgatás (jobb húzás), a CTR, a futópálya + szél, az
   éppen használt pálya, gurulóutak / állóhelyek (csak közelebbi zoomnál), nm skála, a listák
   (dep / arr), a nyitott pozíciók. Kiemelés: avi_controller `getScopeLayout()`.
3. **A címke.** Egy tutorial indulógép áll egy állóhelyen (pl. `TUT101`, A320). A címke sorai
   (CS + CTL, TYPE/WAKE, ALT SPD DEST, SQK csak hoverre), sárga keret = kérés, szürke = nem a tiéd,
   a címke húzható, kattintás = menü.
4. **Delivery.** IFR clearance: SID lista (sárga = javasolt), kezdő szint. Utána pushback (a gép
   a gurulóútra tolatva fordul a pálya felé).
5. **Gurulás.** Taxi a használt pályához; a gép a pályazóna előtt megáll (hold short). Szöveg:
   pályára lépés csak engedéllyel (CROSS / LINE UP / BKTRK, backtrack 80 m felett), sorban állás
   60 m-en, head-on = bírság.
6. **Felszállás és levegő.** Take-off clearance (csak a pályán). A levegőben, még a CTR-ben:
   CFL, iránytű („Fly heading” / „Turn left / right heading”, görgő ±5°), Direct to, és a
   „Transfer to” menü. Amikor kilép a CTR-ből, a zárt APP miatt senkié lesz („no top-down cover”)
   – a lépés ekkor ér véget, a gépet töröljük.
7. **Érkezés.** Egy tutorial érkező gép jelenik meg kb. a final fix előtt a használt pályára
   (`TUT202`). Approach-hívás (sárga keret), landing clearance 400 m-rel a küszöb előtt, különben
   go-around – ha átstartol, a kártya elmagyarázza a `SASFGA` eljárást, és a lépés megvárja a
   következő megközelítést. Kigurulás (vacate exit), taxi állóhelyre. A lépés a parkolásnál ér véget.
8. **Riasztások és fizetés.** A címke riasztásai (EMRG / COMS / DUPE / STCA / RAM) egy rövid
   bemutatóval a tutorial gépen (`/avitraffic sqk`-hoz hasonló, de tutorial export: 7700 → EMRG,
   aztán vissza), bírságok (`CTL.PENALTY`), fizetés (`CTL.PAY_*`), XP, rangok (TWR → APP 5. szint →
   RADAR 8. szint). A játékos kijelentkezik a pozícióról → a nyugta megjelenik (nem fizetett).
9. **Kész.** Összefoglaló, a `sanandreascontrol.eu` dokumentumok sorrendje (NAV → SW → OPS → LOA),
   Finish → vissza az eredeti helyre.

A kártya bal oldalon van; a scope teljes képernyős, ezért a kártya a lista / felső sáv alá kerül
(`side = "left"`, a scope bal oldali listájától jobbra, a layoutból számolva). A scope maga mutatja a
kurzort, ezért a kártya gombjai a scope alatt is működnek.

## 3. Kampók a többi resource-ban (új kód)

**avi_traffic** (a tutorial gépek elválasztása az élő forgalomtól)
- `spawnTutorialFlight(owner, def)` → id. `def`: callsign, type, dep/arr, route, `at = "gate"`
  (rövid várakozással, `gateWait`) vagy `at = "final"` (runway + távolság a final fixtől, magasság).
- `removeTutorialFlights(owner)`, `getTutorialSnapshot(owner)`, `setTutorialSquawk(id, code)`.
- A gépen `ac.tut = owner`. Ezek **nem** kerülnek a `getTrafficSnapshot`-ba (scope-ok, avi_monitors,
  web), a schedule terhelésszámításba, a `MAX_ACTIVE`-be; nem foglalnak állóhelyet / pályát / gurulóutat
  az élő gépek elől és fordítva (a blokkoló függvények csak azonos `tut` gépeket néznek).
- Irányító: a tutorial gép irányítója a tulaj tutorial pozíciója, ha az be van jelentkezve, a
  szektor-szabály ugyanaz (CTR-en kívül → senki).
- Riasztás / szeparáció csak a saját tutorial gépei között; `onAviSeparationLoss` helyett
  `onAviTutorialSeparationLoss(owner, kind, cs1, cs2)` – bírság nincs, csak a kártya magyaráz.

**avi_controller**
- `loginTutorial(player, posId)` / a login `tutorial` jelzővel: a session `tutorial = true`, **nem**
  kerül a `staff` / `getStaffedPositions` listába (az élő SASF_TWR-t közben más is viheti), nincs
  pénz és XP, a forgalom = `getTutorialSnapshot(player)`.
- `avi:ctlCmd`: tutorial session csak a saját tutorial gépeit irányíthatja, élő játékos sosem a
  tutorial gépeket.
- Szerver esemény `onATCTutorialCommand(player, action, callsign, value)` minden elfogadott parancsra
  (a lépések ebből haladnak), és `getTutorialReceipt(player)` (mit fizetett volna).
- Kliens export `getScopeLayout()`: visible, felső sáv gombjai, listák, címkék rect-jei callsign
  szerint, a nyitott menü (rect + sorok címkével), az iránytű, a login ablak sorai.

**avi_core**
- `createTutorialMarker(player, dimension, positions)` / `destroyTutorialMarker(marker)`: az ATC
  marker másolata a tutorial dimenzióban, csak a játékosnak látszik, `useATCConsole` helyett
  tutorial logint nyit.

**work_atc**
- `tutorial/` mappa (config, server/session.lua, client/card.lua – a bt kártya másolata,
  client/steps.lua, fonts), meta.xml bejegyzések, README.
- Szövegek: v_locals `work_atc.tut.*` (en + hu), `[aviation]/tools/loc_tutorial.py` írja (a
  `[bloodtransport]/tools/locadd.py` mintájára / importjával).

## 4. Döntések (2026-10-16)

1. Elválasztott tutorial gépek az élő szimban (a javaslat szerint).
2. Csak a torony. Az APP / RADAR később külön modulokba kerül.
3. Nincs gyorsítás.
4. A dimenzió maradhat (a tutorial 44000-től indul, a játékos végig a 3-as interiorban van).

Eltérés a vázlattól, a megvalósítás közben derült ki: a SASF CTR csak egy sáv a pálya mentén
(2000 ft magas, a 22-es final fix a szélén van). Ebben nincs hely a megközelítésre, a felszállás után
pedig kb. 40 s alatt kirepül belőle a gép. Ezért a tutorial torony a saját két gépénél a zárt SASF APP-ot
(a TMA-t) is lefedi (`ac.tutCover`). Az indulás akkor ér véget, amikor a gép elhagyja a TMA-t (a
stubos tesztben 148 s), az érkező gép pedig a TMA-ban jelenik meg (1400 m-re a final fixtől). A kártya
szövege ezt el is mondja.
