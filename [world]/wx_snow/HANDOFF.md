# wx_snow Hó 2.0: átadó prompt a következő sessionnek

**2026-11-13 (kereszteződések 2.0)**: a kereszteződési nyomok újraépítve (format 4: pályalisták + analitikus Bézier a shaderben, DESIGN.md 3. fejezet vége, "Kereszteződések 2.0"). Offline mérve (`python tests/check_roadmap.py`, `python tests/test_roadwindow.py`, `python tests/test_snow.py`, `python tools/render_junction.py`). Játékban NEM látott: a kereszteződések kinézete, az FPS a LS belvárosban (régi/új), a `junction tables loaded` naplósor a kliensen. Az alábbi "kereszteződések rajzolása hibás" utalások elavultak.

**2026-11-13 (később): a jármű-hó teljesen ki lett véve** (client/server/shared vehicle fájlok, snow_vehicle.fx, vehicle_textures.json, SNOW.VEHICLE, getSnowVehicleState, /snowtest vehicles). Az alábbi F5 / jármű-hó utalások elavultak, ne építsd újra.

**Frissítés (2026-11-13, F5/F6 session)**: a lenti 1–4. teendő megvan. Az utak és a cost mérés rendben (cost: ≈ −5 % minden együtt, tour −0 %), a fű még túl világos volt (sötétítve, nem látott), a kereszteződések rajzolása hibás (külön session). F5 jármű-hó megépítve (DESIGN.md 9. fejezet), F6 docs + offline tesztek kész. Játékban nem látott: a jármű-hó teljesen (`/snowtest vehicles`, `/snowtest vehtex` futtatandó), a sötétebb fű, roof map sütés (`/snowbake start`).

Állapot: 2026-11-13. F1–F4 megépítve, kanyar- és kereszteződés-javítás kész, JÁTÉKBAN CSAK RÉSZBEN látott. Hátra: az utak és a fű újraellenőrzése játékban, a cost mérés, F5 (járművek), F6 (lezárás).

## Mit töltsön be a session (csak ezeket)

1. Terv artifact: `https://claude.ai/artifact/McoqCecNQ157mYr96jbsGJ` (Artifact tool, `action: "read"`). A vizuális terv, a jármű-hó szabályok és a fázisok vannak benne.
2. `[world]/wx_snow/DESIGN.md` (a 3. fejezet "F1", "F2 / F3", "Javítás", "Kanyarok" bekezdései, 9. fejezet járművek, 10. fejezet tesztelés).
3. `[world]/wx_snow/fx/snow_world.fx` (a pixel shader, v2) és `client/ground.lua`.
4. Jármű munkához még: `shared/config.lua`, `client/roofmap.lua` (`ROOF.heightAt`), `client/state.lua` (`snowCurrent`), `client/tests.lua`.
5. Memória: `wx-snow-2-plan.md`, `wx-snow-resource.md`, `feedback-no-commit.md`, `feedback-complete-delivery.md`.

A többi fájlra nincs szükség.

## Prompt (másold be az új session elejére)

```
Folytatjuk a wx_snow Hó 2.0 munkát ([world]/wx_snow). Előbb olvasd el a memóriából a wx-snow-2-plan.md és wx-snow-resource.md fájlokat, a [world]/wx_snow/HANDOFF.md-t, a DESIGN.md 3. (F1, F2/F3, Javítás, Kanyarok bekezdések), 9. és 10. fejezetét, az Artifact toollal (action "read") a https://claude.ai/artifact/McoqCecNQ157mYr96jbsGJ tervet, majd a fx/snow_world.fx és client/ground.lua fájlokat. Mást ne tölts be, amíg nem kell.

Szabályok: nem commitolsz (én commitolok), a játékban nem látott dolgokat nem állítod késznek, a UI szövegek angolul, a chat magyarul, offline teszt: python tests/test_snow.py (fxc fordítást is futtat).

Ahol tartunk:
- F1 (shader gyorsítás), F2 (új talajhó kinézet, tex/macro.png), F3 (utak), F4 (hóesés rétegpárok) kész, játékban részben látott.
- /snowtest cost eredménye: hómentes ~71 FPS, csak hóesés ~65, csak talaj shaderek ~41 (a layered "*" shader második rajzolása a fix költség). A generic kategória maxDist 250 m, az új cost teszt méri a 250/120/60 m-t és a generic nélküli esetet.
- Fű: a fagyás a talaj borításához kötött (snow_grass.fx), új, játékban még nem látott.
- Kanyarok: tools/build_roadmap.py a hosszú linkeket a navi ponton megtöri, kerek illesztés a link végén, kereszteződésben nincs kerékcsík (code 16, packed hó). A data/roadmap*.png újraépítve.

Teendők sorrendben:
1. Kérdezd meg, mit láttam játékban (utak, fű, kereszteződés, /snowtest cost számok), és ahhoz igazíts. Ha a lane map az utakon nem ad találatot (a /snow debug zöld árnyalat hiányzik), azt előbb oldd meg.
2. Ha kell, finomítsd az utak és a fű kinézetét a visszajelzés alapján.
3. F5 járművek az artifact "Járművek" fejezete szerint: fx/snow_vehicle.fx (layered, járművenként külön példány a legközelebbi N járműre), client/vehicles.lua, server/vehicles.lua (vsA / vsT element data a vezetett járművekre), SNOW.VEHICLE a configban, ui_pause minőségi szintek, /snowtest vehicles. A modell: felső korlát szintenként 0/0/0.35/0.6/0.85/1.0, rakódás 1/perc 0/0/0.025/0.04/0.07/0.11, lekopás mozgásban 0.17 x km/h/60 per perc, fedett helyen állva -0.008/perc, a korlát fölötti hó -0.03/perc olvad; a lekopás elölről hátrafelé megy; fedettség a ROOF.heightAt-tal (a roof map-et be kell sütni: /snowbake start). A jármű textúralistát az engineGetModelTextures-ből generáld (tools/vehicle_textures.json).
4. F6: DESIGN.md frissítése, offline tesztek, összefoglaló arról, mi nincs játékban ellenőrizve.
```
