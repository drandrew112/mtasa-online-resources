# gov_works — work pay set by the state

Part of `[government]` (see gov_core README). /gov page **Works** (category Employment). Settings
`work.<id>.payer | multiplier | taxKey | p.<param>`; per-work defaults in `GOV_WORK_DEFAULTS`
(ems, bloodtransport: treasury pays, `exempt` tax key).

A work resource registers its parameters on its start and on gov_works' start and reads them with
`getWage`, falling back to its config (med_erm `server/payment.lua`, bt_dispatch `server/core.lua`,
work_traindriver `server/pay.lua`, avi_controller `server/main.lua`). work_core `payWork` uses the
payer, the multiplier and the income tax rate.

| Export | |
| --- | --- |
| `registerWage(workId, params)` | `{ {key, label, default, kind = "xp"?}, ... }` |
| `getWage(workId, key)` | the /gov override or nil |
| `getWorkPayer(workId)` | v_bank account id or `"system"` (a closed payer = system) |
| `getWorkMultiplier(workId)` | number |
| `getIncomeTaxRate(workId)` | rate, key — nil while the keys are not available (work_core falls back) |
| `getWorkList()`, `getWorkTaxKeys()`, `getStatePayerWorks()`, `getPublicWorks()` | for gov_tax, gov_core, gov_web |

A private company that closes while it pays a work: the work goes back to system (checked after
every gov_core settings re-read).
