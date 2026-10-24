# gov_core — the state, foundation of `[government]`

The base every `gov_*` resource includes. Split out of v_gov on 2026-10-24 ([SPLIT_PLAN.md](SPLIT_PLAN.md),
old design: [DESIGN.md](DESIGN.md)).

| Resource | What it owns | /gov pages |
| --- | --- | --- |
| **gov_core** | settings, roles + members, change log, state companies, the /gov shell, the module lib | State companies, Members, Log |
| gov_treasury | overview, statements, transfers, standing orders, budget | Overview, Treasury, Transfers, Budget |
| gov_tax | company tax (hourly), income tax keys, VAT, property tax, fees, where each goes | Taxes, Fees |
| gov_works | work pay (payer, parameters, multiplier, tax key) | Works |
| gov_health | state healthcare | Healthcare |
| gov_transport | public transport fares + running costs | Public transport |
| gov_votes | state votes, `/vote` | Votes |
| gov_news | government news (phone mails) | News |
| gov_web | public website gov.sa (`/gov_web/`) | – |

Every module only `<include>`s gov_core; calls between modules are optional (a stopped module = its
menu items are gone, the others fall back). Tables keep their v_gov names (`gov_settings`, ...).

## Roles
`viewer` (read) < `official` (healthcare, state companies) < `minister` (everything else). Admins
with level ≥ `GOV.ADMIN_LEVEL` (5) are ministers. Roles live in `gov_members` (Members page).

## The /gov panel
One CEF window (`web/index.html`, `web/js/gov.js`). The side menu is grouped by category
(`server/config.lua` `GOV_CATEGORIES`: Overview on top, Economy, Revenue, Public services,
Employment, State organizations, Public affairs, Administration, Other). A category without a
visible page is hidden; categories collapse (kept per player in the page's localStorage); the open
page's category stays open. The shell loads the page scripts of the running modules
(`/<module>/<script>`); a script registers its pages with `GOV.page(id, { keys, load, render, actions, input })`
and uses `GOV.ui` (building blocks), `GOV.call`, `GOV.change`, `GOV.usePicker` / `GOV.pickerBox`.

Requests: page → `gov_core:call` → role check → `onGovAction` on the module's resourceRoot → the
module answers `exports.gov_core:reply(reqId, result, err)` → `gov_core:reply` to the player
(30 s timeout; a stopping module fails its open requests).

## A module
```lua
-- first server script after locals.lua:
loadstring(exports.gov_core:importLib())()
-- ... GOV.A.myAction = function(player, args, reply, actor) reply(result) / reply(false, "err_key") end
GOV.module({
    settings = { prefixes = { "my." }, defaults = { ["my.value"] = 1 } },   -- only this module may change my.*
    actions = { myPage = "viewer", setMy = "minister" },                    -- "public" = any logged-in player
    pages = { { id = "myPage", category = "services", order = 30, script = "web/js/pages.js" } },
    categories = { { id = "mine", order = 35 } },                           -- optional, text key <module>.menu.mine
})
```
The lib gives `DB.*` (incl. `DB.start(schema, cb)`), `GOV.get/set/log`, `GOV.companyList / companyByCode /
companyById / stateAccounts / treasuryId`, `GOV.specAccount / targetAccount / checkSpec / payerOptions /
targetOptions / companyNames`, `GOV.bankCall`, `GOV.err`, `GOV.coreReady`. It re-registers the module
whenever gov_core starts. Error keys: `reply(false, "x")` → `<module>.err.x` if it exists, else
`gov_core.err.x`. Texts: `<module>.ui.*`, `<module>.page.<id>` (page title), shared ones `gov_core.ui.*`.

## Server exports
| Export | |
| --- | --- |
| `importLib()` | the module lib source |
| `registerModule(def)` / `reply(reqId, result, err)` / `isGovReady()` | module plumbing |
| `getSetting(key)` | stored value, else the owner's default, else nil |
| `setSetting(key, value, actor)` | only for the calling module's own prefixes |
| `getStoredSettings(prefix)` | stored values only |
| `getGovRole(player)` / `canGov(player, role)` | `"viewer" \| "official" \| "minister" \| false` |
| `log(actor, action, detail)` | a gov_log row |
| `getStateCompanies()` / `getStateCompany(code)` / `getStateCompanyById(id)` | active state companies |

Client export: `openGovPage(resource, page)` (gov_votes `/vote`).

## Events (server, source = gov_core resourceRoot)
`onGovSettingChanged(key, value)`, `onGovSettingsSynced()` (after every 60 s re-read).
Of the modules: `onGovTaxRun`, `onGovCompanyTaxed` (gov_tax), `onGovVoteOpened`, `onGovVoteClosed`
(gov_votes), `onGovNewsPosted` (gov_news).
