if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ATC markers: the interact key (server/marker.lua validates; the 3D card is a ui_core marker UI).

local markers = {}

addEventHandler("onClientResourceStart", resourceRoot, function()
    markers = getElementsByType("marker", resourceRoot)
    setTimer(function() markers = getElementsByType("marker", resourceRoot) end, 1000, 0)
end)

local function insideMarker(marker)
    if getElementDimension(marker) ~= getElementDimension(localPlayer)
        or getElementInterior(marker) ~= getElementInterior(localPlayer) then return false end
    local px, py, pz = getElementPosition(getPedOccupiedVehicle(localPlayer) or localPlayer)
    local x, y, z = getElementPosition(marker)
    return pz >= z - 1 and pz <= z + 3
        and getDistanceBetweenPoints2D(px, py, x, y) <= getMarkerSize(marker) / 2 + 0.5
end

bindKey(AVI.MARKER_KEY, "down", function()
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return end
    for _, m in ipairs(markers) do
        if isElement(m) and insideMarker(m) then
            triggerServerEvent("avi:markerUse", resourceRoot, m)
            return
        end
    end
end)

-- The 3D cards above the markers are ui_core marker UIs (server/marker.lua), hidden while an
-- avi_controller window is open.
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "avi.uiOpen" then exports.ui_core:setMarkerUIsHidden(new and true or false) end
end, false)
