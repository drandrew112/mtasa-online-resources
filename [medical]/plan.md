# Kórházi munka (SBO / ER) – végrehajtás követése

Ez a fájl a kórházi rendszer végrehajtásának állapota. Új session esetén **először ezt olvasd el**, utána a lenti memóriafájlokat és a tervet.
A fázisok csak a követést szolgálják: a végrehajtás a fázisok között **nem áll meg**, a teljes terv elkészüléséig folyamatos.

## Források

| Mi | Hol |
|---|---|
| Terv (artifact) | https://claude.ai/artifact/DhTja6KHwrZuoTQnZU2udF · artifact uuid `66d3e3de-ba12-45df-b141-55ff5ae5131e` · utoljára olvasott verzió `1793917508-de11` (2026-11-06) |
| A terv olvasása | Artifact tool `action: "read"` a fenti URL-lel → a teljes HTML egy helyi fájlba kerül (2602 sor, 259 KB). Szövegként: HTMLParser-rel kiszedni a látható szöveget (script / style / svg nélkül) → kb. 1450 sor. A 147 beavatkozás-kód táblája a HTML-ben van, a képek a 62 publikált fájl között. |
| Döntések | K1–K41 és Ú1–Ú12: mind a terv javaslata szerint elfogadva (a felhasználó 2026-11-06-án jóváhagyta a teljes tervet). Az azóta hozott új döntések lent, a **Döntések a terv után** részben. |
| Memória | `hospital-er-plan.md`, `feedback-complete-delivery.md`, `med-hospitals-resource.md`, `medical-system-resource.md`, `ems-competency-system.md`, `claude-mcp-resource.md` (a `C:\Users\DookthorAndriss\.claude\projects\C--Dev-MTASA-server-mods-deathmatch-resources\memory\` mappában) |
| Modul-térkép | `[medical]/med_hospitals/er/README.md` |
| Nyers források | `[medical]/source/BNOTORZS.DBF` (dBase III, CP852, 11 698 kód), `[medical]/source/icd102019en.xml`, `[medical]/source/ecg-12/` (EKG minták) |
| Felhasználói promptok | `[medical]/hospital-prompt-*-IGNORE.txt` (nem kód, ne módosítsd) |

## Munkaszabályok

- **Soha ne commitolj.** A felhasználó commitol; üzenetszöveget kérésre adsz.
- A munkafa más sessionök nem commitolt módosításait is tartalmazza (pl. `med_erm`, `med_hospitals`, `v_scenemanager`): csak a saját változtatásaidat írd, mást ne írj felül.
- `manage_resources refresh` csak új resource-mappához (az `mg_*` mappák ilyenek); minden más módosított resource-ot is újraindít. Utána nézd meg a logot.
- A v_locals restart lánc-újraindítást okoz (minden includer): csak akkor, amikor senki nem játszik, és a végén egyszer.
- A `v_scenemanager` `index.json`-jához **soha** nem nyúlunk.
- UI-szöveg v_locals kulcsokkal, hu + en; a kulcs csak `a-z0-9_.` lehet.
- Vizsgakérdések: a rossz válaszok hihetők és a helyessel azonos hosszúak (`feedback-exam-distractors.md`).
- Tesztek: minden Lua-fájl lupa (lua51) szintaxis-ellenőrzés; szimulációs logika offline unit-teszttel; elhelyezés és folyamatok élőben MCP-vel a **Laptop112** probe-on (`[devtools]/claude-mcp/mcp-server`, `node src/cli.js <tool> '<json>'`, nagy argumentum fájl-alapú runnerrel). Képernyőkép csak végső esetben.
- Csak a ténylegesen elkészült és ellenőrzött tétel kap `[x]`-et. Ami élőben nem volt kipróbálva, az `[x]` mellett `(offline)` jelölést kap, és a végső átadásnál külön listában szerepel.

Jelölés: `[x]` kész · `[~]` részben kész / hibás · `[ ]` nincs meg

## Döntések a terv után

| Dátum | Döntés |
|---|---|
| 2026-11-06 | Hordágy-marker: nincs temp menü. E a markerben: ha a játékos nem tol hordágyat → kér egyet, és azonnal tolja; ha üres kórházi hordágyat tol → törli. |
| 2026-11-06 | Röntgen fali monitor (negatoszkóp): az északi falon, x **1160.46** (a felhasználó pontja: 1160.46, -1292.42, 14.39); a monitor közepe ugyanolyan magasan, mint a CT-monitoré (z **16.2**), dél felé néz (rot 180); y a fal síkjára kerül (élőben raycasttal mérve, kb. -1291.86). Az ólomfal / vezérlő a monitortól nyugatra, hogy ne takarja. |
| 2026-11-06 | Medsys testrész: a `v_scenemanager` **összes meglévő sérülését** átírjuk (testrész + oldal a jelenetfájlokban), nem csak futásidejű feloldó. A jelenetfájlok módosulnak, az `index.json` nem. Futásidejű feloldó csak tartalékként marad a rész nélküli (új vagy hibás) sérülésekhez. |
| 2026-11-06 | EMS és kórházi jog szétválasztása: a kezelési jog (medsys medic szerep) közös marad; az ERM tablet, az ERM egység-bejelentkezés és az EMS táska a mentős szolgálatot (`work_core` "ems") nézi, a kórházi funkciók a `hosp.staff`-ot. |
| 2026-11-06 | EKG-12 csak a sokktalanítóban (ott van EKG-gép), illetve ALS mentőben B+ kompetenciától (Ú8). |
| 2026-11-06 | Teljes labor rendelhető (minden panel egyben). |
| 2026-11-06 | Tablet: jobb felső oldalválasztó és vissza gombok (az ERM tablet hamburger-menüjének mintájára). |

## Ami eddig elkészült (2026-11-06-i állapot, audit után)

| Rész | Állapot | Megjegyzés |
|---|---|---|
| `[work]/work_hospital` szolgálat, rangok (Ápoló, Rezidens, Orvos, Főorvos), medsys limitek, pontok, fizetés szolgálat végén | `[~]` élőben: szolgálat | vizsgafájlok üresek, Ú11 nincs, bemutató nincs, Minigames fül nincs |
| Kórházi hordágy (15 / 10 perc), kérés / törlés | `[~]` élőben | még temp menü, mentős 2146 modell |
| Fix osztályos / intenzív ágyak | `[~]` élőben: felvétel | a betegre nem lehet hatni, nincs Visszavétel |
| Eset (case), police_system név + szül. dátum | `[x]` élőben | csak memóriában, restart után adatvesztés |
| Sokkba tolás → T1 + kezelő | `[x]` élőben | |
| Beteg UI kártya | `[~]` élőben | nincs rendelés-ikon |
| HIS tablet / PC (lista, eset, fülek) | `[~]` élőben | PC nem nyílik restart után, tablet átláthatatlan |
| CT / röntgen / labor lelet | `[~]` élőben | csak rendelés + időzítő; képhiba-párosítások |
| Osztályos felvétel ágyra | `[x]` élőben | |
| EKG dokumentum + papír-nézet | `[~]` élőben | statikus kép, nincs EKG-12 modul |
| Műtő, intenzív, halál / hullaleadó, S1/S2 áthelyezés, paraméterkártya, lábon érkezők, kötelező átadási leírás | `[~]` nincs élő teszt | lásd a hibalistát |
| `med_docs` (tábla, viewer, Mentési lap minden átadáskor) | `[~]` | egyszerűsített sablonok, nincs verzió, Roboto |
| 8 minigame (`mg_suture`, `mg_irrigation`, `mg_cast`, `mg_reduction`, `mg_blooddraw`, `mg_fast`, `mg_chestdrain`, `mg_ecg`) | `[~]` offline | a szerveren nem futnak (nem volt refresh), nincsenek bekötve |
| `police_system` `requestNPCIdentity` / `getSkinGender` | `[x]` élőben | |
| `med_erm` paraméterkártya, kórház-státusz, auto S1/S2 sorrend | `[~]` nincs élő teszt | nincs Kórház fül, nincs S1/S2 jelvény |

---

## F0 – Hibajavítások (a felhasználó jelzései + audit)

- [x] ER markerek alphája 200 (`ER.MARKER_ALPHA` a `core.lua`-ban; hordágy-pont + osztály / intenzív / műtő / hullaleadó)
- [x] Hordágy-marker E-vel: kérés + azonnali tolás / üres tolt hordágy leadása, temp menü törölve (`er/client/er.lua`, `er/server/menus.lua`; új export `med_equipments:pushHospitalStretcher`, `destroyHospitalStretcher(obj, allowPushing)`) — élőben: kérés → tolja, második E → leadva
- [x] PC nem nyílt: a szerver a betöltés után minden kész kliensnek újraküldi a PC-listát (`his.lua` readyClients + LoadHandler), a PC jelölése szinkronizált — élőben: „[E] Hospital PC” felirat megjelenik
- [x] PC-elhelyezés: a PC_1 bounding boxa hibás (a doboz a pivotig ér le), a pivot az asztallapon (`PC_CENTRE` z = 0); PC1 y -1332.46, PC2 x 1154.51, PC3 x 1154.11 rot 60 — élőben képpel: az asztalon áll. (A PC3 forgatását a felhasználó nézze meg.)
- [x] (offline) Osztály / intenzív „Visszavétel”: `ER.retake` (`outcome.lua`), beteg menü + HIS gomb; az eset újranyílik (`c.reopened`). Az Ambuláns lap verziója: F1 med_docs verziózás
- [x] (offline) EKG-12 rendelés csak sokkban (`ERC.ORDER_ROOM.ecg = "shock"`)
- [x] (offline) EMS / kórházi jog szétválasztása: `med_erm` tablet (`Tablet.hasMedicRole`), egység-bejelentkezés (`units.lua hasMedicAccess`), EMS táska (`bag/server/interaction.lua hasEquipmentAccess`) → `hosp.staff` kizárva
- [x] (offline) Teljes labor panel (`lab.full`, HK-L16, `PANELS.full` + vércsoport + tox)
- [ ] Képpárosítás → **F4**-be került (új képgenerátorral együtt; a jelenlegi hibás párosítások: normál lábszár = gipszes kép, medence / gerinc normál = mellkas, ágyéki törés = mellkas, bordatörés = PTX kép, haemothorax röntgen / FAST normál)
- [ ] Áthelyezés gomb igényekkel / célkórházzal / megjegyzéssel → **F7** (végleges UI az F3 PC-oldalakkal)
- [x] 147 beavatkozás-kód adatfájlba: `er/shared/codes.lua` (pont, rang, esetenkénti limit; a terv táblájából generálva) + HK-L16
- Megjegyzés: az új szöveg-kulcsok a v_locals restart után látszanak (F9); addig „missing key” figyelmeztetés a logban.

## F1 – Alapok

- [x] medsys core: `injury.part` / `side` / `cause` (`medsys/shared/body.lua`: 12 testrész, oldal, súlyok típus és ok szerint, `medicResolvePart`, `medicPartLabel`); `applyInjury(el, type, sev, part?, side?, cause?)`, a snapshotban `part/side/cause/partLabel`; az events modul átadja a GTA testrészt (torso → mellkas / has 60/40, esésnél gerinc); új export `resolveInjuryPart` — élőben: esés → ágyéki gerinc, torso → jobb mellkas
- [x] `v_scenemanager`: 1140 jelenetfájl 2550 sérüléséből minden testrészes sérülés kapott `part` + `side` mezőt (script: leírás-kulcsszavak hu/en + kategória-súlyok + fájl+index seed; csak a sérülés-sorok változtak; `index.json` érintetlen); `storage.lua` megtartja, `builder.lua` átadja (rész nélküli sérülésnél a kategória oka dönt, `VSM_CATEGORY_CAUSE`), szerkesztő: sérülésenként Testrész / Bal / Jobb / Törlés almenü
- [x] Egységes időskála: `MEDIC_CLINICAL_SCALE = 6`, `medicClinicalHours`, `medicRealSeconds` (`body.lua`)
- [~] Rejtett leletek: a katalógus a `med_hospitals` `ERC.FINDINGS`-ben marad (az ER használja), a leképezés a core testrészből (`his.lua mapInjury`). Új leletek: face_fx, wound_neck, cspine_fx, tspine_fx, femur_fx, pelvis_fx, rib_fx_single — katalógus-bejegyzésük és képeik az **F4**-ben; új kórképek leletei `ERC.CONDITION_FINDINGS` (F6)
- [x] Laborérték-modell: `medsys/server/labs.lua` `getLabValues` (Hb/Hct, fvs, Plt, Na, K, kreatinin, glükóz, laktát, pH, BE, INR, APTI, CK, troponin, CRP, etanol, D-dimer, vércsoport, tox-szűrés; az alacsony RR / SpO₂ / leállás ideje gyűlik), `MEDIC_LAB_EFFECTS[type]` kórképenként, `getBloodGroup`; az ER labor ebből számol, a vérvételi hibák helyével (`drawErrors`) — élőben: értékek jönnek
- [x] Régi hiba javítva: a labor-lelet üres volt (a rendelés sorszáma ment panelnévként a `makeResult`-ben)
- [x] `getPatientLog(element)` (medsys: minden beavatkozás időbélyeggel, végrehajtóval)
- [ ] Kórházi gyógyszerlista → **F6** (a kórképekkel együtt)
- [x] BNO: `med_docs/bno/build_bno.py` → `bno.db` (11 698 kód; az angol név forrása: exact 8886, mod4 1069, cat 608, mod 72, parent 1040, none 23 — a `parent` csoport magyar 5. karakteres bővítései a WHO szülő-nevet kapják, kézi fordítás nélkül); `server/bno.lua` (memória, ékezetfüggetlen kereső, `searchBNO`, `getBNO`, `getBNOName`, `checkDiagnosis`: lejárt rejtve, nem / kor, max. 5, `*` csak `+` mellett), `client/bno.lua` (név-gyorsítótár, `searchBNO` → `onClientBNOResults`); `med_docs/shared/bno.lua` törölve; az ER diagnózis-felvétel ezen át ellenőriz — élőben: keresés hu / en és ellenőrzés OK
- [x] `med_docs`: `version` + `parent_id` (ALTER, ha hiányzik), `DOCS.VERSIONED` (amb, ems), Tinos Regular / Bold a papír-nézethez (Google Fonts; a Tinos azóta **SIL OFL 1.1** licencű, `Tinos-LICENSE.txt`)
- [x] A 147 kód pontja és esetenkénti limitje a pontozásban (`award` az `ERC.CODES`-ból)
- [x] Lupa szintaxis-ellenőrzés: minden módosított resource hibátlan

## F2 – Beteg a kórházban

- [x] Registry MySQL (`er/server/db.lua`): `hosp_cases` (példányonként: `instance` + `id`, a teljes eset JSON-ban, 2 s-os összevont mentés), `hosp_events` (betegút minden eseménnyel), `hosp_stock`; az esetszám a példány MAX(id)-jától folytatódik; restart után a megmaradt ped a teljes esetét visszakapja (`ERDB.loadCase`) — élőben: tábla létrejött, `dbReady`
- [x] (offline) Restart: a ped nélküli nyitott esetek „Megszakadt ellátás” (interrupted) lezárást és részleges Ambuláns lapot kapnak (`ERDB.closeOrphans`); eltűnt ped esete is így zárul
- [x] SBO-zóna (`er/server/zone.lua`, `er.zone` colshape): nem regisztrált betegek (medsys státusz, nincs eset, nincs mentős hordágyon), „Felvétel (regisztrálás)” menü a betegen, `ER.unregisteredRows` a HIS-nek (token) — élőben: a zónába tett ped „unregistered: 1”
- [ ] Lábon érkezők 11 sablonja → **F6** (mellkasi / hasi fájdalom, vesekólika, hipoglikémia, vágott seb, rándulás az új kórképekkel)
- [x] (offline) K10: triage előtt csak életmentés (CPR, légút, vérzéscsillapítás, O₂, monitor, vizsgálatok; leállásban minden) — medsys `onHostTreatmentCheck` → `med_hospitals:canTreatPatient`; helyiség-szabályok helye: `ER.roomRule` (F5)
- [ ] Triage-súgó → **F3** (vizsgálati panel)
- [x] Beteg UI: nyitott rendelések száma jelvényként, 10 m
- [x] Kórházi hordágy: GTA 1997 `hos_trolley` (`STRETCHER.PROFILES[1997]`, `stretcherSetting`; origó a padlón, matrac ~0,8 m, a beteg a háttámla felé fekszik) a hordágyakhoz és az ideiglenes ágyakhoz — élőben képpel ellenőrizve. Saját ágy-modell → **F7** (Blender)
- [x] (offline) Rendelés rang szerint: gyógyszer-rendelés (`ER.orderDrug`, `c.drugOrders`), az Ápoló a rendelt szert beadhatja (medsys `hostAllowsAction` → `allowsByOrder`), beadáskor a rendelés lezárul
- [x] Kórházi felszerelés (`er/shared/stock.lua`, `er/server/stock.lua`): a dolgozók EMS táska nélkül, a helyiség készletéből kezelnek (medsys `getPatientEquipment` → `getHospitalEquipment`, fogyás `consumeHospitalStock`); készlet hosp_stock-ban, rendelés 30 s (`ER.orderStock`, fizetés: F8)
- [x] `getERState(hospitalId)` export (olvasás: tesztekhez / adminnak)

## F3 – DX felületek

- [x] **Kórházi betegpanel** (`er/client/exam.lua`, 1280×720 tervezési méret, skálázva): fejléc (triage, név, kor, nem, testsúly, szül. dátum, esetszám, kezelő, hely, SBO-n töltött idő, vércsoport, allergia-jelvény), testtérkép elöl / hátul (lelet / ellátva színekkel, tooltip), vitális sáv (HR, RR, SpO₂, LF, EtCO₂, T, GCS, NRS – csak a monitorról vagy a mérésből), fülek: Vizsgálat, Rendelések (indikáció ✓ / !, a kész rendelés leletre kattintható), Beavatkozások (leletek ellátása + helyiség-beavatkozások helye, F5), Gyógyszerek (medsys katalógus, adagok, Rendelés / Beadás, allergia-figyelmeztetés, rendelések listája), Transzfúzió (F6 adatra kész), Dokumentáció (anamnézis / státusz „vizsgálatból” / epikrízis szerkesztés, kimenetek, osztályválasztó, BNO-keresés, javasolt kódok), Betegút; jobb oszlop: rendelések állapottal, diagnózisok, triage 1–4, kezelő; lelet-néző, BNO-kereső, áthelyezés-kérő (S1/S2, igények, célkórház, megjegyzés). Ágy mellett (beteg menü „Betegvizsgálat”) minden, távolról (PC / tablet) a fizikális rész tiltva — élőben: a panel megnyílik és rajzol (képpel)
- [x] (offline) Vizsgálat szerveren (`er/server/exam.lua`): 10 testtáj, 25 lépés 2–6 s animációval, leletsorok a rejtett leletekből és a medsys állapotból (pl. jobb felhasi védekezés májsérülésnél), mért vitális értékek, GCS / NIHSS / NRS / hőmérséklet, kikérdezés (allergia, gyógyszerek – véralvadásgátló → medsys `anticoagulant`), státusz-sablon az Ambuláns laphoz; pontok (V01–V16)
- [x] (offline) medsys exportok: `startTreatmentFor` (gyógyszer beadása a panelről, minden medsys ellenőrzéssel), `getDrugCatalog`, `anticoagulant` állapot
- [x] Tablet / PC keret újra (`er/client/his.lua`): jobb felső oldalválasztó (☰), vissza gomb (oldal-előzmények, Backspace / Esc), tablet: Betegek (saját / minden), Teendők, Kommunikáció, Értesítések; PC: Betegek (érkezés, várakozás, nem regisztráltak „Felvétel” gombbal), Osztály, Felszerelés (készlet + rendelés), Kommunikáció, Értesítések, Dokumentumok; tooltipek
- [x] (offline) Kommunikáció (`er/server/comms.lua`): egységenkénti szál (első üzenettel / paraméterkártyával nyílik, az ERM feladat végén zárul), Belső szál, exportok `sendHospitalMessage`, `getHospitalThreads`, esemény `onHospitalMessage`, értesítések listája
- [x] (offline) ERM tablet „Kórház” oldal (`med_erm/client/pages/hospital.lua` + szerver): kórházak státusszal, a kórházzal folyó üzenetszál, üzenetküldés, paraméterküldés gomb; a kórházi válasz értesítést ad a személyzetnek
- [x] `/ertest [típus] [súlyosság] [testrész] [oldal]` és `/ertest walk` (admin 5+): tesztbeteg kórházi hordágyon egy szabad folyosói helyen — élőben kipróbálva
- [ ] Triage-súgó → **F5** (a beavatkozás-listával együtt)

## F4 – Diagnosztika

- [~] CT: egyszerre egy beteg + **várólista** (T1 előre), a hordágy a beteggel becsúszik a gantryba és vissza (`moveObject`, `ct.slide` 2,4 m), lelet + **fali DX monitor** (render target, `er/server/wall.lua`, `er/client/wall.lua`), jobb oldali CT-képváltozatok (tükrözött anatómia, `_r`); **saját CT-modell: Blender nem fut** (addon nem csatlakozik) → addig a térkép gantry-pótléka
- [x] (offline) Röntgen: 14 testrész (mellkas, felkar, könyök, alkar/csukló, kéz, medence/csípő, comb, térd, lábszár, boka, lábfej, nyaki / háti / ágyéki gerinc), végtagoknál oldalválasztó; rossz oldal = negatív kép + nem indokolt; az expozícióhoz a dolgozónak a vezérlőpultnál (ólomfal mögött) kell állnia, 3 s; kontrollfelvétel gipszben (HK-K06); fali negatoszkóp az északi falon (x 1160.46, z 16.2)
- [x] Képtár: `med_hospitals/tools/gen_xray.py` (52 új röntgenkép bal/jobb változattal ugyanabban a stílusban, a régi hibás párosítások megszűntek; 9 tükrözött CT-kép) — képen ellenőrizve
- [x] (offline) FAST: `mg_fast` bekötve (eFAST 6 ablak, pozitívak a leletekből: máj → RUQ, lép → LUQ, haemothorax → felhasi ablak, PTX → tüdőablak, medence, tamponád), ablakonként pos / neg / nem értékelhető, képek ablakonként
- [x] (offline) Labor + vérvétel: `mg_blooddraw` bekötve (csövek panelenként), hibák → laborhatás (hemolízis, K-EDTA, alultöltött citrát, hemokoncentráció, hígulás infúziónál), 120 s
- [x] (offline) EKG-12 modul (`medsys/ecg12`): szerver-specifikáció (`getECGSpec`: ritmus, frekvencia, PR / QRS / QT / QTc / tengely, K⁺, alternans, alacsony feszültség, STEMI territórium + stádium a kórképekből, elektródahibák), kliens 3D dipólus-renderer (12 elvezetés + II ritmuscsík, reciprok változások), gépi értelmezés; `mg_ecg` bekötve (felcserélt RA/LA → negatív I, rossz V → torz R-progresszió); kórházi lelet a specifikációból rajzol, med_docs EKG-dokumentum és Mentési lap „eMedia – EKG” is
- [x] (offline) Mentős EKG-12 (Ú8): Lifepak „12-LEAD” gomb (work_ems `action.ecg12` = B+), néző PRINT gombbal → `ecg.lastPrint` + med_docs EKG-dokumentum
- [x] Minigame-híd (`er/server/minigames.lua`) mind a 8 játékhoz; az mg_* resource-ok most már futnak (refresh + start, a v_main ezután magától indítja őket)
- [x] v_locals restart megtörtént (üres szerveren): az új szövegek élnek

## F5 – Helyiségek és minigame-ek

- [x] (offline) Sokktalanító: a fali monitor magától csatlakozik a sokk-ágyhelyen (medsys `monitor`); csak itt (és intenzíven) végezhető: RSI / intubáció és RSI-szerek, noradrenalin, alteplase, tűdekompresszió, medenceöv, gépi lélegeztetés, CPAP, artériás vérgáz, mellkasi drain (`mg_chestdrain`), FAST, EKG-12; leállásban és eszméletlen betegnél a légútbiztosítás bárhol (K10)
- [x] (offline) Sebkezelő: irrigálás (`mg_irrigation`) → varrat (`mg_suture`, helyi érzéstelenítés nélkül remeg), fertőtlenítés, helyi érzéstelenítés, végleges kötés, égési kötés; rossz minőség → fertőzés-kockázat; készletből fogy
- [x] (offline) Gipszelő: röntgen kötelező, repozíció (`mg_reduction`, fájdalomcsillapítás számít), gipsz (`mg_cast`, túl szoros → újra), keringés-mozgás-érzés vizsgálat, mitella
- [x] (offline) Helyiség-beavatkozások listája (`er/server/procedures.lua`): rang, helyiség, fogyóeszköz, tiltási ok tooltipben; hólyagkatéter, gyomorszonda, megfigyelés, NPC-konzílium (a megerősített leletekből javasol)
- [x] (offline) Triage-súgó: javasolt szint a mért értékekből a panel jobb oszlopában
- [x] (offline) work_core Minigames fül: mind a 8 kórházi játék gyakorolható (work_hospital config; work_hospital restart után látszik)
- [ ] Álló CPR animáció (IFP) → **Blender kell** (nem fut)

## F6 – Szimulációk

- [x] Új kórképek (`medsys/shared/conditions.lua`, deklaratív): ACS (NSTEMI / STEMI / kardiogén sokk), appendicitis, vesekólika, GI-vérzés, szepszis, DKA, tüdőembólia, anaphylaxia, hyperkalaemia, tamponád, pitvarfibrilláció, teljes AV-blokk, rándulás, vágott seb + 8 új mérgezés (paracetamol, TCA, szerves foszfát, CO, béta-blokkoló, digoxin, metanol, cianid); új ritmusok AFIB / AVB3 a monitoron (szabálytalan RR, független P) — élőben: inferior STEMI, AFIB ritmus, COHb 29%
- [x] (részben élőben) Időbeli lefolyás (`medsys/server/conditions.lua`): STEMI territórium (LAD 56 / RCA 36 / Cx 7 / LM 1%), stádium (hiperakut → akut → evolvált → reperfundált), nekrózis % a reperfúzióig (antiplatelet lassít), szövődmények territórium szerint (inferior → AV-blokk, anterior → VF, laterális → AF); reperfúzió lízissel vagy PCI-vel (`reperfuseACS`); nitrát inferior STEMI-ben → RR-esés; appendicitis romlik és perforál (szepszis); DKA glükóz; CO oxigénre tisztul; TXA egyszer csökkenti a vérzést
- [x] (offline) Stroke-lízis: utoljára jól látott idő, alteplase 4,5 klinikai órán (45 perc) belül, javulási esély az idővel csökken, 6% (kontraindikációval 20%) tünetes vérzés, vérzéses stroke lízise = súlyos romlás; NIHSS a vizsgálatban
- [x] Laborértékek és EKG-12 hatás minden új kórképre (troponin a nekrózisból, CRP, laktát, K⁺, pH, D-dimer, COHb, kolinészteráz, tox-szűrés; STEMI-specifikáció, alternans, széles QRS)
- [x] 25 kórházi gyógyszer (`hospital = true`, csak kórházi készletből): amiodaron, atropin, noradrenalin, propofol, morfin, metamizol, ondansetron, flumazenil, lidokain, TXA, alteplase, ASA, klopidogrél, heparin, ceftriaxon, tetanusz, kalcium, bikarbonát + antidótumok (NAC, pralidoxim, glukagon, fomepizol, digoxin-Fab, hidroxokobalamin, aktív szén); rangok a work_hospital-ban (alteplase, noradrenalin, propofol: Orvos)
- [x] Kórházi leletek a kórképekhez (`med_hospitals/er/shared/conditions.lua`: BNO, labor- / EKG- / képalkotás-kimutatás, műtét, lízis); a labor-panelek felfedik a hozzájuk tartozó leleteket
- [x] (offline) Transzfúzió (`er/server/transfusion.lua`): `bt_stock` új `consume` export, szolgálat alatt a véletlen kórházi fogyasztás szünetel; vércsoport-labor → ismert csoport, keresztpróba (60 s); addig csak 0 Rh− vvt / AB plazma a sokk vérhűtőjéből; kompatibilitás-tábla (vvt, plazma fordítva); 5 perc / egység (masszívnál nyomózsák 2 perc, 4+ egység 10 percen belül = MTP, Orvos); hatás (vérvolumen, alvadás); inkompatibilis → hemolitikus reakció (T8030); volumenterhelés; Ú6 sürgősségi szállítmány
- [x] Lábon érkezők: mind a 11 sablon (rándulás, csuklótörés, vágott seb, égés, mellkasi fájdalom NSTEMI / STEMI, hasi fájdalom, vesekólika, asztma, hipoglikémia, ittasság, fejsérülés)
- [x] v_scenemanager: a heartattack jelenetek ACS-t, a magas glükózú diabétesz-jelenetek DKA-t kapnak

## F7 – Osztályok és szállítás

- [x] (offline) Műtő (`er/server/outcome.lua`): mind a 13 műtét a megerősített / látható leletekből (`ER.surgeryOptions`: a lelet saját műtéte + thoracotomia drénen > 1500 ml-nél, trombectomia ischaemiás stroke-ban, ér-rekonstrukció / debridement végtagsebnél), sürgős műtétek elöl; Ú2: Orvos küld, Rezidens kér (`er.surgery_request`) → Orvos jóváhagy / elutasít a betegpanelen vagy a PC Osztály oldalán, Orvos nélkül a Rezidens küld; átadás 5 s; Ú10 egy várakozó hely (sürgős műtét a normál mellé is beállhat, elé sorolódik); kimenetel a kezdetkor: siker / szövődmény (→ intenzív, intubált, hipotenzió) / halál a sokk-indexből, az eltelt időből, a transzfúzióból, más kezeletlen kritikus leletekből, korból; részleges gyógyulás (medsys új `treatInjuries` export a műtött sérülésekre), PCI → `reperfuseACS`; nagy műtét után intubált; marker-kártya a hátralévő idővel és a várakozóval (`updateMarkerUI`), PC: foglaltság, várakozók, kérések; Műtéti leírás eredménnyel, vérveszteséggel
- [x] (offline) Intenzív (`er/server/icu.lua`): vizit 5 percenként (I01, állapot-pillanatkép), lélegeztetőgép VC / PC, FiO₂, PEEP, LF, VT (I02; FiO₂ + PEEP − tüdőleletek → SpO₂, perctérfogat → EtCO₂, magas PEEP → RR-esés, szedálás nélkül „küzd a géppel”), noradrenalin-titrálás 0–0,5 µg/kg/p lépcsőkben (I03, MAP cél 65, medsys `hypertension`), szedáció nincs / felületes / mély (I04, fájdalom-plafon), vérgáz 30 s (I05); a betegpanel Beavatkozások fülén ICU-blokk; tartózkodás végén stabil beteg „intenzívről osztályra” lezárás. **Ágy- és gépmodellek: Blender kell**
- [x] (offline) Elfekvő / intenzív romlás: a számláló áll, riasztás a kezelőnek; ha nincs: intenzíven minden szolgálatban lévő Orvos, elfekvőn minden dolgozó; Visszavétel (HK-A14) után folytatás
- [x] (offline) Hullakezelés: exitus-rögzítő ablak (idő, ok BNO-val a diagnózisokból vagy gyakori kódokból, körülmények), a halott a hordágyon marad és tolható; érkezéskor halott beteg (mentő hozta, dolgozó jelen) „halott” esetként a kórházi hordágyon; Ú4: rögzítés után 20 perccel az NPC halottszállító viszi, pont nélkül, bizonyítvánnyal. **Lepedő-modell: Blender kell** (a GTA-ban nincs halotti lepedő)
- [x] (offline) Áthelyezés: „Beteg átvétele” marker a `transferPickup` ponton csak mentősöknek (work `ems`, lila kártya); ERM S1 lila / S2 halványlila jelvény (`Gfx.priorityBadge` a `meta.transferClass`-ból) a tablet listáin, az eseten és az admin panelen; a feladat metája: igények, megjegyzés, célkórház; a célkórházban az átadási szöveg automatikusan a kérés megjegyzése („Áthelyezés (S1) innen: …”), az eset „transfer” érkezéssel nyílik; automatikus szállítás és ALS-szűrés (korábbról). A Mentési lap „riasztás oka: betegszállítás” → **F8**

## F8 – Papírok, pénz, súgó

- [x] (offline) Ambuláns lap a minta formátumában (`med_docs/client/viewer.lua` + `med_hospitals/er/server/docs.lua`): kórházi fejléc (osztály, város, sorszám), beteg- és felvételi sorok, anamnézis, státusz (szabad szöveg + mért értékek), beavatkozások kód / megnevezés / db / pont táblában összesen-sorral, műtétek, diagnózisok dátummal, epikrízis, kapcsolódó dokumentumok (a leletek sorszámai `onMedicalDocumentCreated`-ből), kimenet (osztály, hely, idő), aláírás „kezelőorvos”, lábléc `med_docs · sorszám · vN · Oldal 1/1`; verzió visszavételnél (meglévő `DOCS.VERSIONED`)
- [x] (offline) Leletek: labor csoportosítva (Vérkép / Kémia / Vérgáz, alvadás, egyéb), jelzés + referencia, „Mit jelentenek az eltérések?” doboz értékenkénti magyarázattal (25 eltérés-szöveg hu / en), mintavevő, kiadás „automatikusan validálva”; CT / röntgen / UH: vizsgálat + oldal, végző, leletek leírással (32 lelet-leírás), FAST ablakonként, kontrollfelvétel, Vélemény, képek; EKG: idő, ritmus, mérések, gépi értelmezés, 12 elvezetés
- [x] (offline) Mentési lap (`med_docs/server/ems.lua`): Bejelentés (ERM #, prioritás, dátum, riasztás oka mentés / **betegszállítás**, helyszín, vezető), Beteg adatok (vezeték- / keresztnév, szül. dátum, nem, polgári azonosító), Diagnózis (sérülések testrésszel, megbetegedés trauma / belgyógyászati, **NACA** 1–7), Átadás, Epikrízis / Decursus, Mi történt?, Betegvizsgálat **ABCDE**, Áttekintés idővonal + gyógyszerek, EKG, **Adatfelvétel** tábla (mintavétel minden mentős beavatkozásnál, 2 percenként, max. 8 sor), Beteg állapota, bizalmassági lábléc nyelvkóddal és verzióval; **feladat végén is**, ha nem volt átadás (`onErmTaskClosed`, a legénység utolsó betege); Ú12: a vezető 15 percig szerkesztheti (Szerkesztés gomb → Epikrízis, Mi történt? → új verzió, `author_account` megmarad), utána csak a mentős főorvos
- [x] (offline) Műtéti leírás (műtét + kód, kezdés / befejezés, NPC sebész, vérveszteség, eredmény siker / szövődmény / halál, műtétenkénti leírás, transzfúziók, diagnózisok), Halottvizsgálati bizonyítvány (idő, hely, érkezéskor halott, ok BNO-val, körülmények, diagnózisok, NPC halottszállító, halottvizsgáló orvos)
- [x] 147 beavatkozás-kód (F0), 50% indikáció nélkül (meglévő), **kezelői esetbónusz 15%** (`ERC.CASE_BONUS`, a lezárt, dokumentált eset pontjaiból, egyszer); `ER.points(..., c)` minden hívásnál az eset pontösszegébe számol
- [x] Stock modul (F2) + fizetés a `supplies` fizetőtől
- [x] (offline) `gov_health`: kórházanként új fizetők `care` / `salary` / `supplies` (alapból Kincstár), `health.point_care` = 60, `health.point_salary` = 40 (a /gov Egészségügy oldalon szerkeszthető); exportok `payHospitalCare`, `payHospitalSupplies`, `getHospitalSalaryPayer`, `getHospitalPointValues`; lezárt eset → pont × $60 a care fizetőtől, elnyelve (`er/server/pay.lua`); dolgozói fizetés a work_core `payWork` új `opts.payer`-ével a salary fizetőtől, gov_health pontértékkel; **Ú9**: ha a számla nem fedezi → „system” fizet + figyelmeztetés-lista a /gov oldalon (törölhető); a régi `chargeHealthcare` csak dolgozó nélkül (meglévő) — élőben: exportok válaszolnak (60/40, salary payer = kincstár)
- [x] (offline) Vizsgák: `work_hospital/exams/{hu,en}/resident.json` és `physician.json`, 60–60 kérdés, 25 kérdezve, 75%, 5 perc; a rossz válaszok hossza a helyeséhez igazítva (generátor-ellenőrzés: 0 eltérés); **Ú11**: work_core `exams.check` hook → `work_hospital:checkHospitalExam` (Rezidens: 2 óra Ápolóként; Orvos: 4 óra Rezidensként + 20 lezárt eset kezelőként; szolgálati idő rangonként és esetszám accData-ban)
- [x] (offline) Kórházi bemutató (`work_hospital/shared|server|client/tutorial.lua`): első szolgálatkor 17 lépés (hordágy-marker, vizsgaközpont, PC, folyosó, sokk, seb, gipsz, CT, röntgen, műtő, intenzív, elfekvő, hullaleadó, átvételi pont, rangok), lila marker + nyíl + DX kártya; a végén **Ápoló rang** (`grantCompetency`); az Ápoló már nem alaprang, rang nélkül az ER-funkciók tiltva; `/hosptutorial` ismétlés
- [x] `ui_help` Kórház kategória: 27 fejezet hu + en (`content/{hu,en}/hospital/*.txt`), képek `content/images/hospital/` (CT, röntgen, UH, EKG), a vizsga súgója `hospital_exams`
- [ ] Saját orvos- és ápolóskinek (K41): **külső modell kell** (v_modloader); addig a 70 / 274 / 275

---

## F9 – Átadás

- [x] `refresh` (új `mg_*` mappák) + v_locals restart üres szerveren (kétszer: F4 után és F8 után); minden érintett resource újraindítva, hibátlan log (csak a más session `v_scenemanager` locale-kulcs figyelmeztetései: `state.ivAccess`, `state.bloodVolume`, `state.heartRate`, `label.lightsOn` – nagybetű a kulcsban)
- [x] Offline unit-teszt: műtéti opciók és sorrend, Ú2 kérés / jóváhagyás / Orvos nélkül, műtéti kockázat, lélegeztetőgép-modell, FiO₂-korlát, noradrenalin-lépcsők, szedáció, vizit-gyakoriság (11/11)
- [ ] Élő teszt végig Laptop112-n: érkezés (mentő, lábon, behozott), triage, kezelő, vizsgálati panel, labor + vérvétel, CT, röntgen, FAST, EKG-12, sokk, sebkezelő, gipszelő, osztály + visszavétel, intenzív, műtő, halott + hullaleadó, S1/S2 (egységgel és nélküle), dokumentumok, fizetés, vizsgák, bemutató, súgó — **nincs csatlakozott kliens** (a probe nincs bent)
- [ ] Blender kell (nem csatlakozik): saját CT-modell, kórházi / intenzív ágy, lélegeztetőgép, halotti lepedő, álló CPR animáció (IFP)
- [ ] Saját skinek (K41): külső modell
- [x] Memória (`hospital-er-plan.md`) és ez a fájl frissítve

### Élőben még nem tesztelt (offline) tételek
F0–F8 minden `(offline)` jelű sora; különösen: műtő teljes útja (átadás 5 s, várakozó hely, kimenet, posztop hordágy), intenzív panel, exitus-ablak + NPC halottszállító, áthelyezés átvételi marker és célkórházi szöveg, Mentési lap új mezői és szerkesztése, gov_health fizetések és figyelmeztetések, vizsgák feltételei, bemutató, súgóoldalak megjelenése.

---

## F10 – Javítások, 3. kör (2026-11-06, terv: https://claude.ai/artifact/69cenRp7AtF9zE161pz3pV)

- [x] (offline) Tablet: dizájn marad, nincs Dokumentáció fül; új Elhelyezés fül (kimenetek) tableten és PC-n; szerver: szöveg / BNO csak PC mellől (`ER.atPC`, 3 m)
- [x] (offline) PC: Win7 sötét monitor a képernyő 80%-án (`er/client/w7.lua`), üres asztallal nyílik (nincs nyitott alkalmazás): asztal, tálca, Start menü, óra, ablakok SBO / Beteglap / Dokumentumtár; skin réteg a `gfx.lua`-ban; EMS a PC-n csak a Dokumentumtárat kapja (K5)
- [x] (offline) Dokumentumok a PC-ben: `med_docs` beágyazott mód (`openDocuments(filter, { embed = true })`, `setDocumentsRect`, `setDocumentsFilter`)
- [x] (offline) Görgetés: render target vágás, sima görgetés, húzható görgetősáv, PgUp/PgDn/Home/End/nyilak, görgő csak a lista / papír felett; medsys `getECG12Sheet` export az EKG-laphoz
- [x] (offline) Papír-design az eredeti minta szerint: ritkított aláhúzott cím, aláhúzott szakaszcím (h5), vonal az adatblokk után, behúzott szöveg, pontozott aláírás, lábléc vonallal; szürke sáv csak a mentési lapon
- [x] Hordágy marker: a külön képernyő-felirat törölve, a marker kártya mondja az E-t
- [x] (offline) EKG-12: elektróda 22 / 16 px, körvonalas felirat, nagyobb test; Ápoló / Rezidens: célhelyek felirattal, a megfogott elektróda helye pulzál (K7)
- [x] (offline) Vizsgálati panel: lelet nyitva csak a lelet látszik (X / ESC vissza), más dialógusnál nincs hover; X bezáró gomb jobb felül
- [x] (offline) Sikertelen minigame: nincs eredmény / pont / dokumentum, újra megcsinálható; az anyag csak sikerkor fogy (K3), drain érsérülés vérzése marad (K4)
- [x] (offline) Átadás: 3 mp a markerben hordággyal, kártya-visszaszámlálás, utána elengedés + átvétel, minden átadó ponton (K6)
- [x] (offline) Pontok ×5 (`ERC.POINT_MULT`), a dokumentumok pont-oszlopa is; a care érték az alappontból (K1)
- [x] Súgó (panel, docs, ecg, ward, overview, pay hu + en), bemutató PC-szöveg, README-k
- [ ] Élő teszt: v_locals restart (új kulcsok), med_hospitals + med_docs + med_equipments + medsys + mg_ecg restart, amikor nincs játékos
- Eltérés a tervtől: a Win7 PC betűje Roboto maradt (a Selawik letöltéséhez külön engedély kellene)

---

## Session-napló

| Dátum | Session | Mi történt |
|---|---|---|
| 2026-11-05 | 1. | Terv 1. és 2. kör, MCP mérés, döntések K1–K41, Ú1–Ú12 |
| 2026-11-06 | 2. | Végrehajtás elkezdve (work_hospital, er/ modul, med_docs, 8 minigame offline), PC-k, marker-kártyák |
| 2026-11-06 | 3. | Audit: a rendszer félkész, hibalista; új döntések (röntgen monitor, scenemanager átírás, jogok szétválasztása); ez a fájl létrehozva. Végrehajtás a felhasználó engedélyére vár. |
| 2026-11-06 | 4. | F0–F8 végrehajtva (F7: műtő / intenzív / halott / áthelyezés; F8: dokumentumok, gov_health, vizsgák, bemutató, súgó). Offline unit-teszt (OR / ICU 11/11), lupa 190 fájl hibátlan, minden érintett resource újraindítva hibátlanul, v_locals újraindítva. F9 élő teszt: nincs csatlakozott kliens (Laptop112). |
| 2026-11-06 | 5. | 3. kör: terv + képes tervek (artifact), majd végrehajtás (F10): Win7 PC, beágyazott dokumentumok, görgetés, papír-design, tablet dokumentáció nélkül, EKG súgó, átadás 3 mp, sikertelen minigame újra, pontok ×5. Offline: lupa szintaxis, kliens füstteszt 34/34, szürke sáv teszt, szerver teszt 16/16. Élő teszt nincs. |
