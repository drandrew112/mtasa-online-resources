-- ATC markers: a 3D label above the marker and the interact key (server/marker.lua validates).

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

local U = select(2, guiGetScreenSize()) / 1080

addEventHandler("onClientRender", root, function()
    if #markers == 0 or isPlayerMapVisible() or getElementData(localPlayer, "avi.uiOpen") then return end
    local px, py, pz = getElementPosition(localPlayer)
    local maxD = AVI.MARKER_LABEL_DISTANCE
    for _, m in ipairs(markers) do
        if isElement(m) and getElementDimension(m) == getElementDimension(localPlayer)
            and getElementInterior(m) == getElementInterior(localPlayer) then
            local x, y, z = getElementPosition(m)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if dist <= maxD then
                local sx, sy = getScreenFromWorldPosition(x, y, z + 1.5, 0.1)
                if sx then
                    local a = math.min(255, 255 * (maxD - dist) / 5)
                    local k = math.max(0.6, 1 - dist / maxD * 0.4)
                    local w, h, bar = 230 * U * k, 50 * U * k, 3 * U * k
                    dxDrawRectangle(sx - w / 2, sy - h, w, h, tocolor(14, 17, 21, 220 * a / 255))
                    dxDrawRectangle(sx - w / 2, sy - bar, w, bar, tocolor(70, 130, 210, a))
                    dxDrawText(getElementData(m, "avi.marker") or "ATC", sx - w / 2, sy - h, sx + w / 2, sy - h * 0.5,
                        tocolor(255, 255, 255, a), k, "default-bold", "center", "center")
                    dxDrawText(("Press %s · ATC position"):format(AVI.MARKER_KEY:upper()), sx - w / 2, sy - h * 0.5,
                        sx + w / 2, sy - bar, tocolor(200, 205, 212, a), k * 0.9, "default", "center", "center")
                end
            end
        end
    end
end)
