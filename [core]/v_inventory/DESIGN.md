# v_inventory – terv (DESIGN)

Állapot: **terv, 2026-10-15**. Végrehajtásra még nincs engedély. A kérés: `Inventory prompt.txt`.
A UI-tervek: `docs/mockups/01_hud.png`, `02_transfer.png`, `03_medbag.png`.

---

## 0. Felmérés (jelenlegi állapot)

| Resource | Mi van ma | Mit jelent a v_inventory-ra |
|---|---|---|
| `[core]/v_inventory` | csak a prompt | új resource |
| `[medical]/med_bag` (3140 sor) | ambulancánként 1 táska + 1 monitor; saját állapotgép (`stowed / carried / ground / stretcher` + `aboard`), kéz-objektumok kliensen (`medbag.hands`), H = letesz, oldalajtó menü (ui_interactobject), készlet a táskán belül számlálókkal (`drugs`, `ivKits`, `oxygen`), O2-fogyás, monitor-link, hordágy-integráció, ottfelejtés-figyelés, statikus monitorképernyő | a **tárgykezelés** (állapotok, kéz/föld/hordágy objektumok, tartalom) átkerül a v_inventory-ba; a **mentős logika** (kit, oldalajtó, készlet-fogyás, O2, monitor-link, hordágy-szabályok, ottfelejtés, feltöltés) a med_bag-ben marad, de v_inventory exportokra épül |
| `[medical]/medsys` `server/equipment.lua` | adapter: `getEquipmentNear`, `findStockItem`, `consumeStock`, `start/stopPatientOxygen`, `link/unlinkPatientMonitor`, `onTreatmentStart` a med_bag-ből | **változatlan marad**: a med_bag ugyanezeket az exportokat adja tovább, belül v_inventory-val |
| `[medical]/med_stretcher` | `onStretcherPushStart/Stop`, `onStretcherTakeOut`, `onStretcherLoadStart`, `onStretcherLoaded`, `getVehicleStretcher` | nem változik; a med_bag ezekre reagálva hívja a v_inventory `attachItem` / `storeItemInVehicle` exportjait |
| `[ui]/ui_interactobject` | 3D menük elemeken (X, Q/E, 1-9), szerver-validált kiválasztás, több resource menüje egy elemen összeolvad | csomagtartó menü, földön fekvő tárgyak „Felvesz” menüje |
| `[work]/work_core` | marker + 3D DX címke (Roboto, sötét doboz, színes ikon, alsó színcsík), E = interakció | a **porta-marker** ugyanígy néz ki (01-es kép) |
| `[core]/v_locals` | `L()` / `L.text` / `L.config`, namespace = resource, kulcs `^[a-z0-9_]+(\.[a-z0-9_]+)+$`; a lib magától hívja a `resourceReady()`-t `onClientLoadingStarted` után | itemnevek `v_inventory.item.<id>.name` / `.desc`; a v_inventory **nem** kerül a v_accounts `REQUIRED` listájára (kérés szerint) |
| `bt_items` | nem létezik | a v_inventory exportjait fogja használni; az itemjeit a v_inventory előre ismeri |

Foglalt billentyűk: `E` (work_core, ui_interactobject next), `Q`, `X`, `H` (med_bag letesz), `J` (tablet), `R`.
Javaslat: **`I`** = saját inventory, **`H`** = kézben lévő tárgyak letétele (átkerül a med_bag-ből), **`E`** = porta megnyitása a markerben.

---

## 1. Fogalmak

### 1.1 Item definíció (statikus, a v_inventory ismeri – `shared/items.lua`)

```lua
ITEMS.bt_blood_box = {
    category = "container",        -- ikonszín / csoport a UI-on
    weight   = 1.4,                -- kg, üresen
    holdable = true,               -- kézbe vehető
    hands    = 1,                  -- 1 vagy 2 (két kézzel fogott tárgy mindkét kezet foglalja) – K3
    back     = false,              -- hátra vehető
    container = { capacity = 10, accepts = { "blood", "sample", "tool" } }, -- csak tárolónál
    stackable = false,             -- halmozható (pl. gyógyszer ampullák) – K1
    storable  = true,              -- tehető-e tárolóba (a Lifepak pl. nem tehető a táskába)
    model = 1210, scale = 1.0,
    offsets = { left = {x,y,z,rx,ry,rz}, right = {...}, back = {...}, ground = {...} },
    lockControls = { "jump", "fire", "aim_weapon" },  -- kézben tartva
}
```
* Minden itemnek angol **id**-je van, a név/leírás kizárólag v_locals-ból jön: `v_inventory.item.bt_blood_box.name`.
* Ismeretlen id-vel `createItem` hibát ad → nem lehet fordítás nélküli item.
* Csak **egyszerű item** kerülhet tárolóba; tároló tárolóba nem (kérés szerint).

### 1.2 Item példány (szerver, memóriában – nincs DB)

```lua
Item = {
    uid   = "i:42",               -- egyedi, újraindításig
    def   = "bt_blood_unit",
    amount = 1,                    -- stackable-nél darabszám
    meta  = { bloodType = "0-", from = "...", to = "..." },  -- szabad tábla, a létrehozó resource-é
    owner = <resource>,            -- a létrehozó; ha leáll, az itemjei törlődnek
    loc   = Location,
}
```

### 1.3 Helyek (Location)

| `loc.type` | Mező | Látvány |
|---|---|---|
| `slot` | `player`, `slot = "left"|"right"|"back"` | kliens-objektum a csonton (a med_bag `carry.lua` általánosítva) |
| `container` | `item` (a tároló uid) | nincs |
| `ground` | `x,y,z,rz,dim,int` | szerver objektum + ui_interactobject „Felvesz” menü |
| `port` | `port` id | nincs (marker) |
| `trunk` | `vehicle` | nincs |
| `vehicle` | `vehicle`, `tag` (pl. `"aboard"`) | nincs – „Store item in…”, a csomagtartót megkerüli |
| `attached` | `element`, `offset` | szerver objektum az elemhez rögzítve – „Attach item to…” |
| `none` | – | csak adat (a létrehozó resource tartja kézben) |

Tárolóban lévő item helye a tároló helye (pl. a táska a kézben → a gyógyszer is ott van). Ez kell a
medsys hatótáv-szabályához.

### 1.4 Mozgatás és engedélyezés

Minden mozgatás egy szerver függvényen megy át: `moveItem(uid, toLoc, player, amount)`.
Ellenőrzés sorrendje: létezés → hely-szabály (kézbe vehető? hátra vehető? tárolható? tároló tárolóba nem) →
súlykapacitás → **porta-korlátozás** (játékosonként) → hozzáférés (csomagtartó) → **`onInventoryItemMove`**
szerver event (bármely resource `cancelEvent(true, "ok")`-kal tilthatja; a med_bag így tiltja pl. idegen
ambulancia táskájának elrakását) → végrehajtás → `onInventoryItemMoved` event (utólagos értesítés).

Kliens soha nem dönt, csak kérést küld; a UI a szervertől kapott „locked / suggested” jelöléseket mutatja.

---

## 2. Játékos slotok

* **Bal kéz, jobb kéz, hát.** Hátra csak `back = true` item (hátizsák, esetleg hűtőtáska) – K4.
* Két kézzel fogott item (`hands = 2`) mindkét kezet foglalja – K3.
* Fegyver ütközés: később a v_weaponselector-ral (export `isPlayerHandsFree` / `onInventoryHandsChange` event előkészítve).
* Járműbe szállás kézben tartott itemmel: alapból **tiltva** („Tedd le vagy rakd el”), kivéve ha egy resource
  `onInventoryVehicleEnter` eseményben elrakja (a med_bag így rakja el a saját ambulanciájába) – K7.
* Halál / kilépés / dimenzióváltás: a kézben és háton lévő itemek a földre kerülnek (`ground`) – a med_bag
  ottfelejtés-figyelése ezekre is működik.
* `H`: a kézben lévő itemek letétele a játékos elé (a med_bag mostani logikája).
* Szinkron: `inv.slots` elementData a játékoson (`{ left = {def, uid, model}, right = ..., back = ... }`) –
  ebből rajzol minden kliens kéz/hát objektumot; a HUD a saját meta-összefoglalót külön eventben kapja.

---

## 3. Porták (tároló markerek)

```lua
local port = exports.v_inventory:createPort({
    x, y, z, dim, int, radius = 1.5,
    name = { t = "bt_items.port.ls_blood_bank" },   -- v_locals üzenetobjektum
    title = { t = "bt_items.port.blood_storage" },
    color = { 215, 55, 65 }, icon = "B",
    capacity = 40,                                   -- kg, nil = végtelen
    visibleTo = nil,                                 -- nil = mindenki, vagy játékoslista
})
exports.v_inventory:addPortItem(port, uid) / removePortItem(port, uid) / getPortItems(port)
exports.v_inventory:setPortRules(port, player, { allowIn = {...}|true|false, allowOut = {...}|true|false })
exports.v_inventory:setPortSuggestions(port, player, { ["uid"] = "in"|"out", ... }, bannerText)
exports.v_inventory:clearPortRules(port, player)
exports.v_inventory:destroyPort(port)
```
* `allowIn/allowOut` lista elemei lehetnek uid-k vagy def id-k. A szabályok **játékosonként** élnek
  (egy portán több játékosnak eltérő korlátozása lehet).
* Marker UI (01-es kép): shader_markers henger + work_core-stílusú 3D címke, `E` = megnyitás.
  Ha nincs tároló a játékos kezében: piros tipp „Előbb vegyél kézbe egy tárolót”, nem nyílik meg.
* Megnyitáskor az **átpakoló ablak** (02-es kép): bal oldal a játékos (slotok + kiválasztott tároló
  tartalma), jobb oldal a porta. Javasolt itemek sárga keretben („DELIVER »”, „« TAKE”), tiltottak szürkén
  okkal. Felül a javaslatot tevő resource szövege (banner).
* Events: `onPortOpen(port, player)` (cancelable), `onPortItemMoved(port, player, uid, "in"|"out")`.

---

## 4. Csomagtartó

```lua
exports.v_inventory:createTrunk(vehicle, {
    capacity = 60,
    access = { players = {...}, dataKey = "work.id", dataValue = "bloodtransport", owner = true }, -- K8
    offset = { 0, -2.6, 0.2 },          -- a menü pontja a jármű hátulján
})
exports.v_inventory:setTrunkAccess(vehicle, access)
exports.v_inventory:addTrunkItem(vehicle, uid) / removeTrunkItem(vehicle, uid) / getTrunkItems(vehicle)
exports.v_inventory:destroyTrunk(vehicle)
```
* ui_interactobject menü a jármű hátulján (láthatatlan horgony, mint a med_bag oldalajtója): `[X] Trunk (rendszám)` →
  „Megnyit” → ugyanaz az átpakoló ablak, jobb oldalon a csomagtartó.
* Csomagtartóba kézbe vehető item és tároló is mehet (a vérszállító doboz ide kerül).
* A jármű megsemmisülésekor a tartalma törlődik és `onInventoryItemDestroyed` megy a tulajdonos resource-nak.

---

## 5. Store item in… (járműhöz kötés csomagtartó nélkül)

```lua
exports.v_inventory:storeItemInVehicle(uid, vehicle, tag)   -- tag: szabad string, pl. "aboard"
exports.v_inventory:getVehicleStoredItems(vehicle [, tag])
exports.v_inventory:takeItemFromVehicle(uid, player, slot)  -- a tulajdonos resource hívja
```
Nincs UI, a tulajdonos resource kezeli (a med_bag oldalajtója). A hordágy-szabály
(„a hordágyra tett item az oldalajtón is kivehető, de a hordággyal együtt is kijön”) a med_bag-ben marad:
loadingkor `storeItemInVehicle(uid, amb, "aboard")`, kivételnél `getVehicleStoredItems(amb, "aboard")` → `attachItem`.

## 6. Attach item to…

```lua
exports.v_inventory:attachItem(uid, element, { x, y, z, rx, ry, rz })
exports.v_inventory:detachItem(uid [, toLoc])
```
Szerver objektum az elemhez csatolva (a mostani `BAG.STRETCHER_OFFSETS` logika). A rögzített item helyét
a v_inventory a csatolási lánc tetejéről adja (`rootPosition`, a med_bag tapasztalata).

---

## 7. Meta adatok megjelenítése

A meta szabad tábla, de a UI csak a **`meta.display`** sorokat mutatja (v_locals üzenetobjektumokkal, így a
nyelv a kliensen dől el):
```lua
meta.display = {
    { label = { t = "bt_items.meta.from" }, value = { t = "bt_items.place.ls_blood_bank" } },
    { label = { t = "bt_items.meta.to" },   value = "All Saints General" },
}
meta.bar = { label = { t = "v_inventory.meta.oxygen" }, value = 64, max = 100 }  -- opcionális sáv (O2)
```
Megjelenik: a HUD-on a kézben tartott itemnél (01), a listasorban (első sor), a tooltipben és a részletek panelen (03).
`setItemMeta(uid, key, value)` / `getItemMeta(uid [, key])`.

---

## 8. UI

| # | Felület | Kép | Leírás |
|---|---|---|---|
| U1 | Kéz/hát HUD | 01 | jobb lent (a med_bag carry HUD helyén): L / R / BACK, ikon, név, súly, a kézben lévő tároló meta-sorai + tartalom-összesítő; alul `H` letesz, `I` inventory |
| U2 | Porta címke | 01 | work_core-stílusú 3D DX címke a marker felett; távolsággal kicsinyedik; hiba-tipp piros |
| U3 | Csomagtartó / föld | 01 | ui_interactobject meglévő megjelenése |
| U4 | Átpakoló ablak | 02 | kurzoros DX ablak: bal = játékos, jobb = porta / csomagtartó / földön lévő tároló; drag & drop, dupla katt = gyors mozgatás, Shift+húzás = stack megosztás, javaslat-banner, súlysávok, tooltip |
| U5 | Saját inventory (`I`) | 03 | ugyanaz az ablak egy oldallal; tároló tartalma kétoszlopos kompakt listában csoportosítva, jobb oldalon részletek panel (meta, sáv) |

Stílus: a med_bag / ui_interactobject palettája (háttér `16,18,24`, csempe `28,31,40`, piros akcentus `215,55,65`,
kulcs-sárga `240,184,74`), Roboto (work_core fontok), skálázás `sh/1080`. Az ikonok első körben betűs színes
négyzetek (kategória-színnel) – később PNG ikonokra cserélhetők (K10).

---

## 9. Itemek (előre definiálva)

### 9.1 Medsys (a mostani med_bag szerint)

| id | típus | megjegyzés |
|---|---|---|
| `medical_bag` | kézbe vehető tároló | kapacitás ~12 kg; hátra? (K4) |
| `lifepak15` | kézbe vehető, **nem tárolható** a táskában | monitor/defibrillátor, a statikus képernyő marad |
| `medical_oxygen_cylinder` | egyszerű | `meta.oxygen` 0–100 (sáv) |
| `iv_kit` | egyszerű, stackable | 6 db |
| `drug_<id>` ×12 | egyszerű, stackable | ketamine, rocuronium, fentanyl, epinephrine, captopril, nitroglycerin, glucose, glucose_gel, insulin, naloxone, salbutamol, midazolam (a `MEDIC_DRUGS` id-k) |
| `glucometer`, `bandage`, `splint`, `airway_kit` | egyszerű | ma korlátlanok – K2 |

A gyógyszer-itemek neve a v_locals `v_inventory` namespace-ben él (a medsys `MEDIC_DRUGS.name`-ből átvéve).
Új medsys gyógyszerhez új itemet kell felvenni (egyébként „korlátlan” marad, ahogy ma).

### 9.2 Vérszállítás (bt_items-nek, K5 – pontosítandó)

`bt_blood_box` (kézbe vehető tároló), `bt_blood_unit` (nem kézbe vehető, meta: vércsoport, from, to),
`bt_plasma_unit`, `bt_sample_kit`, `bt_cooling_element`, `backpack` (hátra vehető tároló).

---

## 10. Exportok (szerver, összefoglaló)

```lua
-- itemek
createItem(defId, meta, loc [, amount]) -> uid | false, err
destroyItem(uid) ; getItem(uid) -> { def, amount, meta, loc } ; getItemDef(defId)
setItemMeta(uid, key, value) ; getItemMeta(uid [, key]) ; setItemAmount(uid, n) ; takeItemAmount(uid, n)
moveItem(uid, loc [, player, amount]) -> bool, err
getItemPosition(uid) -> x, y, z, dim, int       -- tárolón/kézen át feloldva
findItems(filter) -> { uid... }                 -- { def=, owner=, near = {element, range}, loc = {...} }
-- tárolók
getContainerItems(uid) ; getContainerWeight(uid) -> used, cap ; addToContainer(uid, itemUid)
-- játékos
getPlayerSlots(player) ; giveItemToPlayer(player, uid [, slot]) ; dropPlayerItems(player [, x, y]) ; isPlayerHandsFree(player)
-- porta / csomagtartó / jármű / attach  (3–6. fejezet)
-- UI
openInventory(player [, otherSide]) ; closeInventory(player)   -- otherSide: port | trunk | containerUid
```
Events (szerver): `onInventoryItemMove` (cancelable, előtte), `onInventoryItemMoved`, `onInventoryItemDestroyed`,
`onInventoryVehicleEnter` (cancelable / elrakás), `onPortOpen`, `onPortItemMoved`, `onInventoryReady` (újraindulás után –
a resource-ok újra létrehozzák az itemjeiket).

---

## 11. A med_bag átírása

Marad a med_bag-ben (v_inventory-ra építve): kitek ambulancia-felismerése, oldalajtó menü (ui_interactobject),
készlet-fogyasztás (`takeItemAmount` a táska tartalmán), O2 fogyás (`meta.oxygen`), monitor-link, hordágy-integráció
(`attachItem` / `storeItemInVehicle(…, "aboard")`), ottfelejtés-figyelés (`getItemPosition`), feltöltés a kórházi
helyen, „EQUIPMENT MISSING”, statikus monitorkép. **Nem** használ csomagtartót.

Kikerül a med_bag-ből: `client/carry.lua` (kéz-objektumok), a carry HUD, a „Check contents” ablak, a földi
„Pick up” menü, a H-billentyű, a saját állapotgép objektum-kezelése.

A medsys felé a mostani exportok **név és szignatúra szerint változatlanok** (`getEquipmentNear`, `findStockItem`,
`consumeStock`, …), így a medsys-ben csak a `MEDIC_EQUIPMENT` / panel szövegek igazítása kell (ha egyáltalán).
Új szabály a táska tartalmára: ha egy itemet kivesznek a táskából (pl. az O2 palackot a másik táskába), a medsys
az elérhető itemeket a táska **valós tartalmából** látja.

---

## 12. Fázisok

1. **Mag**: item-definíciók, példányok, helyek, mozgatás + validálás, súly, events, v_locals namespace (en + hu).
2. **Slotok és látvány**: kéz/hát objektumok, H letesz, föld + Felvesz menü, járműbe szállás, halál/kilépés.
3. **UI**: HUD (U1), átpakoló ablak (U4), saját inventory (U5), tooltip / részletek.
4. **Porták** (U2), játékosonkénti szabályok és javaslatok.
5. **Csomagtartó**, store-in-vehicle, attach.
6. **med_bag átírás** (itemek, oldalajtó, hordágy, készlet, O2, monitor), medsys ellenőrzés, work_ems tutorial igazítása.
7. Teszt: lupa szintaxis + stubolt unit tesztek; élő ellenőrzés exportokkal / logokkal (kevés képernyőkép).

---

## 13. Nyitott kérdések (K)

Lásd a válaszüzenetet; a döntések ide kerülnek.
