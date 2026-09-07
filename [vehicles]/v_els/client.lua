local siren3D = {}
local horn3D  = {}

-- script sziréna hangereje (0.0 - 1.0), halkabbra véve
local SIREN_VOLUME = 0.4

------------------------------------------------------------
-- SEGÉDFÜGGVÉNYEK
------------------------------------------------------------

local function stopSoundSafe(s)
    if s and isElement(s) then
        stopSound(s)
    end
end

local function isDriver(player)
    local veh = getPedOccupiedVehicle(player)
    return veh and getVehicleController(veh) == player
end

------------------------------------------------------------
-- SZIRÉNA FRISSÍTÉS (KÖZPONTI LOGIKA)
------------------------------------------------------------

function updateVehicleSiren(veh)
    if not isElement(veh) then return end
    if not sirenVehicles[getElementModel(veh)] then return end

    local sirenState = getElementData(veh, "sirenState")
    local sirenIndex = getElementData(veh, "sirenIndex") or 1
    local sirenHorn  = getElementData(veh, "sirenHorn")
    local sirenType  = getElementData(veh, "sirenType") or "fsvas320"

    local cfg = sirenTypes[sirenType]
    if not cfg then return end

    -- minden előző hang OFF
    stopSoundSafe(siren3D[veh])
    stopSoundSafe(horn3D[veh])
    siren3D[veh] = nil
    horn3D[veh]  = nil

    -- HORN → fő sziréna szünetel
    if sirenHorn then
        local h = playSound3D(cfg.horn, 0, 0, 0, true)
        attachElements(h, veh)
        setSoundVolume(h, 1)
        setSoundMinDistance(h, 1)
        setSoundMaxDistance(h, 150)
        horn3D[veh] = h
        return
    end

    -- FŐ SZIRÉNA
    if sirenState then
        local path = cfg.sirens[sirenIndex]
        if not path then return end

        local s = playSound3D(path, 0, 0, 0, true)
        attachElements(s, veh)
        setSoundVolume(s, SIREN_VOLUME)
        setSoundMinDistance(s, 1)
        setSoundMaxDistance(s, 150)
        siren3D[veh] = s
    end
end

------------------------------------------------------------
-- ELEMENT DATA FIGYELÉS
------------------------------------------------------------

addEventHandler("onClientElementDataChange", root,
    function(dataName)
        if getElementType(source) ~= "vehicle" then return end

        if dataName == "sirenState"
        or dataName == "sirenIndex"
        or dataName == "sirenHorn"
        or dataName == "sirenType" then
            updateVehicleSiren(source)
        end
    end
)

addEventHandler("onClientElementDestroy", root,
    function()
        stopSoundSafe(siren3D[source])
        stopSoundSafe(horn3D[source])
        siren3D[source] = nil
        horn3D[source]  = nil
    end
)

------------------------------------------------------------
-- KLIENS VEZÉRLÉS (BINDOK)
------------------------------------------------------------

-- FÉNYEK
bindKey("0", "down", function()
    if not isDriver(localPlayer) then return end

    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end
    if not sirenVehicles[getElementModel(veh)] then return end

    local state = not getElementData(veh, "mkjState")
    triggerServerEvent(
        "siren:setData",
        resourceRoot,
        veh,
        "mkjState",
        state
    )
end)

-- SZIRÉNA BE/KI

bindKey("1", "down", function()
    if not isDriver(localPlayer) then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    if not sirenVehicles[getElementModel(veh)] then return end

    local state = not getElementData(veh, "sirenState")
    triggerServerEvent("siren:setData", resourceRoot, veh, "sirenIndex", 1)
    triggerServerEvent("siren:setData", resourceRoot, veh, "sirenState", state)
end)

-- SZIRÉNA TÍPUS VÁLTÁS
bindKey("2", "down", function()
    if not isDriver(localPlayer) then return end

    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end
    if not sirenVehicles[getElementModel(veh)] then return end

    local sirenType  = getElementData(veh, "sirenType") or "fsvas320"
    local cfg = sirenTypes[sirenType]
    if not cfg then return end

    local maxIndex = #cfg.sirens
    if maxIndex < 1 then return end

    local current = getElementData(veh, "sirenIndex") or 1
    local nextIndex = current % maxIndex + 1

    triggerServerEvent(
        "siren:setData",
        resourceRoot,
        veh,
        "sirenIndex",
        nextIndex
    )
end)


-- HORN (lenyom = pause, felenged = vissza)
bindKey("3", "down", function()
    if not isDriver(localPlayer) then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    triggerServerEvent("siren:setData", resourceRoot, veh, "sirenHorn", true)
end)

bindKey("3", "up", function()
    if not isDriver(localPlayer) then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    triggerServerEvent("siren:setData", resourceRoot, veh, "sirenHorn", false)
end)

-- draw siren type
local sx, sy = guiGetScreenSize()
local show_els_info = false

addEventHandler("onClientRender", root, function()
    if not show_els_info then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh then
        local mkj    = getElementData(veh, "mkjState")
        local sType  = getElementData(veh, "sirenType") or "?"
        local sState = getElementData(veh, "sirenState")
        local sHorn  = getElementData(veh, "sirenHorn")
        local sIndex = getElementData(veh, "sirenIndex")

        local onOff = function(val)
            return val and "#00FF00ON" or "#FF0000OFF"
        end

        local text = "ELS: " .. onOff(mkj) .. "#FFFFFF" ..
                     "\nSiren type: #FFFFFF" .. sType .. 
                     "\nSiren state: " .. onOff(sState) .. "#FFFFFF"

        -- Ha be van kapcsolva a sziréna, írjuk ki az indexet is
        if sState then
            text = text .. "\nSiren index: #FFFF00" .. (sIndex or "OFF") .. "#FFFFFF"
        end

        -- Kürt hozzáadása a végére
        text = text .. "\nHorn state: " .. onOff(sHorn)

        -- Megjelenítés (colorCoded = true)
        dxDrawText(text, sx*0.2, sy-60, _, _, tocolor(255, 255, 255, 255), 1.3, "default", "left", "bottom", false, false, false, true)
    end
end)

addCommandHandler("debugels", function ()
    show_els_info = not show_els_info
end)
