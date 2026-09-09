uicore = exports.ui_core

local elevatorId = nil   -- elevator the player is currently standing in
local menuId     = nil   -- id of the open ui_inac temp menu (nil = none)
local showHelp   = false

addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

local function openSelector()
    if not elevatorId then return end
    local elevator = elevators[elevatorId]
    if not elevator then return end

    local items = {}
    for i, floor in ipairs(elevator.floors) do
        items[i] = { label = floor.name, value = i }
    end

    menuId = exports.ui_inac:createTempMenu({
        title = elevator.name or "ELEVATOR",
        items = items,
    }) or nil
end

local function closeSelector()
    if menuId then
        exports.ui_inac:closeTempMenu()
        menuId = nil
    end
end

local function toggleSelector()
    if menuId then closeSelector() else openSelector() end
end

addEventHandler("ui_inac:tempMenuSelect", root, function(id, index, floorId)
    if id ~= menuId then return end

    local elevator = elevators[elevatorId]
    local floor    = elevator and elevator.floors[floorId]
    if not floor then return end

    local x, y, z = floor.x, floor.y, floor.z
    fadeCamera(false)
    setTimer(function()
        if isElement(localPlayer) then
            setElementPosition(localPlayer, x, y, z)
        end
        fadeCamera(true)
    end, 2000, 1)
end)

addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id == menuId then menuId = nil end
end)

addEventHandler("onClientRender", root, function()
    if showHelp and not menuId then
        local sw, sh = guiGetScreenSize()
        dxDrawText("Press E to use the elevator", sw / 2, sh * 0.12, _, _,
            tocolor(255, 255, 255, 255), 1.4, "default", "center", "center")
    end
end)

addEventHandler("onClientColShapeHit", getResourceRootElement(), function(hitElement)
    if hitElement ~= localPlayer then return end
    if getElementData(source, "elevator") then
        elevatorId = getElementData(source, "elevator_id")
        showHelp = true
        bindKey("e", "down", toggleSelector)
    end
end)

addEventHandler("onClientColShapeLeave", getResourceRootElement(), function(leaveElement)
    if leaveElement ~= localPlayer then return end
    if getElementData(source, "elevator") then
        unbindKey("e", "down", toggleSelector)
        closeSelector()
        showHelp = false
        elevatorId = nil
    end
end)
