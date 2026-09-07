addEvent("radio:setStation", true)
addEventHandler("radio:setStation", root,
    function(vehicle, stationId)
        if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return end
        setElementData(vehicle, "radiostation_id", stationId, true)
    end
)

addEventHandler("onElementDestroy", root,
    function ()
        if getElementType(source) == "vehicle" then
            setElementData(source, "radiostation_id", nil)
        end
    end
)
