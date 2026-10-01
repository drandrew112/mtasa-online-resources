-- Sziréna és kürt hangok a betöltött (streamed in) ELS járművekre.

local SIREN_VOLUME   = 0.4  -- script sziréna hangereje (0.0 - 1.0)
local HORN_VOLUME    = 1.0
local SOUND_MIN_DIST = 1
local SOUND_MAX_DIST = 150

-- [veh] = épp szóló hang (sziréna VAGY kürt, egyszerre csak egy)
local activeSound = {}
-- [veh] = timer, ami váltáskor SIREN_SWITCH_DELAY után indítja az új szirénahangot
local pendingStart = {}

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
    local cfg = sirenTypes[getElementData(veh, "sirenType") or DEFAULT_SIREN_TYPE]
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

    local s = playSound3D(path, 0, 0, 0, true)
    if not s then return end
    attachElements(s, veh)
    setSoundVolume(s, volume)
    setSoundMinDistance(s, SOUND_MIN_DIST)
    setSoundMaxDistance(s, SOUND_MAX_DIST)
    activeSound[veh] = s
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

local soundDataKeys = { sirenState = true, sirenIndex = true, sirenHorn = true, sirenType = true }

addEventHandler("onClientElementDataChange", root, function(dataName)
    if soundDataKeys[dataName] and getElementType(source) == "vehicle" then
        updateVehicleSound(source)
    end
end)

-- csak a látótávon belüli járműveknek szól hang
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then
        updateVehicleSound(source)
    end
end)

local function onVehicleGone()
    if activeSound[source] or pendingStart[source] then
        stopVehicleSound(source)
    end
end
addEventHandler("onClientElementStreamOut", root, onVehicleGone)
addEventHandler("onClientElementDestroy", root, onVehicleGone)
