# gov_loans — state loans

Part of `[government]` (see gov_core README). /gov page **Loans** (category Economy). The treasury
and the state companies borrow from the bank through eco_loan (kind `state`); the bank's terms are
eco_loan's `LOAN.KINDS.state` (`shared/config.lua`: 3 % flat interest, € 100 000 – 1 000 000 000,
up to 365 installments, one every 24 real hours, always collected: the account may go negative).

- Everyone with a /gov role: state debt, open loans, the last 25 closed loans, the payments of a loan.
- Minister: take a loan (borrower = an active state account, amount, number of installments, note;
  the page previews the repayment), repay any amount early or pay a loan off.
- Change log: `loan.take`, `loan.repay` (gov_log).

Money moves only through eco_loan / v_bank (`loan.*` keys, ledger group Loans). Depends on
gov_core, eco_loan. Texts: v_locals `gov_loans.*` (+ `eco_loan.status.*`, `eco_loan.error.*`).
