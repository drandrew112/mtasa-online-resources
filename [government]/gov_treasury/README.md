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
