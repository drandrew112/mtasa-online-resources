-- Sofőr vezérlés (0-4 gombok) és /debugels kijelzés.

-- a jármű, amit a localPlayer sofőrként vezet, ha ELS-es
function getControlledSirenVehicle()
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh and getVehicleController(veh) == localPlayer and sirenVehicles[getElementModel(veh)] then
        return veh
    end
end

local function requestData(veh, key, value)
    triggerServerEvent("siren:setData", resourceRoot, veh, key, value)
end

local function nextIndex(current, count)
    return (current or 1) % count + 1
end

-- 0: FÉNYEK BE/KI
bindKey("0", "down", function()
    local veh = getControlledSirenVehicle()
    if veh then
        requestData(veh, "mkjState", not getElementData(veh, "mkjState"))
    end
end)

-- 1: SZIRÉNA BE/KI (mindig az első hanggal indul)
bindKey("1", "down", function()
    local veh = getControlledSirenVehicle()
    if veh then
        requestData(veh, "sirenIndex", 1)
        requestData(veh, "sirenState", not getElementData(veh, "sirenState"))
    end
end)

-- 2: KÖVETKEZŐ SZIRÉNA HANG
bindKey("2", "down", function()
    local veh = getControlledSirenVehicle()
    if not veh then return end

    local cfg = sirenTypes[getElementData(veh, "sirenType") or DEFAULT_SIREN_TYPE]
    if cfg and #cfg.sirens > 0 then
        requestData(veh, "sirenIndex", nextIndex(getElementData(veh, "sirenIndex"), #cfg.sirens))
    end
end)

-- 3: KÜRT (lenyomva tartva)
local function setHorn(state)
    local veh = getControlledSirenVehicle()
    if veh then
        requestData(veh, "sirenHorn", state)
    end
end
bindKey("3", "down", function() setHorn(true) end)
bindKey("3", "up",   function() setHorn(false) end)

-- 4: KÖVETKEZŐ VILLOGÁSI MINTA
bindKey("4", "down", function()
    local veh = getControlledSirenVehicle()
    if veh then
        requestData(veh, "elsPattern", nextIndex(getElementData(veh, "elsPattern"), #ELS_PATTERNS))
    end
end)

------------------------------------------------------------
-- DEBUG KIJELZÉS (/debugels)
------------------------------------------------------------

local sx, sy = guiGetScreenSize()
local debugVisible = false

local function onOff(val)
    return val and "#00FF00ON#FFFFFF" or "#FF0000OFF#FFFFFF"
end

local function drawDebug()
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end

    local sirenState = getElementData(veh, "sirenState")
    local pattern = ELS_PATTERNS[getElementData(veh, "elsPattern") or 1]
    local text = "ELS: " .. onOff(getElementData(veh, "mkjState")) ..
                 "\nPattern: " .. (pattern and pattern.name or "?") ..
                 "\nSiren type: " .. tostring(getElementData(veh, "sirenType") or "?") ..
                 "\nSiren state: " .. onOff(sirenState)

    if sirenState then
        text = text .. "\nSiren index: #FFFF00" .. tostring(getElementData(veh, "sirenIndex") or "?") .. "#FFFFFF"
    end
    text = text .. "\nHorn state: " .. onOff(getElementData(veh, "sirenHorn"))

    dxDrawText(text, sx * 0.2, sy - 60, nil, nil, tocolor(255, 255, 255, 255), 1.3, "default",
        "left", "bottom", false, false, false, true)
end

-- a render handler csak bekapcsolt debug mellett fut
addCommandHandler("debugels", function()
    debugVisible = not debugVisible
    if debugVisible then
        addEventHandler("onClientRender", root, drawDebug)
    else
        removeEventHandler("onClientRender", root, drawDebug)
    end
end)
