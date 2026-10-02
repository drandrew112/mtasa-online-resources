-- Sziréna és kürt hangok a betöltött (streamed in) ELS járművekre.

local SIREN_VOLUME   = 0.4  -- script sziréna hangereje (0.0 - 1.0)
local HORN_VOLUME    = 1.0
local SOUND_MIN_DIST = 1
local SOUND_MAX_DIST = 150

-- [veh] = épp szóló hang (sziréna VAGY kürt, egyszerre csak egy)
local activeSound = {}
-- [veh] = timer, ami váltáskor SIREN_SWITCH_DELAY után indítja az új szirénahangot
local pendingStart = {}
-- [veh] = másodlagos szirénahang (a fő mellett szól, kürt alatt szünetel)
local secondarySound = {}

local function createVehicleSound(veh, path, volume)
    local s = playSound3D(path, 0, 0, 0, true)
    if not s then return end
    -- a 3D hang a 0-s dimenzióban születik: a jármű dimenziójában kell szólnia (pl. v_introduce, műhely)
    setElementDimension(s, getElementDimension(veh))
    setElementInterior(s, getElementInterior(veh))
    attachElements(s, veh)
    setSoundVolume(s, volume)
    setSoundMinDistance(s, SOUND_MIN_DIST)
    setSoundMaxDistance(s, SOUND_MAX_DIST)
    return s
end

local function stopSecondarySound(veh)
    local s = secondarySound[veh]
    if s and isElement(s) then
        destroyElement(s)
    end
    secondarySound[veh] = nil
end

local function getSirenConfig(veh)
    return sirenTypes[getElementData(veh, "sirenType") or getDefaultSirenType(getElementModel(veh))]
end

local function stopVehicleSound(veh)
    local s = activeSound[veh]
    if s and isElement(s) then
        destroyElement(s)
    end
    activeSound[veh] = nil

    local t = pendingStart[veh]
    if t and isTimer(t) then
        killTimer(t)
    end
    pendingStart[veh] = nil
end

-- path, volume, isHorn
local function getSoundPath(veh)
    local cfg = getSirenConfig(veh)
    if not cfg then return end

    -- kürt alatt a fő sziréna szünetel
    if getElementData(veh, "sirenHorn") then
        return cfg.horn, HORN_VOLUME, true
    end
    if getElementData(veh, "sirenState") then
        return cfg.sirens[getElementData(veh, "sirenIndex") or 1], SIREN_VOLUME, false
    end
end

local function playVehicleSound(veh)
    pendingStart[veh] = nil
    if not isElement(veh) or not isElementStreamedIn(veh) then return end

    local path, volume = getSoundPath(veh)
    if not path then return end

    activeSound[veh] = createVehicleSound(veh, path, volume)
end

local function getSecondaryPath(veh)
    if getElementData(veh, "sirenHorn") then return end
    if not (getElementData(veh, "sirenState") and getElementData(veh, "sirenSecondary")) then return end
    local cfg = getSirenConfig(veh)
    return cfg and cfg.secondary or nil
end

local function updateSecondarySound(veh)
    stopSecondarySound(veh)
    if not isElementStreamedIn(veh) then return end
    if not sirenVehicles[getElementModel(veh)] then return end

    local path = getSecondaryPath(veh)
    if path then
        secondarySound[veh] = createVehicleSound(veh, path, SIREN_VOLUME)
    end
end

local function updateVehicleSound(veh)
    local switching = activeSound[veh] ~= nil or pendingStart[veh] ~= nil
    stopVehicleSound(veh)
    if not isElementStreamedIn(veh) then return end
    if not sirenVehicles[getElementModel(veh)] then return end

    local path, _, isHorn = getSoundPath(veh)
    if not path then return end

    -- hangváltáskor rövid csend; első indításkor és kürtnél nincs késleltetés
    if switching and not isHorn and SIREN_SWITCH_DELAY >= 50 then
        pendingStart[veh] = setTimer(playVehicleSound, SIREN_SWITCH_DELAY, 1, veh)
    else
        playVehicleSound(veh)
    end
end

local soundDataKeys     = { sirenState = true, sirenIndex = true, sirenHorn = true, sirenType = true }
local secondaryDataKeys = { sirenState = true, sirenSecondary = true, sirenHorn = true, sirenType = true }

addEventHandler("onClientElementDataChange", root, function(dataName)
    if getElementType(source) ~= "vehicle" then return end
    if soundDataKeys[dataName] then
        updateVehicleSound(source)
    end
    if secondaryDataKeys[dataName] then
        updateSecondarySound(source)
    end
end)

-- csak a látótávon belüli járműveknek szól hang
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then
        updateVehicleSound(source)
        updateSecondarySound(source)
    end
end)

local function onVehicleGone()
    if activeSound[source] or pendingStart[source] then
        stopVehicleSound(source)
    end
    if secondarySound[source] then
        stopSecondarySound(source)
    end
end
addEventHandler("onClientElementStreamOut", root, onVehicleGone)
addEventHandler("onClientElementDestroy", root, onVehicleGone)

-- dimenzióváltáskor a hangok mennek a járművel
addEventHandler("onClientElementDimensionChange", root, function(_, newDimension)
    local main, second = activeSound[source], secondarySound[source]
    if isElement(main) then setElementDimension(main, newDimension) end
    if isElement(second) then setElementDimension(second, newDimension) end
end)
