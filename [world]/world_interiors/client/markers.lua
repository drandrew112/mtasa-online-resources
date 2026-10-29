if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- world_interiors / client/markers.lua
-- The interact key of the interior markers: standing in a marker is not enough, INT.key has to
-- be pressed. The 3D cards above them are ui_core marker UIs (server/registry.lua).

local markers = {}
local current          -- marker the local player stands in

local function refresh()
    markers = {}
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, "interior:id") then markers[#markers + 1] = m end
    end
end

---------------------------------------------------------------- key

local function onKey()
    if not isElement(current) then return end
    if isCursorShowing() or isChatBoxInputActive() or isMainMenuActive() then return end
    if exports.ui_inac:isTempMenuOpen() then return end
    if isPedInVehicle(localPlayer) then return end
    triggerServerEvent("world_interiors:use", resourceRoot, current)
end

local function setCurrent(marker)
    if marker == current then return end
    if marker and not current then bindKey(INT.key, "down", onKey) end
    if not marker and current then unbindKey(INT.key, "down", onKey) end
    current = marker
end

addEventHandler("onClientMarkerHit", resourceRoot, function(hit, matchingDim)
    if hit ~= localPlayer or not matchingDim or not getElementData(source, "interior:id") then return end
    setCurrent(source)
end)

addEventHandler("onClientMarkerLeave", resourceRoot, function(leaver)
    if leaver == localPlayer and source == current then setCurrent(nil) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    refresh()
    setTimer(function()
        refresh()
        -- teleports do not always fire hit / leave: re-check the marker we think we are in
        if current and (not isElement(current) or not isElementWithinMarker(localPlayer, current)
            or getElementDimension(current) ~= getElementDimension(localPlayer)) then
            setCurrent(nil)
        end
        if not current then
            for _, m in ipairs(markers) do
                if getElementDimension(m) == getElementDimension(localPlayer)
                    and getElementInterior(m) == getElementInterior(localPlayer)
                    and isElementWithinMarker(localPlayer, m) then
                    setCurrent(m)
                    break
                end
            end
        end
    end, 500, 0)
end)
