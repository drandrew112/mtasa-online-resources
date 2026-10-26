-- resourceReady() reports of the LOADING_REQUIRED resources (config.lua).
--
-- A report is kept from the moment it arrives - also long before the loading
-- starts (e.g. while the player is still in the account menu) - and only
-- dropped when that resource stops on this client (it reports again after its
-- restart). When the server asks (v_loading:checkReady) and every running
-- required resource has reported, the client answers v_loading:clientReady.

READY = {}            -- [resource name] = true
local checking = false
local warnTimer

addEvent("onClientReadyCheck") -- local; report ready now (loading screen active, or v_loading just started)

-- { name, ... } of the required resources running here that have not reported
function missingResources()
    local missing = {}
    for _, name in ipairs(LOADING_REQUIRED) do
        if not READY[name] then
            local res = getResourceFromName(name)
            if res and getResourceState(res) == "running" then missing[#missing + 1] = name end
        end
    end
    return missing
end

-- reported / running required resources (loading screen counter)
function readyCounts()
    local done, total = 0, 0
    for _, name in ipairs(LOADING_REQUIRED) do
        local res = getResourceFromName(name)
        if res and getResourceState(res) == "running" then
            total = total + 1
            if READY[name] then done = done + 1 end
        end
    end
    return done, total
end

function isCheckingReady() return checking end

local function tryReport()
    if not checking then return end
    if #missingResources() > 0 then return end
    checking = false
    if isTimer(warnTimer) then killTimer(warnTimer) end
    triggerServerEvent("v_loading:clientReady", localPlayer)
end

-- Exported (client). The name comes from sourceResource.
function resourceReady()
    if not sourceResource then return end
    READY[getResourceName(sourceResource)] = true
    tryReport()
end

addEvent("v_loading:checkReady", true)
addEventHandler("v_loading:checkReady", localPlayer, function()
    checking = true
    -- resources that started after the loading screen appeared missed
    -- onClientLoadingStarted: let them report now
    triggerEvent("onClientReadyCheck", localPlayer)
    if isTimer(warnTimer) then killTimer(warnTimer) end
    warnTimer = setTimer(function()
        local missing = missingResources()
        if checking and #missing > 0 then
            outputDebugString("[v_loading] still waiting for resourceReady from: " .. table.concat(missing, ", "), 2)
        end
    end, LOADING_WARN_INTERVAL, 0)
    tryReport()
end)

-- a stopped resource has to report again after its restart
addEventHandler("onClientResourceStop", root, function(res)
    if res == resource then return end
    READY[getResourceName(res)] = nil
    -- a required resource stopped for good is not waited for any more
    if checking then setTimer(tryReport, 100, 1) end
end)

-- a resource (re)started while the check is already running missed both
-- onClientLoadingStarted and the check's onClientReadyCheck: ask again
addEventHandler("onClientResourceStart", root, function(res)
    if res == resource or not checking or READY[getResourceName(res)] then return end
    triggerEvent("onClientReadyCheck", localPlayer)
    tryReport()
end)

-- Resources that tried to report before v_loading ran on this client (their
-- export call failed) get one more chance now. Only for a loaded player: before
-- the loading the resources must not set up their texts yet (they would lock
-- them in before the login), and the loading's own check asks them anyway.
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") == true then
        triggerEvent("onClientReadyCheck", localPlayer)
    end
end)
