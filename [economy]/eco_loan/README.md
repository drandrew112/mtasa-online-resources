# eco_loan — loans

Every loan of the server is one row in MySQL `eco_loans`; every payout, installment, missed
installment and forgiveness is one row in `eco_loan_payments`. Money moves only through v_bank,
with the `loan.*` keys (v_bank `shared/keys.lua`, ledger group **Loans**).

| Kind | Borrower (`borrower`) | Installment | Default terms (`shared/config.lua`) |
| --- | --- | --- | --- |
| `personal` | a logged-in player (element or account name) | every **online hour** of the player | 10 %, 24 installments, € 1 000 – 5 000 000, max 2 open |
| `company` | a biz_core company id | every hour the company **runs** (founder online, not paused) | 8 %, 48 installments, € 10 000 – 50 000 000, max 3 open |
| `state` | a state account code (`treasury`, a state company code) | every **24 real hours** | 3 %, 30 installments, € 100 000 – 1 000 000 000 |

- **Interest** is flat: `total = principal × (1 + rate / 100)`, split into equal installments
  (rounded up, the last one is what is left). Rate, installments and the interval can be given per
  loan within the kind's limits.
- **Lender**: the bank itself (the payout is created, the repayments disappear) or a state /
  company bank account (`options.lender` = account id): it pays the loan out (needs the money)
  and receives the installments.
- **Missed installment** (not enough money, frozen / closed account): the debt grows by
  `penaltyRate` % of the installment (5 %), the next try comes after the next interval. After
  `forceAfterMissed` misses in a row (3) the installment is taken with `loan.installment_forced`:
  the account may go below 0. State loans are always forced (no penalty).
- Online seconds are counted in the table (`progress_sec`), so a loan keeps its progress across
  disconnects and restarts. The due installment is claimed with one UPDATE, so both server
  instances can run at once; after a downtime the missed state installments follow one per minute.
- Notifications (ui_core, v_locals `eco_loan.*`): the player / the company founder. State loans
  notify nobody.

Depends on `v_mysql`, `v_bank`, `v_locals`; `biz_core` for company loans.

## Server exports

```lua
local loans = exports.eco_loan
```

| Export | Returns |
| --- | --- |
| `isLoanReady()` | tables + open loans loaded, v_bank ready |
| `getLoanConfig()` | the kinds' settings (copy) |
| `quoteLoan(kind, amount [, options])` | `{ principal, interest, total, rate, installments, installment, interval }` \| false, err |
| `createLoan(kind, borrower, amount [, options, actor])` | true, quote \| false, err — the id comes with `onLoanCreated` |
| `getLoan(id)` | open loan \| false |
| `getLoans({ kind, borrower })` | open loans |
| `getPlayerLoans(player)` / `getCompanyLoans(companyId)` / `getStateLoans(code)` | open loans |
| `getDebt(kind, borrower)` | sum of the remaining debt |
| `repayLoan(id, amount, actor)` | true, paid \| false, err — early repayment from the borrower's account |
| `payOffLoan(id, actor)` | true, paid \| false, err — the whole remaining debt |
| `forgiveLoan(id, actor)` | true \| false, err |
| `loanCall(requestId, action, args, actor)` | true — answers later with `triggerEvent("<caller>:remoteResult", <caller root>, requestId, result)` |

`options = { rate, installments, interval (s), lender (bank account id), note, tag }`

A loan: `{ id, kind, borrower, borrowerName, borrowerAccount, lender, principal, rate, total,
installment, installments, paidCount, paidAmount, remaining, penalties, interval, progress,
nextDue, nextIn, online, missed, missedStreak, status, note, createdBy, createdAt, lastPaymentAt,
closedAt, closedBy }`. `nextIn` = seconds until the next installment (online seconds for
personal / company). Status: `pending` (being paid out), `active`, `paid`, `forgiven`, `failed`.

`loanCall` actions (for the gov / bank websites, admin):
- `history { kind, borrower, status = "open"|"closed"|<status>, beforeId, limit }` → `{ ok, loans }`
- `payments { id }` → `{ ok, loan, payments }`
- `create { kind, borrower, amount, options }` → `{ ok, id }`
- `repay { id, amount }` → `{ ok, paid }`, `forgive { id }` → `{ ok }`, `quote { kind, amount, options }` → `{ ok, quote }`

Errors: `bad_kind`, `bad_amount`, `bad_rate`, `bad_installments`, `bad_interval`, `bad_lender`,
`borrower_offline`, `no_account`, `too_many_loans`, `no_loan`, `unavailable` + the v_bank errors
(`not_enough_money`, `frozen` ...). Texts: `eco_loan.error.<err>`.

## Events (server, source = eco_loan resourceRoot)
- `onLoanCreated(loanId, kind, borrowerRef, principal, tag)` / `onLoanFailed(kind, borrowerRef, err, tag)`
- `onLoanPayment(loanId, amount, "installment"|"forced"|"extra", remaining)`
- `onLoanMissed(loanId, missedStreak, penalty)`
- `onLoanClosed(loanId, "paid"|"forgiven")`

## Tests
`python tests/run.py` (lupa, Lua 5.1): quotes, creation / payout, limits, online and real-time
collection, missed → forced, early repayment, forgiveness.
