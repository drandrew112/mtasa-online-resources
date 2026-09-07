
function init()
    for id,elevator in ipairs(elevators) do
        local elevator_id = id
        for i,floor in ipairs(elevators[id].floors) do
            local col = createColSphere(floor.x, floor.y, floor.z, 2)
            setElementData(col, "elevator", true)
            setElementData(col, "elevator_id", elevator_id)
            setElementData(col, "elevator_floor_id", i)
        end
    end
end

addEventHandler("onResourceStart", getResourceRootElement(), init)

