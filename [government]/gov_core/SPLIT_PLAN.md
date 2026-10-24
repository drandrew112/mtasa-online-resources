# v_gov split plan → `[government]/gov_*`

Status: implemented 2026-10-24 (all resources built, callers updated, v_gov removed); offline-tested only, not yet tested in game. The menu categories (section 3) were added on request.

Goal: v_gov (≈2700 lines Lua + 1100 JS) becomes one foundation resource plus independent
modules in `resources/[government]/`. gov_web moves there too. **No function is lost**: every
export, panel action, event, command, table, timer and element data of today has a new home
(coverage table in section 6).

---

## 1. Target layout

```
[government]/
  gov_core/       foundation: settings, roles, log, state companies, /gov panel shell, helper lib
  gov_treasury/   treasury, overview, transfers, standing orders, budget
  gov_tax/        company tax (hourly), income tax keys, VAT, property tax, tax targets, fees + fee targets
  gov_works/      work pay: payer, parameters, multiplier, income tax key per work
  gov_health/     state healthcare: prices, per-hospital payer / receiver, charging
  gov_transport/  public transport money: fares, running costs (pt.<mode>)
  gov_votes/      votes, /vote page
  gov_news/       government news (phone mails)
  gov_web/        public site gov.sa (moved from [web]), now builds its own snapshot
```

Dependency rule: **every module `<include resource="gov_core" />`, nothing else from gov_***.
Calls between modules are optional (`isResourceRunning` guard + fallback), so any module can be
stopped / restarted alone. v_main starts resources in include order, so gov_core always starts
first.

Database: **all table names stay** (`gov_settings`, `gov_members`, …). Each resource creates
only its own tables (`CREATE TABLE IF NOT EXISTS`), so the existing data is used as it is – no
migration.

---

## 2. Resources

### 2.1 gov_core – foundation
| | |
| --- | --- |
| From v_gov | `server/db.lua` (core part), `settings.lua`, `companies.lua`, `panel.lua` (plumbing, bankCall, members / log / companies actions, findCompanies), `main.lua`, `client/panel.lua`, `web/index.html`, `web/css/gov.css`, `web/js/gov.js` (shell part) |
| Tables | `gov_settings`, `gov_members`, `gov_log`, `gov_companies` |
| Pages | Companies, Members, Log |
| Command | `/gov` |
| Timers | settings + members + companies resync (`RESYNC_MS`) |
| Events | `onGovSettingChanged(key, value)` (unchanged), new `onGovSettingsSynced()` after every re-read |

**Settings ownership.** Every module registers the defaults of its keys on its start and on
gov_core's start: `registerSettings(prefix, defaults)` (`tax.` / `fee.` → gov_tax, `work.` →
gov_works, `health.` → gov_health, `pt.` → gov_transport). `getSetting(key)` keeps working for
everyone: stored value, else the registered default, else nil. `setSetting(key, value, actor)`
is accepted only for a prefix the calling resource (`sourceResource`) owns. A module that is not
running → its defaults are not registered → `nil` → callers use their existing fallback (work_core,
pt_tickets, avi_traffic already have one).

**State companies** stay here because nearly every module needs them (payer / target options,
budget, standing orders). Read exports: `getStateCompanies()`, `getStateCompany(code | id)`,
`getStateAccounts()` (treasury + companies with bank info). The Companies page needs two answers
from other modules, asked only if they run: `gov_works:getStatePayerWorks()` (the "pays works"
column and the delete block) – if gov_works does not run, deleting is refused (safe side).

**Panel shell.** One `/gov` window as today. The shell holds the menu, the request plumbing,
the dialogs and the shared widgets (company picker, payer / target select). Pages come from the
modules (section 3).

**Helper lib** – `loadstring(exports.gov_core:importLib())()` (same pattern as v_locals / VAT),
one source instead of copies in 8 resources:
- `DB.*` (async MySQL import, exec / query / int / clip), `GOV.now`, `GOV.instance`,
  `GOV.accountOf`, `GOV.bank`, `isResourceRunning`
- `GOV.bankCall` – v_bank answers `"<caller resource>:remoteResult"`, the lib registers the
  event under the module's own name (works unchanged in v_bank)
- `GOV.specAccount(spec)`, `GOV.targetAccount(setting, key)`, `GOV.checkSpec(spec, side, cb)`
  (the `system | player | state:<code> | company:<id>` check with the biz_companies query –
  today copied in setHealth / setTransport / setWork), `GOV.companyNames(ids, cb)`
- `GOV.module{ settings = …, actions = …, pages = … }` – registers everything with gov_core now and
  again whenever gov_core (re)starts
- `GOV.log(actor, action, detail)` → `exports.gov_core:log`

Exports: `getSetting`, `setSetting`, `registerSettings`, `getGovRole`, `canGov(player, role)`,
`log`, `importLib`, `registerModule`, `reply`, state company reads, client `openGovPage`.

### 2.2 gov_treasury
| | |
| --- | --- |
| From v_gov | `standing.lua`, `budget.lua` (`GOV.budget`), panel actions overview / treasuryLedger / budget / transfers / treasuryTransfer / moneyTransfer / create- / toggle- / deleteStanding |
| Tables | `gov_standing_orders` |
| Pages | Overview (default page), Treasury, Transfers, Budget |
| Timers | standing order runner (`STANDING_CHECK_MS`) |
| Exports | `getBudget()` (for gov_web), `getPublicFinance()` |

Overview shows the last tax runs: `gov_tax:getTaxRuns(24)` when gov_tax runs, else an empty list.

### 2.3 gov_tax (taxes + fees)
| | |
| --- | --- |
| From v_gov | `tax.lua`, `vat.lua`, `shared/vat.lua`, the tax / fee parts of `works.lua` (`getCompanyTaxRate`, `getTaxTarget`, `getFeeTarget`, `getFee`), panel actions taxes / setCompanyTax / setTaxKey / deleteTaxKey / setVat / setPropertyTax / setTaxTarget / fees / setFee / setFeeTarget |
| Tables | `gov_tax_runs` |
| Settings | `tax.*`, `fee.*` |
| Pages | Taxes, Fees |
| Timers | hourly company tax + 24 h catch-up (starts when v_bank is ready – today in main.lua) |
| Events | `onGovTaxRun`, `onGovCompanyTaxed` (names unchanged; biz_core listens on `root`, OK) |
| Element data | `v_gov.vat` → `gov_tax.vat` |
| Exports | `getFee`, `getFeeTarget`, `getCompanyTaxRate`, `getTaxTarget`, `importVat` (server + client), `getVatRate`, `getVatRates`, `bookVat`, `getPropertyTaxRate`, `getIncomeTaxKeys`, new `getTaxRuns(n)`, `getPublicTaxes()` |

- `download_priority_group 1000` moves here (the VAT client export must exist before
  ui_browser 997 / ui_core 999). Its client side must not call gov_core on load.
- Income tax keys page: "used by" and the delete block need `gov_works:getWorkTaxKeys()`; if
  gov_works does not run, deleting a key is refused.
- Fees stay with the taxes (same target mechanism, ~40 lines). If you want, they can be a separate
  `gov_fees` later without touching anything else.

### 2.4 gov_works
| | |
| --- | --- |
| From v_gov | `works.lua` (wages, payer, multiplier, `getIncomeTaxRate`), `GOV.workList`, works part of `checkPayers`, actions works / setWork |
| Settings | `work.*` (+ `GOV_WORK_DEFAULTS`) |
| Pages | Works |
| Exports | `registerWage`, `getWage`, `getWorkPayer`, `getWorkMultiplier`, `getIncomeTaxRate`, new `getWorkList()`, `getWorkTaxKeys()`, `getStatePayerWorks()`, `getPublicWorks()` |

`getIncomeTaxRate` reads the keys from gov_core settings (`tax.income_keys`); with gov_tax
stopped and no stored row it returns nil → work_core uses its config fallback (as without v_gov
today). The closed-company payer check runs on `onGovSettingsSynced`.

### 2.5 gov_health
| | |
| --- | --- |
| From v_gov | `health.lua`, `hospitalList`, health part of `checkPayers`, actions health / setHealth |
| Settings | `health.*` |
| Pages | Healthcare |
| Exports | `healthcareCost`, `chargeHealthcare`, `getHealthcarePayer`, `isHealthcarePaidByPatient`, `getPublicHealth()` |

### 2.6 gov_transport
| | |
| --- | --- |
| From v_gov | `transport.lua`, `GOV_PT_*`, actions transport / setTransport |
| Settings | `pt.*` |
| Pages | Public transport |
| Exports | `getTransportSettings`, `getTransportFare`, `bookFareIncome`, `chargeTransportCost` |

### 2.7 gov_votes
| | |
| --- | --- |
| From v_gov | `votes.lua`, `web/vote.html`, `web/js/vote.js`, client vote notification, actions votes / openVote / closeVote / cancelVote / voteList / voteCast |
| Tables | `gov_votes`, `gov_vote_ballots` |
| Pages | Votes (in /gov); `/vote` opens `vote.html` through `gov_core:openGovPage("gov_votes", "vote.html")` |
| Command | `/vote` |
| Timers | close expired votes (`VOTE_CHECK_MS`) |
| Events | `onGovVoteOpened`, `onGovVoteClosed` |
| Exports | `getPublicVotes()` |

### 2.8 gov_news
| | |
| --- | --- |
| From v_gov | `news.lua`, actions news / postNews / deleteNews |
| Tables | `gov_news` |
| Pages | News |
| Events | `onGovNewsPosted` |

### 2.9 gov_web
Moves from `[web]/gov_web` to `[government]/gov_web` (name unchanged → URL `/gov_web/` and the
ui_browser site gov.sa stay). The snapshot builder (today `rebuild()` in budget.lua) moves here:
every `PUBLIC_REFRESH_MS` it asks `gov_treasury:getPublicFinance()`, `gov_tax:getPublicTaxes()`,
`gov_works:getPublicWorks()`, `gov_health:getPublicHealth()`, `gov_votes:getPublicVotes()` and
merges them into the same JSON shape the page reads today (a stopped module = its part empty).
`<include resource="v_gov" />` → `gov_core`. `govWebState` http export unchanged.

---

## 3. Panel: shell + module pages

**Server routing.** gov_core keeps one `NEED` table filled by the modules
(`actions = { setVat = "minister", … }`; a name already taken by another resource is rejected and
logged). Flow:

```
page  mta.triggerEvent("gov_core:pageCall", id, action, args)
gov_core client  -> "gov_core:call"
gov_core server  role check (viewer / official / minister / public), GOV ready check
                 -> triggerEvent("onGovAction", <module resourceRoot>, reqId, action, args, actor, player)
module           handles it, answers exports.gov_core:reply(reqId, result, err)
gov_core server  -> "gov_core:reply" to the player
```
Pending requests time out after 30 s (`gov.err.unknown`) and are dropped when their module stops.
Action names stay the same as now, so the page code changes little.

**Pages.** `gov.js` (968 lines) is cut into the shell (gov_core: `GOV.call`, menu, dialogs,
helpers, pickers) and one file per page in its module (`gov_tax/web/js/taxes.js`, …). A page file
registers itself: `GOV.page('taxes', { keys: [...], render(view) })`. On `/gov` the
server sends the role and the running modules' page list; the shell loads
`http://mta/<resource>/web/js/<page>.js` (client files of the module), collects the `keys` of every
page and asks their texts in one `pageReady`. A stopped module = its menu item is missing.

**Menu: categories.** The flat 14-item side menu becomes a grouped menu. gov_core owns the
categories (id, order, text key); a module names the category and the order of each page it
registers on the server:

```lua
GOV.module{ pages = {
    { id = "taxes", category = "revenue", order = 10, need = "viewer", script = "web/js/taxes.js" },
    { id = "fees",  category = "revenue", order = 20, need = "viewer", script = "web/js/fees.js" },
} }
```

| Category (`gov.menu.<id>`) | en / hu | Pages (module) |
| --- | --- | --- |
| – (always on top) | Overview / Áttekintés | Overview (gov_treasury) |
| `economy` | Economy / Gazdaság | Treasury / Kincstár, Transfers / Pénzmozgás, Budget / Költségvetés (gov_treasury) |
| `revenue` | Revenue / Bevételek | Taxes / Adók, Fees / Díjak (gov_tax) |
| `services` | Public services / Közszolgáltatások | Healthcare / Egészségügy (gov_health), Public transport / Tömegközlekedés (gov_transport) |
| `employment` | Employment / Foglalkoztatás | Works / Munkák (gov_works) |
| `organizations` | State organizations / Állami szervezetek | State companies / Állami cégek (gov_core) |
| `public` | Public affairs / Közélet | Votes / Szavazások (gov_votes), News / Hírek (gov_news) |
| `admin` | Administration / Adminisztráció | Members / Tagok, Log / Napló (gov_core) |

Rules:
- A category with no visible page (its modules are stopped, or the role is too low) is hidden.
- A page with an unknown category goes under `other` (Other / Egyéb, last), so a new module never
  disappears because of a typo; gov_core logs a warning.
- A new module may add a category with `registerCategory(id, order, textKey)`; the fixed list
  above is registered by gov_core itself.
- `need` is checked for the menu too: a page the role cannot open is not listed (today every page
  is `viewer`, so nothing changes now).
- Categories can be collapsed; the collapsed state and the last opened page are kept per player in
  the page's localStorage (try/catch, works without it). The open page's category is always
  expanded.
- The order inside a category comes from `order`, then the page title.

The ledger text formatting of the client relay (today hard-wired to `treasuryLedger`) becomes
generic: a result with `ledgerRows = true` gets the `v_bank.tx.*` texts.

---

## 4. Texts (v_locals)

`locales/{en,hu}/v_gov.json` is split per resource (`gov_core.json`, `gov_tax.json`, ...). v_locals wants the
first key segment to be the resource (the namespace), so `v_gov.ui.save` became `gov_core.ui.save`,
`v_gov.vat.weapons` `gov_tax.vat.weapons` and so on: shared ui / err / role / menu keys in gov_core,
page keys in the module that owns the page (a page script asks `<module>.ui.<key>`, else
`gov_core.ui.<key>`). Done with a script; `v_locals/meta.xml` file list updated. Hungarian texts are moved, not rewritten.

---

## 5. Changes in other resources

| Resource | Change |
| --- | --- |
| avi_controller `server/main.lua` | `registerWage` / `getWage` + start check → `gov_works` |
| avi_traffic `server/fees.lua` | `getFee` / `getFeeTarget` → `gov_tax` |
| bt_dispatch `server/core.lua` | wages → `gov_works` |
| med_erm `server/payment.lua` | wages → `gov_works` |
| work_traindriver `server/pay.lua` | wages → `gov_works` |
| work_core `server/payment.lua` | `getTaxTarget("income")` → `gov_tax`; `getWorkMultiplier`, `getIncomeTaxRate` → `gov_works` |
| biz_core `meta.xml`, `shared/config.lua` | include + `importVat` → `gov_tax` |
| biz_core `server/actions.lua`, `tick.lua` | fees, `getPropertyTaxRate`, `getTaxTarget` → `gov_tax` (`money.lua` event: no change) |
| med_hospitals `heal.lua`, `handover.lua`, `hospitals.lua` | `chargeHealthcare` / `isHealthcarePaidByPatient` → `gov_health`; `onResourceStart/Stop` name `"v_gov"` → `"gov_health"` |
| med_hospitals `restricted.lua` | bay fine fee → `gov_tax` |
| pt_tickets `server/tickets.lua` | fares → `gov_transport` |
| rw_timetable `server/costs.lua` | `chargeTransportCost` → `gov_transport` |
| ui_browser, ui_phone, v_customs, wp_shop, world_clothes-shop | `<include resource="gov_tax" />`, `exports.gov_tax:importVat()` |
| v_bank `shared/keys.lua`, `server/*.lua` | comments only (`v_gov` → module names); bankCall needs no change |
| v_locals | locale files + meta (section 4) |
| comments / README mentions | avi_traffic, med_hospitals, pt_tickets, work_core configs |

The `"v_gov"` origin string passed to `bank:transfer(…, "v_gov")` stays `"v_gov"`, so old and new
ledger rows look the same.

No compatibility `v_gov` shim: the switch is one change (new resources + all callers + v_gov
deleted). Running v_gov and the gov_* resources side by side is not allowed (both would register
`/gov` and `/vote` and write the same element data).

---

## 6. Coverage – every function of v_gov and where it goes

| v_gov today | New home |
| --- | --- |
| exports getSetting, getGovRole | gov_core |
| exports getFee, getFeeTarget, getCompanyTaxRate, getTaxTarget, importVat (s+c), getVatRate, getVatRates, bookVat, getPropertyTaxRate | gov_tax |
| exports registerWage, getWage, getWorkPayer, getWorkMultiplier, getIncomeTaxRate | gov_works |
| exports healthcareCost, chargeHealthcare, getHealthcarePayer, isHealthcarePaidByPatient | gov_health |
| exports getTransportSettings, getTransportFare, bookFareIncome, chargeTransportCost | gov_transport |
| export getPublicState | gov_web builds it itself (same shape) |
| actions companies, company, create/rename/describe/deleteCompany, companyMember, companyOverdraft, members, setMember, log, findCompanies | gov_core |
| actions overview, treasuryLedger, budget, transfers, treasuryTransfer, moneyTransfer, create/toggle/deleteStanding | gov_treasury |
| actions taxes, setCompanyTax, setTaxKey, deleteTaxKey, setVat, setPropertyTax, setTaxTarget, fees, setFee, setFeeTarget | gov_tax |
| actions works, setWork | gov_works |
| actions health, setHealth | gov_health |
| actions transport, setTransport | gov_transport |
| actions votes, openVote, closeVote, cancelVote, voteList, voteCast | gov_votes |
| actions news, postNews, deleteNews | gov_news |
| `/gov`, `/vote` | gov_core, gov_votes |
| events onGovSettingChanged / onGovTaxRun, onGovCompanyTaxed / onGovVoteOpened, onGovVoteClosed / onGovNewsPosted | gov_core / gov_tax / gov_votes / gov_news |
| timers: settings resync, tax hour + catch-up, vote close, standing runner, public rebuild, checkPayers | gov_core, gov_tax, gov_votes, gov_treasury, gov_web, gov_works + gov_health |
| tables gov_settings, gov_members, gov_log, gov_companies / gov_tax_runs / gov_standing_orders / gov_votes, gov_vote_ballots / gov_news | gov_core / gov_tax / gov_treasury / gov_votes / gov_news |
| element data `v_gov.vat` | gov_tax (`gov_tax.vat`) |

---

## 7. Order of work

1. **gov_core**: lib (`importLib`), settings with registered defaults, members, log, state
   companies, routing + `reply`, client opener, shell page, Companies / Members / Log pages.
2. **Modules** one by one, code moved nearly verbatim (`GOV.get/set` → lib wrappers over the
   gov_core exports): gov_tax → gov_works → gov_health → gov_transport → gov_treasury →
   gov_votes → gov_news. Every page file split out of gov.js together with its module.
3. **gov_web**: move to `[government]`, snapshot builder, include.
4. **Texts**: locale split + prefix rename script.
5. **Callers**: the table in section 5, then `grep -rn "v_gov"` over resources must find nothing
   except the ledger origin string and history notes.
6. Delete `[economy]/v_gov`; README per resource, DESIGN.md split into the resources it
   describes (gov_core keeps the overview + roles + DB sections).
7. **Tests**: lupa syntax check of every file; offline unit tests for settings defaults,
   routing / role check, VAT lib; in game: every page once read + one change, `/vote`, a tax
   hour, a standing order, a healthcare charge, a ticket sale, gov_web snapshot, and stopping /
   restarting each module alone (its menu item disappears / comes back, callers fall back).

## 8. Risks / to decide
- **Folder name**: written here as `[government]`; the request said `[goverment]`.
- **Settings across resources**: every `getSetting` is now an export call. The hot paths (VAT
  uses element data, getWage per payment, fare per ticket) are rare enough; if needed a module can
  keep a local copy refreshed by `onGovSettingChanged`.
- **gov_core restart**: the modules re-register on its `onResourceStart`; open /gov windows close
  (as when v_gov restarts today).
- **Cross-resource page scripts** (`http://mta/<other resource>/…`): web_api's loader already loads
  pages of another resource, but this is verified first with a minimal page before the JS split.
