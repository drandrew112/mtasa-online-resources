local trial = Timetrials[ACTIVE_TIMETRIAL]
local startMarker, endMarker

addEventHandler("onResourceStart", resourceRoot, function()
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
    setElementData(endMarker, "tt:end", true)
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
