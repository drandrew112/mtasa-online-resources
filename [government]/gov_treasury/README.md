# gov_treasury — state money

Part of `[government]` (see gov_core README). /gov pages **Overview** (on top), **Treasury**,
**Transfers**, **Budget** (category Economy). Table `gov_standing_orders`.

- **Overview**: treasury balance, last 24 h / 7 days by group, state accounts, last tax runs (gov_tax).
- **Treasury**: statement of the treasury or a state company (last 30 days), money between the
  treasury and a state company.
- **Transfers**: between state accounts, payment to a private company, collection (inkasszó, forced)
  from a private company; **standing orders** = the same three as recurring transfers (checked every
  30 s, a due order is claimed so one instance books it; a failed one waits for the next interval).
- **Budget**: income / expense of the treasury and every state company by group, daily bars (30 days).

Every transfer is a `transfer.*` row of gov_core's log. Export `getPublicFinance()`: the money part
of gov_web (rebuilt every minute).

## Budget plan (page `budgetPlan`, server/plan.lua)
A 24-hour plan for every day of the next week (Monday..Sunday, each column = the next date of that
weekday): first for the whole state, then one card per state account (State Treasury + every state
company). Rows:
- plan items (setting `plan.items`, minister): account (state code, default treasury), name,
  income / expense, an amount per weekday, note; only a plan, nothing is booked
- standing orders: the amount of every enabled order that falls on the day. A state <-> state order
  is an expense of the sender and an income of the receiver; in the whole-state plan it is shown
  dimmed and not counted (the money stays inside the state). Payments / collections with private
  companies count everywhere.
- railway running costs from gov_transport `getRailDayCosts` (that day's rw_timetable timetable ×
  the pt.rail costs): an expense of the paying state account, an income of the receiving one;
  not a state account / from nobody to nowhere = shown dimmed in the whole-state plan.

Totals per day and for the week. Log: `plan.create / update / delete`.
