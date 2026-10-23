-- v_bank / server/main.lua
-- Start order: schema -> migration -> accounts (state + company + the logged-in players).
-- Bookings are refused ("unavailable") until the accounts are loaded.

addEventHandler("v_bank:dbReady", resourceRoot, function()
    runMigration(function() startAccounts() end)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start()
end)
