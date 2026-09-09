uicore = exports.ui_core

local elevatorId = nil   -- elevator the player is currently standing in
local menuOpen   = false
local showHelp   = false

local function openSelector()
    if not elevatorId then return end
    local elevator = elevators[elevatorId]
    if not elevator then return end

    local items = {}
    for i, floor in ipairs(elevator.floors) do
        local floorId = i
        items[i] = {
            label  = floor.name,
            action = function()
                local dest = elevator.floors[floorId]
                fadeCamera(false)
                setTimer(function()
                    if isElement(localPlayer) then
                        setElementPosition(localPlayer, dest.x, dest.y, dest.z)
                    end
                    fadeCamera(true)
                end, 2000, 1)
            end,
        }
    end

    menuOpen = exports.ui_inac:createTempMenu({
        title   = elevator.name or "ELEVATOR",
        items   = items,
        onClose = function() menuOpen = false end,
    }) and true or false
end

local function closeSelector()
    if menuOpen then
        exports.ui_inac:closeTempMenu()
        menuOpen = false
    end
end

local function toggleSelector()
    if menuOpen then closeSelector() else openSelector() end
end

addEventHandler("onClientRender", root, function()
    if showHelp and not menuOpen then
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
