# v_gov — the state

`/gov` opens the government panel (a full-screen CEF page, `web/`): taxes, work pay, fees and
fines, state healthcare, state companies, members and the change log. The money is the **State Treasury** of v_bank. Design and
decisions: [DESIGN.md](DESIGN.md).

Depends on `v_mysql`, `v_locals` and `web_api` (`<include>`); uses v_bank, work_core, medsys, biz_core when
they run.

## Roles
`viewer` (read) < `official` (healthcare prices, state companies) < `minister` (taxes, works,
fees, members, treasury transfers). Admins with level ≥ `GOV.ADMIN_LEVEL` (5) are ministers.
Roles live in `gov_members` (Members page).

## What it does
- **Company income tax**: every full hour (+30 s) the taxable ledger rows of each company account
  (now: the casino result, net) of the hour that ended are summed; a positive base pays
  `floor(base * rate)` (default 10 %) to the tax's account (`tax.company_income`). One instance runs an
  hour (`gov_tax_runs` claim); missed hours of the last 24 h are caught up on start.
- **Works** (per work, Works page): payer (system by default, treasury, a state or a private
  company), every pay and XP parameter the work registered, wage multiplier, income tax rate key.
- **Income tax rate keys** (Taxes page): `standard` 12 %, `exempt` 0 %, more can be added; work_core
  `payWork` takes the tax of the work's key from the whole positive wage.
- **Fees & fines**: company registration fee (→ treasury), rename fee, ambulance bay fine,
  airspace fees takeoff / landing / overflight (→ SA Control).
- **State healthcare**: med_hospitals bills every treatment (treatment marker, ambulance handover;
  players and NPC patients) to the treasury: missing HP × price + injury prices.
- **VAT** (Taxes page): a rate per product group, added on top of every shop price, booked to the
  tax's account (`tax.vat`). Shops: `<include resource="v_gov" />` and
  `if not VAT then loadstring(exports.v_gov:importVat())() end`, then `VAT.gross` / `VAT.split` /
  `VAT.book` (shared/vat.lua).
- **Property tax** (Taxes page): biz_core pays `rate × property prices` every 24 online hours.
- **Where the taxes go** (Taxes page, setting `tax.targets`): company, income, VAT and property tax
  each go to the state account chosen for it (the treasury or any state company). With none chosen
  (the default) the money disappears; a chosen account that is closed / gone also means disappears.
- **Votes** (Votes page, minister): title, description, options, length; players vote with `/vote`;
  results after the close.
- **News** (News page, minister): title + text in every language (`gov_news`); sent as a phone email
  to every account, deleting it takes the emails back.
- **Budget**: treasury + every state company, income / expense by group. Money data of /gov is
  limited to the last 30 days (`GOV.HISTORY_DAYS`).
- **State companies** (`gov_companies` + a v_bank state account each): create, rename, describe, close (balance moved to the treasury first), members (bank
  access), overdraft.

## Server exports
| Export | |
| --- | --- |
| `getSetting(key)` | a setting (stored or default) |
| `getFee(key)` | `register`, `rename`, `bay_fine`, `airspace.takeoff` / `.landing` / `.overflight` |
| `getCompanyTaxRate()` | 0..1 |
| `getGovRole(player)` | `"viewer" \| "official" \| "minister" \| false` |
| `registerWage(workId, params)` | a work's pay / XP parameters `{ {key, label, default, kind = "xp"?}, ... }` |
| `getWage(workId, key)` | the /gov override or nil (= use the default) |
| `getWorkPayer(workId)` | v_bank account id or `"system"` |
| `getWorkMultiplier(workId)` | number |
| `getIncomeTaxRate(workId)` | rate, key |
| `getTaxTarget(tax)` | v_bank account id the tax (`company` / `income` / `vat` / `property`) goes to, or nil = disappears |
| `importVat()` (server + client) | the VAT lib source (shared/vat.lua) |
| `getVatRate(group)` / `getVatRates()` | 0..1 |
| `bookVat(group, net, vat, item)` | the VAT of a purchase to the tax's account (none = nothing booked) |
| `getPropertyTaxRate()` | 0..1, per 24 online hours |
| `getPublicState()` | the gov_web snapshot (30 days, no account names) |
| `healthcareCost(patient)` | amount, `{ hp, injuries }` (books nothing) |
| `chargeHealthcare(patient, hospitalName [, taskId])` | true, amount \| false, err |

A work resource registers its parameters on its start and on v_gov's start (see med_erm
`server/payment.lua`, bt_dispatch `server/core.lua`, work_traindriver `server/pay.lua`,
avi_controller `server/main.lua`) and reads them with `getWage`, falling back to its config.

## Events (server)
`onGovSettingChanged(key, value)`, `onGovTaxRun(periodStart, companies, total)`,
`onGovCompanyTaxed(companyId, tax, base, periodStart)`.
