# v_bank 2 – design

Status: **implemented 2026-10-23** (all phases), offline-tested only (unit tests, syntax); not yet
tested in-game. Decisions in section 12. Author in meta.xml: `DrAndrew112`.

Deviations of the implementation: the airspace fee is three keys (`atc.fee_takeoff`,
`atc.fee_landing`, `atc.fee_overflight`); the casino uses `biz.casino_hour` / `biz.casino_loss`;
extra keys `biz.register_refund`, `biz.office_refund`, `biz.write_off`; transfers use one key
(`transfer.account`) with the text picked by the sign (`.in` / `.out`).

Change 2026-10-24: v_bank creates only the **State Treasury** by itself; SA Control (and every other
state body) is an ordinary state company made on the /gov Companies page. Every tax and every fee
(registration, rename, bay fine, airspace takeoff / landing / overflight) goes to the state account
chosen for it on the Taxes / Fees page (`tax.targets`, `fee.targets`; v_bank side `"payee"`); with
none chosen (the default) the money disappears. The ATC work is paid from system unless /gov sets a
payer. Statements below that send a tax or fee to the treasury or to SA Control describe the old
default.

## 1. Goals

- Every bank balance lives in MySQL in **`bank_accounts`**; every change of a balance writes one row
  to **`bank_ledger`**. `bank_money` is **no longer stored in the account data** at all – the table
  and v_bank's cache own it.
- Three kinds of account:
  - **personal** – one per player account;
  - **company** – one per biz_core organization, *clean money only*;
  - **state** – state bodies: the **State Treasury** and the **state companies** admins create
    (first one: **SA Control**).
- Bookings use **predefined transaction keys** only. A key decides the direction, the counterparty
  and the text. The text is localized when shown (v_locals), so the ledger is language-independent.
- **Cash is not tracked.** The ledger sees cash only at the bank's edge: deposit and withdrawal.
- Dirty money stays in biz_core (`balance_dirty`, `biz_ledger`) and **never enters a bank account**:
  dirty withdrawals and the associates' / outside thieves' delivery shares are paid in cash, and a company's dirty
  money is lost when the company is sold.
- Some accounts may go **negative**; they are on the overdraft list (section 3.2).
- Works on both server instances at once (they share the database).

Non-goals (now): taxes themselves (keys reserved), loans/interest, cards, ATMs.

## 2. Database

```sql
CREATE TABLE IF NOT EXISTS bank_accounts (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    number      VARCHAR(20)  NOT NULL,              -- shown to players, e.g. "LB-1-000042"
    kind        VARCHAR(16)  NOT NULL,              -- 'personal' | 'company' | 'state'
    owner_ref   VARCHAR(64)  NOT NULL,              -- personal: account name (lower-case)
                                                    -- company:  biz_companies.id
                                                    -- state:    code, e.g. 'treasury', 'sacontrol'
    name        VARCHAR(64)  NOT NULL DEFAULT '',   -- display name (company / state body)
    balance     BIGINT       NOT NULL DEFAULT 0,
    allow_negative TINYINT   NOT NULL DEFAULT 0,    -- the overdraft list (3.2)
    status      VARCHAR(16)  NOT NULL DEFAULT 'active',  -- 'active' | 'frozen' | 'closed'
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    created_by  VARCHAR(64)  NOT NULL DEFAULT '',
    closed_at   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_number (number),
    UNIQUE KEY uq_owner (kind, owner_ref),          -- every "create if missing" is idempotent
    KEY idx_kind (kind, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- who may see / use an account besides the personal owner (implicit)
CREATE TABLE IF NOT EXISTS bank_account_access (
    account_id   INT UNSIGNED NOT NULL,
    account_name VARCHAR(64)  NOT NULL,             -- player account name (lower-case)
    role         VARCHAR(16)  NOT NULL,             -- 'owner' | 'manager' | 'viewer'
    granted_by   VARCHAR(64)  NOT NULL DEFAULT '',
    granted_at   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (account_id, account_name),
    KEY idx_name (account_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS bank_ledger (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    account_id    INT UNSIGNED NOT NULL,
    ts            INT UNSIGNED NOT NULL,
    amount        BIGINT       NOT NULL,            -- signed: + in, - out
    balance_after BIGINT       NULL,                -- NULL when booked on an unloaded account (2.1)
    tx_key        VARCHAR(48)  NOT NULL,            -- section 4
    params        VARCHAR(255) NOT NULL DEFAULT '', -- JSON, values for the localized text
    counter_id    INT UNSIGNED NULL,                -- the other account of a transfer
    ref           VARCHAR(32)  NOT NULL DEFAULT '', -- same value on both rows of a transfer
    actor         VARCHAR(64)  NOT NULL DEFAULT '', -- account name of who caused it ('' = system)
    instance      VARCHAR(16)  NOT NULL DEFAULT '', -- which server booked it
    PRIMARY KEY (id),
    KEY idx_account (account_id, id),
    KEY idx_key (tx_key, ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

`bank_account_access` is a third table next to the two requested ones: "who may access" is a list
per account, and the bank website must answer "which accounts can *I* see" with one indexed query.

### 2.1 Bookings on accounts that are not loaded

A booking is always a **delta** (`UPDATE bank_accounts SET balance = balance + ? WHERE id = ?`), so
it is safe on an account that is not in this server's memory (offline player, a company whose founder
is offline, an account in use on the other instance). `balance_after` is then `NULL`.

## 3. Accounts

| Kind | Created by | owner_ref | Access |
| --- | --- | --- | --- |
| personal | migration; on first login of a new account | account name | the owner (implicit) |
| company | migration; biz_core when an organization is founded | company id | founder = `owner` row, kept current by biz_core |
| state | treasury: v_bank on start; state companies: admin panel | code | rows in `bank_account_access`, set in the admin panel; admins see all |

Account number: `LB-<kind digit>-<6-digit id>` – `1` personal, `2` company, `9` state
(e.g. `LB-9-000001` treasury). Built from the id, so it never collides.

Taxes, healthcare billing, wage payers and the management of state companies belong to **v_gov**
(`[economy]/v_gov/DESIGN.md`); v_bank only books.

Closing: a sold company's account is emptied by the sale (6.3) and set to `closed`. Closed and frozen
accounts refuse every booking except `admin.*` keys.

### 3.1 State companies

A **state company** is a `state` account with a code, a name and access rows – **not** a biz_core
organization (no properties, upkeep, dirty money, OrgOS). They are created, renamed, deleted and their members
managed in the **v_gov** panel (`/gov`, v_gov DESIGN 9). The first one is **SA Control** (`sacontrol`), responsible for aviation: it collects the
airspace usage fees and pays the controllers' wages. The **State Treasury** (`treasury`) is created
by v_bank itself and cannot be closed.

Other resources find a state account by code: `exports.v_bank:getStateAccount("sacontrol")`. A code
used in a config that does not exist (yet) makes the booking fail with `"unavailable"` and a log line.

### 3.2 Overdraft list

`allow_negative = 1` marks the accounts whose balance may go below 0 on *any* outgoing booking. The
list is managed in the admin panel (Bank → Overdraft list) and seeded with **treasury** and
**sacontrol**. Everyone else can only go negative through `force` keys (fines, work deductions), as
today; such debt is paid off by the next incoming money.

## 4. Transaction keys

`v_bank/shared/keys.lua` is the **only** list of what can happen to a balance. A booking with an
unknown key, a key used on the wrong account kind or in the wrong direction is refused
(`"bad_key"`) and logged with the calling resource name.

```lua
TX.KEYS["fine.hospital_bay"] = {
    dir     = "out",          -- "in" | "out" | "both"
    kinds   = { personal = true },
    counter = "treasury",     -- "treasury" | "system" | "cash" | "account" | "payer"
    force   = true,           -- may push the balance below 0 (debt)
    params  = { "hospital" }, -- allowed params (anything else is dropped)
    taxable = false,          -- counts as legal company income for the hourly tax (v_gov 4)
}
```

Counterparty:
- `"treasury"` – automatically a transfer with the State Treasury.
- `"system"` – money enters / leaves the economy (shop prices, property market, admin).
- `"cash"` – deposit / withdrawal only.
- `"account"` – a transfer between two accounts the caller gives (player ↔ company, player ↔ player).
- `"settled later"` – the money leaves the player now and the caller books the matching income in
  one sum later (hospital bay fines, 6.4).
- `"payer"` – the caller gives the paying account: a `state` or `company` account, or `system`
  (work wages, set per work in v_gov).
- `"payee"` – the caller gives the receiving `state` account, or none = `system` (the money
  disappears): the taxes, sent where the v_gov Taxes page says (`getTaxTarget`).

Text: `L.msg("v_bank.tx.<key>", params)` in the **viewer's** language. Params hold plain values
(work id, company name *snapshot*, hospital id, the transfer's note …).

### 4.1 Key list

| Key | Dir | Kinds | Counter | Used by |
| --- | --- | --- | --- | --- |
| `cash.deposit` / `cash.withdraw` | in / out | personal | cash | bank website, `depositMoney` / `withdrawMoney` |
| `transfer.out` / `transfer.in` `{note}` | pair | personal, company, state | account | bank website transfer (section 8) |
| `work.pay` `{work}` | in | personal | payer (force: the payer may go negative) | work_core `payWork` |
| `work.deduction` `{work}` | out (force) | personal | payer | work_core `payWork` negative total (ATC mistakes) |
| `fine.hospital_bay` `{hospital}` | out (force) | personal | settled later | med_hospitals, every fine interval (6.4) |
| `fine.hospital_bay_income` `{patient, hospital, count}` | in | state (treasury) | system | med_hospitals, once the vehicle left the bay (6.4) |
| `atc.airspace_fee` `{kind, callsign, airline, airport}` | in | state (sacontrol) | system | aviation, per flight event (6.5) |
| `shop.weapon` / `shop.weapon_refund` | out / in | personal | system | wp_shop |
| `shop.vehicle` / `shop.vehicle_refund` | out / in | personal | system | ui_browser dealership |
| `phone.service` `{contact, action}` | out | personal | system | ui_phone contacts |
| `biz.register_fee` | out | personal | treasury | biz_core createCompany (registration fee) |
| `biz.office_purchase` `{property}` | out | personal | system | biz_core createCompany (office price) |
| `biz.deposit` / `biz.withdraw` | pair | personal ↔ company | account | biz_core founder deposit / clean withdrawal |
| `biz.close_payout` | pair | company → personal | account | biz_core sellCompany (clean balance) |
| `biz.asset_sale` | in | personal | system | biz_core sellCompany (asset part) |
| `biz.property_buy` / `_refund` / `_sell` / `_upgrade` `{property}` | out / in | company | system | biz_core units |
| `biz.upkeep` `{count}` | out | company | system | biz_core tick |
| `biz.rename_fee` | out | company | system | biz_core rename |
| `biz.launder` `{fee}` | in | company | system | biz_core processLaunder (clean side) |
| `biz.casino_hour` (taxable) | both | company | system | biz_casino |
| `biz.weed_supply` `{units}` | out | company | system | biz_weed |
| `tax.company_income` `{hour, base, rate}` | out (force) | company | treasury | v_gov hourly company tax |
| `tax.income` `{work, key, rate}` | out | personal | treasury | work_core `payWork` (income tax) |
| `health.care` `{patient, account, hospital, hp, injuries}` | pair (force) | system / state / company | system / state / company | v_gov / med_hospitals (per-hospital payer) |
| `health.patient` `{hospital, hp, injuries}` | out (force) | personal | system / state / company | v_gov / med_hospitals (the patient pays) |
| `gov.transfer` `{note}` | pair | state ↔ state | account | v_gov panel |
| `gov.company_payment` `{note}` | pair | state → company | account | v_gov Transfers page |
| `gov.collection` `{note}` | pair (force) | company → state | account | v_gov Transfers page (inkasszó) |
| `admin.credit` / `admin.debit` `{note}` | in / out (force) | all | system | admin panel |
| `admin.transfer` `{note}` | pair | all | account | admin panel |
| `migration.opening` | in | all | system | one-time migration (section 7) |

## 5. Runtime (v_bank server)

- **Cache.** `ACC[id] = { id, kind, ownerRef, balance, status, allowNegative }`. Personal accounts
  are loaded asynchronously on `onPlayerLoaded` and bound to the player; until then a booking on them
  returns `"unavailable"`. On `onPlayerQuit` the account leaves the cache – there is nothing to save,
  every booking is already in the table.
- **Mirror.** The personal balance stays in the synced element data **`bank_money`** (read-only for
  clients, the existing guard stays) plus `bank_account` (number), so ui_core, ui_pause, the browser
  HUD, biz_pc, biz_web and the v_admin panel keep working unchanged. Element data only – never
  written to account data.
- **Writes.** Every booking: check (cache) → update cache → `mysqlExec` delta UPDATE + ledger INSERT
  (fire-and-forget, retried by v_mysql after reconnect; same connection = FIFO). Exports stay
  **synchronous** (`true` / `false, err`).
- **Shared accounts** (company, state) can be booked from both instances. They are cached on use and
  re-read every 30 s with the "deltas issued after the SELECT are added on top" trick of biz_core
  `CO.resync`. The balance check uses the cache, so a cross-instance race can overdraw a company by a
  little; it is logged and accepted.
- **Personal accounts** are online on one instance only, so their cache is authoritative.
- Event `onBankBalanceChanged(accountId, balance, amount, key)` (server, at v_bank resourceRoot).

## 6. API (server exports)

```lua
-- accounts
getPlayerAccount(player)              -> id | false (not loaded)
getCompanyAccount(companyId)          -> id | false
getStateAccount(code)                 -> id | false      -- "treasury", "sacontrol", ...
getAccountByNumber(number)            -> id | false
getAccountInfo(id)                    -> { id, number, kind, name, balance, status, allowNegative } | false
getBalance(id)                        -> number | false
createCompanyAccount(companyId, name, founderAccountName) -> id | false
createStateAccount(code, name, actor) -> id | false, err   -- admin panel
closeAccount(id, actor)               -> true | false, err  (balance must be 0)
setAccountStatus(id, status, actor)   / setAllowNegative(id, bool, actor)
setAccess(id, accountName, role|nil, actor)
hasAccess(player, id, need)           -> bool   -- need = "view" | "use"
getAccessibleAccounts(player)         -> { {id, number, kind, name, balance, role}, ... }

-- bookings (amount = positive integer, key from section 4)
credit(id, amount, key, params, actor)             -> true | false, err
debit(id, amount, key, params, actor)              -> true | false, err
transfer(fromId, toId, amount, key, params, actor) -> true | false, err
--   err: "bad_amount" | "bad_key" | "unavailable" | "not_enough_money" | "account_closed" | "frozen"

-- player wrappers (kept, now with a key)
giveBankMoney(player, amount, key, params [, payerId])  -> true | err
takeBankMoney(player, amount, key, params)              -> true | err
forceTakeMoney(player, amount, key, params [, payeeId]) -> true, newBalance | err
depositMoney(player, amount)                            -> true | err   -- cash.deposit
withdrawMoney(player, amount)                           -> true | err   -- cash.withdraw
payMoney(player, amount, key, params)                   -> true, "cash"|"bank" | false, err
--   the cash branch books nothing; only the bank branch writes a ledger row

-- ledger (website / admin panel; async, answers with a client event)
requestLedger(player, id, beforeId, limit, keyPrefix) -> true | false, err
```

`playPickupMoneySound` and `createMoneyPickup` stay as they are (cash only).

### 6.1 Work wages

The payer of every work is a v_gov setting (`exports.v_gov:getWorkPayer(workId)`, Works page):
system (the default), the treasury, a state company or a private company. Seeded: `ems`,
`bloodtransport` → treasury, `atc` → SA Control. Without v_gov every work is paid from system.

`payWork` books `work.pay` from that payer, then the personal income tax (`tax.income`, v_gov 5). New option `chargeNegative = true`: a negative total is
taken from the player as `work.deduction` (force) and goes **to the same payer** (ATC mistakes →
SA Control).

### 6.2 Treasury

In: company income tax, personal income tax, hospital bay fines, and of all fees **only the company
registration fee (€ 50 000)**.
Out: the EMS and blood transport wages and hospital care (`health.care`, players and NPC patients) –
healthcare only – plus transfers to state companies from the v_gov panel. It is on the overdraft list.

Money that **disappears** (counter "system", against inflation): every shop purchase paid from the
bank, every property purchase / upgrade (office price included), the rename fee, company upkeep.

### 6.3 Company money (biz_core)

- Clean balance = the company bank account; `c.clean` mirrors `onBankBalanceChanged`.
- `MONEY.debit` still takes the clean part first (bank), then dirty (biz_core).
- Dirty withdrawal by the founder → **cash** (`givePlayerMoney`), not booked.
- Sale delivery: the founder's delivery goes (dirty) to the company as now; the **associate's** share
  and the **outside thief's** share are paid as **cash** at the end.
- Casino: the whole hour result flows into the company account (`biz.casino_hour`); the company
  income tax is taken afterwards as a separate ledger row by v_gov's hourly run.
- Sale of the company: clean balance → founder (`biz.close_payout`), asset part (`biz.asset_sale`),
  **dirty money is lost**; then `closeAccount`.

### 6.4 Hospital bay fines

While an unauthorized vehicle stays in an ambulance bay, med_hospitals takes `HOSP.BAY_FINE` from the
driver every interval (`forceTakeMoney`, key `fine.hospital_bay` – the player sees each one) and adds
it up per violation. When the vehicle **leaves the bay** (or the offender quits, or med_hospitals
stops) the violation is closed and the sum is credited to the treasury in **one** row,
`fine.hospital_bay_income` `{patient = name, hospital, count}`. The fine amount is a v_gov setting.

### 6.5 Airspace usage fees (SA Control)

Money from nothing (counter "system"): it is paid by the airline of the AI flight. avi_traffic gets
a new event `onAviFlightFee(kind, callsign, airline, airport)` for three moments, each with its own
amount (v_gov setting, Fees page):
- `takeoff` – a departure from a San Andreas airport becomes airborne;
- `landing` – an arrival touches down at a San Andreas airport;
- `overflight` – an external → external flight leaves the airspace.

The aviation side books `atc.airspace_fee` on SA Control, one row per event, e.g.
"Landing fee – SAX123 (Sky Airlines), LSIA". The ATC wages SA Control pays come out of this income.

## 7. Migration (automatic, idempotent)

On v_bank start (both instances may run it; `uq_owner` + `INSERT IGNORE` make it safe):

1. `CREATE TABLE IF NOT EXISTS` the three tables. `INSERT IGNORE` the treasury and SA Control
   (`allow_negative = 1`).
2. **Players:** one `INSERT IGNORE INTO bank_accounts … SELECT … FROM accounts` for every account
   without a personal bank account, balance = `account_data.$.bank_money.v` (0 when missing, debt
   kept), plus a `migration.opening` ledger row for each.
3. Then `bank_money` is **removed** from the account data JSON (`JSON_REMOVE`) of every account that
   has a bank account – from now on it exists only in the table and the cache.
4. **Companies:** every active `biz_companies` row without a company account gets one with balance =
   `balance_clean` and an `owner` access row; then `balance_clean = 0` (column kept, unused).
5. New accounts later: personal on first `onPlayerLoaded`, company in biz_core `createCompany`.

## 8. Liberty Bank website (ui_browser, libertybank.eu)

- **Account switcher:** personal + every account from `getAccessibleAccounts` (company accounts of
  the founder, state companies where the player has access). Header: number, holder, balance.
- **Transactions:** paged list (25 rows, "older" → `requestLedger` with `beforeId`), filter by
  category (cash, work, fine, shop, biz, transfer). Row: date, localized text, signed amount
  (green / red), balance after when known, counterparty number for transfers.
- **Deposit / withdraw** (personal account) as now.
- **Transfer:** from the selected account (role `owner`/`manager`, or personal) to an account number,
  amount, short note (max 60 chars, shown in both ledgers). Confirmation step shows the recipient's
  name. Checks: target exists and is active, not the same account, balance (overdraft list counts).
- Company account (founder): the same page; dirty money is not shown (OrgOS computer only).

## 9. Admin panel (v_admin, O-key panel and /v_admin/ web)

New page **Bank**:
- **Accounts:** search by number / holder / kind; list with balance, status, overdraft flag.
- **Account view:** ledger (paged, filter), access list (add / remove / role), freeze / unfreeze,
  overdraft on / off.
- **Add / take money:** amount + mandatory note → `admin.credit` / `admin.debit` (system), or
  `admin.transfer` between two accounts. Works on offline accounts too (delta booking). Every action
  also goes to the admin log.
- State companies are managed in v_gov (`/gov`); here they appear like any other account.
- **Overdraft list:** every account with `allow_negative = 1`, toggle.
- Admin level for each action from v_admin perms (new perms: `bank.view`, `bank.edit`).

The existing Accounts page: list query `LEFT JOIN bank_accounts` instead of `jsonKey("bank_money")`;
the "bank" edit becomes an `admin.credit`/`admin.debit` of the difference.

## 10. Integration – what changes where

| Resource | File(s) | Change |
| --- | --- | --- |
| **v_bank** | all | rewrite: `server/db.lua` (schema, migration), `server/accounts.lua` (cache, resync), `server/ledger.lua`, `server/exports.lua`, `shared/keys.lua`, `locals.lua` (tx texts), README |
| main.sql | – | the three tables |
| **v_gov** (new) | – | taxes, healthcare billing, wage payers, state companies, `/gov` panel – see `v_gov/DESIGN.md` |
| **work_core** | `server/payment.lua`, `shared/config.lua` | payer per work (6.1), income tax line, `chargeNegative` |
| med_hospitals | `server/heal.lua`, `server/handover.lua` | `v_gov:chargeHealthcare` before `healCompletely` |
| avi_controller | `server/main.lua:186-188` | drop own `forceTakeMoney`, `payWork(..., { chargeNegative = true })`; wages from SA Control |
| avi_traffic, avi_controller | `server/sim.lua` + a fee handler | `onAviFlightFee` at takeoff / landing / overflight exit; `atc.airspace_fee` into SA Control (6.5) |
| med_hospitals | `server/restricted.lua` | per-violation sum, one treasury credit when the bay is left (6.4) |
| med_erm, bt_dispatch, work_traindriver | – | no code change; payer in work_core config |
| wp_shop | `server/main.lua:104,110` | keys `shop.weapon` / `shop.weapon_refund` |
| ui_browser | `dealership.lua:152,160` | keys `shop.vehicle` / `_refund` |
| ui_browser | `server.lua`, `core/home.lua` | website of section 8 (account switch, ledger, transfer) |
| ui_phone | `server/apps/contacts.lua:31,43` | balance via `getBalance`, key `phone.service` |
| **biz_core** | `money.lua`, `actions.lua`, `sales.lua`, `units.lua`, `tick.lua`, `admin.lua`, `companies.lua`, `db.lua` | 6.3 + keys of 4.1; resync reads only dirty / launder; `biz_ledger` keeps only dirty rows |
| biz_casino, biz_weed | `creditCompany` / `debitCompany` callers | category → bank key |
| biz_pc, biz_web | finance pages | `bank_ledger` (clean) + `biz_ledger` (dirty) merged by time |
| biz_core tests | `tests/stubs.lua` | new v_bank stub |
| **v_admin** | `server/pages/accounts.lua`, new `server/pages/bank.lua` + web page | section 9 |
| acc_savesys | `server/modules.lua:115` | menu balance from `getBalance` / join, not account data |
| ui_core, ui_pause, browser HUD, v_admin panel | – | no change (element data mirror) |
| v_introduce | `modules/06_money` texts | mention transfers / statements (text only) |
| v_jobmanager, v_gangwar, v_timetrial, v_weekly, v_customs, clothes shop, v_shop_robbery, v_admin `/money` | – | **no change** – cash only, not tracked |

## 11. Implementation phases

1. v_bank core: schema, keys, cache, bookings, exports, migration (incl. treasury + SA Control),
   locales, README.
2. Callers: work_core (+payer, chargeNegative), avi_controller, med_hospitals, wp_shop, dealership,
   ui_phone, acc_savesys.
3. biz_core + biz_casino + biz_weed + biz_pc/biz_web ledger merge + tests.
4. Liberty Bank website (accounts, ledger, transfer).
5. v_admin Bank page (accounts, ledger, add/take, state companies, overdraft list) + Accounts page.
6. Airspace fees (after Q1), docs, memory.

Offline tests with the Lua test runner (lupa): key validation, transfer pairs, force/debt, overdraft
list, cache resync with in-flight deltas.

## 12. Decisions and open questions

Decided 2026-10-23:
- Outside thief's delivery share → cash. Dirty money of a sold company → lost. Dirty withdrawal → cash.
- Treasury and SA Control may go negative; overdraft list managed by admins.
- Transfers on the bank website: yes.
- `bank_money` is not kept in account data; the table + cache own it (removed by the migration).
- Treasury pays only the EMS and blood transport wages.
- SA Control = state company, collects airspace usage fees, pays the controllers.
- Admin panel: manage accounts, view statements, add / take money.
- State companies, taxes (company 10 % hourly, income 12 %), state healthcare: v_gov (`/gov`).

Decided later the same day:
- Airspace usage fee = money from nothing, paid by the flight's airline; takeoff, landing and
  overflight have separate amounts (6.5).
- The associate's delivery share is cash too.
- Shop and property purchases from the bank disappear ("system"), against inflation. Of all fees
  only the company registration fee (€ 50 000) goes to the treasury.
- Hospital bay fines reach the treasury in one sum when the vehicle has left the bay (6.4).
- Wages of the works are set in `/gov` (v_gov DESIGN 5).

No open questions left in this document.
