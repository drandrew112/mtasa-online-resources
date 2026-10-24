-- eco_loan / shared/config.lua
-- Loan settings. Three borrower kinds:
--   personal - a player account; an installment every ONLINE hour of the player
--   company  - a biz_core organization; an installment every hour the company runs (founder online)
--   state    - a state bank account (treasury / state company); an installment every 24 real hours
--
-- The lender is the bank itself (money created / the repayments disappear) or a state / company
-- bank account given at creation (it pays the loan out and receives the installments).

LOAN = {
    KINDS = {
        personal = {
            interval = 3600,           -- s between two installments
            online = true,             -- the interval counts only while the borrower is online
            rate = 10,                 -- default total interest in % of the principal
            maxRate = 100,
            minAmount = 1000,
            maxAmount = 5000000,
            installments = 24,         -- default number of installments
            maxInstallments = 336,
            maxActive = 2,             -- open loans of one borrower
            forceAfterMissed = 3,      -- after this many missed installments in a row the bank takes it anyway (debt); 0 = always
            penaltyRate = 5,           -- a missed installment adds this % of the installment to the debt
        },
        company = {
            interval = 3600,
            online = true,
            rate = 8,
            maxRate = 100,
            minAmount = 10000,
            maxAmount = 50000000,
            installments = 48,
            maxInstallments = 720,
            maxActive = 3,
            forceAfterMissed = 3,
            penaltyRate = 5,
        },
        state = {
            interval = 86400,
            online = false,            -- real time: the state pays even when nobody is online
            rate = 3,
            maxRate = 50,
            minAmount = 100000,
            maxAmount = 1000000000,
            installments = 30,
            maxInstallments = 365,
            maxActive = 10,
            forceAfterMissed = 0,      -- the state always pays (its account may go into debt)
            penaltyRate = 0,
        },
    },

    TICK_MS = 60000,       -- online seconds are counted / due loans are collected this often
    RESYNC_MS = 30000,     -- open loans are re-read this often (the other server instance)
    NOTE_MAX = 64,
    HISTORY_PAGE = 25,
    HISTORY_MAX = 100,
}

LOAN_STATUS = { pending = true, active = true, paid = true, forgiven = true, failed = true }
LOAN_OPEN = { pending = true, active = true }
