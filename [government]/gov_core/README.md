# gov_core — the state, foundation of `[government]`

The base every `gov_*` resource includes. Split out of v_gov on 2026-10-24 ([SPLIT_PLAN.md](SPLIT_PLAN.md),
old design: [DESIGN.md](DESIGN.md)).

| Resource | What it owns | /gov pages |
| --- | --- | --- |
| **gov_core** | settings, permission checks, change log, state companies (+ branch), the /gov shell, the module lib | State companies, Log |
| gov_perms | the permission system: catalogue of rights, positions (+ hourly salary), appointments, branches; state company bank access | Permissions |
| gov_treasury | overview, statements, transfers, standing orders, budget, weekly budget plan | Overview, Treasury, Transfers, Budget, Budget plan |
| gov_loans | state loans from the bank (eco_loan) | Loans |
| gov_tax | company tax (hourly), income tax keys, VAT, property tax, fees, where each goes | Taxes, Fees |
| gov_works | work pay (payer, parameters, multiplier, tax key) | Works |
| gov_health | state healthcare | Healthcare |
| gov_transport | public transport fares + running costs | Public transport |
| gov_railways | railway operator company, the whole rw_timetable timetable | Railways |
| gov_votes | state votes, `/vote` | Votes |
| gov_news | government news (phone mails) | News |
| gov_web | public website gov.sa (`/gov_web/`) | – |

Every module only `<include>`s gov_core; calls between modules are optional (a stopped module = its
menu items are gone, the others fall back). Tables keep their v_gov names (`gov_settings`, ...).

## Permissions (since 2026-10-24)
The three roles are gone: every action and page needs a **permission key** of gov_perms
([../gov_perms/DESIGN.md](../gov_perms/DESIGN.md), [../gov_perms/README.md](../gov_perms/README.md)).
Officials hold positions, positions hold rights; allow-only. Admins with level ≥ `GOV.ADMIN_LEVEL`
(5) may do everything. While gov_perms does not run only admins get in (fail closed).

- A module declares its rights in `GOV.module{ perms = { { key, area, danger } },
  families = { { "x.*.y", area, danger, exclude = {...} } } }`; a family's `*` is filled with the
  targets the module reports (`GOV.setTargets(prefix, { {id, name}, ... })`). gov_core reports the
  `gov` targets itself: `"treasury"` + every state company id (`gov.<id>.bank.pay`, ...).
- An action needs a key (`"tax.vat.edit"`), a family = any target of it (`"works.*.view"`), a key
  filled from the request (`{ perm = "gov.{id}.edit", arg = "id" }`), `"panel"` (any official; the
  handler checks with `GOV.has`) or `"public"` (any logged-in player). Old role strings still work
  (`legacy.<role>`).
- In a handler: `GOV.has(player, key)`, `GOV.targets(player, family)` -> `{ all = true }` or a set,
  `GOV.reach(set, target)`, `GOV.accountTarget(bankId)` / `GOV.codeTarget(code)`.
- Pages: `GOV.can(key)` in the page script (hides buttons; the server checks every request).
- State companies have a `branch` (gov_perms' editable list): a grant `gov.*.…` + branch covers
  every company of that branch.

## Sectors
A module may hand a public service to a company: `GOV.module{ sectors = { { id, setting, perms } } }`.
The module's setting holds the operator (`"state:<code>"` | `"company:<id>"`, anything else =
nobody); everyone with bank access to that company's account (a state company: the
`gov.<id>.bank.*` rights of the positions; a private company: its founder / managers) gets the
sector's `perms` without a position. Export `isGovSectorMember(player, sector)`. Used by
gov_railways (`railways`, setting `rail.operator`, perms rail.view / rail.timetable.*).

## The /gov panel
One CEF window (`web/index.html`, `web/js/gov.js`). The side menu is grouped by category
(`server/config.lua` `GOV_CATEGORIES`: Overview on top, Economy, Revenue, Public services,
Employment, State organizations, Public affairs, Administration, Other). A category without a
visible page is hidden; categories collapse (kept per player in the page's localStorage); the open
page's category stays open. The shell loads the page scripts of the running modules
(`/<module>/<script>`); a script registers its pages with `GOV.page(id, { keys, load, render, actions, input })`
and uses `GOV.ui` (building blocks), `GOV.call`, `GOV.change`, `GOV.usePicker` / `GOV.pickerBox`.

Requests: page → `gov_core:call` → permission check → `onGovAction` on the module's resourceRoot → the
module answers `exports.gov_core:reply(reqId, result, err)` → `gov_core:reply` to the player
(30 s timeout; a stopping module fails its open requests).

## A module
```lua
-- first server script after locals.lua:
loadstring(exports.gov_core:importLib())()
-- ... GOV.A.myAction = function(player, args, reply, actor) reply(result) / reply(false, "err_key") end
GOV.module({
    settings = { prefixes = { "my." }, defaults = { ["my.value"] = 1 } },   -- only this module may change my.*
    perms = { { "my.view", "services", 0 }, { "my.edit", "services", 1 } },  -- area = menu category, danger 0..3
    actions = { myPage = "my.view", setMy = "my.edit" },                    -- "public" = any logged-in player
    pages = { { id = "myPage", category = "services", order = 30, script = "web/js/pages.js", need = "my.view" } },
    categories = { { id = "mine", order = 35 } },                           -- optional, text key <module>.menu.mine
})
-- the start: never onResourceStart (gov_core may not have loaded its settings yet)
GOV.onReady(function() DB.start(SCHEMA, loadMyData) end)
```
**Start order:** gov_core is ready once schema, settings and state companies are loaded (async MySQL);
then it triggers `gov_core:ready` (source = gov_core resourceRoot, listen on `root`; export
`isGovReady()`). A module loads nothing before that: `GOV.onReady(fn)` runs fn once, after the module
started and gov_core is ready (at once, or at `gov_core:ready`), and the module is registered (pages,
actions, settings defaults) only then — before the onReady fns, and again at every `gov_core:ready`
(gov_core restarted).

The lib gives `DB.*` (incl. `DB.start(schema, cb)`), `GOV.get/set/log`, `GOV.companyList / companyByCode /
companyById / stateAccounts / treasuryId`, `GOV.specAccount / targetAccount / checkSpec / payerOptions /
targetOptions / companyNames`, `GOV.bankCall`, `GOV.err`, `GOV.coreReady / onReady`, the permission helpers
`GOV.has / targets / reach / setTargets / accountTarget / codeTarget / permMatch`. Error keys: `reply(false, "x")` → `<module>.err.x` if it exists, else
`gov_core.err.x`. Texts: `<module>.ui.*`, `<module>.page.<id>` (page title), shared ones `gov_core.ui.*`.

## Server exports
| Export | |
| --- | --- |
| `importLib()` | the module lib source |
| `registerModule(def)` / `reply(reqId, result, err)` / `isGovReady()` | module plumbing |
| `getSetting(key)` | stored value, else the owner's default, else nil |
| `setSetting(key, value, actor)` | only for the calling module's own prefixes |
| `getStoredSettings(prefix)` | stored values only |
| `hasGovPerm(player, key)` | positions (gov_perms) + sectors; admins always; a family = any target |
| `getGovPermTargets(player, family)` | `{ all = true }` or `{ [target] = true }` |
| `setGovTargets(prefix, list)` / `getGovPermDefs()` | targets of a module's families / every module's rights (gov_perms) |
| `getGovRole(player)` / `canGov(player, role)` | legacy: answered from the `legacy.<role>` rights |
| `log(actor, action, detail)` | a gov_log row |
| `getStateCompanies()` / `getStateCompany(code)` / `getStateCompanyById(id)` | active state companies |

Client export: `openGovPage(resource, page)` (gov_votes `/vote`).

## Events (server, source = gov_core resourceRoot)
`onGovSettingChanged(key, value)`, `onGovSettingsSynced()` (after every 60 s re-read),
`onGovModulesChanged()` (a module / target list / company branch changed; gov_perms rebuilds).
gov_perms: `onGovPermsChanged(account | false)`, `onGovAppointed`, `onGovDismissed`, `onGovSalaryPaid`.
Of the modules: `onGovTaxRun`, `onGovCompanyTaxed` (gov_tax), `onGovVoteOpened`, `onGovVoteClosed`
(gov_votes), `onGovNewsPosted` (gov_news).
