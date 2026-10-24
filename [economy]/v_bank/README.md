# v_bank — bank accounts

Every bank balance of the server lives in MySQL (`bank_accounts`); every change of a balance is
one row in `bank_ledger` with a **transaction key** from `shared/keys.lua`. Design and decisions:
[DESIGN.md](DESIGN.md). Taxes, wages, fees and state companies are set in the **gov_*** resources (`/gov`, `[government]`).

- **personal** account: one per player account (created on the first login, or by the migration)
- **company** account: one per biz_core organization — the **clean** money only (dirty money stays
  in biz_core)
- **state** accounts: the **State Treasury** (`treasury`, the only one v_bank creates) and the
  state companies made on `/gov` (e.g. SA Control)

**Cash is not tracked.** It is GTA's own money; the ledger only sees it at deposit / withdrawal.

Depends on `v_mysql` (`<include>`). Works on both server instances at once: every booking is a
delta, the cache re-reads the shared accounts every 30 s.

## Start and migration

On start: schema → migration (`server/migrate.lua`, idempotent, may run on both instances) →
accounts. The migration
1. creates the State Treasury (on the overdraft list; re-created by the 30 s re-read if its row is
   deleted),
2. gives every player account without a bank account one, with the old account-data `bank_money`
   as opening balance (`migration.opening` row),
3. removes `bank_money` from the account data (from now on only the table + cache hold it),
4. gives every active organization a company account with its `balance_clean` (then zeroed).

Until the accounts are loaded every booking answers `"unavailable"`.

## Transaction keys

`shared/keys.lua` lists every possible booking: the paying side (`from`) and the receiving side
(`to`) — an account kind, `"system"` (money created / disappearing), `"cash"`, `"treasury"`
(filled in by v_bank), `"settled"` (the caller books the income later) or `"payer"` (a state /
company account or system) / `"payee"` (a state account or system; the taxes). `force` keys may push the payer below 0; accounts on the **overdraft
list** (`allow_negative`) may always go below 0. An unknown key, or an account on a side the key
does not allow, is refused (`"bad_key"`). The ledger text is `v_bank.tx.<key>[.in|.out]` in
v_locals, shown in the viewer's language.

## Server exports

```lua
local bank = exports.v_bank
```

### Accounts
| Export | Returns |
| --- | --- |
| `isBankReady()` | accounts loaded |
| `getPlayerAccount(player)` | account id \| false |
| `getPlayerBalance(player)` | number \| false |
| `getCompanyAccount(companyId)` / `getStateAccount(code)` | account id \| false |
| `getAccountInfo(id)` | `{ id, number, kind, ownerRef, name, balance, status, allowNegative }` \| false |
| `getBalance(id)` | number \| false |
| `getStateAccounts()` | list of infos |
| `getTaxableKeys()` | keys counting as legal company income (gov_tax) |
| `createCompanyAccount(companyId, name, founderAccount)` | true (async: `onBankAccountReady`) |
| `createStateAccount(code, name, allowNegative, actor)` | true \| false, err |
| `renameAccount(id, name)`, `setAccountStatus(id, "active"\|"frozen")`, `setAllowNegative(id, bool)`, `closeAccount(id)` | |
| `setAccess(id, accountName, "owner"\|"manager"\|"viewer"\|nil, actor)`, `hasAccess(player, id, "view"\|"use")` | |

### Bookings
`credit(id, amount, key, params, actor [, fromId])`, `debit(id, amount, key, params, actor [, toId])`,
`transfer(fromId, toId, amount, key, params, actor)` → `true, ref | false, err`
(`"bad_amount" | "bad_key" | "unavailable" | "not_enough_money" | "account_closed" | "frozen" | "same_account"`).

### Player wrappers
| Export | Returns |
| --- | --- |
| `giveBankMoney(player, amount, key, params [, payerId])` | true \| err |
| `takeBankMoney(player, amount, key, params [, payeeId])` | true \| err (not for force keys) |
| `forceTakeMoney(player, amount, key, params [, payeeId])` | true, newBalance \| err (force keys only) |
| `depositMoney(player, amount)` / `withdrawMoney(player, amount)` | true \| `"not_enough_cash"` / `"not_enough_money"` \| err |
| `payMoney(player, amount, key, params)` | true, `"cash"`\|`"bank"` \| false, err — cash first (not booked), else the bank |

Every booking on a player's own account shows on the ui_core money HUD.

### Website / admin
- `requestBankAccounts(player)`, `requestLedger(player, id, beforeId, group)`,
  `requestTransfer(player, fromId, number, amount, note, confirm)` — answer with the client events
  `v_bank:accounts`, `v_bank:ledger`, `v_bank:transfer` (ui_browser Liberty Bank).
- `bankCall(requestId, action, args, actor)` — admin panel / gov_* requests that answer later with
  `triggerEvent("<caller>:remoteResult", <caller root>, requestId, result)`; actions: search,
  account, ledger, stats, byNumber, adjust, transfer, status, overdraft, access, rename, close,
  createState.

### Cash helpers
`playPickupMoneySound([player])` (server + client), `createMoneyPickup(x, y, z, money [, player])`.

## Events (server, source = v_bank resourceRoot)
- `onBankBalanceChanged(accountId, balance, amount, key, params)`
- `onBankAccountReady(accountId, kind, ownerRef)`

## Element data
`bank_money` (balance) and `bank_account` (number) on the player: a read-only mirror for the HUDs;
a client cannot change them.

## Tests
`python tests/run.py` (lupa, Lua 5.1): bookings, keys, sides, overdraft, transfers, resync with
deltas in flight, player wrappers.
