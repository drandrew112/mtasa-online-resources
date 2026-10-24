# gov_web

Open government website of San Andreas, on web_api: `http://<server>:<httpport>/gov_web/` and the
in-game ui_browser site **gov.sa**.

Shows the State Treasury (balance, income / expense, daily bars, by category), the budget of every
state company (balance, income / expense by category, the works it pays), the tax rates (company
income tax, property tax, personal income tax keys, VAT per product group), fees and fines, the state
healthcare prices, public pay (payer, multiplier, income tax key per work) and the state votes (open
ones with the number of voters, closed ones with the results).

Read only, no login. The only export, `govWebState` (`http="true"`), returns
`exports.v_gov:getPublicState()`: a snapshot v_gov rebuilds every minute, with money data of the last
30 days only and no account names.

Depends on `web_api`, `ui_browser`, `v_gov` (`<include>`).
