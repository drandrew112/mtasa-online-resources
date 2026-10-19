-- Start-up: table, first load (retried until the database answers), periodic last_run refresh.

local function loadAll(attempt)
    GangWars.load(function(ok)
        if ok then
            local n = 0
            for _ in pairs(GangWars.list) do n = n + 1 end
            outputDebugString(("[v_gangwar] %d gang war(s) loaded"):format(n))
            return
        end
        outputDebugString(("[v_gangwar] loading the gang wars failed (attempt %d), retrying in 10 s"):format(attempt), 2)
        setTimer(loadAll, 10000, 1, attempt + 1)
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    GangWars.ensureTable()
    loadAll(1)
    setTimer(function()
        if GangWars.loaded then GangWars.refreshLastRun() end
    end, GW.RELOAD_INTERVAL, 0)
end)
