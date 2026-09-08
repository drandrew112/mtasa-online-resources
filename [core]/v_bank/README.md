# v_baml — Bank kezelo

Szerver oldali bankszámla-kezelő. A `bank_money` futásidőben a player element
data-ján él, és tükröződik az account data-ba, így túléli az újracsatlakozást és
a resource újraindítást. A **cash** a GTA saját pénze, azt csak a beépített
`takePlayerMoney` / `givePlayerMoney` mozgatja.

## Perzisztencia

| Esemény | Művelet |
| --- | --- |
| `onPlayerLogin`, `onResourceStart` | account → element data betöltés (első login: 0) |
| `onPlayerQuit`, `onPlayerLogout`, `onResourceStop` | element data → account mentés |
| 5 percenként | minden bejelentkezett játékos mentése |
| minden export ami módosít | az adott játékos azonnali mentése |

Guest (be nem jelentkezett) játékosnál a `bank_money` csak futásidőben létezik,
mentés nem történik.

## Szerver oldali exportok

```lua
local bank = exports.v_baml
```

### `takeBankMoney(player, amount)`
Levon a bankszámláról.
- `true` — siker
- `"not_enough_money"` — nincs elég pénz a számlán
- `"player_not_found"` — érvénytelen player elem vagy `amount`

### `giveBankMoney(player, amount)`
Hozzáad a bankszámlához.
- `true` — siker
- `"player_not_found"` — érvénytelen player elem vagy `amount`

### `depositMoney(player, amount)`
Elveszi a cash-t és a számlához adja.
- `true` — siker
- `"not_enough_cash"` — nincs elég készpénz
- `"player_not_found"` — érvénytelen player elem vagy `amount`

### `withdrawMoney(player, amount)`
Elveszi a számláról és cash-ként adja oda.
- `true` — siker
- `"not_enough_money"` — nincs elég pénz a számlán
- `"player_not_found"` — érvénytelen player elem vagy `amount`

> **Eltérés a specifikációtól:** a `withdrawMoney` a bankegyenleget vizsgálja,
> ezért az elégtelen fedezet hibája `"not_enough_money"` (a `takeBankMoney`-val
> egységesen), nem `"not_enough_cash"`. Ha mégis a `"not_enough_cash"` string
> kell, a `server.lua`-ban egy sor átírásával megoldható.

Az `amount` minden exportnál pozitív egész számmá kerekítődik; 0 vagy negatív
érték `"player_not_found"`-ot ad vissza (érvénytelen bemenet).

### `playPickupMoneySound([player])`
Lejátssza a "pickup money" hangot.

- **Szerver oldali export:** `exports.v_bank:playPickupMoneySound(player)` —
  a megadott játékosnál szólal meg. `player` nélkül mindenkinél lejátszódik.
  Visszatérés: `true` vagy `"player_not_found"`.
- **Kliens oldali export:** `exports.v_bank:playPickupMoneySound()` —
  a helyi játékosnál szólal meg, visszaadja a sound elemet (vagy `false`).

### `createMoneyPickup(x, y, z, money [, player])` — szerver
Létrehoz egy pénzeszsák pickupot (`1550` modell). Amikor egy játékos rálép:
kap `money` készpénzt, lejátszódik neki a pickup hang, elindul a
`v_bank:moneyCollected` kliens event (`money` argumentummal), és a pickup törlődik.

- `money` — pozitív egész
- `player` — opcionális; ha megadva, csak ő tudja felvenni; `nil` esetén bárki
- Visszatérés: a pickup elem, vagy `false` (érvénytelen argumentum)
