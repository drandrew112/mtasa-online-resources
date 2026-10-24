-- eco_loan / server/main.lua
-- Start order: schema -> open loans -> collector + resync timer.

addEventHandler("eco_loan:dbReady", resourceRoot, function()
    LOANS.resync()
    setTimer(LOANS.resync, LOAN.RESYNC_MS, 0)
    COLLECT.start()
end)

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start()
end)
