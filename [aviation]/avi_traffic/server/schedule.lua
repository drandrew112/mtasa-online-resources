-- Starts the flights of the database by the real (server) clock: a flight starts when
-- minute-of-day % period == offset. At most TR.MAX_ACTIVE flights fly at once.
-- Admin command: /avitraffic list | spawn <callsign> | random [n] | remove <callsign> | clear | schedule on|off

local lastMinute

local function minuteOfDay()
    local t = getRealTime()
    return t.hour * 60 + t.minute
end

local function tryStart(fl)
    if countActive() >= TR.MAX_ACTIVE then return nil, "traffic limit reached" end
    return spawnFlight(fl)
end

local function scheduleTick()
    if not TR.SCHEDULE then return end
    local m = minuteOfDay()
    if m == lastMinute then return end
    lastMinute = m
    for _, fl in ipairs(DB.flights) do
        if m % fl.period == fl.offset % fl.period then tryStart(fl) end
    end
end

local function spawnRandom(n)
    local pool = {}
    for _, fl in ipairs(DB.flights) do
        if not isCallsignActive(fl.callsign) then pool[#pool + 1] = fl end
    end
    local started = 0
    while started < n and #pool > 0 do
        local fl = table.remove(pool, math.random(#pool))
        if tryStart(fl) then started = started + 1 end
    end
    return started
end

addEventHandler("onResourceStart", resourceRoot, function()
    math.randomseed(getTickCount())
    lastMinute = minuteOfDay()           -- the current minute does not fire again
    -- give the other avi_* resources a moment to start, then put some traffic up
    setTimer(function() spawnRandom(TR.INITIAL_SPAWN) end, 3000, 1)
    setTimer(scheduleTick, 5000, 0)
end)

-- ---------------------------------------------------------------- exports for other resources / tests
function spawnFlightByCallsign(cs)
    local fl = DB.byCallsign[tostring(cs or ""):upper()]
    if not fl then return false, "unknown flight" end
    local ac, err = spawnFlight(fl)
    return ac and ac.id or false, err
end

function removeFlight(cs)
    cs = tostring(cs or ""):upper()
    for _, ac in pairs(AIRCRAFT) do
        if ac.cs == cs then removeAircraft(ac, "removed") return true end
    end
    return false
end

-- ---------------------------------------------------------------- admin command
local function isAdmin(player)
    local res = getResourceFromName("avi_core")
    return res and getResourceState(res) == "running" and exports.avi_core:isAviationAdmin(player)
end

local function say(player, text)
    triggerClientEvent(player, "avi:notify", root, "TRAFFIC", text)
    outputConsole("[avi_traffic] " .. text, player)
end

addCommandHandler("avitraffic", function(player, _, action, arg)
    if not isAdmin(player) then return end
    action = action and action:lower() or "list"
    if action == "list" then
        local lines = {}
        for _, ac in pairs(AIRCRAFT) do
            lines[#lines + 1] = ("%s %s %s-%s %s %dft %dkt %s"):format(ac.cs, ac.type, ac.dep, ac.arr, ac.phase,
                ac.alt, ac.spd, ac.ctl or "-")
        end
        table.sort(lines)
        say(player, #lines .. " active flights (details in F8)")
        for _, l in ipairs(lines) do outputConsole(l, player) end
    elseif action == "spawn" then
        local id, err = spawnFlightByCallsign(arg)
        say(player, id and ("Started " .. tostring(arg):upper()) or ("Cannot start: " .. tostring(err)))
    elseif action == "random" then
        say(player, ("Started %d flights"):format(spawnRandom(tonumber(arg) or 1)))
    elseif action == "remove" then
        say(player, removeFlight(arg) and "Removed" or "Not active")
    elseif action == "clear" then
        for _, ac in pairs(AIRCRAFT) do removeAircraft(ac, "cleared") end
        say(player, "All traffic removed")
    elseif action == "schedule" then
        TR.SCHEDULE = arg ~= "off"
        say(player, "Schedule " .. (TR.SCHEDULE and "on" or "off"))
    else
        say(player, "/avitraffic list | spawn <cs> | random [n] | remove <cs> | clear | schedule on|off")
    end
end)
