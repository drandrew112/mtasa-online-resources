local activeIndex = ACTIVE_TIMETRIAL
local trial = Timetrials[activeIndex]
local startMarker, endMarker, startBlip
local BLIP_ICON = 61

addEvent("tt:requestActive", true)

local function createMarkers()
    if isElement(startMarker) then destroyElement(startMarker) end
    if isElement(endMarker) then destroyElement(endMarker) end
    if isElement(startBlip) then destroyElement(startBlip) end

    startMarker = createMarker(
        trial.start.x, trial.start.y, trial.start.z - 1,
        "cylinder", 4, 0, 150, 255, 120
    )

    startBlip = createBlipAttachedTo(startMarker, BLIP_ICON, 2, 255, 255, 255, 255, 0, 99999)

    setElementData(startMarker, "tt:start", true)
    setElementID(startMarker, "tt:start")

    endMarker = createMarker(
        trial.finish.x, trial.finish.y, trial.finish.z - 1,
        "cylinder", 6, 255, 255, 0, 120
    )

    setElementData(endMarker, "tt:end", true)
    setElementID(endMarker, "tt:end")

    setElementAlpha(endMarker, 0)
end

addEventHandler("onResourceStart", resourceRoot, createMarkers)

-- Called by v_weekly (and usable by anything else): switches the active trial.
function setActiveTimetrial(index)
    index = tonumber(index)
    if not index or not Timetrials[index] then return false end
    if index == activeIndex then return true end

    activeIndex = index
    trial = Timetrials[index]
    for _, p in ipairs(getElementsByType("player")) do
        setElementData(p, "tt:canStart", false)
        setElementData(p, "tt:active", false)
    end
    createMarkers()
    triggerClientEvent(root, "tt:setActive", resourceRoot, index)
    return true
end

function getActiveTimetrial()
    return activeIndex
end

-- -> { [index] = { name, time, reward } }
function getTimetrials()
    local list = {}
    for i, t in ipairs(Timetrials) do
        list[i] = { name = t.name, time = t.time, reward = t.reward }
    end
    return list
end

addEventHandler("tt:requestActive", root, function()
    triggerClientEvent(client, "tt:setActive", resourceRoot, activeIndex)
end)

-- === TEST MODE (/tttest, admin >= 4) ===
-- Private markers visible only to the tester; any trial, no reward.
local TEST_ADMIN_LEVEL = 4
local tests = {} -- [player] = { index, start, finish }

local function notice(player, text)
    triggerClientEvent(player, "tt:notice", resourceRoot, text)
end

local function stopTest(player, silent)
    local t = tests[player]
    if not t then return end
    tests[player] = nil
    if isElement(t.start) then destroyElement(t.start) end
    if isElement(t.finish) then destroyElement(t.finish) end
    if isElement(t.blip) then destroyElement(t.blip) end
    if isElement(player) then
        setElementData(player, "tt:canStart", false)
        setElementData(player, "tt:active", false)
        triggerClientEvent(player, "tt:test", resourceRoot, false)
        if not silent then notice(player, "Time trial test stopped") end
    end
end

local function startTest(player, index)
    stopTest(player, true)
    local tr = Timetrials[index]
    local sm = createMarker(tr.start.x, tr.start.y, tr.start.z - 1, "cylinder", 4, 0, 150, 255, 120)
    local fm = createMarker(tr.finish.x, tr.finish.y, tr.finish.z - 1, "cylinder", 6, 255, 255, 0, 120)
    for _, m in ipairs({ sm, fm }) do
        setElementVisibleTo(m, root, false)
        setElementVisibleTo(m, player, true)
    end
    local blip = createBlipAttachedTo(sm, BLIP_ICON, 2, 255, 255, 255, 255, 0, 99999)
    setElementVisibleTo(blip, root, false)
    setElementVisibleTo(blip, player, true)
    setElementData(player, "tt:active", false)
    tests[player] = { index = index, start = sm, finish = fm, blip = blip }

    local veh = getPedOccupiedVehicle(player)
    local target = veh or player
    setElementPosition(target, tr.start.x, tr.start.y, tr.start.z + 1)
    triggerClientEvent(player, "tt:test", resourceRoot, index, sm, fm)
end

addCommandHandler("tttest", function(player, _, arg)
    if getElementData(player, "isLogged") ~= true
        or (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) < TEST_ADMIN_LEVEL then
        return
    end
    if arg == "stop" then
        if not tests[player] then return notice(player, "No test running") end
        return stopTest(player)
    end
    local index = tonumber(arg)
    if not index or not Timetrials[index] then
        local parts = {}
        for i, t in ipairs(Timetrials) do parts[#parts + 1] = i .. " = " .. t.name end
        return notice(player, "/tttest <1-" .. #Timetrials .. "|stop>   " .. table.concat(parts, "  |  "))
    end
    startTest(player, index)
    notice(player, "Testing: " .. Timetrials[index].name .. " (no reward)")
end)

addEventHandler("onPlayerQuit", root, function() stopTest(source, true) end)
addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(tests) do stopTest(p, true) end
end)

addEventHandler("onPlayerMarkerHit", root, function(marker)
    local t = tests[source]
    if t then
        if marker == t.start then
            setElementData(source, "tt:canStart", true)
        elseif marker == t.finish and getElementData(source, "tt:active") and isLandDriver(source) then
            triggerClientEvent(source, "tt:finish", source, true)
        end
        return
    end

    if marker == startMarker then
        setElementData(source, "tt:canStart", true)
        return
    end

    if marker == endMarker and getElementData(source, "tt:active") and isLandDriver(source) then
        givePlayerMoney(source, trial.reward)
        triggerClientEvent(source, "tt:finish", source, true)
    end
end)

addEventHandler("onPlayerMarkerLeave", root, function(marker)
    local t = tests[source]
    if marker == startMarker or (t and marker == t.start) then
        setElementData(source, "tt:canStart", false)
    end
end)
