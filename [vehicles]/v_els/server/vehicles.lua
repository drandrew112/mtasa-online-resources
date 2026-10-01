-- ELS-es járművek: elementData állapot, gyári sziréna beállítása, kliens kérések.

function isSirenVehicle(veh)
    return isElement(veh) and sirenVehicles[getElementModel(veh)] == true
end

------------------------------------------------------------
-- GYÁRI SZIRÉNA
------------------------------------------------------------

-- A gyári szirénát a GTA hangja miatt mindig felülírjuk (silent = true).
-- Ha a modellnek van saját elrendezése, a fényeket a kliens rajzolja: a gyári
-- sziréna láthatatlan (1-es típus) és sosem kapcsol be, mert bekapcsolva a GTA
-- a talajon/környezeten is villogtatja a saját fényeffektjeit.
-- Saját elrendezés nélkül marad a gyári villogó.
--
-- Járművenként csak egyszer állítjuk be: a korábbi verzió minden beszálláskor
-- remove+add-olta a szirénákat, emiatt a kliensen eltűntek a fények.

local INVISIBLE, QUINTUPLE = 1, 6

local configured = {} -- [veh] = "model:custom" | "model:native"

-- a gyári sziréna csak saját elrendezés nélküli modellen és bekapcsolt fénynél ég
local function wantsNativeSirens(veh)
    return getElementData(veh, "mkjState") == true and not Layouts.get(getElementModel(veh))
end

local function applySirens(veh, model, key)
    removeVehicleSirens(veh)
    if Layouts.get(model) then
        addVehicleSirens(veh, 1, INVISIBLE, false, false, false, true)
    else
        addVehicleSirens(veh, 2, QUINTUPLE, false, true, true, true)
    end
    configured[veh] = key
end

local function ensureSirens(veh)
    if not isSirenVehicle(veh) then
        configured[veh] = nil
        return
    end

    local model = getElementModel(veh)
    local key = model .. (Layouts.get(model) and ":custom" or ":native")
    if configured[veh] ~= key then
        applySirens(veh, model, key)
    end
    setVehicleSirensOn(veh, wantsNativeSirens(veh))
end

-- új elrendezés mentésekor az adott modell járműveit átállítjuk
function refreshModelSirens(model)
    for _, veh in ipairs(getElementsByType("vehicle")) do
        if getElementModel(veh) == model then
            ensureSirens(veh)
        end
    end
end

------------------------------------------------------------
-- ÁLLAPOT
------------------------------------------------------------

local function sirenCount(veh)
    local cfg = sirenTypes[getElementData(veh, "sirenType")]
    return cfg and #cfg.sirens or 0
end

local function isIndex(value, max)
    return value % 1 == 0 and value >= 1 and value <= max
end

-- érték ellenőrzése a kulcs alapján (a kliensnek nem hiszünk)
local function isValidValue(veh, key, value)
    if type(value) ~= SIREN_DATA_KEYS[key] then return false end

    if key == "sirenType" then
        return sirenTypes[value] ~= nil
    elseif key == "sirenIndex" then
        return isIndex(value, sirenCount(veh))
    elseif key == "elsPattern" then
        return isIndex(value, #ELS_PATTERNS)
    end
    return true
end

local function setSirenType(veh, sirenType)
    setElementData(veh, "sirenType", sirenType)
    -- más típusnak kevesebb hangja lehet, ezért az elsőre állunk
    setElementData(veh, "sirenIndex", 1)
end

local DEFAULTS = { mkjState = false, sirenState = false, elsPattern = 1 }

local function initVehicleData(veh)
    if getElementData(veh, "sirenType") == nil then
        setSirenType(veh, DEFAULT_SIREN_TYPE)
    end
    for key, value in pairs(DEFAULTS) do
        if getElementData(veh, key) == nil then
            setElementData(veh, key, value)
        end
    end
    -- beragadt kürt elleni védelem
    if getElementData(veh, "sirenHorn") then
        setElementData(veh, "sirenHorn", false)
    end
end

local function prepareVehicle(veh)
    if not isSirenVehicle(veh) then return end
    initVehicleData(veh)
    ensureSirens(veh)
end

------------------------------------------------------------
-- KLIENS KÉRÉSEK
------------------------------------------------------------

addEvent("siren:setData", true)
addEventHandler("siren:setData", resourceRoot, function(veh, key, value)
    if not isSirenVehicle(veh) then return end
    if getVehicleController(veh) ~= client then return end
    if not isValidValue(veh, key, value) then return end

    if key == "sirenType" then
        setSirenType(veh, value)
        return
    end

    setElementData(veh, key, value)

    -- sziréna hang csak égő fényekkel: a sziréna felkapcsolja a fényt, a fény
    -- lekapcsolása leállítja a szirénát. A kürt (sirenHorn) ettől független.
    if key == "sirenState" and value and not getElementData(veh, "mkjState") then
        key = "mkjState"
        setElementData(veh, key, true)
    elseif key == "mkjState" and not value and getElementData(veh, "sirenState") then
        setElementData(veh, "sirenState", false)
    end

    if key == "mkjState" then
        setVehicleSirensOn(veh, wantsNativeSirens(veh))
    end
end)

------------------------------------------------------------
-- JÁRMŰ ESEMÉNYEK
------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle")) do
        prepareVehicle(veh)
    end
end)

addEventHandler("onVehicleEnter", root, function(_, seat)
    if seat == 0 then
        prepareVehicle(source)
    end
end)

addEventHandler("onVehicleExit", root, function(_, seat)
    if seat == 0 and isSirenVehicle(source) and getElementData(source, "sirenHorn") then
        setElementData(source, "sirenHorn", false)
    end
end)

addEventHandler("onElementModelChange", root, function()
    if getElementType(source) == "vehicle" then
        configured[source] = nil
        -- az esemény a csere előtt fut, ezért kicsit később állítjuk be
        setTimer(prepareVehicle, 50, 1, source)
    end
end)

addEventHandler("onElementDestroy", root, function()
    configured[source] = nil
end)

------------------------------------------------------------
-- SZIRÉNA TÍPUS PARANCSOK
------------------------------------------------------------

local typeCommands = {
    stso    = "soundoff",
    stfs    = "fsvas320",
    strtk   = "hella_rtk7",
    rumbler = "rumbler",
    stitaly = "italy",
    eriston = "eriston",
    dal     = "dal",
}

for command, sirenType in pairs(typeCommands) do
    addCommandHandler(command, function(player)
        local veh = getPedOccupiedVehicle(player)
        if isSirenVehicle(veh) and getVehicleController(veh) == player then
            setSirenType(veh, sirenType)
        end
    end)
end
