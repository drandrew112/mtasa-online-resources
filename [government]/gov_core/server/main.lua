-- gov_core / server/main.lua
-- Start: schema (+ new columns) -> settings -> state companies -> ready. Every RESYNC_MS the three are
-- re-read (the other server instance may have changed them), then onGovSettingsSynced.

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start(GOV.SCHEMA, function()
        GOV.upgradeSchema(function()
            loadSettings(function()
                GOV.loadCompanies(function()
                    GOV.ready = true
                end)
            end)
        end)
        setTimer(function()
            loadSettings(function()
                GOV.loadCompanies(function()
                    triggerEvent("onGovSettingsSynced", resourceRoot)
                end)
            end)
        end, GOV.RESYNC_MS, 0)
    end)
end)
