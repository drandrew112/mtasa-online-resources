local activeIndex = ACTIVE_TIMETRIAL
local trial = Timetrials[activeIndex]
local startMarker, endMarker

addEvent("tt:requestActive", true)

local function createMarkers()
    if isElement(startMarker) then destroyElement(startMarker) end
    if isElement(endMarker) then destroyElement(endMarker) end

    startMarker = createMarker(
        trial.start.x, trial.start.y, trial.start.z - 1,
        "cylinder", 4, 0, 150, 255, 120
    )

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

addEventHandler("onPlayerMarkerHit", root, function(marker)
    if marker == startMarker then
        setElementData(source, "tt:canStart", true)
        return
    end

    if marker == endMarker and getElementData(source, "tt:active") then
        givePlayerMoney(source, trial.reward)
        triggerClientEvent(source, "tt:finish", source, true)
    end
end)

addEventHandler("onPlayerMarkerLeave", root, function(marker)
    if marker == startMarker then
        setElementData(source, "tt:canStart", false)
    end
end)
