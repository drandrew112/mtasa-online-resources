-- biz_core / server/main.lua
-- Start-up order: tables -> registry -> companies of the players already online
-- -> "biz_core:ready" (root) for the dependent resources (biz_int, activities,
-- v_weekly multipliers).

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start()
end)

addEventHandler("biz_core:dbReady", resourceRoot, function()
    REG.refresh()
    CO.loadEveryone()
    setTimer(REG.refresh, BIZ.REGISTRY_REFRESH_MS, 0)
    setTimer(CO.resync, BIZ.RESYNC_MS, 0)
    triggerEvent("biz_core:ready", root)
end)

-- the online time up to now is credited before the companies stop
addEventHandler("onResourceStop", resourceRoot, function()
    local list = {}
    for _, c in pairs(CO.byId) do list[#list + 1] = c end
    for _, c in ipairs(list) do CO.unload(c, "stop") end
end)

function isReady()
    return DB.ready
end
