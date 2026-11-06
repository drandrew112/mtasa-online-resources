-- Hospital tutorial, server side: started on duty for everyone without the Ápoló (nurse) rank; the
-- client walks the steps (shared/tutorial.lua) and reports the end; the rank is given then. Until
-- then the ER activities (er.*) are refused (canStaffPerform).

local running = {}   -- player -> { at, step }

local function wc() local r = getResourceFromName("work_core") return r and getResourceState(r) == "running" and exports.work_core or nil end

function hasNurseRank(player)
    local w = wc()
    return w ~= nil and w:hasCompetency(player, HOSPW.WORK_ID, "nurse") == true
end

function isHospitalTutorialRunning(player) return running[player] ~= nil end

local function start(player)
    if running[player] or hasNurseRank(player) then return end
    running[player] = { at = getRealTime().timestamp, step = 0 }
    triggerClientEvent(player, "hosp:tut:start", resourceRoot)
end

addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId ~= HOSPW.WORK_ID then return end
    local player = source
    -- competencies load with the account: a moment later
    setTimer(function() if isElement(player) then start(player) end end, 1500, 1)
end)

addEventHandler("onPlayerWorkDutyEnd", root, function(workId)
    if workId ~= HOSPW.WORK_ID or not running[source] then return end
    running[source] = nil
    triggerClientEvent(source, "hosp:tut:stop", resourceRoot)
end)

addEventHandler("onPlayerQuit", root, function() running[source] = nil end)

addEvent("hosp:tut:step", true)
addEventHandler("hosp:tut:step", resourceRoot, function(i)
    local r = running[client]
    if r and tonumber(i) and tonumber(i) == r.step + 1 then r.step = r.step + 1 end
end)

addEvent("hosp:tut:done", true)
addEventHandler("hosp:tut:done", resourceRoot, function()
    local player = client
    local r = running[player]
    if not r then return end
    local need = #HOSPW_TUTORIAL.steps
    if r.step < need - 1 or getRealTime().timestamp - r.at < HOSPW_TUTORIAL.minSeconds then return end
    running[player] = nil
    local w = wc()
    if not w then return end
    local ok = w:grantCompetency(player, HOSPW.WORK_ID, "nurse", "auto", "tutorial")
    if ok and isRunning("v_mysql") then exports.v_mysql:setAccData(player, "hosp.tutorialDone", true) end
    triggerClientEvent(player, "hosp:tut:granted", resourceRoot, ok == true)
end)

-- /hosptutorial: run it again (for those who have the rank: just the walk, nothing is given)
addCommandHandler("hosptutorial", function(player)
    local w = wc()
    if not w or not w:isPlayerOnDuty(player, HOSPW.WORK_ID) then return end
    running[player] = { at = getRealTime().timestamp, step = 0 }
    triggerClientEvent(player, "hosp:tut:start", resourceRoot)
end)
