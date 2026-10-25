# gov_perms – design

Status: **implemented 2026-10-24**, offline-tested only (Lua syntax + unit tests of the matching,
branch rules and catalogue; `node --check` of the pages); **not yet tested in-game**. Replaces the
three fixed /gov roles (`viewer` < `official` < `minister`, table `gov_members`) with
fine-grained permissions grouped into positions (Governor, Transport Minister, ...), each with its
own hourly salary. Author in meta.xml: `DrAndrew112`. How it is used: [README.md](README.md).

**Deviations of the implementation from the text below:**
- The rank column is `seniority` (RANK is a reserved word in MySQL 8).
- Company creation / branch: `companies.create`, `companies.branch` (not `gov.create`): the `gov.`
  prefix is kept for the per-company families only, so `gov.*.*` + branch never covers them.
- No `panel.open` / `panel.office` rights: an action may need `"panel"` (anyone with any right,
  an admin or a sector company); the gov_office computers open /gov for exactly those. The
  `/govpcs` editor needs `office.edit`.
- `treasury.overview` covers Overview + Budget; the Treasury / Transfers pages need any
  `gov.*.bank.view` and list only the accounts the official sees (`treasury.transfers.view` dropped).
  State loans: `gov.<id>.loans` for take and repay.
- The salary key is `salary.gov` (its own ledger group "Salaries"), not `gov.salary`.
- All right names are in the gov_perms locale namespace: `gov_perms.perm.<key>` /
  `gov_perms.perm.<family>` (with `{target}`); an unknown key is shown as it is.
- Transport: `transport.fares.edit` = fare per km / minimum / IC supplement; everything with money
  flows (running costs, payer / receiver, the fare receiver) = `transport.costs.edit`.
- Seeded positions: §11 + the Interior and Justice Ministers (§16); no `panel.office` grants.

## 1. Rules (user, 2026-10-24)

- Every right that exists in the state system is one row in **`gov_perms`** – including the rights
  of every single state company (`gov.<company id>.bank.pay`, ...), work and hospital.
- **Allow-only.** What a position has no right to, it simply cannot see or do. No deny rules.
- Rights are put into **groups** (`gov_perms_groups`) = positions; positions are given to officials.
- **One official may hold several positions** at once (e.g. Mayor of Los Santos and Transport
  Minister); the effective rights are the union, each salary is paid.
- **Only the Governor or an admin** (level ≥ `GOV.ADMIN_LEVEL`) appoints officials, edits groups,
  their rights and salaries.
- **No cities on companies, no municipal layer.** A city is an ordinary state company
  (City of Los Santos); a mayor is just a position with the rights of that company.
  The system does **not** create mayor positions; the Governor makes them when needed.
- City hospitals may be funded by the city company, but prices are the state's.
- **State company bank access is a right:** `gov.<id>.bank.view|pay|manage`. v_bank access of a
  state company account follows the rights, nothing else.
- **Branches** (ágazatok) are an editable list, seeded on the first start.
- **Salaries:** every group has its own salary, paid by the State Treasury **per online hour** of
  each holder, and counted in the Budget plan.
- Elections come later and will build on this (appoint / dismiss exports are prepared, §13).
- Aviation is part of **Transport**. **Interior** will oversee the police, fire service and
  military; **Justice** handles the fines.

## 2. Where it lives

New resource `[government]/gov_perms`, `<include resource="gov_core"/>` like every module.

| Part | Owner |
| --- | --- |
| tables, catalogue sync, groups, appointments, branches, the check, caches, cross-instance reload | gov_perms |
| salaries (online-hour counter, payout, plan figures) | gov_perms |
| `/gov` page **Permissions** (Administration; tabs Groups / Officials / Branches / Catalogue) | gov_perms |
| request routing: the permission check before `onGovAction` | gov_core (asks gov_perms) |
| v_bank access sync of state company accounts | gov_perms |
| salaries in the Budget plan / Budget pages | gov_treasury (reads gov_perms) |
| declaring perms (static + generated), filtering lists | each module (through the lib) |

**gov_perms not running → fail closed:** gov_core only lets admins in; everybody else gets
`gov_core.err.perms_offline`. Public actions (`/vote`) keep working. No salaries are paid while it
is stopped (the online seconds are not counted either).

## 3. Tables

### 3.1 `gov_perms` – the catalogue

```sql
CREATE TABLE IF NOT EXISTS gov_perms (
    perm        VARCHAR(64)  NOT NULL,              -- "treasury.collect", "gov.12.bank.pay"
    module      VARCHAR(32)  NOT NULL,              -- resource that declares it
    area        VARCHAR(24)  NOT NULL,              -- economy | revenue | services | employment |
                                                    -- organizations | public | admin | other
    family      VARCHAR(48)  NOT NULL DEFAULT '',   -- generated perms: the pattern, "gov.*.bank.pay"
    target      VARCHAR(32)  NOT NULL DEFAULT '',   -- generated perms: "12" (company id), "ems" (work)
    danger      TINYINT UNSIGNED NOT NULL DEFAULT 1,-- 0 read, 1 settings, 2 moves money, 3 critical
    sort        SMALLINT UNSIGNED NOT NULL DEFAULT 100,
    active      TINYINT(1)   NOT NULL DEFAULT 1,    -- 0 = its module / company / work is gone now
    first_seen  INT UNSIGNED NOT NULL DEFAULT 0,
    last_seen   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (perm),
    KEY idx_module (module),
    KEY idx_family (family)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

- **Static perms** (`treasury.collect`, `tax.vat.edit`) come from `GOV.module{ perms = ... }`.
- **Generated perms** come from data: a family (`gov.*.bank.pay`) × every target (every state
  company id, every work, every hospital). The owning module reports its targets (§5.2); a new
  state company immediately has its `gov.<id>.*` rows, a closed one gets `active = 0`.
- The code owns the catalogue, the table mirrors it: rows are upserted on registration and
  **never deleted automatically** (a grant of a stopped module or closed company survives,
  greyed); the Governor may purge inactive rows.
- Texts are locale keys: static `<module>.perm.<perm>` / `<module>.perm_desc.<perm>`; generated
  ones use the family key (`gov_core.perm.gov.*.bank.pay` = "Pay from the account of {target}")
  with the target's name filled in.

### 3.2 `gov_perms_groups` – positions

```sql
CREATE TABLE IF NOT EXISTS gov_perms_groups (
    id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    code        VARCHAR(32)  NOT NULL,              -- "governor", "min_transport", "mayor_ls"
    name        VARCHAR(64)  NOT NULL,              -- "Transport Minister" (free text, shown in-game)
    description VARCHAR(255) NOT NULL DEFAULT '',
    kind        VARCHAR(16)  NOT NULL DEFAULT 'position', -- position | team | system
    rank        SMALLINT UNSIGNED NOT NULL DEFAULT 100,   -- order in lists; highest = shown title
    max_holders SMALLINT UNSIGNED NOT NULL DEFAULT 0,     -- 0 = unlimited, 1 = single holder
    salary      INT UNSIGNED NOT NULL DEFAULT 0,          -- € per online hour, gross
    tax_key     VARCHAR(24)  NOT NULL DEFAULT 'standard', -- gov_tax income tax key of the salary
    color       CHAR(7)      NOT NULL DEFAULT '#888888',
    status      VARCHAR(16)  NOT NULL DEFAULT 'active',   -- active | archived
    created_by  VARCHAR(64)  NOT NULL DEFAULT '',
    created_at  INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

No inheritance between groups: a person with two positions already gets both; a "copy group"
button covers templates. Simpler to read and to check.

### 3.3 `gov_perms_group_perms` – the rights of a group

```sql
CREATE TABLE IF NOT EXISTS gov_perms_group_perms (
    group_id    INT UNSIGNED NOT NULL,
    perm        VARCHAR(64)  NOT NULL,              -- a key or a pattern: "rail.*", "gov.*.bank.view", "*"
    branch      VARCHAR(24)  NOT NULL DEFAULT '',   -- only with a "gov.*..." pattern: just the
                                                    -- companies of this branch ("" = all)
    granted_by  VARCHAR(64)  NOT NULL DEFAULT '',
    granted_at  INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (group_id, perm, branch)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 3.4 `gov_perms_members` – appointments

```sql
CREATE TABLE IF NOT EXISTS gov_perms_members (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    account_name VARCHAR(64)  NOT NULL,
    group_id     INT UNSIGNED NOT NULL,
    granted_by   VARCHAR(64)  NOT NULL DEFAULT '',  -- account; later "gov_votes#<id>"
    granted_at   INT UNSIGNED NOT NULL DEFAULT 0,
    expires_at   INT UNSIGNED NOT NULL DEFAULT 0,   -- 0 = no end (a mandate will have one)
    salary_sec   INT UNSIGNED NOT NULL DEFAULT 0,   -- online seconds since the last salary
    note         VARCHAR(128) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    UNIQUE KEY uq_member (account_name, group_id),
    KEY idx_group (group_id),
    KEY idx_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 3.5 `gov_branches` – editable branch list

```sql
CREATE TABLE IF NOT EXISTS gov_branches (
    code        VARCHAR(24)  NOT NULL,              -- "transport"
    name        VARCHAR(64)  NOT NULL,              -- "Transport" (free text)
    sort        SMALLINT UNSIGNED NOT NULL DEFAULT 100,
    status      VARCHAR(16)  NOT NULL DEFAULT 'active', -- active | archived
    PRIMARY KEY (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Seeded only when the table is empty:

| Code | Name | Covers |
| --- | --- | --- |
| `transport` | Transport | public transport, railways **and aviation** (SA Control / ATC, airports, airspace) |
| `health` | Health | hospitals, EMS, blood transport |
| `finance` | Finance | treasury-side companies, state bank matters |
| `interior` | Interior | police, fire service, military (later) |
| `justice` | Justice | fines, courts, prisons (later) |
| `public_works` | Public works | roads, maintenance |
| `media` | Media | state news, gov.sa |
| `municipal` | Municipal | the city companies (City of Los Santos, ...) |
| `other` | Other | everything else | `gov_companies` gets a `branch VARCHAR(24) NOT NULL DEFAULT 'other'` column, picked
on the State companies page. An archived branch keeps its companies (shown with the old name);
it is no longer offered.

### 3.6 `gov_perms_salaries` – salary payouts

```sql
CREATE TABLE IF NOT EXISTS gov_perms_salaries (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ts           INT UNSIGNED NOT NULL,
    account_name VARCHAR(64)  NOT NULL,
    group_id     INT UNSIGNED NOT NULL,
    gross        INT UNSIGNED NOT NULL,
    tax          INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    KEY idx_ts (ts),
    KEY idx_group_ts (group_id, ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

For the plan (§9.3), the Officials tab ("paid in the last 30 days") and gov_web later. Rows older
than 30 days are deleted (`GOV.HISTORY_DAYS`), like every money history of /gov.

## 4. Permission keys

### 4.1 Format and patterns

`<area>.<object>.<verb>`, lower case, dots, max 64 chars. Generated perms have the target as a
segment: `gov.<company id>.bank.pay`, `works.<work id>.pay`, `health.<hospital id>.billing`.
The treasury uses the company family with the target `treasury`: `gov.treasury.bank.pay`.

In grants (never in checks):
- `*` as a whole segment matches any one segment: `gov.*.bank.view` = every company's statement.
- `.*` at the end matches the rest: `rail.*`, `gov.12.*` (everything of company 12).
- `*` alone = everything (the Governor).
- `branch` column: a `gov.*.…` grant limited to the companies of one branch
  (`gov.*.bank.pay` + `health` = pay from every health company, also future ones). The treasury
  has no branch: only a grant without branch reaches it.

### 4.2 The check

```lua
-- gov_perms server, cached per account (§14)
-- EFFECTIVE[account] = { { perm = "gov.*.bank.view", branch = "health", group = 7 }, ... }
function PERMS.has(account, perm)
    if PERMS.isSuper(account) then return true end          -- admin, or a "*" grant
    for _, g in ipairs(PERMS.effective(account)) do
        if PERMS.match(g.perm, perm) and PERMS.branchOk(g.branch, perm) then return true end
    end
    return false
end
-- match:    segment by segment, "*" = one segment, a trailing ".*" = the rest
-- branchOk: "" -> true; else perm must be gov.<id>.… with company <id> in that branch
```

`PERMS.targets(account, family)` → `{ all = true }` or `{ ["12"] = true, ["treasury"] = true }` –
the targets the account reaches in a family. Modules filter lists with it: a mayor with
`gov.12.*` sees only company 12 on State companies, only its account on Treasury / Transfers.

## 5. How modules declare and check

### 5.1 Static perms and actions

```lua
GOV.module({
    perms = {
        -- key                       area        danger
        { "transport.view",          "services", 0 },
        { "transport.fares.edit",    "services", 1 },
        { "transport.costs.edit",    "services", 2 },
    },
    actions = {
        transport     = "transport.view",                              -- a perm instead of a role
        setTransport  = "transport.fares.edit",
        renameCompany = { perm = "gov.{id}.edit", arg = "id" },         -- {id} <- args.id
    },
})
```

- `{arg}` placeholders: gov_core fills the key from the request (`gov.12.edit`) and checks it
  **before** the module sees the request. Data, not a callback (functions do not cross exports).
- Actions with more than one target (a transfer from A to B) or several fields (`setWork`,
  `setHealth`, `setTransport`) check inside the module with `GOV.has(player, key)` for each.
- Pages: `{ id = "transport", need = "transport.view" }`, or a family for generated perms
  (`need = "gov.*.view"`): shown when the player reaches **any** target.
- Old role strings (`"viewer"` / `"official"` / `"minister"`) are accepted during the migration
  (mapped to `legacy.viewer|official|minister`, §11). `"public"` stays.

### 5.2 Generated perms

```lua
GOV.module({
    families = {
        -- pattern               area             danger  label key (target name filled in)
        { "works.*.view",        "employment",    0 },
        { "works.*.pay",         "employment",    2 },
    },
})
-- whenever the targets change (start, a work registers, a company is created / closed):
GOV.setTargets("works", { { id = "ems", name = "EMS" }, { id = "traindriver", name = "Train driver" } })
```

gov_perms multiplies families × targets into `gov_perms` rows. gov_core reports the state
companies (+ `treasury`), gov_works the works, gov_health the hospitals.

### 5.3 The client

`gov_core:open` sends the effective grants (patterns kept) and the company → branch map; `gov.js`
gets `GOV.can(key)` with the same matching to hide buttons. The server stays the authority.

### 5.4 Sectors

A sector (railway operator company) keeps working; the implicit rights become perms listed in
the sector declaration:
`sectors = { { id = "railways", setting = "rail.operator", perms = { "rail.view", "rail.timetable.edit", "rail.timetable.toggle" } } }`.
Whoever has bank access to the operator's account (for a state company: `gov.<id>.bank.view`;
for a private company: its founder / managers) gets those perms, without a position.

## 6. Who manages the system

One right, **`perms.manage`** (danger 3): groups, their rights and salaries, appointments,
branches, catalogue purge. Held by the Governor (through `*`) and admins only; the editor refuses
to put `perms.manage` or `*` into any other group.

1. The Governor group itself (rights, salary, holder) is changed only by admins – the Governor
   cannot appoint a second Governor or dismiss themself.
2. `max_holders`: a full single-holder position offers "replace" (dismiss + appoint, one log entry).
3. `danger >= 2` rights are red in the editor, `danger = 3` needs a confirmation.
4. `perms.view` (read the Permissions page) may be given to anyone.

## 7. The catalogue (first version)

`D` = danger. Generated families show the target as `<id>` / `<work>` / `<hospital>`.

### Administration (`gov_core`, `gov_perms`)
| Perm | D | Today |
| --- | --- | --- |
| `panel.open` | 0 | any role (implicit when the account has any right) |
| `panel.office` | 0 | gov_office PCs (now minister) |
| `panel.log` | 0 | `log` |
| `perms.view` | 0 | – (Permissions page, read only) |
| `perms.manage` | 3 | `setMember` – Governor / admin only |

### State organizations (`gov_core`)
| Perm | D | Today |
| --- | --- | --- |
| `gov.create` | 2 | `createCompany` |
| `gov.<id>.view` | 0 | `companies`, `company`, `findCompanies` (only the reachable ones listed) |
| `gov.<id>.edit` | 1 | `renameCompany`, `describeCompany`, the branch field |
| `gov.<id>.close` | 3 | `deleteCompany` |
| `gov.<id>.bank.view` | 0 | statement; v_bank `view` |
| `gov.<id>.bank.pay` | 2 | payments / transfers from the account; v_bank `pay` |
| `gov.<id>.bank.manage` | 3 | v_bank `manage` |
| `gov.<id>.overdraft` | 3 | `companyOverdraft` |
| `gov.<id>.standing` | 2 | standing orders from the account |
| `gov.<id>.loans` | 3 | `takeLoan` / `repayLoan` for this account |

`<id>` = every state company id and `treasury`. `companyMember` (manual bank access list) is
removed: bank access = these rights (§8).

### Economy (`gov_treasury`, `gov_loans`)
| Perm | D | Today |
| --- | --- | --- |
| `treasury.overview` | 0 | `overview`, `budget` (whole-state figures) |
| `treasury.transfers.view` | 0 | `transfers` (lists only the accounts with `gov.<id>.bank.view`) |
| `treasury.transfer.company` | 2 | `moneyTransfer` kind pay: state → private company (+ `gov.<from>.bank.pay`) |
| `treasury.collect` | 3 | `moneyTransfer` kind collect (inkasszó) |
| `treasury.plan.view` | 0 | `budgetPlan` |
| `treasury.plan.edit` | 1 | `savePlanItem`, `deletePlanItem` |
| `loans.view` | 0 | `loans`, `loanPayments` |

A state ↔ state transfer needs `gov.<from>.bank.pay` only; a standing order `gov.<from>.standing`.

### Revenue (`gov_tax`)
| Perm | D | Today |
| --- | --- | --- |
| `tax.view` | 0 | `taxes` |
| `tax.company.edit` | 1 | `setCompanyTax` |
| `tax.income.edit` | 1 | `setTaxKey`, `deleteTaxKey` |
| `tax.vat.edit` | 1 | `setVat` |
| `tax.property.edit` | 1 | `setPropertyTax` |
| `tax.targets.edit` | 2 | `setTaxTarget` |
| `fees.view` | 0 | `fees` |
| `fees.<fee>.edit` | 1 | `setFee` of one fee |
| `fees.<fee>.target` | 2 | `setFeeTarget` of one fee |

`<fee>` = every fee of gov_tax that is a **fee**: `register`, `rename`, `airspace_takeoff`,
`airspace_landing`, `airspace_overflight` (the setting keys keep their names, only the perm
target uses `_`). Fines are separate (Justice, below).

### Justice (`gov_tax` now, a `gov_justice` module later)
| Perm | D | Today |
| --- | --- | --- |
| `fines.view` | 0 | the fines part of the Fees page |
| `fines.<fine>.edit` | 1 | `setFee` of one fine |
| `fines.<fine>.target` | 2 | `setFeeTarget` of one fine (where the money goes) |

`<fine>` = `bay_fine` (hospital bay fine) now. gov_tax marks each of its fee keys as `fee` or
`fine`; the Fees page shows fines in their own box. Later fines (police tickets, court
penalties) register as more `fines.<fine>` targets, so the Justice Minister gets them without a
change of their group.

### Public services (`gov_health`, `gov_transport`, `gov_railways`)
| Perm | D | Today |
| --- | --- | --- |
| `health.view` | 0 | `health` |
| `health.prices.edit` | 1 | `setHealth` HP / injury prices – the state only |
| `health.<hospital>.billing` | 2 | `setHealth` payer / receiver of one hospital |
| `transport.view` | 0 | `transport` |
| `transport.fares.edit` | 1 | `setTransport` fares, IC supplement |
| `transport.costs.edit` | 2 | `setTransport` running costs, payer / receiver |
| `rail.view` | 0 | `railways` |
| `rail.timetable.edit` | 1 | `saveRailRow`, `deleteRailRow` |
| `rail.timetable.toggle` | 1 | `toggleRailRow` |
| `rail.operator.set` | 2 | `setRailOperator` |

### Employment (`gov_works`)
| Perm | D | Today |
| --- | --- | --- |
| `works.<work>.view` | 0 | `works` (only reachable works listed) |
| `works.<work>.pay` | 2 | `setWork` pay + XP params |
| `works.<work>.payer` | 2 | `setWork` payer |
| `works.<work>.multiplier` | 1 | `setWork` multiplier |
| `works.<work>.taxkey` | 1 | `setWork` income tax key |

### Public affairs (`gov_votes`, `gov_news`)
| Perm | D | Today |
| --- | --- | --- |
| `votes.view` | 0 | `votes` |
| `votes.open` | 1 | `openVote` |
| `votes.close` | 1 | `closeVote`, `cancelVote` |
| `news.view` | 0 | `news` |
| `news.post` | 1 | `postNews` |
| `news.delete` | 1 | `deleteNews` |

Later modules add rows the same way (police, licences, land registry, `transport.bus.*`,
elections); gov_perms does not change for them.

## 8. State company bank access = rights

A sync (after every appointment / right change, and every 60 s) sets the v_bank access of each
state company account and the treasury from the effective rights:

| Right | v_bank access |
| --- | --- |
| `gov.<id>.bank.manage` | `manage` |
| `gov.<id>.bank.pay` | `pay` |
| `gov.<id>.bank.view` | `view` |
| none | removed |

The bank is never the source: an access row nobody's right explains is removed. Admins keep
their own v_bank admin view (not an access row). Sector membership (§5.4) reads the bank access,
so the railway operator's people follow automatically.

## 9. Salaries

### 9.1 Setting

Each group: `salary` (€ per online hour, gross) and `tax_key` (a gov_tax income tax key,
default `standard`). Edited on the Groups tab with `perms.manage`; logged `perm.salary`. A change
applies from the next payout. Default for every seeded group: 0 (nothing is paid until the
Governor / an admin sets it).

### 9.2 Payout – every online hour

- Every 60 s each instance adds 60 to `salary_sec` of every appointment whose holder is logged
  in **on that instance** (a player is online on one instance only, so two instances never count
  the same hour – same idea as eco_loan's `progress_sec`). One UPDATE per tick.
- When `salary_sec >= 3600`: one payout per position (two positions = two separate payouts),
  `salary_sec -= 3600`.
- Payout: v_bank booking key **`gov.salary`** from the **State Treasury** to the player's
  personal account; income tax by the group's `tax_key` (like work_core `payWork`) as `tax.income`
  to the account set on the Taxes page. The salary is always paid, the treasury may go negative
  (same rule as work payers).
- A row in `gov_perms_salaries`; ui_core notification to the player
  ("Salary: Transport Minister €X (tax €Y)").
- Salary 0 = no booking, the counter still resets every hour.
- Dismissal / expiry: the started hour is lost (no partial pay).

### 9.3 In the budget

- **Budget plan** (gov_treasury `plan.lua`): a new row **Salaries** as an expense of the treasury
  for every day of the next 7 days:
  `Σ over appointments: salary × expected online hours per day of that holder`.
  Expected hours = the holder's average paid hours per day over the last 7 days
  (`gov_perms_salaries`), or, without 7 days of history, the setting `perms.salary.plan_hours`
  (default 4, editable on the Groups tab). The row expands per position. gov_perms export
  `getSalaryDayPlan()` → `{ total, rows = { { group, name, holders, salary, hours, amount } } }`.
- **Budget** (actual, last 30 days): the `gov.salary` ledger key shown as its own line
  "Salaries" in the treasury's expenses.
- **Groups tab:** per group the hourly cost (salary × holders) and the paid total of 30 days;
  in the footer the whole estimated daily salary cost.

## 10. The /gov page **Permissions** (Administration)

One menu item (replaces Members), visible with `perms.view`, editable with `perms.manage`.

| Tab | What |
| --- | --- |
| **Groups** | list: name, rank, color, holders x / max, salary / h, cost / day. Editor: name, code, kind, rank, max holders, salary, tax key, color; the **rights tree** by area (the menu categories) – a checkbox per static right; for families (state companies, works, hospitals) a row per family with "all" / "branch: …" / a checklist of the targets; danger colors; inactive rights greyed. Save, copy as new group, archive. |
| **Officials** | everyone with a position: account, display name (`acc_auth:getDisplayName`), positions (expiry, salary, paid in 30 days). Appoint (account picker + group + optional expiry + note), dismiss, replace. "Effective rights" of one official, each with the position it comes from. |
| **Branches** | the branch list: add, rename, reorder, archive; number of companies per branch. |
| **Catalogue** | every `gov_perms` row by area / family: name, key, module, danger, active; which groups hold it; purge inactive. |

## 11. First start

Guarded by `gov_settings` key `perms.migrated` (one instance does it):

1. Creates the tables, seeds `gov_branches` (§3.5).
2. Creates the default groups (all salaries 0):

| Group | rank | max | Rights |
| --- | --- | --- | --- |
| **Governor** (`governor`, system) | 1000 | 1 | `*` |
| **Finance Minister** (`min_finance`) | 900 | 1 | `treasury.*`, `loans.*`, `tax.*`, `fees.view`, `fees.register.*`, `fees.rename.*`, `gov.*.view`, `gov.*.bank.view`; `gov.*.*` + branch `finance`; `gov.treasury.*` |
| **Transport Minister** (`min_transport`) | 900 | 1 | `transport.*`, `rail.*`, `treasury.overview`; aviation: `fees.view`, `fees.airspace_takeoff.*`, `fees.airspace_landing.*`, `fees.airspace_overflight.*`; `gov.*.*` + branch `transport` (incl. SA Control); `works.traindriver.*`, `works.atc.*` |
| **Health Minister** (`min_health`) | 900 | 1 | `health.*`; `gov.*.*` + branch `health`; `works.ems.*`, `works.bloodtransport.*` |
| **Interior Minister** (`min_interior`) | 900 | 1 | `gov.*.*` + branch `interior`; later the police / fire / military rights of their modules |
| **Justice Minister** (`min_justice`) | 900 | 1 | `fines.*`; `gov.*.*` + branch `justice` |
| **Employment Minister** (`min_employment`) | 900 | 1 | `works.*`, `tax.view`, `tax.income.edit` |
| **Government Spokesperson** (`spokesperson`) | 400 | 1 | `news.*`, `votes.*` |

   No mayor, no company positions – the Governor creates them (e.g. "Mayor of Los Santos" =
   `gov.<City of LS id>.*`; "LSPT clerk" = `gov.<LSPT id>.view` + `gov.<LSPT id>.bank.view`).
3. Migration of the old roles: system groups `legacy_viewer` / `legacy_official` /
   `legacy_minister` (viewer = every `*.view`; official = viewer + `gov.*.*`, `health.*`;
   minister = everything except `perms.manage`), every `gov_members` row appointed into its
   group; gov_core's `canGov` / `getGovRole` answer from these for old callers. The existing v_bank
   access rows of state company accounts become migration groups ("<company> – manage / pay / view
   (migrated)" with the matching `gov.<id>.bank.*`), so nobody loses access before the Governor
   sorts them out. `gov_members` is kept read-only for one version, then dropped (`main.sql`).
4. Log `perm.migrate`.

## 12. Suggested further branches (not seeded)

Ideas for the Branches tab, the ones that match systems on the server first:

| Code | Name | Fits |
| --- | --- | --- |
| `education` | Education | driving schools, licences, tutorials |
| `energy` | Energy & utilities | power, water, waste companies |
| `logistics` | Post & logistics | state postal / delivery company, blood transport fleet |
| `culture` | Culture & tourism | events, museums, the casino oversight |
| `housing` | Housing & land | land registry, property tax side, state real estate |
| `environment` | Environment & agriculture | weed licences (biz_weed), parks |
| `telecom` | Telecommunications | phone network, gov.sa website, news |
| `sport` | Sport & youth | races / DM events (Jobs), stadiums |

## 13. Exports and events

| Export (gov_perms, server) | |
| --- | --- |
| `hasGovPerm(playerOrAccount, key)` | `true` / `false` |
| `getGovPermTargets(playerOrAccount, family)` | `{ all = true }` or `{ [target] = true }` |
| `getGovPositions(account)` | `{ { id, code, name, rank, salary, expires_at }, ... }` |
| `getGovPermCatalogue()` | active catalogue rows |
| `getGovBranches()` | active branches |
| `getSalaryDayPlan()` | §9.3 |
| `isGovSuper(playerOrAccount)` | admin or `*` |
| `appointGov(account, groupCode, expiresAt, actor)` / `dismissGov(account, groupCode, actor)` | prepared for the election system; callable only from resources in `PERMS.AUTOMATION` (empty now, `gov_votes` later), checked with `sourceResource` |

Events (source = gov_perms resourceRoot): `onGovPermsChanged(account | false)` (gov_core re-sends
open menus), `onGovAppointed(account, groupCode)`, `onGovDismissed(account, groupCode)`,
`onGovSalaryPaid(account, groupCode, gross, tax)`.

## 14. Caching and several instances

- Effective grant lists cached per account; dropped on a change of that account / group.
- Every change bumps `perms.rev` in `gov_settings`; the other instances rebuild their caches when
  the 60 s settings sync sees a new rev. A dismissal applies at once on the changing instance, at
  most 60 s later on the others.
- Company → branch from gov_core's company cache.

## 15. Log (`gov_log`)

`perm.group.create|edit|archive`, `perm.grant` / `perm.revoke`, `perm.salary` (group, old, new),
`perm.member.appoint|dismiss|replace|expire`, `perm.branch.create|edit|archive`,
`perm.catalogue.purge`, `perm.migrate`. Salary payouts are in `gov_perms_salaries` + the bank
ledger, not in gov_log.

## 16. Implementation order

1. gov_perms: tables, branches seed, catalogue (static + generated), `has` / `targets`, caches,
   exports.
2. gov_core: routing through perms (`{arg}` keys), legacy mapping, `branch` column, company targets,
   menu by perms, grants to the client; lib `GOV.has` / `GOV.targets` / `GOV.setTargets`.
3. First start (§11): default groups + migration.
4. Each module: perms / families, actions on perm keys, list filtering, per-field checks;
   gov_works and gov_health report their targets.
5. v_bank access sync (§8).
6. Salaries: counter, payout, `gov.salary` key in v_bank, Budget plan row, Budget line.
7. The Permissions page (4 tabs); `gov.js` `GOV.can`.
8. Locales `gov_perms.*` en + hu, perm names in each module's namespace; README, main.sql.

## 17. Decisions (all settled 2026-10-24)

- Bank access of state companies = rights `gov.<id>.bank.view|pay|manage`, synced into v_bank.
- No cities on companies, no municipal layer, no seeded mayor positions.
- Branches: editable table, seeded with §3.5; more ideas in §12. Aviation belongs to Transport;
  Interior (police, fire service, military later) and Justice (fines) are branches with their
  own minister.
- Fees and fines are separate rights: `fees.<fee>.*` (Finance: registration / rename; Transport:
  airspace) and `fines.<fine>.*` (Justice).
- Allow-only.
- Salary per group, per online hour, from the treasury, in the Budget plan; set by Governor / admin.
- Several positions per official; only the Governor or an admin appoints.
- Elections later on top of `appointGov` / `dismissGov`.
