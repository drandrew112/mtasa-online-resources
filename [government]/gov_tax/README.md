# gov_tax — state revenue

Part of `[government]` (see gov_core README). /gov pages **Taxes** and **Fees** (category Revenue).
Settings `tax.*`, `fee.*` (defaults: `server/config.lua`). Table `gov_tax_runs`.

- **Company income tax**: every full hour (+30 s) the taxable ledger rows of each company account of
  the hour that ended are summed; a positive base pays `floor(base * rate)` (default 10 %) to the
  tax's account (`tax.company_income`). One instance runs an hour (`gov_tax_runs` claim); missed hours
  of the last 24 h are caught up once gov_core and v_bank are ready.
- **Income tax rate keys** (`standard` 12 %, `exempt` 0 %, more can be added); gov_works assigns a key
  per work. A key a work uses cannot be deleted (refused while gov_works is not running).
- **VAT** per product group on top of every shop price; rates published as root element data
  `gov_tax.vat`. Shops: `<include resource="gov_tax" />` and
  `if not VAT then loadstring(exports.gov_tax:importVat())() end`, then `VAT.gross` / `VAT.split` /
  `VAT.book` (shared/vat.lua). `download_priority_group` 1000 (before ui_browser / ui_core).
- **Property tax**: biz_core pays `rate × property prices` every 24 online hours.
- **Fees & fines**: register, rename, bay_fine, airspace takeoff / landing / overflight.
- **Where the money goes** (`tax.targets`, `fee.targets`): the treasury or a state company per tax /
  fee; none chosen (default) or a closed account = the money disappears.

| Export | |
| --- | --- |
| `getCompanyTaxRate()` / `getPropertyTaxRate()` | 0..1 |
| `getTaxTarget(tax)` | account id of `company` / `income` / `vat` / `property`, or nil |
| `getIncomeTaxKeys()` | `{ key = rate }` |
| `getTaxRuns(n, since)` | last runs `{ period, companies, total, instance }` (cached, gov_treasury overview) |
| `importVat()` (server + client), `getVatRate(group)`, `getVatRates()`, `bookVat(group, net, vat, item)` | VAT |
| `getFee(key)` / `getFeeTarget(key)` | fee amount / account id or nil |
| `getPublicTaxes()` | gov_web part |

Events: `onGovTaxRun(periodStart, companies, total)`, `onGovCompanyTaxed(companyId, tax, base, periodStart)`.
