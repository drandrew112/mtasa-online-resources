-- v_bank / shared/config.lua
-- Settings of the bank (DESIGN.md). The transaction keys are in shared/keys.lua.

BANK = {
    -- shared accounts (company, state) and the cached personal accounts are re-read this often,
    -- so a booking made on the other server instance shows up here (DESIGN.md 5)
    RESYNC_MS = 30000,

    -- account number: LB-<digit>-<6-digit id>
    KIND_DIGIT = { personal = 1, company = 2, state = 9 },

    -- state accounts created by v_bank itself (migration, every start: INSERT IGNORE); every other
    -- state account (SA Control too) is a state company made on the /gov Companies page
    STATE = {
        { code = "treasury",  name = "State Treasury", allowNegative = true },
    },
    TREASURY = "treasury",

    -- ledger pages (website, admin panel)
    LEDGER_PAGE = 25,
    LEDGER_MAX = 100,

    -- transfer note shown in both ledgers
    NOTE_MAX = 60,

    -- one booking never moves more than this (typo guard)
    MAX_AMOUNT = 1000000000,
}
