# wx_snow – hórendszer

Állapot: **alaprendszer (F1–F5) 2026-11-12, Hó 2.0 (új talajhó, utak, hóesés rétegek) 2026-11-13 (a jármű-hó elvetve, 9. fejezet), offline tesztelve** (Lua szintaxis + logika + szerver mock: `python tests/test_snow.py`; shaderek `fxc /T fx_2_0` fordítással). Játékban csak részben látott (lásd a fejezetek végén, mi nem). A kereszteződések 2026-11-13 óta pályalistás, analitikus Bézier-nyomokkal rajzolódnak (3. fejezet vége, "Kereszteződések 2.0"), offline mérve, játékban nem látott.

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

**F1 gyorsítás (2026-11-13, a kép ugyanaz, olcsóbb)** – `fx/snow_world.fx` (v2), a régi `fx/snow_world_v1.fx` A/B méréshez megmaradt (`/snow shader v1|v2`, csak a saját kliensen):
1. Deriváltak előre (normál, textúra- és világkoordináta-gradiens), az ágakban minden olvasás `tex2Dgrad` / `tex2Dlod`.
2. Korai kilépés valódi `[branch]`-csal: nincs mit rajzolni, a pixel a **köd vége** mögött van (`gFogEnd`, a pixel ott ködszínű), vagy a felület nem hóképes és nem is nedvesedhet (fal, alsó lap; `up` és `flat` alapján). Ezekre nincs textúraolvasás, zaj, roof map.
3. Távolsági szintek (`SNOW.LOD`, Low-on ×0,6): a legfinomabb zaj-oktáv 100 m-ig (utána a textúra átlaga), a középső 300 m-ig, a csillogás 30 m-ig, a sávlookup 70 m-ig teljes és 110 m-nél kikeveredik, a roof map 80 m-ig bilineáris (4 minta), 250 m-ig 1 pont-minta, azon túl nincs.
4. A roof map és az indoor dobozok csak ott futnak, ahol a pixel havat vagy nedvességet kapna (vagy debug nézet van).
5. Lomb kategória: `maxDist` 110 m a shader létrehozásakor, Low-on nincs lomb hó (a `"*"` shader is lemond a lomb textúrákról).
Eltérés a képtől: távoli (>70–110 m) úton nincs kerékcsík / latyak, 100 m-nél messzebb nincs finom zaj, 80 m-nél messzebb pont-mintás a roof map éle, a sávzaj gradiensei most analitikusak (nincs csík a 4 m-es sávtérkép-cellák határán). A ködlevágás csak akkor jó, ha a `FOGEND` render state a valódi köd vége; ha játékban a messzi hegyek elvesztik a havat, ez a gyanús.

**F2 / F3 új kinézet (2026-11-13, `fx/snow_world.fx` v2, játékban nem látott)**:
- Nincs 23 m ismétlődés: a nagy oktávok az új `tex/macro.png`-ből (1024², 256 m / ismétlés, `python tools/make_assets.py --macro-only`) jönnek lassú domain warp-on át, a második oktáv 31°-kal elforgatva, más skálán. A finom szemcse marad a `noise.png`.
- Vastagságmodell: küszöb a zajon (+ az alap textúra világossága 6 %-ban, így a fűcsomók és repedések vékony hóból kilátszanak), vékony szélen sötétebb kékes perem az alap színével.
- Fény: a GTA vertex fényből csak a **fényerő** számít (a meleg árnyalata krémszínűvé tette a havat), árnyékban kék, napkeltekor / napnyugtakor meleg (`gSunWarm`), közeli mikro-relief a nap irányával (`gSunDir`, játékidőből). Az ég horizontszíne (`gSky`, `getSkyGradient`) tükröződik a nedves úton.
- Utak: hóhányás a sávtérkép link szélén (`edgeD`), latyak a kerékcsík körül, a kerékcsík-nyom tükröz.
**F4 hóesés**: a 4 hengerréteg 2 henger lett, mindegyik két réteget hordoz (a második ugyanaz a nézősugár a szélesebb hengeren, saját textúraskála / görgetés / alfa): fele akkora teljes képernyős overdraw. Low: 1 henger (r 4 + 9, mint eddig).
**Diagnosztika**: `/snowtest cost` (aktuális helyen, nappal, 4. szint): hómentes / minden / csak hóesés / csak talaj / talaj lomb nélkül FPS, `@wx_snow_cost_<variant>.json`. Az első mérés (v2, tour) szerint a 2., 4., 5. szint és az éjjel ugyanannyit esik (kb. 72 → 48 FPS): ez nem pixelköltség, hanem fix (draw call / frame limiter lépcső), ezért ezt kell szétszedni.

**Mérés játékban (2026-11-13, később)**: a `/snowtest cost` új száma (nem szétszedett, 4. szint, nappal): hómentes 73,2 FPS, csak hóesés 73,1, talaj generic korlátlan 70,2 / 250 m 71,5 / 120 m 72,1 / 60 m 72,0 / generic nélkül 72,4, minden együtt 69,7 (≈ −5 %). A korábbi ~41 FPS egy másik helyen / az F4 előtti állapotban volt. A generic `maxDist` marad 250 m. `/snowtest tour` (4. szint, 11 hely): átlag −0 %.
**Fű (2026-11-13, a mérés után)**: játékban még mindig túl világos volt, ezért a fagyás fehérsége `min(0,6, 0,85 × borítás)` (volt 0,8 / 1,1), a szín sötétebb (`snow_grass.fx` 0,76 / 0,79 / 0,85 szorzó + a penge saját árnyalatának 22–30 %-a). Játékban nem látott.

**Javítás 2026-11-13 a játékbeli képek után**: (1) `/snowtest cost` eredmény: hómentes ~71 FPS, csak hóesés ~65, **csak talaj ~41**, talaj lomb nélkül ~45 => a fix költség a talaj shaderek másodszori rajzolása (a `"*"` generic minden textúrát), nem a pixel. A generic kategória `maxDist` = 250 m (`SNOW.CATEGORIES[1]`), a `/snowtest cost` 250 / 120 / 60 m-t és a generic nélküli esetet is méri; a végleges érték ebből jön. (2) Fű: a fehér penge csupasz talajon világított (a 2. szinten 0,85 fehér, a talaj alig havas), most a fagyás a talaj borításához kötött (`min(0.8, 1.1 × borítás)`, a "hide" szinteken 0,6–0,8 borítás közt zsugorodik el), a talaj havával azonos fényszámítás (`gSunWarm`). (3) Utak: a vékony kék perem csak a hó legszélén (nem az egész úton), az utak a v1-hez hasonló lágy fedést kapnak (2. szinten sem csupasz), kevésbé kék árnyék. `/snow debug`: zöld árnyalat = a sávtérkép ismeri az utat.

**Kanyarok és kereszteződések (2026-11-13, `tools/build_roadmap.py`, újraépítve a `data/roadmap*.png`)**: (1) A hosszú link (átlag 13 m, ritkán 40 m) egy görbe húrja, a navi pont az úton van, akár 2–5 m-re a húrtól. A lépcsőt az okozta, hogy a szomszédos linkek sávjai a saját navi vonaluk köré voltak rendezve. Most az a link, amelynek navi pontja ≥ 0,15 m-re van a húrtól, két darab lesz (A → navi pont → B), a sávok ezt a megtört vonalat követik, a csomópontok közösek. (2) A link végén túl a lateralis távolság a végpontig mért előjeles euklideszi távolság (kerek illesztés), a `B` csatorna a távolság gradiensének irányát tárolja. (3) Kereszteződés: ahol két, > 35°-ban eltérő irányú, azonos magasságú link sávja fedi egymást (6573 cella), a cella kódja 16 (nincs sáv): a shader nem rajzol kerékcsíkot, hanem letaposott havat (`packed` 0,85, `/snow debug`-ban szürke-zöld). Mérés: `python tools/build_roadmap.py`, a régi és új térkép összevetése a kanyar- és kereszteződés-rajzokkal volt (nem automata teszt).

**Sávtérkép nem töltődött be (2026-11-13)**: a kliens logban (`clientscript.log`) `/restart wx_snow` után többször: `DxCreateTexture Failed to create texture from file 'data/roadmap.png'` (vagy `roadmapz.png`), "may be corrupt, unsupported format, or out of memory". A térkép és a shader rendben volt, a 32 bites kliens memóriája fogyott el (3 × 1536² sávtérkép + roof map + macro zaj, az újraindításkor a régi még él). Sávtérkép nélkül nincs kerékcsík. Most: a betöltés 2,5 s-onként legfeljebb 8-szor újrapróbál, a resource leállításakor azonnal felszabadítja a textúrákat, a `/snow debug` konzolsora kiírja, betöltődött-e a sávtérkép. Ha így sem tölt be: a játék kliens újraindítása.

**Sávtérkép streamelve (2026-11-13)**: a kliens a három 1536²-os képet (28 MB) már nem tölti be. A shader a sávtérképet csak 110 m-en belül olvassa, ezért a kliens egy 128 × 128 cellás (512 m) ablakot tart a kamera körül (3 textúra, 64 KB-os egyenként), és a `data/road/c_<cx>_<cy>.png` chunkokból (256 × 256 cella, a 3 réteg egymásra rakva, 36 db, összesen 1,4 MB) tölti: a kamera 32 cellánál (128 m) közelebb ér az ablak széléhez => újratöltés, 8 sor / frame, a háttérben (`client/roofmap.lua` ROAD). A shader változatlan, a `gRoadRect` az ablakot írja le. A `tools/build_roadmap.py` írja a chunkokat és a `meta.xml` `ROAD CHUNKS` blokkját; a teljes `roadmap*.png` csak a `tests/check_roadmap.py`-hoz marad. Teszt: `python tests/test_roadwindow.py` (az ablak pixelre egyezik a teljes képpel, 5 kamerapozícióra, chunkhatáron és a térkép szélén is). A roof map hasonló ablakra váltása a következő lépés lehet (baked állapotban az 9,4 MB + pixelmásolat).

**Egyedi útmodellek (2026-11-13)**: ahol a v_modloader saját útmodellje máshogy vezeti az utat, mint a GTA útvonal-csomópontjai, a sávtérkép a `data/road_custom.json`-ból javít (`tools/build_roadmap.py` `apply_custom`): egy területen eldobja azokat a GTA linkeket, amelyeknek mindkét vége a dobozban van, és a megadott vonalláncokból új linkeket rak (pontonként `[x, y, z, bal sáv, jobb sáv, középsáv fél szélesség]`, a sávok a pontból induló darabé). `caps: [eleje, vége]` = false: a lánc azon a végén nem foglal cellát a végpont mögött (nincs kerek illesztés, ami egysávos láncnál kis gyűrűket rajzolna). Első eset: 4139 `Roads09_LAn` (Commerce, 1374..1435 / -1446..-1392): a GTA két egyirányú, derékszögű ága helyett egy S-ív, a középvonal a modell COL aszfaltjából mérve; játékban jóváhagyva. Új egyedi útnál: a COL tarmac lapjaiból mért középvonal + szélesség, aztán `python tools/build_roadmap.py`, `python tools/render_junction.py x,y,z --size 100` ellenőrzésre. Ugyanehhez a modellhez: `lan_merge` az út, `*grssdrt*` a soft kategóriába került.

Egyéb: köd `drawdistance:setFogOverride` (új export), színek `shader_colors:pushColorOverride("wx_snow")`, szélhang eltávolítva (2026-11-12, kérésre; a wav már nincs a meta-ban). Mind csak kint.

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
| `/snowtest interiors / zones / tour / cost / stop` | automata tesztek (10) |

Exportok – szerver: `getSnowLevel`, `getSnowCoverage`, `isSnowing`, `setSnowOverride(level|false, instant)`; kliens: `getSnowLevel`, `getSnowCoverage`, `isSnowing`, `isSnowVisibleHere`, `getSnowDebugState`, `get/setSnowQuality`, `setSnowPreview(level|false, instant)`.

## 9. Járművek

### Jármű-hó: ELVETVE (2026-11-13)

A járművenkénti hó shader (layered shader, `vsA` / `vsT` állapot, `SNOW.VEHICLE`, `/snowtest vehicles`) teljesen ki lett véve: nem sikerült szépre megcsinálni. Nincs jármű-hó kód, shader, config vagy teszt; ha újra előkerül, tiszta lappal indul.

### Még csak terv
- **Fizika**: szintenkénti handling szorzók (`tractionMultiplier`, `tractionLoss`, fék) szerveren, `veh_manager`-en át, hogy ne ütközzön a v_customs tuninggal; téli gumi v_customs alkatrészként.
- **AI**: ai_land_traffic sebesség- és követési táv szorzó 4–5. szinten.
- **Effektek**: kerék hópor, keréknyom decal közelben.

## 10. Tesztelés

1. **Offline**: `python tests/test_snow.py` – minden érintett Lua fájl fordul (lupa lua51), coverage/dinamikus logika, szerver állapotgép mockolt MTA-val (heti érték, override, hétváltás, jogosultság, időjárás visszaállítás). Shaderek: `fxc /T fx_2_0`.
2. **`/snowtest interiors`**: minden world_interiors belső: 5. vs 0. szint képernyő-diff a kép közepén (átlag < 2.5, változott pixel < 1 %) + állapot (indoor, nincs talaj shader, 0 pehely). Eredmény: F8 konzol + `@wx_snow_interiors.json`, hibánál `@shots/fail_<id>.png` (a kliens wx_snow privát mappájában).
3. **`/snowtest zones`**: ugyanez minden maps_loader indoor dobozra (int 0).
4. **`/snowtest tour`**: 40 külső pont (LS, SF, LV, vidék, Chiliad, sivatag, híd, benzinkút-tető…), esetek: nappal 0/2/4/5, éjjel 4. FPS, a kép „hófehér” aránya, képernyőkép `@shots/<pont>_<eset>.png`, jelentés `@wx_snow_tour.json`; a végén átlagos FPS-esés és a kevés havat mutató pontok listája.
5. Kézi: `/snow debug` (kategóriák, fedett, indoor), shader_detail be/ki, éjjeli ELS fények, shader_colors presetek, drawdistance min/max.
6. FPS cél: High 3. szinten ≤ 8 %, 5. szinten ≤ 12 % (szigorítva 2026-11-13, korábban 10 / 15 %).
7. **A/B mérés (F0 / F1)**: ugyanazon a gépen, ugyanabban a menetben: `/snow shader v1`, `/snowtest tour`, majd `/snow shader v2`, `/snowtest tour`. A jelentés `@wx_snow_tour_<v1|v2>_<quality>.json`, a konzolon minden esetre (d0, d2, d4, d5, n4) átlag FPS és az esés a hómentes d0-hoz képest. A képernyőképek (`@shots/<pont>_<eset>.png`) a két menet közt felülíródnak, a v1 képeit előtte másold el.


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

**Sima aszfalt nem kapott kerékcsíkot (2026-11-13)**: a sávtérkép betöltődött (`clientscript.log`: `lane map window filled`), mégsem látszott nyom. Ok: a LS úttestek aszfaltja `greyground256` (a `*road*` textúrák csak a felfestések / kereszteződések), ami a `generic` kategóriába esett (`road = 0`). Javítás: új `roadplain` kategória (`road = 2`, `greyground256`), a shaderben az útkinézet a sávtérkép szerint keveredik (`roadW`: sávon / kereszteződésben úthatás, máshol sima hó, mert a textúrát terek és parkolók is használják).

**Valódi ok: a három ablak-réteg ugyanaz volt (2026-11-13)**: `exports.wx_snow:getSnowRoadSample(x, y)` (új, `client/debug.lua`) az ablak tényleges pixelét adja vissza: mindhárom réteg a magasság-réteg adata volt (`17,123,0,0`), a sáv-réteg alfája 0, így a shader sosem látott sávot. A kliensben a három `dxGetTexturePixels` hívás ugyanazt a puffert adta, az utolsó (magasság) írta felül a másik kettőt. A `fillJob` ezért Lua táblákba gyűjt, és rétegenként olvas / ír vissza. Élő ellenőrzés: 25 minta (chunkhatárokon is) pixelre egyezik a `data/road/c_*.png`-vel, a kerékcsík megjelent. Az offline `tests/test_roadwindow.py` mockja nem modellezi a közös puffert, ezért nem fogta meg.

**Kanyarodó pályák a kereszteződésekben (2026-11-13, `tools/build_roadmap.py`, újraépítve a `data/roadmap*.png` + chunkok)**: a kereszteződés-cellák (kód 16) eddig egyszínű letaposott hó voltak. Most minden összefüggő kereszteződés-folt (`_label_junctions`, 8-szomszédos, 1 cellával növelve, hogy az osztott pálya két négyzete egy legyen) KÜLSŐ karjaiból (a link vége a foltban, a másik vége kint; a belső rövid linkeket kihagyja, mert az osztott pályás kereszteződés több navi csomópont) pályákat épít: minden bejövő sávtól minden kimenő sávig négyzetes Bézier (áthaladás, jobb és bal kanyar, U-kanyar nincs). A belépési pont az a hely, ahol a kar sávvonala az első kereszteződés-cellát eléri. A pálya 2,5 m-es, 1 sávos darabokból áll (kód 4), a kereszteződés-cella a legkisebb távolság × büntetés szerinti darabot kapja (egyenes ×1, jobb ×1,3, bal ×2; `TURN_PEN_*`), 3 m-en túl marad a 16-os kód (letaposott hó). A shader nem változott. Fontos adatfelismerés: a navi link JOBB sávjai a navi irányban, a BAL sávjai azzal szemben haladnak (egy osztott pálya egymás utáni linkjeinek navi iránya eltér, a sávok mindig ugyanazon az oldalon vannak), az egyirányú karok forgalomirányát ebből kell venni (`_arm_lanes`). Eredmény: 6573 kereszteződés-cellából 5393 kap kanyarsávot. Korlát: a térkép 4 m-es cellánként egy irányt tárol, ezért a kereszteződésben a nyomok foltokban váltanak irányt (felülnézetben négyzetes darabok). Kirajzolás offline: a `render_junction.py` típusú dekódolás (`tests/check_roadmap.py` logikája).

**Kereszteződések 2.0 (2026-11-13, format 4; terv: https://claude.ai/artifact/L41fgcC52aDT1EFy2ZfHqL, C megoldás)**: a régi módszer (cellánként egy egyenes, a legközelebbi kanyarpálya-darab) a cellahatárokon elvágta a nyomokat, felülnézetben 4 m-es négyzetes foltok lettek. Most:
- **Builder** (`tools/build_roadmap.py`): minden pálya egy négyzetes Bézier-rekord (`data/road/jpaths.png`, pályánként 4 texel: origócella + típus + a be- és kilépő kar zajkeretének iránya, p0/p1/p2 relatívan ±64 m, 16 bit = 2 mm). A belépési pont ott van, ahol a kar sávvonala a keresztező kar útsávjába ér, onnan 1 + 4 m-rel kijjebb (átfedés a kar sávjaival). Ha nincs keresztező kar: majdnem párhuzamos kar (elágazás), az első foltcella, végül a csomópont. A csomóponti maszk a régi folt és a geometriai mag (két eltérő irányú kar útsávjának metszete) uniója. A maszkcellák és az 1 cellás gyűrű cellái pályalistát kapnak (`data/road/jlists.png`: az 1,6 m-en belül haladó pályák súly, majd távolság szerint, legfeljebb K = 8). 12-nél több karú folt (csomópontrendszer, parkoló) nem kap pályát. A chunkok 4. blokkja (768–1023. sor) a csomóponti réteg: RG listaeltolás, B listahossz, A régió (255 csomópont, 128 gyűrű, 0).
- **Kliens** (`client/roofmap.lua`): negyedik 128×128-as ablaktextúra; a két tábla egyszer töltődik be, a méretük a naplóba kerül (`junction tables loaded: ... KB`).
- **Shader** (`fx/snow_world.fx`, `JunctionTracks`): a cella listájának pályái (`[loop]`, K = 8), húrvetítés + 3 Newton-lépés a legközelebbi pontra, a nyom profilja a kar sávjaival azonos. A zaj a belépő kar sávkeretében mintázódik és a kilépőébe keveredik, így a nyom hullámzása a kar sávjából folytonosan megy tovább. A pályák `max`-szal keverednek, a keresztező nyomok keresztezik egymást. Bilineáris régió: a gyűrű közepétől a csomópont széléig a link sávjai kiúsznak, a gyűrű külső szélétől a pályák beúsznak, és a pálya első és utolsó 4 m-e is áttűnik. Forgalmi súly: egyenes 1,0, jobbra 0,7, balra 0,5, a kanyarnyom kicsit szélesebb. A csomópont közepe taposott hó, a stopvonalnál latyak, hóviharban a nyomok ugyanúgy betemetődnek (`refill`). Csak az 1. réteg magasságán és `gLodRoad.y`-on belül fut.
- **Mérés** (`python tests/check_roadmap.py [--old DIR]`, numpy port: `tools/roadmap_decode.py`): 1382 folt, 10164 pálya (egyenes 3381, jobb 3377, bal 3406), lista p50 3 / p95 7 / max 35, K fölött 626 cella. Varrat-pontszám a csomópont- és gyűrűcellák határain: látható ugrás 1,77 % (ebből a pályák 0,37 %, a többi az 1. réteg régi linkváltása), a régi formátumban 9,60 %. Pályalefedettség 98,4 % (a maradék a K-levágás). Offline kép: `python tools/render_junction.py --old DIR` (előtte/utána PNG).
- **Ismert korlátok**: az 1,40 % lane jump az 1. réteg cellánkénti linkváltásából jön a gyűrűben, ahol a maszk még nem takar (egy "a sávjain lévő link előnyben" próba csak 1,36 %-ra vitte le, ezért nincs benne); a csomóponti réteg felüljáró alatt (2. réteg) nem működik; a belépési pontok kb. 5 %-a csak a csomópont-tartalékkal áll. Játékban nem látott, FPS nem mérve.

