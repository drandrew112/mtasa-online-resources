if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The training marker in the SA Control room: the interact key, which asks the server for the
-- module list (server/session.lua validates). The 3D card above it is a ui_core marker UI (on
-- duty only, server/session.lua), hidden while an avi_controller window is open.

local M = TRAINING.MARKER
local marker

local function findMarker()
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, "atc.training") then return m end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    marker = findMarker()
    setTimer(function()
        if not isElement(marker) then marker = findMarker() end
    end, 1000, 0)
end)

local function insideMarker()
    if not isElement(marker) then return false end
    if getElementDimension(marker) ~= getElementDimension(localPlayer)
        or getElementInterior(marker) ~= getElementInterior(localPlayer) then return false end
    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z = getElementPosition(marker)
    return pz >= z - 1 and pz <= z + 3 and getDistanceBetweenPoints2D(px, py, x, y) <= M.size / 2 + 0.5
end

bindKey(M.key, "down", function()
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return end
    if TRN.isActive() or not insideMarker() then return end
    triggerServerEvent("atc:trn:marker", resourceRoot)
end)

addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "avi.uiOpen" then exports.ui_core:setMarkerUIsHidden(new and true or false) end
end, false)
