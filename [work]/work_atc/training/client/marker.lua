if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The training marker in the SA Control room: a 3D label (on duty only) and the interact key, which
-- asks the server for the module list (server/session.lua validates). Same look as the ATC markers of
-- avi_core.

local M = TRAINING.MARKER
local marker
local onDuty = false

local function findMarker()
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, "atc.training") then return m end
    end
end

local function checkDuty()
    local res = getResourceFromName("work_core")
    if not (res and getResourceState(res) == "running") then return false end
    local ok, r = pcall(function() return exports.work_core:isPlayerOnDuty(localPlayer, ATC.WORK_ID) end)
    return ok and r == true
end

-- The label render is attached only on duty. Going off duty removes it at once (work change
-- event); the timer only finds the marker and catches a work_core restart.
local renderLabel
local fade = 0

local function updateDuty()
    local d = checkDuty()
    if d == onDuty then return end
    onDuty = d
    if d then
        addEventHandler("onClientRender", root, renderLabel)
    else
        removeEventHandler("onClientRender", root, renderLabel)
        fade = 0
    end
end

addEvent("onClientPlayerWorkChange")
addEventHandler("onClientPlayerWorkChange", localPlayer, updateDuty)

addEventHandler("onClientResourceStart", resourceRoot, function()
    marker = findMarker()
    updateDuty()
    setTimer(function()
        if not isElement(marker) then marker = findMarker() end
        updateDuty()
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

local U = select(2, guiGetScreenSize()) / 1080

local function inSight(cx, cy, cz, x, y, z)
    return isLineOfSightClear(cx, cy, cz, x, y, z + 1.5, true, false, false, true, false, false, false, localPlayer)
        or isLineOfSightClear(cx, cy, cz, x, y, z + 0.3, true, false, false, true, false, false, false, localPlayer)
end

renderLabel = function()
    if not isElement(marker) or isPlayerMapVisible() or getElementData(localPlayer, "avi.uiOpen") then return end
    if getElementDimension(marker) ~= getElementDimension(localPlayer)
        or getElementInterior(marker) ~= getElementInterior(localPlayer) then return end
    local px, py, pz = getElementPosition(localPlayer)
    local cx, cy, cz = getCameraMatrix()
    local x, y, z = getElementPosition(marker)
    local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
    local maxD = M.labelDistance
    if dist <= maxD and inSight(cx, cy, cz, x, y, z) then
        fade = math.min(1, fade + 0.12)
    else
        fade = math.max(0, fade - 0.12)
    end
    if fade <= 0 or dist > maxD then return end
    local sx, sy = getScreenFromWorldPosition(x, y, z + 1.5, 0.1)
    if not sx then return end
    local a = math.min(255, 255 * (maxD - dist) / 5) * fade
    local k = math.max(0.6, 1 - dist / maxD * 0.4)
    local w, h, bar = 230 * U * k, 50 * U * k, 3 * U * k
    local c = M.color
    dxDrawRectangle(sx - w / 2, sy - h, w, h, tocolor(14, 17, 21, 220 * a / 255))
    dxDrawRectangle(sx - w / 2, sy - bar, w, bar, tocolor(c[1], c[2], c[3], a))
    dxDrawText(L("work_atc.trn.menu.marker"), sx - w / 2, sy - h, sx + w / 2, sy - h * 0.5,
        tocolor(255, 255, 255, a), k, "default-bold", "center", "center")
    dxDrawText(L("work_atc.trn.menu.marker_press", { key = M.key:upper() }), sx - w / 2, sy - h * 0.5,
        sx + w / 2, sy - bar, tocolor(200, 205, 212, a), k * 0.9, "default", "center", "center")
end
