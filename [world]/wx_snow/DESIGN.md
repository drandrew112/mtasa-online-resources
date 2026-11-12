# wx_snow – hórendszer

Állapot: **F1–F5 megépítve 2026-11-12, offline tesztelve** (Lua szintaxis + logika + szerver mock: `python tests/test_snow.py`; shaderek `fxc /T fx_2_0` fordítással). Játékban még nem futott. A járművek (9. fejezet) csak terv.

## 1. Célok

- A világ (int 0 külső terület) havas lesz, **6 szinten** (0–5), fokozatos felhalmozódással és olvadással.
- Beállítás: **v_admin → Weekly oldal → Snow fül** (a heti event része, `v_weekly` `custom.snow`).
- Teszt: **`/snow`**, `/snowbake`, `/snowtest`, admin_level >= 5.
- **Beltérben nincs hó**: GTA interiorok (int ≠ 0), maps_loader `indoor` zónák, fedett részek (híd alja, alagút, benzinkút-tető – roof map).
- Kompatibilis a `[graphics]` shaderekkel (3. fejezet).

## 2. Szintek (`shared/config.lua` `SNOW.LEVELS`)

| Szint | Név | Borítás | Pelyhek | Szél m/s | Köd m | GTA weather | Fű (tx*) |
|---|---|---|---|---|---|---|---|
| 0 | Off | 0 | – | – | – | eredeti | – |
| 1 | Flurries | 0 (nedves út) | 0.18 | 0.8 | – | 12 | marad |
| 2 | Light snow | 0.32 | 0.35 | 1.0 | – | 12 | fehér |
| 3 | Snowy | 0.62 | 0.55 | 1.4 | 900 | 15 | fehér |
| 4 | Heavy snow | 0.85 | 0.8 | 2.2 | 480 | 9 | rejtve |
| 5 | Blizzard | 0.96 | 1.0 | 7 (+4 lökés) | 170 | 9 | rejtve |

- **Felhalmozódás** (`shared/coverage.lua`): a borítás 0→1 `ACCUM_MIN` (20 perc), 1→0 `MELT_MIN` (40 perc) alatt mozog. A szerver csak `{level, from, at}` + a szerver órát küldi (`wx_snow:state`), a kliensek számolnak. Szerver induláskor és a `/snow` parancsoknál (kivéve `slow`) azonnal a célon van; a heti event váltásai mindig fokozatosak.
- **Dinamikus hét**: a heti szint 3 óránként −1 / 0 / 0 / +1 (min. 1, max. 5), a sorrend a week_start-ból jön, minden instance ugyanazt látja. A szerver percenként ellenőrzi.

## 3. Kompatibilitás

MTA-ban egy textúrán csak egy nem-layered shader rajzolódik; a shader_detail nem-layered, a dynamic_lighting world shadere layered.

**A talajhó layered world shader** (`fx/snow_world.fx`, prioritás 0, távolság korlát nélkül, `"world,object"`): alpha-blendelt plusz passz, semmit nem cserél le. A hó a GTA épület-megvilágítást (`MTACalcGTABuildingDiffuse`) és a GTA ködöt kapja, a mélység ugyanazzal a biasszal megy, mint a dynamic_lighting rétegé. Az alap textúra alfája alatt (lomb, kerítés, rács) `clip`.

**Ellenőrizendő játékban**: a dynamic_lighting fényei és a hó réteg sorrendje (éjjel ELS / lámpák a havon).

Hómaszk: `smoothstep(1-c±0.11, zaj*0.85 + up*0.15) * up` × (1 − tető alatt) × (1 − indoor doboz); `up` = a felület normáljának z-je a kategória `upLo/upHi` küszöbei közt (több hónál lejjebb csúszik). Ahol nincs hó, `wet` sötétít.

**Normál (2026-11-12 javítás)**: a GTA épületeknek sokszor nincs (vagy rossz) vertex normálja, ettől a falak is fehérek lettek. Most a pixel világpozíciójának deriváltjaiból (`ddx/ddy`) számolt lapnormál dönt, a kamera felé fordítva (plafon alulról lefelé néz → nincs hó); a sima vertex normál csak ott, ahol egyezik a lappal.

**Utak – keréknyomok**: sávtérkép (`tools/build_roadmap.py` a GTA `data/Paths/NODES*.DAT` navi node-jaiból: sávszám bal/jobb, 5 m sáv, középsáv szélesség; ellenőrzés: `python tests/check_roadmap.py`). Format 3: 4 m cellánként a legközelebbi útszakasz (link) EGYENESE két magassági rétegben – `roadmap.png` (legközelebbi), `roadmap2.png` (legközelebbi, ami ≥ 4 m-rel magasabb/alacsonyabb: felüljáró / aluljáró), `roadmapz.png` (a két réteg útmagassága). Cella: RG = a cellaközép előjeles távolsága a középvonaltól (16 bit, ±32 m), B = normál iránya, A = bal sávok + jobb sávok×4 + középsáv fél szélesség/0.5×16. A shader pont mintavétellel azt a réteget veszi, amelyik útmagassága ±3.5 m-en belül van a pixelhez, és pixelenként pontos oldaltávolságot számol. A link teljes keresztmetszete (bal sávok, középsáv, jobb sávok) a navi vonalra KÖZÉPRE igazított (a reptéri 2+2-es úton mérve: két egyirányú link 15 m-re, köztük 5 m elválasztó). Korábbi hibák: interpolált sávkoordináta → „C” csíkok; egyoldalra rakott sávok → rossz 2×2-es utak; 2D térkép → felüljáró nyomai az alatta futó úton. Linkek találkozásánál kanyarban kis lépcső maradhat. A shader sávonként két keréknyomot rajzol (a sáv 0.32 / 0.68-ánál, kicsit kanyargó, az út irányában nyújtott csíkos zajjal), a nyomban nedves aszfalt látszik, a sáv közepe letaposott szürke latyak, a sávszéleken félretolt hó. 5. szinten a nyomok részben visszatelnek. Út a sávtérképen kívül (parkoló): sima hó.

Kategóriák (`SNOW.CATEGORIES`, mindegyik külön shader példány, egy textúra csak egyet kap): generic `*`, soft (fű/föld/homok), road, pavement, foliage. Kizárás: `SNOW.EXCLUDE` (dynamic_lighting removeList + víz, üveg, lámpák, árnyékok, effektek). GTA fű `tx*`: `fx/snow_grass.fx` (nem-layered, prioritás 5) fehérít / elrejt.

Egyéb: köd `drawdistance:setFogOverride` (új export), színek `shader_colors:pushColorOverride("wx_snow")`, szélhang `sounds/wind_loop.wav` (generált). Mind csak kint.

## 4. Beltér kizárása

1. **Kamera / játékos interior ≠ 0** → a talaj shaderek borítása és nedvessége 0 (minden pixel `clip`, ugyanazok a textúranevek bent is vannak), pehely 0, köd/szín/hang ki. A shaderek nem semmisülnek meg, így kilépéskor azonnal ott a hó; az interior/dimenzió váltást esemény jelzi, nem kell a következő ellenőrzésre várni. Kilépéskor a hóesés, a köd és a színek is azonnal váltanak (nincs 6 s-os beúszás).
2. **world_interiors**: int ≠ 0 → az 1. pont. Ha egy regisztrált interior int 0-ban van, a `/snowtest interiors` FAIL-lel jelzi.
3. **maps_loader indoor zónák**: új kliens export `maps_loader:getIndoorZones(all)`. A legközelebbi 4 doboz a talaj shaderbe, 2 a pelyhekbe megy: a dobozon belüli pixel / pehely nem kap havat (a doboz teteje 0.25 m-rel lejjebb, hogy a tetőn maradjon hó). Ha a kamera dobozban van → nincs hóesés / köd / szín, de a talaj shaderek dolgoznak tovább, így az üvegajtón kinézve kint havas minden.
   - Eltérés a tervtől: per-objektum shader levétel helyett doboz-maszk, mert az a „keep” héjak padlóját és a GTA épületek padlóját is lefedi.
4. **Fedett részek**: roof map (5).
5. **`SNOW.CLEAR_AREAS`**: mindig hómentes dobozok (talaj + pelyhek), a kamera ott „kint” marad. Most: All Saints mentőbeálló.
6. **`SNOW.ZONE_MASKS`**: térképenként saját maszk dobozok a maps_loader `indoor` dobozai helyett (azok gyakran kilógnak a falon túl). Most: ls_allsaints = az ER padló (med_hospitals er.zone).
7. **Ha a roof map be van sütve**, a maps_loader dobozai már nem maszkolnak a talajon (a tető alatti padlót a roof map pontosan tudja), csak a kamera „bent” állapotát adják. Sütés nélkül a kilógó dobozok alatt (sárga a `/snow debug`-ban) kint sincs hó.

## 5. Roof map

- `data/roofmap.png` (RG = 16 bites legfelső felület magasság, -60…1000 m) + `data/roofmap.json`. Amíg nincs sütve (placeholder, `cells = 0`), semmi nem számít fedettnek, a kamera fedettségét egy felfelé lőtt line of sight dönti el.
- **Sütés** `/snowbake start` (admin kliensen, gyalog): 6144 m², 4 m cella (1536²), 64 cellás csempék (576 db). Csempénként a fagyasztott játékos + kamera odamegy (collision + maps_loader objektumok streamelése, `WAIT_MS` 1.6 s), cellánként 4 lefelé sugár (±1 m), a cella értéke a **legalacsonyabb** első találat (fal melletti föld nem lesz fedett; ha egy minta vizet / semmit lát, a cella nyitott). Kb. 20–25 perc. `stop` szünetel, `start <csempe>` folytat, `save` a meglévőből épít. A végén plain pixel → PNG, 450 KB-os latent darabokban a szerverre (`server/bake.lua` írja), majd **wx_snow restart** kell, hogy mindenki megkapja.
- Shader: 2×2 cella, a „fedett” eredményen bilineáris (puha 4 m-es szél), tolerancia 1.6 m. Pelyhek és rétegek ugyanígy takarva.
- Pályák változásakor újra kell sütni.

## 6. Hóesés (`client/precip.lua`)

- **Közeli pelyhek**: statikus vertex kötegek (400 pehely / draw), `dxDrawMaterialPrimitive3D` + `fx/snow_flakes.fx`: hullás + szél (Lua-ban halmozott drift), lengés, kamera körüli 36×36×22 m dobozba csomagolás, billboard, roof map / indoor doboz takarás. High 1400, Low 500 pehely.
- **Rétegek**: 4 henger (4 / 9 / 18 / 34 m, Low: az első 2) görgetett hó-textúrával, rétegenként külön shader.
- Kamera tető alatt → elhalványul (`PRECIP_FADE` 6 s), beltérben azonnal 0. Szél iránya lassan vándorol + lökések, a szerver órájából (minden kliensen hasonló).

## 7. Minőség

ui_pause Graphics → **Snow**: High / Low / Off (`gfx_snow`, fiókon mentve; a wx_snow saját `@quality.txt`-ben is). Low: nincs csillogás, kevesebb pehely és réteg. Off: semmi.

## 8. Vezérlés

### Heti event
- `v_weekly:setWeekValue(offset, "snow", { level, dynamic })`; a wx_snow az `onWeeklyChanged`-re és induláskor olvassa (`getCurrentWeek`). Hétváltás törli a `/snow global` overridet.
- **v_admin Weekly → Snow fül**: szintgombok (Off … Blizzard), Dynamic kapcsoló, szintleírás, „Preview (only me)” / „End preview” (csak az admin kliense). Szerver action: `edit { action = "snow", a = level, b = "1"/"0" }`.
- A heti panel kap egy „Weather of the week” sort, a Discord embed egy „❄️ Weather” mezőt.

### Parancsok (admin_level >= 5)
| Parancs | Hatás |
|---|---|
| `/snow` | szerver + saját kliens állapot (szint, borítás, hátralévő idő, hely, shaderek, roof map, pelyhek) |
| `/snow <0-5> [slow]` | csak saját előnézet, azonnal (`slow`: 20 perces lerakódás) |
| `/snow cover <0-1>` | saját borítás rögzítve |
| `/snow reset` | előnézet ki |
| `/snow global <0-5> [slow]` / `/snow global reset` | mindenkinek, hétváltásig, azonnal (`slow`: fokozatosan) |
| `/snow debug` | kategória nézet: piros út, narancs járda, zöld puha, türkiz lomb, kék egyéb, lila fedett, sárga indoor doboz |
| `/snow quality off/low/high` | mint az ui_pause |
| `/snowbake start [csempe] / stop / status / save` | roof map |
| `/snowtest interiors / zones / tour / stop` | automata tesztek (10) |

Exportok – szerver: `getSnowLevel`, `getSnowCoverage`, `isSnowing`, `setSnowOverride(level|false, instant)`; kliens: `getSnowLevel`, `getSnowCoverage`, `isSnowing`, `isSnowVisibleHere`, `getSnowDebugState`, `get/setSnowQuality`, `setSnowPreview(level|false, instant)`.

## 9. Járművek – csak terv

- **Vizuális**: layered vehicle shader (a dynamic_lighting vehicle és a v_paintjobs shaderek nem-layered → csak layered fér mellé). Hó a felfelé néző paneleken a `vehicleSnow` element data szerint: állva, kint, leállított motorral nő; vezetés közben / fedett helyen (roof map) olvad. Szélvédő-törlő maszk később.
- **Fizika**: szintenkénti handling szorzók (`tractionMultiplier`, `tractionLoss`, fék) szerveren, `veh_manager`-en át, hogy ne ütközzön a v_customs tuninggal; téli gumi v_customs alkatrészként. Jobs (race/DM) dimenziókban kikapcsolva.
- **AI**: ai_land_traffic sebesség- és követési táv szorzó 4–5. szinten.
- **Effektek**: kerék hópor, keréknyom decal közelben.

## 10. Tesztelés

1. **Offline**: `python tests/test_snow.py` – minden érintett Lua fájl fordul (lupa lua51), coverage/dinamikus logika, szerver állapotgép mockolt MTA-val (heti érték, override, hétváltás, jogosultság, időjárás visszaállítás). Shaderek: `fxc /T fx_2_0`.
2. **`/snowtest interiors`**: minden world_interiors belső: 5. vs 0. szint képernyő-diff a kép közepén (átlag < 2.5, változott pixel < 1 %) + állapot (indoor, nincs talaj shader, 0 pehely). Eredmény: F8 konzol + `@wx_snow_interiors.json`, hibánál `@shots/fail_<id>.png` (a kliens wx_snow privát mappájában).
3. **`/snowtest zones`**: ugyanez minden maps_loader indoor dobozra (int 0).
4. **`/snowtest tour`**: 40 külső pont (LS, SF, LV, vidék, Chiliad, sivatag, híd, benzinkút-tető…), esetek: nappal 0/2/4/5, éjjel 4. FPS, a kép „hófehér” aránya, képernyőkép `@shots/<pont>_<eset>.png`, jelentés `@wx_snow_tour.json`; a végén átlagos FPS-esés és a kevés havat mutató pontok listája.
5. Kézi: `/snow debug` (kategóriák, fedett, indoor), shader_detail be/ki, éjjeli ELS fények, shader_colors presetek, drawdistance min/max.
6. FPS cél: High 3. szinten ≤ 10 %, 5. szinten ≤ 15 %.

## 11. Fájlok

```
[world]/wx_snow/
  meta.xml, locals.lua
  shared/config.lua      szintek, kategóriák, kizárások, roof map + hóesés beállítások
  shared/coverage.lua    borítás / dinamikus hét (szerver + kliens)
  server/state.lua       heti érték, override, dinamikus hét, sync, weather, exportok
  server/commands.lua    /snow, /snowbake, /snowtest, wx_snow:testMove
  server/bake.lua        roof map feltöltés -> data/
  client/state.lua       állapot, előnézet, minőség, hely (interior / zóna / fedett), /snow kliens rész
  client/roofmap.lua     roof map betöltés, heightAt, shader paraméterek
  client/ground.lua      talaj shaderek, kategóriák, fű, dobozok
  client/precip.lua      pelyhek + rétegek
  client/env.lua         köd, színek, szélhang
  client/bake.lua        /snowbake
  client/debug.lua       getSnowDebugState
  client/tests.lua       /snowtest
  fx/  snow_world.fx, snow_flakes.fx, snow_layer.fx, snow_grass.fx, mta-helper.fx
  tex/ noise.png, flake.png, layer.png      (tools/make_assets.py)
  sounds/wind_loop.wav                      (tools/make_assets.py)
  data/roofmap.png + roofmap.json           (placeholder; /snowbake)
  tests/test_snow.py
Módosult: drawdistance (setFogOverride/getFogDistance), maps_loader (getIndoorZones), v_weekly (snow a payloadban,
          panel sor, Discord mező, admin overview), v_admin Weekly (Snow fül + snow action), ui_pause (gfx_snow),
          v_locals (wx_snow en/hu + v_admin/v_weekly/ui_pause kulcsok, meta.xml)
```

## 12. Döntések (a nyitott kérdésekre az alapértékek)

1. „exterior” = beltér (interior) értelmezés.
2. `/snow <szint>` csak saját előnézet, mindenkinek `global`.
3. Roof map 4 m.
4. Dinamikus hét benne van (kapcsolható).
