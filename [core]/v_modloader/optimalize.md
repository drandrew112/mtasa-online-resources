# v_modloader – optimalizálási terv

Készült: 2026-11-09 (FPS-audit, Los Santos / All Saints). Mérés: a DFF geometria háromszögszáma és a TXD
fejlécek (formátum, méret, mip-szintek) közvetlenül a fájlokból (`tools/txdopt.py`, illetve a mellé írt
elemző szkript). Gyári GTA:SA autó: kb. 3–5 ezer háromszög, a táblázatban ehhez mérünk (×).

## Összesítés

| | |
|---|---|
| modellek | 67 (jármű 38, skin 13, fegyver 1, objektum 15) |
| DFF összesen | 216 MB |
| TXD összesen | 240 MB (1099 textúra) |
| ebből tömörítetlen (ARGB / XRGB) | 79 MB |
| 256 px feletti textúra mipmap nélkül | 509 db |
| AI-forgalmi autó átlaga (TRAFFIC_MODELS súlyokkal) | 45311 háromszög (gyári: ~4000) |
| 60 forgalmi autó egy játékos körül | 2.7 millió háromszög (gyári: 0.24 millió) |

A cserélt modellek a 32 bites GTA-folyamat memóriájában állandóan bent vannak (DFF + TXD), ez a streaming
mozgásterét is szűkíti: sűrű területen ettől is akad a játék.

## 1. Járművek háromszögszám szerint

| # | ID | név | szerep | háromszög | × gyári | DFF MB | TXD MB | tömörítetlen MB | mip nélkül | prioritás |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | 550 | Mitsubishi Lancer Evolution X | AI-forgalom (súly 3) | 402 218 | 101 | 20.4 | 17.1 | 0.0 | 52 | P1 |
| 2 | 551 | Hyundai Tucson Hybrid | AI-forgalom (súly 3) | 351 308 | 88 | 15.6 | 3.1 | 0.0 | 2 | P1 |
| 3 | 421 | Renault Talisman | AI-forgalom (súly 2) | 290 528 | 73 | 17.1 | 4.0 | 0.2 | 0 | P1 |
| 4 | 415 | Skoda Octavia Blood Transporter | vérszállító | 265 841 | 66 | 13.6 | 3.8 | 0.0 | 16 | P1 |
| 5 | 546 | Audi A3 Sedan (Police) | rendőr | 244 985 | 61 | 13.2 | 2.5 | 0.0 | 0 | P1 |
| 6 | 445 | Audi RS6 C7 (Police) | rendőr | 224 851 | 56 | 10.6 | 43.9 | 43.2 | 6 | P1 |
| 7 | 490 | Mercedes V Class | szolgálati | 207 527 | 52 | 9.3 | 5.7 | 0.0 | 0 | P1 |
| 8 | 538 | BR 262 | vasút (mozdony) | 205 648 | 51 | 13.8 | 16.1 | 0.0 | 0 | P1 |
| 9 | 405 | 2004 Jaguar XJ-8 | AI-forgalom (súly 3) | 152 375 | 38 | 6.4 | 0.6 | 0.0 | 10 | P1 |
| 10 | 598 | Skoda Octavia MK3 Facelift | rendőr | 130 853 | 33 | 7.6 | 0.6 | 0.1 | 7 | P1 |
| 11 | 547 | Mercedes Benz C350 Avantgarde | AI-forgalom (súly 3) | 120 406 | 30 | 5.6 | 4.7 | 0.0 | 23 | P1 |
| 12 | 416 | Mercedes Sprinter (with lightbar) | EMS mentő | 116 750 | 29 | 6.7 | 6.8 | 0.0 | 46 | P1 |
| 13 | 582 | Toyota HiAce XH10 Ambulance | EMS mentő | 113 141 | 28 | 5.6 | 15.8 | 15.8 | 0 | P1 |
| 14 | 529 | 1999 Jeep Grand Cherokee | AI-forgalom (súly 2) | 110 915 | 28 | 4.7 | 0.9 | 0.0 | 7 | P1 |
| 15 | 466 | Subaru Impreza RC Sport | AI-forgalom (súly 3) | 90 709 | 23 | 6.1 | 4.6 | 2.7 | 16 | P1 |
| 16 | 596 | Ford Crown Vic Police | LSPD | 83 331 | 21 | 6.0 | 9.0 | 0.1 | 1 | P1 |
| 17 | 599 | Police Ranger (NYPD) | rendőr | 79 229 | 20 | 5.4 | 8.3 | 2.1 | 26 | P2 |
| 18 | 580 | 1993 Honda Civic | AI-forgalom (súly 2) | 78 939 | 20 | 4.1 | 2.5 | 0.0 | 15 | P1 |
| 19 | 410 | 1987 Ford Festiva | AI-forgalom (súly 3) | 68 800 | 17 | 3.3 | 7.1 | 5.8 | 16 | P1 |
| 20 | 560 | 2006 Subaru Impreza WRX STi | AI-forgalom (súly 1) | 61 275 | 15 | 3.3 | 3.6 | 0.0 | 21 | P1 |
| 21 | 426 | 2003 Audi A8 | AI-forgalom (súly 3) | 55 770 | 14 | 3.6 | 1.2 | 0.0 | 14 | P2 |
| 22 | 492 | BMW X5 | AI-forgalom (súly 2) | 47 063 | 12 | 2.3 | 0.6 | 0.0 | 14 | P3 |
| 23 | 541 | Koenigsegg CC 8S | játékos / egyéb | 45 037 | 11 | 2.2 | 0.2 | 0.0 | 2 | P3 |
| 24 | 483 | 2018 Mercedes Sprinter | EMS | 43 283 | 11 | 2.0 | 15.5 | 0.0 | 0 | P3 |
| 25 | 540 | 2013 Dodge Dart | AI-forgalom (súly 3) | 36 106 | 9 | 1.7 | 2.0 | 0.0 | 11 | P3 |
| 26 | 506 | Bugatti Veyron | játékos / egyéb | 29 436 | 7 | 3.7 | 0.8 | 0.0 | 8 | - |
| 27 | 516 | 2006 Saab 9-7X | AI-forgalom (súly 3) | 28 401 | 7 | 1.6 | 4.7 | 0.0 | 11 | - |
| 28 | 407 | Fire Truck (HU) | tűzoltó | 27 516 | 7 | 1.5 | 11.0 | 0.0 | 24 | - |
| 29 | 562 | BMW M3 GTR | AI-forgalom (súly 1) | 22 804 | 6 | 1.5 | 0.8 | 0.0 | 15 | - |
| 30 | 427 | Riot (GTA5) | rendőr (riot) | 22 130 | 6 | 1.5 | 0.5 | 0.0 | 7 | - |
| 31 | 597 | Vapid Police Cruiser (GTA5) | rendőr | 21 602 | 5 | 1.4 | 1.1 | 0.0 | 10 | - |
| 32 | 487 | Air Ambulance (GTA5) | légimentő | 18 659 | 5 | 1.0 | 1.7 | 0.0 | 2 | - |
| 33 | 559 | Porsche Carrera GT | játékos / egyéb | 18 223 | 5 | 1.1 | 0.6 | 0.0 | 9 | - |
| 34 | 497 | Police Maverick (GTA5) | rendőr heli | 18 182 | 5 | 1.0 | 1.7 | 0.0 | 2 | - |
| 35 | 531 | MTZ-80 | traktor | 16 382 | 4 | 1.4 | 0.3 | 0.0 | 3 | - |
| 36 | 456 | Misson Row Ambulance | EMS mentő | 11 389 | 3 | 2.0 | 3.2 | 0.0 | 3 | - |
| 37 | 411 | McLaren F1 LM | játékos / egyéb | 11 252 | 3 | 0.7 | 0.5 | 0.0 | 6 | - |
| 38 | 585 | Alfa Romeo 75 | AI-forgalom (súly 2) | 7 390 | 2 | 0.7 | 0.4 | 0.1 | 4 | - |

## 2. Textúra-méret szerint (minden kategória, felső 25)

| # | kategória | ID | név | TXD MB | tömörítetlen MB | textúra | legnagyobb | mip nélkül |
|---|---|---|---|---:|---:|---:|---:|---:|
| 1 | vehicles | 445 | Audi RS6 C7 (Police) | 43.9 | 43.2 | 31 | 2048 px | 6 |
| 2 | vehicles | 550 | Mitsubishi Lancer Evolution X | 17.1 | 0.0 | 67 | 2048 px | 52 |
| 3 | vehicles | 538 | BR 262 | 16.1 | 0.0 | 33 | 2048 px | 0 |
| 4 | vehicles | 582 | Toyota HiAce XH10 Ambulance | 15.8 | 15.8 | 37 | 1024 px | 0 |
| 5 | vehicles | 483 | 2018 Mercedes Sprinter | 15.5 | 0.0 | 25 | 2048 px | 0 |
| 6 | vehicles | 407 | Fire Truck (HU) | 11.0 | 0.0 | 30 | 2048 px | 24 |
| 7 | vehicles | 596 | Ford Crown Vic Police | 9.0 | 0.1 | 39 | 2048 px | 1 |
| 8 | skins | 287 | army | 8.7 | 0.0 | 6 | 2048 px | 6 |
| 9 | vehicles | 599 | Police Ranger (NYPD) | 8.3 | 2.1 | 31 | 2048 px | 26 |
| 10 | vehicles | 410 | 1987 Ford Festiva | 7.1 | 5.8 | 29 | 1360 px | 16 |
| 11 | vehicles | 416 | Mercedes Sprinter (with lightbar) | 6.8 | 0.0 | 56 | 2048 px | 46 |
| 12 | vehicles | 490 | Mercedes V Class | 5.7 | 0.0 | 21 | 2048 px | 0 |
| 13 | vehicles | 516 | 2006 Saab 9-7X | 4.7 | 0.0 | 12 | 2048 px | 11 |
| 14 | vehicles | 547 | Mercedes Benz C350 Avantgarde | 4.7 | 0.0 | 24 | 1024 px | 23 |
| 15 | vehicles | 466 | Subaru Impreza RC Sport | 4.6 | 2.7 | 29 | 1024 px | 16 |
| 16 | vehicles | 421 | Renault Talisman | 4.0 | 0.2 | 26 | 1024 px | 0 |
| 17 | vehicles | 415 | Skoda Octavia Blood Transporter | 3.8 | 0.0 | 24 | 2048 px | 16 |
| 18 | objects | 5708 | ls_allsaints | 3.7 | 0.0 | 20 | 1024 px | 0 |
| 19 | vehicles | 560 | 2006 Subaru Impreza WRX STi | 3.6 | 0.0 | 25 | 512 px | 21 |
| 20 | vehicles | 456 | Misson Row Ambulance | 3.2 | 0.0 | 6 | 2048 px | 3 |
| 21 | vehicles | 551 | Hyundai Tucson Hybrid | 3.1 | 0.0 | 27 | 512 px | 2 |
| 22 | vehicles | 580 | 1993 Honda Civic | 2.5 | 0.0 | 17 | 1024 px | 15 |
| 23 | vehicles | 546 | Audi A3 Sedan (Police) | 2.5 | 0.0 | 35 | 1024 px | 0 |
| 24 | objects | 1581 | Lifepak 15 | 2.1 | 2.1 | 8 | 512 px | 4 |
| 25 | vehicles | 540 | 2013 Dodge Dart | 2.0 | 0.0 | 15 | 1024 px | 11 |

## 3. Már elvégezve (2026-11-09)

| fájl | előtte | utána | megjegyzés |
|---|---:|---:|---|
| objects/5708.txd (All Saints épület) | 72,3 MB, 19 tömörítetlen, 1 mip | 3,7 MB, DXT1/DXT5, teljes mip-lánc | 4 db 2048² → 1024², PSNR 34–51 dB |
| objects/3271.txd (All Saints) | 8,4 MB tömörítetlen | 1,4 MB DXT1 + mip | |
| objects/14802.txd (volan, buszpályaudvar) | 5,3 MB XRGB | 1,0 MB DXT1 + mip | nem 2-hatvány méretek → 2-hatvány |
| objects/3976, 4230, 14846 (int_lspd) | DXT / ARGB, mip nélkül | DXT + mip | a régi map_ls_int_pd-ből |
| objects/7557 (zebra) | DXT3, mip nélkül | DXT3 + mip (az 1. szint bájtra azonos) | a régi DOUBLE_ZEBRA-ból |
| objects/11326, 11387, 11389 (sf_garage) | DXT1, mip nélkül | DXT1 + mip (az 1. szint bájtra azonos) | a régi map_sf_garage-ból |

A térképek modelljei mind a `ALWAYS_LOAD_OBJECTS` listán vannak (a „Custom object models” kikapcsolása
nem bontja szét a térképeket), a buszpályaudvar LOD-távolsága a `MODEL_LOD` táblában van.

## 4. Megoldási terv

### 4.1 Költségvetés (célértékek)

| típus | háromszög | textúra |
|---|---:|---|
| AI-forgalomban is megjelenő autó | ≤ 25 000 | ≤ 4 MB, max 1024², DXT1/DXT5, mip |
| játékos-autó, sportautó | ≤ 40 000 | ≤ 6 MB, max 1024² (karosszéria-atlasz 2048² DXT1) |
| szolgálati jármű (mentő, rendőr, BT) | ≤ 40 000 | ≤ 8 MB, matricák 2048² DXT5 |
| mozdony, nagy jármű | ≤ 60 000 | ≤ 10 MB |
| skin | ≤ 10 000 | ≤ 2 MB |
| objektum / épület | a látható méret szerint, belső bútor ≤ 2 000 | max 1024², DXT + mip |

### 4.2 Textúrák – gépi, a kinézetet nem változtatja (P0, 1 nap)

1. `python tools/txdopt.py vehicles/*.txd skins/*.txd weapons/*.txd objects/*.txd` (alapból max 1024 px;
   a már DXT + mip textúrák változatlanok, a mip nélküli DXT-k első szintje bájtra azonos marad).
   Előtte `--dry-run`-nal a lista; ahol egy felirat (rendszám, matrica) 2048-ban kell, `--max 2048`.
2. `/modloader update` (manifest + md5 frissítés), restart.
3. Ellenőrzés a játékban: a 445, 582, 410, 466 és a kézi eszközök (1581 Lifepak kijelző!) közelről.
4. A `/modloader update` kapjon figyelmeztetést, ha egy új TXD-ben 256 px feletti tömörítetlen vagy mip nélküli kép van
   (a fejléc-olvasás a `txdopt.py`-ban megvan, Lua-ba átírható a `checkFile` mellé).

### 4.3 Geometria – Blender (P1 → P3 sorrendben, 1–3 hét)

1. P1 modellek (táblázat): a nem látható részek törlése (motortér, belső csavarok, alváz rejtett része, duplikált
   lapok), utána Decimate (Collapse, a UV-varratok megőrzésével) a célértékig. Karosszéria-ívek, lámpák, felnik
   kapják a legtöbb háromszöget; a kerékdob, belső tér a legkevesebbet.
2. Minden cserélt járműbe `_vlo` LOD-atomic (2–5 ezer háromszög, ugyanaz a TXD). Ettől a GTA távolról a
   könnyű változatot rajzolja, és a drawdistance jármű-LOD alapértéke 500-ról 150–200-ra vehető úgy, hogy a
   távoli autók nem tűnnek el.
3. Export DragonFF-fel, a dummy-k (wheel_*, door_*, bump_*, ped_frontseat) és a frame-hierarchia változatlan →
   a kezelés, ajtók, ülések, ELS-pozíciók (v_els) ugyanazok maradnak.
4. Modellenként mérés: `python tools/txdopt.py --dry-run` + háromszögszám, a táblázat frissítése.

### 4.4 Ha egy modellt nem lehet egyszerűsíteni

Az AI-forgalom kaphat külön, könnyű modellt: `engineRequestModel("vehicle", parent)` saját ID-t ad, a
forgalom ezt használja, a játékosok autói a részletes modellt. Ez a forgalom kinézetét megváltoztatja, ezért
csak végső megoldás.

### 4.5 Sorrend

1. Textúrák (4.2) – minden modell.
2. P1 geometria: 550 (Mitsubishi Lancer Evolution X), 551 (Hyundai Tucson Hybrid), 421 (Renault Talisman), 415 (Skoda Octavia Blood Transporter), 546 (Audi A3 Sedan (Police)), 445 (Audi RS6 C7 (Police)), 490 (Mercedes V Class), 538 (BR 262), 405 (2004 Jaguar XJ-8), 598 (Skoda Octavia MK3 Facelift), 547 (Mercedes Benz C350 Avantgarde), 416 (Mercedes Sprinter (with lightbar)), 582 (Toyota HiAce XH10 Ambulance), 529 (1999 Jeep Grand Cherokee), 466 (Subaru Impreza RC Sport), 596 (Ford Crown Vic Police), 580 (1993 Honda Civic), 410 (1987 Ford Festiva), 560 (2006 Subaru Impreza WRX STi).
3. `_vlo` LOD-ok a P1 modellekbe, utána jármű-LOD alapérték 200.
4. P2, P3 modellek.

