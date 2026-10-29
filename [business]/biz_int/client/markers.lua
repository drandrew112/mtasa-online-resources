if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_int / client/markers.lua
-- The interact key of the entrance / exit markers: standing in a marker is
-- not enough, BINT.key has to be pressed (the 3D cards above them are ui_core
-- marker UIs, server/main.lua). When a door leads to several of the player's places, the server
-- sends the list and a ui_inac temp menu asks which one.

local markers = {}
local current
local chooseMenu, chooseMarker, chooseUnits

local function refresh()
    markers = {}
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, "bizint:kind") then markers[#markers + 1] = m end
    end
end

---------------------------------------------------------------- key

local function onKey()
    if not isElement(current) then return end
    if isCursorShowing() or isChatBoxInputActive() or isMainMenuActive() then return end
    if exports.ui_inac:isTempMenuOpen() then return end
    if isPedInVehicle(localPlayer) then return end
    triggerServerEvent("bizint:use", resourceRoot, current)
end

local function setCurrent(marker)
    if marker == current then return end
    if marker and not current then bindKey(BINT.key, "down", onKey) end
    if not marker and current then unbindKey(BINT.key, "down", onKey) end
    current = marker
    if not marker and chooseMenu then
        exports.ui_inac:closeTempMenu()
    end
end

addEventHandler("onClientMarkerHit", resourceRoot, function(hit, matchingDim)
    if hit ~= localPlayer or not matchingDim or not getElementData(source, "bizint:kind") then return end
    setCurrent(source)
end)

addEventHandler("onClientMarkerLeave", resourceRoot, function(leaver)
    if leaver == localPlayer and source == current then setCurrent(nil) end
end)

addEventHandler("onClientElementDestroy", resourceRoot, function()
    if source == current then setCurrent(nil) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    refresh()
    setTimer(function()
        refresh()
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

---------------------------------------------------------------- choose (several places behind one door)

addEvent("bizint:choose", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")
addEventHandler("bizint:choose", resourceRoot, function(marker, units)
    if type(units) ~= "table" or #units == 0 then return end
    local items = {}
    for _, u in ipairs(units) do
        local label = u.role == "founder" and L("biz_int.choose.own", { name = u.name })
            or L("biz_int.choose.associate", { name = u.name, company = u.companyName })
        items[#items + 1] = { label = label, value = u.unitId, desc = u.companyName }
    end
    chooseMarker, chooseUnits = marker, units
    chooseMenu = exports.ui_inac:createTempMenu({ title = L("biz_int.choose.title"), items = items })
end)

addEventHandler("ui_inac:tempMenuSelect", localPlayer, function(rootId, value)
    if not chooseMenu or rootId ~= chooseMenu then return end
    local marker = chooseMarker
    exports.ui_inac:closeTempMenu()
    triggerServerEvent("bizint:choose", resourceRoot, marker, value)
end)

addEventHandler("ui_inac:tempMenuClose", localPlayer, function(rootId)
    if rootId == chooseMenu then chooseMenu, chooseMarker, chooseUnits = nil, nil, nil end
end)
