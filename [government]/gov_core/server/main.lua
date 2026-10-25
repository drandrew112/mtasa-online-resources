-- gov_core / server/main.lua
-- Start: schema (+ new columns) -> settings -> state companies -> ready ("gov_core:ready", source =
-- gov_core resourceRoot; the gov_* modules start their own loading only then, GOV.onReady). Every
-- RESYNC_MS the three are re-read (the other server instance may have changed them), then
-- onGovSettingsSynced.

GOV.ready = false

addEvent("gov_core:ready", false)

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start(GOV.SCHEMA, function()
        GOV.upgradeSchema(function()
            loadSettings(function()
                GOV.loadCompanies(function()
                    GOV.ready = true
                    triggerEvent("gov_core:ready", resourceRoot)
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
