# v_inventory – DESIGN

Állapot: **megvalósítva 2026-10-15** (szerver oldal élőben exportokkal tesztelve, a UI játékban még nincs kipróbálva).
A kérés: `Inventory prompt.txt`. A UI-tervek: `docs/mockups/01_hud.png`, `02_transfer.png`, `03_medbag.png`.
Szerző a meta.xml-ben: `DrAndrew112`.

---

## 0. Döntések (2026-10-15)

| # | Kérdés | Döntés |
|---|---|---|
| K1 | Halmozás | A gyógyszer, IV kit, kötszer, sín **halmozható** (egy tárgy, darabszám). |
| K2 | Glucometer, kötszer, sín, légútkészlet | **Valódi tárgyak** a táskában. A kötszer és a sín fogy (egy / sikeres beavatkozás), a glucometer és a légútkészlet nem. Nincs a táskában → a beavatkozás tiltva. |
| K3 | Két kézzel fogott tárgy | **Nincs.** Minden kézbe vehető tárgy egykezes. |
| K4 | Hát | Csak a hátizsák vehető hátra. A mentőtáska kézben vihető. |
| K5 | Vérszállítás | Egyelőre csak a doboz (`bt_blood_box`); a többi a bt_items fejlesztésekor. |
| K6 | Földre tett tárgy felvétele | Bárki, de a létrehozó script tilthatja (`access`, `onInventoryItemMove`). |
| K7 | Járműbe szállás | **Tilos**, ha a kézben vagy a háton bármi van. Script általi berakásnál a tárgyak a jármű mellé kerülnek. |
| K8 | Csomagtartó hozzáférés | ElementData kulcs (+ opcionális érték). A med_bag-nél ez a `medic.role`. |
| K9 | Lifepak, mentőtáska | Nem tárolhatók (`storable = false`): autóba csak a med_bag menüjével vagy a hordággyal kerülnek. |
| K10 | Ikonok | Opcionális PNG ikon (`icon`), egyébként betűs csempe. A gyógyszereknek közös ikonjuk van. |
| – | Porták láthatósága | Állítható: játékoslista és / vagy elementData kulcs (+ érték). |
| – | Nyelvi szövegek | Csak az `onClientLoadingStarted` után töltődnek be, utána `resourceReady()`; a v_inventory **nincs** a v_accounts várólistáján. |

---

## 1. Fogalmak

### 1.1 Item definíció (`shared/items.lua`)

Minden létrehozható tárgyat a v_inventory előre ismer; ismeretlen id-t a `createItem` visszautasít.
A szövegek: `v_inventory.item.<id>.name` és `.desc` (v_locals).

| Mező | Jelentés |
|---|---|
| `category` | ikonszín és a tárolók `accepts` szűrője (`ITEM_CATEGORIES`) |
| `weight` | kg / darab (tárolónál üresen) |
| `holdable`, `hand` | kézbe vehető; kedvelt kéz (`left` / `right`) |
| `back` | hátra vehető |
| `storable` | `false`: játékos nem teheti tárolóba / portára / csomagtartóba |
| `stackable` | halmozható |
| `container` | `{ capacity = kg, accepts = { category = true } }` – csak egyszerű tárgyat tárol |
| `model`, `fallback`, `scale` | világobjektum |
| `offsets` | `right` / `left` (a kéz csonttól, a hordozó keretében; a hiányzó oldal a tükrözött), `back`, `ground` |
| `icon`, `glyph` | PNG ikon / betűk |
| `lockControls` | kézben tartva tiltott vezérlők (alap: `INV.CARRY_LOCKED_CONTROLS`) |

Tárgyak: `medical_bag`, `lifepak15`, `medical_oxygen_cylinder`, `iv_kit`, `airway_kit`, `glucometer`, `bandage`,
`splint`, `drug_<id>` (a 12 medsys gyógyszer), `bt_blood_box`, `backpack`.

### 1.2 Példány (szerver memória, nincs DB)

`{ uid = "i42", def, amount, meta, owner (a létrehozó resource neve), access = { dataKey, dataValue }, loc, contents }`.
A létrehozó resource leállásakor a tárgyai törlődnek. A v_inventory újraindulásakor minden tárgy elvész;
indulás után `onInventoryReady` szól, hogy a resource-ok hozzák létre újra (a med_bag ezt teszi).

### 1.3 Helyek

| `loc.type` | Mezők | Látvány |
|---|---|---|
| `none` | – | csak adat |
| `slot` | `player`, `slot` (`left` / `right` / `back`) | kliens objektum a csonton (`client/hands.lua`) |
| `container` | `container` (uid) | – |
| `ground` | `x, y, z, rz, dim, int` | fagyasztott objektum + ui_interactobject menü (Felvesz / Kinyit) |
| `attached` | `element`, `offset` | objektum az elemhez rögzítve (a hordágy) |
| `port` | `port` (id) | – |
| `trunk` | `vehicle` | – |
| `vehicle` | `vehicle`, `tag` | – („Store item in…”, a csomagtartót megkerüli) |

A tárolóban lévő tárgy pozíciója a tárolóé, a rögzítetté a csatolási lánc tetejéé (`getItemPosition`).

### 1.4 Mozgatás

Minden mozgatás a `moveItem`-en megy át: szabályok (`checkPlace`) → súly → porta-szabály (játékosonként) →
hozzáférés → **`onInventoryItemMove`** (megszakítható, `cancelEvent(true, ok)`) → végrehajtás (részmennyiség
leválasztása, azonos halom összevonása) → **`onInventoryItemMoved`**.
Játékos mozgatásánál (UI) a `storable` és a porta-szabályok is élnek; exportnál (script) nem, a súlyhatár igen.

---

## 2. Játékos slotok (`server/slots.lua`)

* Bal kéz, jobb kéz, hát. Kézben tartott tárgy: ugrás / lövés / célzás / fegyverváltás tiltva.
* `H`: a kézben lévő tárgyak letétele. Halál, kilépés, dimenzió- / interiorváltás: minden letéve.
* Járműbe szállás tárggyal tilos (K7); script általi berakásnál a tárgyak a jármű bal oldalára kerülnek.
* `inv.slots` elementData: `{ left = { d = itemId, u = uid, m = model }, ... }` – ebből rajzol minden kliens.

## 3. Porták (`server/ports.lua`)

Marker + work_core stílusú 3D címke; `E` a markerben nyit, ha a játékosnál (kézben / háton) tároló van.
Láthatóság: `visibleTo` lista és / vagy `dataKey` (+ `dataValue`). Játékosonkénti `allowIn` / `allowOut` szabály
és javaslatok (`in` / `out` jelölés + banner szöveg). Események: `onPortOpen` (megszakítható), `onPortItemMoved`.

## 4. Csomagtartó (`server/trunks.lua`)

Láthatatlan horgony a jármű hátulján (`INV.TRUNK_OFFSET` vagy `opts.offset`), ui_interactobject menü
(`selfDataKey` = a hozzáférés kulcsa), „Csomagtartó kinyitása” → átpakoló ablak. Kapacitás kg-ban.
A jármű megszűnésekor a tartalma törlődik.

## 5. UI (kliens)

| Felület | Fájl | Leírás |
|---|---|---|
| Kéz / hát HUD | `client/hud.lua` | jobb lent: L / R / BACK, ikon, név, súly, a tárgy `meta.display` sorai, tároló-összesítő, `meta.bar`; `H` / `I` kulcsok |
| Ablak | `client/window.lua` | `I` = saját inventory (jobb oldalon a kijelölt tárgy részletei); porta / csomagtartó / tároló: jobb oldalon a másik fél. Húzás, dupla katt (gyors mozgatás), » / « gombok, Shift = egy darab, kihúzás az ablakból = letesz. ESC / I zár. |
| Porta címke | `client/ports.lua` | 3D címke, `E` |
| Kézi objektumok | `client/hands.lua` | csontra helyezés `onClientPedsProcessed`-ben |

Nyitott ablaknál a `inventoryOpen` helyi elementData él; a ui_interactobject, a ui_inac és a ui_pause ezt
blokkoló panelnek veszi.

### 5.1 Meta megjelenítés

`meta.display = { { label = <szöveg | v_locals üzenetobjektum>, value = ... }, ... }` – a HUD és az ablak mutatja.
`meta.bar = { label, value, max }` – sáv (pl. oxigén).

---

## 6. Exportok (szerver)

```lua
-- tárgyak
createItem(defId, meta, loc, { amount, access = { dataKey, dataValue } }) -> uid | false, err
destroyInventoryItem(uid)          getItem(uid)            getItemDef(defId)       isItem(uid)
setItemMeta(uid, key, value)       getItemMeta(uid [, key])
setItemAmount(uid, n)              takeItemAmount(uid, n)  -> maradék (0-nál törlődik)
setItemAccess(uid, dataKey | false [, dataValue])
moveInventoryItem(uid, loc, { amount, player })            -> uid | false, reason
getItemPosition(uid)               -> x, y, z, dim, int, topLocType
findItems(loc, { def, owner, deep })                       -> { uid }
getContainerItems(uid)  getContainerContents(uid)  getContainerWeight(uid)  clearContainer(uid)
-- játékos
getPlayerSlots(player)  giveItemToPlayer(player, uid [, slot])  isPlayerHandsFree(player)
dropPlayerItems(player [, slots, px, py, uids])  dropItem(uid, x, y, z, rz, dim, int [, snapPlayer])
-- rögzítés / jármű
attachItem(uid, element, offset)   getItemAttachedTo(uid)
storeItemInVehicle(uid, vehicle [, tag])                   getVehicleStoredItems(vehicle [, tag])
-- porták
createPort(opts) -> id   destroyPort(id)   setPortVisibleTo(id, players | nil [, dataKey | false, dataValue])
addPortItem(id, uid)   removePortItem(id, uid [, loc])   getPortItems(id)
setPortRules(id, player, { allowIn, allowOut })   clearPortRules(id, player)
setPortSuggestions(id, player, { [uid | defId] = "in" | "out" }, banner)   isPlayerInPort(player, id)
-- csomagtartó
createTrunk(vehicle, { capacity, dataKey, dataValue, offset, title })   destroyTrunk(vehicle)   hasTrunk(vehicle)
setTrunkAccess(vehicle, dataKey, dataValue)   addTrunkItem(vehicle, uid)   removeTrunkItem(vehicle, uid [, loc])
getTrunkItems(vehicle)
-- ablak
openInventory(player [, { container = uid, readOnly }])   closeInventory(player)
```

Események (szerver, source = a v_inventory resourceRoot): `onInventoryItemMove` (megszakítható),
`onInventoryItemMoved`, `onInventoryItemDestroyed`, `onInventoryItemChanged`, `onInventoryReady`,
`onPortOpen` (megszakítható), `onPortItemMoved`.

---

## 7. Más resource-ok változásai

| Resource | Változás |
|---|---|
| med_bag | Teljes átírás a v_inventory-ra (lásd med_bag/DESIGN.md 17. fejezet). |
| medsys | `MEDIC_EQUIPMENT`: kötszer / sín fogy (`consume = "done"`), glucometer / légútkészlet kell a táskába; új szövegek. |
| work_ems tutorial | A kézben tartás az `inv.slots`-ból; a szövegek (tartalomablak, járműbe szállás, fogyás) frissítve. |
| ui_interactobject, ui_inac, ui_pause | Az `inventoryOpen` blokkoló jelző. |
| v_locals | `locales/en|hu/v_inventory.json`, új med_bag / medsys / work_ems kulcsok. |

## 8. Tesztek

`python tests/run.py` – lupa (Lua 5.1), a szerver logika MTA-csonkokkal: 41 eset (létrehozás, halmozás, súly,
accepts, slotok, részmennyiség, megszakítható esemény, porta-szabályok, jármű, rögzítés, csomagtartó, tulajdonos leállása).
Élőben (2026-10-15, claude-mcp): a v_inventory és a med_bag hiba nélkül indul; egy teszt-ambulancia kitje
létrejött (18 tárgy, 6,95 / 10 kg); fogyasztás, letevés, hordágyra rögzítés, `aboard` tárolás, feltöltés,
porta, csomagtartó működik. **A UI (HUD, ablak, címkék, kézi offsetek) játékban még nincs kipróbálva.**

## 9. Nyitott / később

* A `bt_blood_box` (2969) és a `backpack` (371) modellje és offsetjei nincsenek ellenőrizve.
* Fegyver és tárgy egyszerre a kézben: a v_weaponselector fejlesztésekor (`isPlayerHandsFree`).
* A régi, már nem használt med_bag szövegkulcsok a katalógusban maradtak.
