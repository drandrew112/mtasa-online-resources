# gov_perms — the state permission system

Every right of the state, positions that hold rights, officials that hold positions, an hourly
salary per position. Design and decisions: [DESIGN.md](DESIGN.md). Implemented 2026-10-24,
**not yet tested in-game**.

## In short
- **Allow-only.** A right nobody granted is refused; whatever a position cannot do, its holder
  does not see (menu items, buttons) and cannot do (every request is checked by gov_core).
- **Catalogue** (`gov_perms` table): the rights the modules declare (`GOV.module{ perms, families }`)
  - static keys (`tax.vat.edit`) and generated ones: a family × its targets
  (`gov.<company id>.bank.pay`, `works.<work>.pay`, `health.<hospital>.billing`, `fees.<fee>.edit`,
  `fines.<fine>.edit`). A new state company has its rights at once; rights of a stopped module or a
  closed company stay (inactive, greyed).
- **Positions** (`gov_perms_groups`): name, rank, max holders (1 = single holder), salary per online
  hour, income tax key, color; rights in `gov_perms_group_perms` as keys or patterns
  (`rail.*`, `gov.*.bank.view`, `gov.*.*` + branch, `*`).
- **Officials** (`gov_perms_members`): one account may hold several positions (rights add up, every
  salary is paid); an appointment may end (`expires_at`).
- **Only the Governor or an admin** (level ≥ 5) appoints and edits positions (`perms.manage`, held
  only by the Governor's system group). System groups (Governor, the legacy roles) are changed by
  admins only.
- **Branches** (`gov_branches`, editable): every state company has one, set by the Governor / an
  admin only (State companies page, needs `perms.manage`); a minister's grant `gov.*.*` + branch
  `health` covers every health company at once, also future ones.
- **Bank access of the state accounts = rights:** `gov.<id>.bank.manage` → v_bank owner, `.pay` →
  manager, `.view` → viewer, nothing → removed (synced 2 s after a change and every 60 s). The
  company page shows the access read-only.
- **Salaries:** the State Treasury pays every position's salary per online hour of the holder
  (`salary.gov`, then `tax.income` by the position's tax key). The Budget plan shows them as a
  treasury expense (salary × expected online hours: last 7 days, else the plan default).

## First start
One instance (the `perms.migrated` row in `gov_settings`): branches (transport incl. aviation,
health, finance, interior, justice, public works, media, municipal, other), the positions Governor,
Finance / Transport / Health / Interior / Justice / Employment Minister and Government
Spokesperson (salaries 0), the old `gov_members` roles → system groups `legacy_viewer /
legacy_official / legacy_minister`, the existing bank access rows of the state accounts →
"<account> - <role> (migrated)" positions. No mayor positions: a city is a state company; the
Governor makes e.g. "Mayor of Los Santos" with `gov.<City of LS id>.*`.

## /gov → Administration → Permissions
| Tab | |
| --- | --- |
| Positions | list (holders, salary); settings, holders, the rights tree by menu area (a checkbox per right; a family: all / by branch / one by one), other rules (patterns) |
| Officials | appoint (account, position, days, note; a full single-holder position is replaced), dismiss, end date, paid in 30 days, the resolved rights of one official |
| Branches | add, rename, order, archive (`other` stays) |
| Catalogue | every right, also the inactive ones (purge), who holds it |

## For a module
```lua
GOV.module({
    perms = { { "my.view", "services", 0 }, { "my.edit", "services", 1 } },   -- key, area (menu category), danger 0..3
    families = { { "my.*.run", "services", 2 } },                              -- "*" = the targets below
    actions = { myPage = "my.view", setMy = "my.edit", runIt = { perm = "my.{id}.run", arg = "id" } },
    pages = { { id = "myPage", category = "services", order = 30, script = "web/js/pages.js", need = "my.view" } },
})
GOV.setTargets("my", { { id = "a", name = "Thing A" } })
-- in a handler: GOV.has(player, "my.a.run"), GOV.targets(player, "my.*.run") -> { all = true } | { a = true }
-- in the page: GOV.can("my.edit")
```
Names of the rights: `gov_perms.perm.<key>` / `gov_perms.perm.<family>` (`{target}`) in
v_locals `gov_perms.json`; the Permissions page asks the ones listed in its `PERM_KEYS`.

## Server exports
| Export | |
| --- | --- |
| `isGovPermsReady()` | |
| `hasGovPerm(accountOrPlayer, key)` / `getGovPermTargets(who, family)` / `hasAnyGovPerm(who)` / `getGovGrants(who)` | positions only (gov_core adds admins + sectors: use `exports.gov_core:hasGovPerm`) |
| `getGovPositions(account)` | `{ {id, code, name, rank, salary, expiresAt} }` |
| `getGovPermCatalogue()` / `getGovBranches()` / `isGovSuper(who)` | |
| `getSalaryPlan()` | the salaries for the Budget plan |
| `appointGov(account, groupCode, expiresAt, actor)` / `dismissGov(account, groupCode, actor)` | automation (the election system later): only resources in `PERMS.AUTOMATION` |

Events (source = gov_perms resourceRoot): `onGovPermsChanged(account | false)`,
`onGovAppointed(account, group code)`, `onGovDismissed(account, group code)`,
`onGovSalaryPaid(account, group code, gross, tax)`.
