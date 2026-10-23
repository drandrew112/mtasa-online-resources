# v_gov – design

Status: **implemented 2026-10-23** together with v_bank 2, offline-tested only; not yet tested
in-game. Decisions in section 14. Author in meta.xml: `DrAndrew112`.

Deviation: there is no `importWage()` lib; each work registers its parameters with
`registerWage` and reads them with `getWage` through a small local helper.

## 1. What it is

The state of San Andreas as a system: one place for **taxes, wages, fees and fines, state
healthcare, the state companies and every important state setting**. Its money is the **State
Treasury** (v_bank `state:treasury`). Opened with **`/gov`**, which shows its own panel.

v_gov owns the *rules and numbers*; v_bank does every booking. Other resources ask v_gov
(`getSetting`, `getWage`, `getWorkPayer`, `getIncomeTaxRate`, `chargeHealthcare`, …) and book through v_bank with the keys
of section 8.

## 2. Access

- `/gov` opens the panel for players with a gov role; others get "no access".
- Roles in `gov_members` (section 9): `viewer` (read everything), `official` (state companies,
  healthcare prices), `minister` (tax rates, wages, fees, members – everything). Admins with level
  ≥ 5 (`GOV.ADMIN_LEVEL`) count as `minister` without a row.
- Members are managed on the panel's Members page (minister).

## 3. Panel pages

Own DX panel, built like the v_admin panel (page list on the left, page modules; server handlers
answer `reply(result, message)`), English UI text.

| Page | Content | Edit |
| --- | --- | --- |
| **Overview** | treasury balance, income / expense of the last 24 h and 7 days by category (company tax, income tax, fines, registration fees, healthcare, wages), last tax run | – |
| **Treasury** | treasury statement (paged ledger, filter by key), transfer to a state company | minister |
| **Taxes** | company income tax rate (**10 %**), the personal income tax **rate keys** (5.3: `standard` 12 %, `exempt` 0 %, new ones can be added), history of the hourly runs | minister |
| **Works** | per work, everything (section 5): payer (system / treasury / state company / private company), every pay and XP parameter, wage multiplier, income tax rate key | minister |
| **Fees & fines** | company registration fee (**€ 50 000**, → treasury), rename fee, hospital bay fine, airspace usage fees: takeoff / landing / overflight (→ SA Control) | minister |
| **Healthcare** | on / off, price per HP (**€ 50**), injury price list (type × severity), totals per hospital, last bills | official |
| **State companies** | list (code, name, balance, members, overdraft), create, rename, delete, members, overdraft on / off, transfer treasury ↔ company | official |
| **Members** | gov roles | minister |
| **Log** | every change made on the panel (who, when, old → new) | – |

Every value is validated server-side against the range of its definition (e.g. tax 0–50 %, a wage
parameter 0 … 10 × its default).

## 4. Company income tax (hourly)

Every full hour the state takes **10 %** of the **legal** income a company had in that hour, as a
separate, visible row in the company's books.

- **Legal income** = bank_ledger rows of the company account in that hour whose key is flagged
  `taxable = true` in v_bank's key list. For now that is **only the casino** (`biz.casino_hour`); more
  legal activities get the flag later. Deliveries are dirty money and never taxed; deposits,
  property sales, laundering, transfers and admin bookings are not income.
- The casino's whole hour result flows into the company first (v_bank DESIGN 6.3); the tax comes
  afterwards in the run.
- **Base** = sum of the taxable rows of the hour (a losing casino hour is a negative row, so the base
  is the hour's net result). Tax only when base > 0 – a losing hour pays nothing: `tax = floor(base * rate)`.
- **Run:** at every full hour (+30 s): `SELECT account_id, SUM(amount) FROM bank_ledger WHERE tx_key
  IN (…) AND ts >= ? AND ts < ? GROUP BY account_id`, then one `tax.company_income` booking per
  company: company → treasury, `force` (a company may go into debt, paid off by its next income).
  Params `{ hour = "14:00", base = 12345, rate = 10 }` → "Company income tax 10 % of € 12 345
  (14:00–15:00)".
- **One instance only:** the run claims the hour with `INSERT IGNORE INTO gov_tax_runs
  (period_start, …)`; only the instance whose insert affected a row runs it. Unclaimed hours of the
  last 24 h are caught up on start.
- The founder gets a notification when online; biz_pc / biz_web show the row in the merged ledger.

## 5. Works

**Everything about a work's pay is set here**, per work, on the Works page:

| Setting | Default | Section |
| --- | --- | --- |
| payer | **system** (money from nothing) | 5.2 |
| every pay parameter | the work's current config value | 5.1 |
| every XP parameter | the work's current config value | 5.1 |
| wage multiplier | 1.0 (on the whole total, before the v_weekly multiplier) | – |
| income tax rate key | `standard` (`ems`, `bloodtransport`: `exempt`) | 5.3 |

The page lists every work registered with work_core; a work without `WAGE_PARAMS` still gets payer,
multiplier and tax key. Each value shows current / default and "reset to default".

### 5.1 Pay and XP parameters

Every work declares its pay **and XP** parameters in its own config (`WAGE_PARAMS`, the current
values become the defaults) and registers them with v_gov on start:

```lua
exports.v_gov:registerWage("bloodtransport", {
    { key = "base",        label = "Base pay (per service)",    default = 600 },
    { key = "delivered",   label = "Per delivered task",        default = 1200 },
    { key = "in_transit",  label = "Per task still in transit", default = -450 },
    { key = "xp_delivery", label = "XP per delivery",           default = 40, kind = "xp" },
})
-- in the pay code:
local amount = Wage("delivered")   -- v_gov override, or the default when none / v_gov is down
```

v_gov stores only the overrides (`gov_settings` key `work.<work>.<param>`), so a work keeps paying its
defaults when v_gov is not running. The v_weekly multipliers still apply on top (work_core).

Initial parameters (from today's configs):

| Work | Pay | XP |
| --- | --- | --- |
| `ems` (med_erm `Config.PAY.RATES`) | base + per minute for each outcome: handover, released, left, task closed, shift ended, default | its XP values |
| `bloodtransport` (bt_dispatch `PAY`) | base, per delivered task, per task in transit | `XP_PER_DELIVERY` |
| `traindriver` (work_traindriver `PAY`) | base RB / IC / default, per stop, punctuality bonus (2 tiers), skip fine, early departure fine, delay fine | its XP values |
| `atc` (avi_controller) | per action, minute bonus, max multiplier, per controlled aircraft, mistake penalties GND / TMA / CTA | `XP_ACTIONS` per action type, `XP_DEFAULT` |

### 5.2 Payer

Per work: **system** (money from nothing – the **default** for every work), the **treasury**, a
**state company** or a **private company** (a biz_core organization's account, picked by name).

- `exports.v_gov:getWorkPayer(workId)` → v_bank account id or `"system"`; without v_gov: system.
- Seeded by the earlier decisions (changeable like any other value): `ems`, `bloodtransport` →
  treasury; `atc` → `sacontrol`. Every other work stays on system.
- Deductions of a negative total (`work.deduction`, e.g. ATC mistakes) go to the same payer.
- The wage is **always paid**: the payer's side of `work.pay` is a `force` booking, so a payer
  without enough money (e.g. a private company) simply goes **negative** and pays the debt off from
  its next income. The payer gets a notification when its balance drops below 0.
- A private company that is sold / closed while it is a payer: the work falls back to system and the
  Log page records it.

### 5.3 Personal income tax (SZJA)

- **Rate keys** are defined on the Taxes page: a key has a name and a rate, e.g. `standard` = 12 %,
  `exempt` = 0 %; ministers can add more (e.g. `reduced` = 5 %) and change the rates. A key in use by
  a work cannot be deleted.
- **Per work** the Works page picks the key. Changing a key's rate changes it for every work on it.
- Applied in work_core `payWork`, **after** the work's and the weekly multiplier, on the **whole**
  total; only when the final total is **positive** and the rate is above 0.
- `tax = floor(total * rate)` → an extra receipt line "Income tax (12 %)" with `-tax`; the player
  gets `total - tax`.
- Bookings (the player's ledger shows both): `work.pay` gross from the payer, then `tax.income`
  `{work, key, rate}` player → treasury. For an ATC wage SA Control pays the gross, the treasury gets
  the tax.
- Fallback without v_gov: 12 %, ems + bloodtransport 0 %.

## 6. Fees and fines

| Setting | Default | Goes to | Used by |
| --- | --- | --- | --- |
| company registration fee | € 50 000 | **treasury** | biz_core createCompany |
| rename fee | biz_core `RENAME_COST` | disappears (system) | biz_core |
| hospital bay fine (per interval) | `HOSP.BAY_FINE` | treasury, one sum when the bay is left (v_bank 6.4) | med_hospitals |
| airspace fee: takeoff | proposal € 1 500 | SA Control | aviation (v_bank 6.5) |
| airspace fee: landing | proposal € 2 000 | SA Control | aviation |
| airspace fee: overflight | proposal € 800 | SA Control | aviation |

The airspace fees are money from nothing, paid by the AI flight's airline (the airline name is in
the ledger row). Each resource keeps its own config value as fallback.

## 7. State healthcare

Treatment at a hospital is **free for the patient**; the state pays it from the treasury.

- **Billed:**
  - the free treatment marker (med_hospitals `server/heal.lua` `finish`);
  - handover of a patient by an ambulance crew (`server/handover.lua` `completeProc`) – **players and
    NPC patients** (NPC: "Unidentified patient" + the ERM task id).
- **Not billed:** respawn after death (v_spawnmanager); treatment on scene.
- **Cost** (computed *before* `healCompletely`): `missing HP × price per HP` (€ 50) + Σ price of each
  injury by type × severity (from `medsys:getMedicalState`). Proposed starting prices per severity
  1 / 2 / 3: gunshot 800 / 2 000 / 4 500, fracture 500 / 1 200 / 2 500, burn 400 / 1 500 / 4 000,
  head injury 700 / 2 000 / 5 000, other conditions 300 / 800 / 2 000.
- **Booking:** one `health.care` debit on the treasury per treatment (counter system), params
  `{ patient, account, hospital, hp, injuries, task }` → one treasury line, e.g.
  "Healthcare: John_Smith, All Saints General Hospital".
- Cost 0 → nothing booked. Healthcare switched off → nothing booked (still free for the patient).
- Players have no injuries now (`medsys PLAYER_PATIENTS = false`), so for players the bill is HP
  only; NPC patients do have injuries, their bills use the price list.

## 8. v_bank keys owned by v_gov

| Key | Dir | Kinds | Counter | Notes |
| --- | --- | --- | --- | --- |
| `tax.company_income` `{hour, base, rate}` | out (force) | company | treasury | hourly run |
| `tax.income` `{work, key, rate}` | out | personal | treasury | payWork |
| `health.care` `{patient, account, hospital, hp, injuries, task}` | out | state (treasury) | system | med_hospitals |
| `gov.transfer` `{note}` | pair | state ↔ state | account | treasury ↔ state company |

v_bank's key format gets the flag `taxable = true`; for now only on `biz.casino_hour`.

## 9. Database

```sql
CREATE TABLE IF NOT EXISTS gov_settings (
    skey       VARCHAR(64)  NOT NULL,   -- 'tax.company', 'tax.income_keys', 'work.atc.payer', 'fee.register',
                                        -- 'fee.airspace.landing', 'health.hp_price', 'work.ems.handover_base', ...
    value      TEXT         NOT NULL,   -- JSON
    updated_by VARCHAR(64)  NOT NULL DEFAULT '',
    updated_at INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (skey)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gov_members (
    account_name VARCHAR(64)  NOT NULL,
    role         VARCHAR(16)  NOT NULL,  -- 'viewer' | 'official' | 'minister'
    granted_by   VARCHAR(64)  NOT NULL DEFAULT '',
    granted_at   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (account_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gov_tax_runs (
    period_start INT UNSIGNED NOT NULL,  -- unix ts of the full hour
    instance     VARCHAR(16)  NOT NULL,
    companies    INT UNSIGNED NOT NULL DEFAULT 0,
    total        BIGINT       NOT NULL DEFAULT 0,
    finished_at  INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (period_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS gov_log (
    id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ts     INT UNSIGNED NOT NULL,
    actor  VARCHAR(64)  NOT NULL,
    action VARCHAR(48)  NOT NULL,          -- 'setting', 'company.create', 'member.set', ...
    detail VARCHAR(255) NOT NULL DEFAULT '', -- JSON (old / new)
    PRIMARY KEY (id),
    KEY idx_ts (ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Settings are cached; both instances re-read `gov_settings` every 60 s (the instance that changed a
value applies it at once), so a change reaches the other server within a minute.

## 10. State companies

A state company is a v_bank `state` account (code, name, access rows, overdraft flag) – v_bank
DESIGN 3.1. Managed here:

- **Create:** code (`[a-z0-9_]{3,24}`, unique, never changes), name, overdraft flag, first members
  (`exports.v_bank:createStateAccount`).
- **Rename:** the name only.
- **Delete:** only with balance 0 – the page offers "move the balance to the treasury" first
  (`gov.transfer`). The account is closed, its ledger stays readable. `treasury` cannot be deleted;
  a company that is a work payer cannot be deleted (the Works page names it).
- **Members:** v_bank access rows (`manager` = may transfer on the bank website, `viewer`).
- **SA Control** (`sacontrol`) is created by the v_bank migration: airspace usage fees in, ATC wages
  out, overdraft allowed.

v_admin keeps its Bank page for *all* accounts (statements, add / take money, freeze, overdraft list).

## 11. Exports (server)

```lua
getSetting(key)                      -> value
registerWage(workId, params)         -> true          -- 5.1
getWage(workId, key)                 -> number | nil  -- nil: use the default
getWorkPayer(workId)                 -> v_bank account id | "system"
getCompanyTaxRate()                  -> number        -- 0.10
getIncomeTaxRate(workId)             -> rate, key     -- the work's rate key, e.g. 0.12, "standard"
getWorkMultiplier(workId)            -> number
getFee(key)                          -> number        -- "register", "rename", "bay_fine", "airspace.takeoff", ...
healthcareCost(patient)              -> amount, details    -- player or ped; books nothing
chargeHealthcare(patient, hospitalId, taskId) -> true, amount | false, err
getGovRole(player)                   -> "viewer" | "official" | "minister" | false
```

A small shared helper (`exports.v_gov:importWage()`, like v_locals' import) gives works the
`Wage(key)` function with the fallback built in.

Events: `onGovSettingChanged(key, value)`, `onGovTaxRun(periodStart, companies, total)`.

## 12. Changes in other resources

| Resource | Change |
| --- | --- |
| v_bank | keys of section 8, `taxable` flag, state-account API |
| work_core `payWork` | work multiplier, income tax line by the work's rate key + `tax.income`; payer from `getWorkPayer` |
| med_erm, bt_dispatch, work_traindriver, avi_controller | `WAGE_PARAMS` + `Wage(key)` instead of the config numbers |
| med_hospitals `heal.lua`, `handover.lua` | `chargeHealthcare` before `healCompletely` (players and NPC patients) |
| med_hospitals `restricted.lua` | bay fine from `getFee("bay_fine")`, one treasury credit per violation |
| biz_core | registration / rename fee from `getFee` |
| avi_traffic + aviation fee handler | `onAviFlightFee` (takeoff / landing / overflight), amounts from `getFee`, booked on SA Control |
| biz_pc, biz_web | tax rows appear in the merged ledger |
| v_admin | Bank page without state-company management |

## 13. Implementation order (with v_bank 2)

1. v_bank core (v_bank DESIGN phase 1) incl. the keys above.
2. v_gov core: tables, settings cache, exports, Wage helper, `/gov` panel skeleton (Overview, Log,
   Members).
3. Taxes: hourly company run + income tax in work_core.
4. Works: `WAGE_PARAMS` (pay + XP) in the four works + Works page (payer, multiplier, tax key).
5. Healthcare billing in med_hospitals + Healthcare page.
6. Fees & fines (bay fine settlement, airspace fees, biz fees) + State companies page.
7. Remaining v_bank phases (callers, biz_core, bank website, admin page).

## 14. Decisions and open questions

Decided 2026-10-23:
- `/gov` with the roles of section 2; admins ≥ 5 are ministers.
- Company tax only on legal activity, for now only the casino; the casino result flows in whole,
  the tax is a separate row afterwards.
- Income tax 12 % on the whole positive wage incl. multipliers; EMS and blood transport exempt.
- Everything of a work is set in `/gov`: payer (system by default, treasury, state or private
  company), pay and XP parameters, multiplier, income tax rate key; the rate keys themselves are
  set separately on the Taxes page.
- Of all fees only the company registration fee (€ 50 000) goes to the treasury; purchases disappear.
- Hospital bay fines reach the treasury in one sum when the bay is left.
- Airspace fees are money from nothing paid by the airlines; takeoff / landing / overflight
  separately, into SA Control.
- The state also pays for NPC patients; respawn after death is not healthcare.

Decided later the same day:
- Company tax: fixed hourly run on the hour's net legal income; only a positive result is taxed.
- The proposed starting prices (airspace fees, injury prices) are fine; every one of them is
  editable in `/gov` (Fees & fines, Healthcare pages).
- A work payer that cannot pay goes negative; the wage is always paid.

No open questions left in this document.
