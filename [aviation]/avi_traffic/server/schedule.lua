-- Starts the flights of the database by the real (server) clock: a flight starts when
-- minute-of-day % period == offset. At most TR.MAX_ACTIVE flights fly at once.
-- Workload keeper: every staffed position gets extra flights (up to TR.LOAD_MAX_ACTIVE) when its
-- load falls below TR.MIN_LOAD, so a controller is never left with an empty scope.
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

-- ---------------------------------------------------------------- workload keeper
local DEP_PHASES = { gate = true, pushback = true, pushed = true, taxi_out = true, hold = true, lined = true, takeoff = true }
local lastExtra = {}     -- [positionId] = tick of the last extra flight

local function isDeparting(ac)
    return DEP_PHASES[ac.phase] and ac.gndApt == ac.dep
end

-- in-sector aircraft count 1, the ones heading for the sector TR.PIPELINE_WEIGHT
local function positionLoad(pos)
    local icao = pos:match("^(.+)_TWR$") or pos:match("^(.+)_APP$")
    local isCenter = isCenterPosition(pos)
    if not isCenter and not icao then return math.huge end
    local load = 0
    for _, ac in pairs(AIRCRAFT) do
        local sec = sectorPosition(ac)
        if sec == pos then
            load = load + 1
        else
            local coming
            local airborne = ac.phase == "air" or ac.phase == "final"
            if isCenter then
                -- departures that have not reached the CTA yet
                coming = isDeparting(ac) or (ac.phase == "air" and airport(ac.dep) and
                    (sec == ac.dep .. "_TWR" or sec == ac.dep .. "_APP"))
            elseif pos == icao .. "_TWR" then
                coming = airborne and ac.arr == icao
            else
                coming = (isDeparting(ac) and ac.dep == icao) or
                    (airborne and ac.arr == icao and sec ~= icao .. "_TWR")
            end
            if coming then load = load + TR.PIPELINE_WEIGHT end
        end
    end
    return load
end

-- weighted candidates: flights that show up at the position soonest are preferred
local function candidates(pos)
    local icao = pos:match("^(.+)_TWR$") or pos:match("^(.+)_APP$")
    local twr = pos:match("_TWR$") ~= nil
    local out, total = {}, 0
    for _, fl in ipairs(DB.flights) do
        if not isCallsignActive(fl.callsign) then
            local fromApt, w = airport(fl.dep) ~= nil, 0
            if UPPER_POSITIONS[pos] then
                -- an upper sector (above FL205) only gets high overflights
                w = (not fromApt and not airport(fl.arr) and fl.cruise > (tonumber(WORLD.centre.split) or 20500)) and 4 or 0
            elseif isCenterPosition(pos) then
                w = fromApt and 1 or 3                          -- externals enter straight into the CTA
            elseif fl.dep == icao then
                w = twr and 3 or 1
            elseif fl.arr == icao then
                w = fromApt and 1 or 2
            end
            if w > 0 then
                out[#out + 1] = { fl = fl, w = w }
                total = total + w
            end
        end
    end
    return out, total
end

local function spawnFor(pos)
    local list, total = candidates(pos)
    for _ = 1, 6 do
        if #list == 0 then return nil end
        local r, pick = math.random() * total, #list
        for i, c in ipairs(list) do
            r = r - c.w
            if r <= 0 then pick = i break end
        end
        local c = table.remove(list, pick)
        total = total - c.w
        local ac = spawnFlight(c.fl)
        if ac then return ac end
    end
end

local function loadTick()
    if not TR.SCHEDULE then return end
    local now = getTickCount()
    for pos in pairs(staffedPositions()) do
        if countActive() >= TR.LOAD_MAX_ACTIVE then return end
        if now - (lastExtra[pos] or -math.huge) >= TR.LOAD_COOLDOWN * 1000 and positionLoad(pos) < TR.MIN_LOAD then
            local ac = spawnFor(pos)
            if ac then
                lastExtra[pos] = now
                outputDebugString(("[avi_traffic] workload: %s started for %s"):format(ac.cs, pos))
            end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    math.randomseed(getTickCount())
    lastMinute = minuteOfDay()           -- the current minute does not fire again
    -- give the other avi_* resources a moment to start, then put some traffic up
    setTimer(function() spawnRandom(TR.INITIAL_SPAWN) end, 3000, 1)
    setTimer(scheduleTick, 5000, 0)
    setTimer(loadTick, TR.LOAD_CHECK * 1000, 0)
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

addCommandHandler("avitraffic", function(player, _, action, arg, arg2)
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
    elseif action == "sqk" then
        local ok, err = setSquawk(arg, arg2)
        say(player, ok and (tostring(arg):upper() .. " squawks " .. arg2) or ("Cannot set: " .. tostring(err)))
    elseif action == "schedule" then
        TR.SCHEDULE = arg ~= "off"
        say(player, "Schedule " .. (TR.SCHEDULE and "on" or "off"))
    else
        say(player, "/avitraffic list | spawn <cs> | random [n] | remove <cs> | clear | sqk <cs> <code> | schedule on|off")
    end
end)
