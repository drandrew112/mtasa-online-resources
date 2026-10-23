-- v_gov / server/main.lua
-- Start: schema -> settings + members -> (once v_bank is ready) the hourly company tax.

local taxesStarted = false

local function startTaxesWhenBankReady()
    if taxesStarted then return end
    local bank = GOV.bank()
    if bank and bank:isBankReady() then
        taxesStarted = true
        startTaxes()
        return
    end
    setTimer(startTaxesWhenBankReady, 5000, 1)
end

addEventHandler("v_gov:dbReady", resourceRoot, function()
    loadSettings(function()
        GOV.ready = true
        startTaxesWhenBankReady()
    end)
    setTimer(function()
        loadSettings(GOV.checkPayers)
    end, GOV.RESYNC_MS, 0)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start()
end)
