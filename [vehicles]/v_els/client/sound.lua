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
-- [veh] = { sound, start, volume }: egyszer szóló bevezető hang (cfg.intro), ami
-- a start mp után átúszik a vele szinkronban, némán futó loop hangba (activeSound)
local introSound = {}
local INTRO_FADE = 0.15 -- átúszás hossza (mp)

local function createVehicleSound(veh, path, volume, once)
    local s = playSound3D(path, 0, 0, 0, not once)
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

    local intro = introSound[veh]
    if intro and isElement(intro.sound) then
        destroyElement(intro.sound)
    end
    introSound[veh] = nil

    local t = pendingStart[veh]
    if t and isTimer(t) then
        killTimer(t)
    end
    pendingStart[veh] = nil
end

-- path, volume, isHorn, introPath
local function getSoundPath(veh)
    local cfg = getSirenConfig(veh)
    if not cfg then return end

    -- kürt alatt a fő sziréna szünetel
    if getElementData(veh, "sirenHorn") then
        return cfg.horn, HORN_VOLUME * (cfg.hornVolume or cfg.volume or 1), true
    end
    if getElementData(veh, "sirenState") then
        local index = getElementData(veh, "sirenIndex") or 1
        return cfg.sirens[index], SIREN_VOLUME * (cfg.volume or 1), false, cfg.intro and cfg.intro[index]
    end
end

local function playVehicleSound(veh)
    pendingStart[veh] = nil
    if not isElement(veh) or not isElementStreamedIn(veh) then return end

    local path, volume, _, introPath = getSoundPath(veh)
    if not path then return end

    local s = createVehicleSound(veh, path, volume)
    activeSound[veh] = s
    if not (s and introPath) then return end

    -- a loop fájl a bevezető vége (az utolsó loopLen mp-e): a bevezető start mp-től
    -- ugyanazt játssza, ezért a loopot úgy indítjuk, hogy ott épp az elején tartson
    local intro = createVehicleSound(veh, introPath, volume, true)
    if not intro then return end
    local loopLen = getSoundLength(s) or 0
    local start = (getSoundLength(intro) or 0) - loopLen
    if loopLen <= 0 or start <= 0 then
        destroyElement(intro)
        return
    end
    setSoundPosition(s, (-start) % loopLen)
    setSoundVolume(s, 0)
    introSound[veh] = { sound = intro, start = start, volume = volume }
end

addEventHandler("onClientRender", root, function()
    for veh, intro in pairs(introSound) do
        local s = activeSound[veh]
        local k = isElement(intro.sound) and ((getSoundPosition(intro.sound) or 0) - intro.start) / INTRO_FADE or 1
        if k >= 1 or not isElement(s) then
            if isElement(intro.sound) then destroyElement(intro.sound) end
            if isElement(s) then setSoundVolume(s, intro.volume) end
            introSound[veh] = nil
        elseif k > 0 then
            setSoundVolume(intro.sound, intro.volume * (1 - k))
            setSoundVolume(s, intro.volume * k)
        end
    end
end)

local function getSecondaryPath(veh)
    if getElementData(veh, "sirenHorn") then return end
    if not (getElementData(veh, "sirenState") and getElementData(veh, "sirenSecondary")) then return end
    local cfg = getSirenConfig(veh)
    if cfg and cfg.secondary then
        return cfg.secondary, SIREN_VOLUME * (cfg.volume or 1)
    end
end

local function updateSecondarySound(veh)
    stopSecondarySound(veh)
    if not isElementStreamedIn(veh) then return end
    if not sirenVehicles[getElementModel(veh)] then return end

    local path, volume = getSecondaryPath(veh)
    if path then
        secondarySound[veh] = createVehicleSound(veh, path, volume)
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
    local main, second, intro = activeSound[source], secondarySound[source], introSound[source]
    if isElement(main) then setElementDimension(main, newDimension) end
    if isElement(second) then setElementDimension(second, newDimension) end
    if intro and isElement(intro.sound) then setElementDimension(intro.sound, newDimension) end
end)
