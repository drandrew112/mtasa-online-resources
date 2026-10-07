-- Sofőr vezérlés (0-5 gombok) és /debugels kijelzés.

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

-- 1: SZIRÉNA BE/KI (mindig az első hanggal indul; kikapcsolt fényt a szerver felkapcsolja)
function turnSiren(state)
    local veh = getControlledSirenVehicle()
    if veh then
        requestData(veh, "sirenIndex", 1)
        if state ~= nil then
            requestData(veh, "sirenState", state)
        else
            requestData(veh, "sirenState", not getElementData(veh, "sirenState"))
        end
    end
end
bindKey("1", "down", function() turnSiren() end)

-- 2: KÖVETKEZŐ SZIRÉNA HANG
function nextTone()
    local veh = getControlledSirenVehicle()
    if not veh then return end
    
    local cfg = sirenTypes[getElementData(veh, "sirenType") or getDefaultSirenType(getElementModel(veh))]
    if cfg and #cfg.sirens > 0 then
        requestData(veh, "sirenIndex", nextIndex(getElementData(veh, "sirenIndex"), #cfg.sirens))
    end
end
bindKey("2", "down", nextTone)

-- 3: KÜRT (lenyomva tartva)
local function setHorn(state)
    local veh = getControlledSirenVehicle()
    if veh then
        requestData(veh, "sirenHorn", state)
    end
end
bindKey("3", "down", function() setHorn(true) end)
bindKey("3", "up",   function() setHorn(false) end)

-- 4: MÁSODLAGOS SZIRÉNA BE/KI (csak szóló fő szirénánál, ha a típusnak van ilyen hangja)
bindKey("4", "down", function()
    local veh = getControlledSirenVehicle()
    if not veh then return end

    local secondary = getElementData(veh, "sirenSecondary") == true
    local cfg = sirenTypes[getElementData(veh, "sirenType") or getDefaultSirenType(getElementModel(veh))]
    if secondary or (cfg and cfg.secondary and getElementData(veh, "sirenState")) then
        requestData(veh, "sirenSecondary", not secondary)
    end
end)

-- 5: KÖVETKEZŐ VILLOGÁSI MINTA
bindKey("5", "down", function()
    local veh = getControlledSirenVehicle()
    if veh then
        requestData(veh, "elsPattern", nextIndex(getElementData(veh, "elsPattern"), #ELS_PATTERNS))
    end
end)

-- GTA-ban a kürt ki/be kapcsolja a gyári szirénát. Saját fényes modellen ezt
-- visszakapcsoljuk, különben a GTA fényeffektjei villognának (a sofőr szinkronizálja).
-- A horn viszont kezelheti a sziréna hangját is. Ki/be kapcsolhatja valamint hang válthat.
local hornPressedAt = 0
local hornHoldTime = 250
local lastShortPress = 0
local doubleTapTime = 300
local hornHoldTimer = nil
local hornPressed = false
local hornHeld = false

bindKey("horn", "down", function()
    local veh = getControlledSirenVehicle()
    if not veh or not Beacons.hasLayout(getElementModel(veh)) then return end

    hornPressed = true
    hornHeld = false
    hornPressedAt = getTickCount()

    -- GTA gyári sziréna letiltása
    setTimer(function()
        if isElement(veh) and getVehicleSirensOn(veh) then
            setVehicleSirensOn(veh, false)
        end
    end, 50, 1)

    -- Csak akkor indul a kürt, ha ténylegesen nyomva tartjuk
    hornHoldTimer = setTimer(function()
        if hornPressed then
            hornHeld = true
            setHorn(true)
        end
    end, hornHoldTime, 1)
end)

bindKey("horn", "up", function()
    local veh = getControlledSirenVehicle()
    if not veh or not Beacons.hasLayout(getElementModel(veh)) then return end

    hornPressed = false

    if isTimer(hornHoldTimer) then
        killTimer(hornHoldTimer)
        hornHoldTimer = nil
    end

    -- Hosszú nyomás → csak kürt
    if hornHeld then
        setHorn(false)
        hornHeld = false
        return
    end

    -- Rövid nyomás
    local now = getTickCount()

    if now - lastShortPress <= doubleTapTime then
        -- Dupla rövid nyomás → sziréna ki
        turnSiren(false)
        lastShortPress = 0
        return
    end

    lastShortPress = now

    local sirenState = getElementData(veh, "sirenState") == true

    if not sirenState then
        -- Első rövid nyomás → fő sziréna be
        turnSiren(true)
    else
        -- Rövid nyomás → hangváltás
        nextTone()
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
        text = text .. "\nSiren index: #FFFF00" .. tostring(getElementData(veh, "sirenIndex") or "?") .. "#FFFFFF" ..
                       "\nSecondary: " .. onOff(getElementData(veh, "sirenSecondary"))
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
