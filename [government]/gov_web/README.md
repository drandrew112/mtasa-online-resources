# gov_web

Open government website of San Andreas, on web_api: `http://<server>:<httpport>/gov_web/` and the
in-game ui_browser site **gov.sa**.

Shows the State Treasury (balance, income / expense, daily bars, by category), the budget of every
state company (balance, income / expense by category, the works it pays), the tax rates (company
income tax, property tax, personal income tax keys, VAT per product group), fees and fines, the state
healthcare prices, public pay (payer, multiplier, income tax key per work) and the state votes (open
ones with the number of voters, closed ones with the results).

Read only, no login. The only export, `govWebState` (`http="true"`), returns a snapshot gov_web
rebuilds every minute from the public exports of the gov_* modules (`gov_treasury:getPublicFinance`,
`gov_tax:getPublicTaxes`, `gov_works:getPublicWorks`, `gov_health:getPublicHealth`,
`gov_votes:getPublicVotes`): money data of the last 30 days only, no account names. A module that
does not run leaves its part empty.

Depends on `web_api`, `ui_browser`, `gov_core` (`<include>`). Lives in `[government]` since 2026-10-24.
