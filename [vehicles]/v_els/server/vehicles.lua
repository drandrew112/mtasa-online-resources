-- ELS-es járművek: elementData állapot, gyári sziréna beállítása, kliens kérések.

function isSirenVehicle(veh)
    return isElement(veh) and sirenVehicles[getElementModel(veh)] ~= nil
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
    return getElementData(veh, "mkjState") == true and hasElsExtra(veh)
        and not Layouts.get(getElementModel(veh))
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

local function hasSecondary(veh)
    local cfg = sirenTypes[getElementData(veh, "sirenType")]
    return cfg and cfg.secondary and true or false
end

-- ezek csak felrakott extránál kapcsolhatók be
ELS_EXTRA_GATED = { mkjState = true, sirenState = true, sirenSecondary = true, sirenHorn = true }

local function isIndex(value, max)
    return value % 1 == 0 and value >= 1 and value <= max
end

-- érték ellenőrzése a kulcs alapján (a kliensnek nem hiszünk)
local function isValidValue(veh, key, value)
    if type(value) ~= SIREN_DATA_KEYS[key] then return false end

    -- extra nélkül semmi nem kapcsolható be
    if value == true and ELS_EXTRA_GATED[key] and not hasElsExtra(veh) then return false end

    if key == "sirenType" then
        return sirenTypes[value] ~= nil
    elseif key == "sirenIndex" then
        return isIndex(value, sirenCount(veh))
    elseif key == "sirenSecondary" then
        -- bekapcsolni csak szóló fő szirénával és másodlagos hanggal rendelkező típusnál lehet
        return not value or (getElementData(veh, "sirenState") == true and hasSecondary(veh))
    elseif key == "elsPattern" then
        return isIndex(value, #ELS_PATTERNS)
    end
    return true
end

local function setSirenType(veh, sirenType)
    setElementData(veh, "sirenType", sirenType)
    -- más típusnak kevesebb hangja lehet, ezért az elsőre állunk
    setElementData(veh, "sirenIndex", 1)
    if getElementData(veh, "sirenSecondary") and not hasSecondary(veh) then
        setElementData(veh, "sirenSecondary", false)
    end
end

local DEFAULTS = { mkjState = false, sirenState = false, sirenSecondary = false, elsPattern = 1 }

local function initExtraData(veh)
    if extraVehicles[getElementModel(veh)] and getElementData(veh, "elsExtra") == nil then
        setElementData(veh, "elsExtra", false)
    end
end

-- a már beállított szirénatípust nem írjuk felül, csak a hiányzót / érvénytelent
local function initVehicleData(veh)
    initExtraData(veh)
    if not sirenTypes[getElementData(veh, "sirenType")] then
        setSirenType(veh, getDefaultSirenType(getElementModel(veh)))
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

------------------------------------------------------------
-- EXTRA (fényhíd)
------------------------------------------------------------

local OFF_VARIANT = 255

local extraApplied = {} -- [veh] = true ha a variánst már beállítottuk

-- az extra állapotát a modellre (variáns) és az ELS állapotra is ráírja;
-- extra nélkül mindent lekapcsol
local function applyExtra(veh)
    local cfg = extraVehicles[getElementModel(veh)]
    if not cfg then
        extraApplied[veh] = nil
        return
    end

    local on = getElementData(veh, "elsExtra") == true
    local index = math.min(math.max(getElementData(veh, "elsExtraIndex") or 1, 1), cfg.count)
    setVehicleVariant(veh, on and index - 1 or OFF_VARIANT, OFF_VARIANT)
    extraApplied[veh] = true

    if not on then
        for key in pairs(ELS_EXTRA_GATED) do
            if getElementData(veh, key) then
                setElementData(veh, key, false)
            end
        end
        setVehicleSirensOn(veh, false)
    end
end

local function setExtra(veh, on, index)
    setElementData(veh, "elsExtra", on)
    if index then
        setElementData(veh, "elsExtraIndex", index)
    end
    applyExtra(veh)
end

local function prepareVehicle(veh)
    if not isSirenVehicle(veh) then return end
    initVehicleData(veh)
    applyExtra(veh)
    ensureSirens(veh)
end

-- nem használt járműveken is beállítjuk a variánst (a GTA véletlen extrát választ)
setTimer(function()
    for _, veh in ipairs(getElementsByType("vehicle")) do
        if extraVehicles[getElementModel(veh)] and not extraApplied[veh] then
            prepareVehicle(veh)
        end
    end
end, 3000, 0)

------------------------------------------------------------
-- KLIENS KÉRÉSEK
------------------------------------------------------------

-- egy ELS adat beállítása ellenőrzéssel és a függő állapotok követésével
-- (kliens kérés és exportok közös útja); true, ha elfogadta
local function applyData(veh, key, value)
    if not isValidValue(veh, key, value) then return false end

    if key == "sirenType" then
        setSirenType(veh, value)
        return true
    end

    setElementData(veh, key, value)

    -- sziréna hang csak égő fényekkel: a sziréna felkapcsolja a fényt, a fény
    -- lekapcsolása leállítja a szirénát. A fő sziréna leállása a másodlagos hangot
    -- is leállítja. A kürt (sirenHorn) ettől független.
    if key == "sirenState" and value and not getElementData(veh, "mkjState") then
        key = "mkjState"
        setElementData(veh, key, true)
    elseif key == "mkjState" and not value and getElementData(veh, "sirenState") then
        setElementData(veh, "sirenState", false)
    end
    if not getElementData(veh, "sirenState") and getElementData(veh, "sirenSecondary") then
        setElementData(veh, "sirenSecondary", false)
    end

    if key == "mkjState" then
        setVehicleSirensOn(veh, wantsNativeSirens(veh))
    end
    return true
end

addEvent("siren:setData", true)
addEventHandler("siren:setData", resourceRoot, function(veh, key, value)
    if not isSirenVehicle(veh) then return end
    -- sofőr vagy első utas (jobb1); hátsó ülésekről nem
    local seat = getPedOccupiedVehicleSeat(client)
    if getPedOccupiedVehicle(client) ~= veh or (seat ~= 0 and seat ~= 1) then return end
    applyData(veh, key, value)
end)

------------------------------------------------------------
-- SZIRÉNA EXPORTOK
------------------------------------------------------------

-- exports.v_els:setElsState(vehicle, key, value): bármelyik ELS adat
-- (mkjState, sirenState, sirenIndex, sirenHorn, sirenSecondary, sirenType, elsPattern),
-- ugyanazokkal az ellenőrzésekkel, mint a sofőr gombjainál (pl. extrás modellen extra nélkül
-- semmi nem kapcsolható be). true, ha elfogadta.
function setElsState(veh, key, value)
    if not isSirenVehicle(veh) or SIREN_DATA_KEYS[key] == nil then return false end
    if getElementData(veh, "mkjState") == nil then
        prepareVehicle(veh)
    end
    return applyData(veh, key, value)
end

-- fények be/ki (kikapcsoláskor a sziréna is leáll)
function setElsLights(veh, state)
    return setElsState(veh, "mkjState", state and true or false)
end

-- sziréna be/ki, opcionálisan a hang sorszámával (bekapcsoláskor a fények is felkapcsolnak)
function setElsSiren(veh, state, index)
    if index ~= nil and not setElsState(veh, "sirenIndex", index) then return false end
    return setElsState(veh, "sirenState", state and true or false)
end

-- sziréna típus beállítása (sirenTypes kulcs); a jármű megtartja, amíg újra nem állítják
function setElsSirenType(veh, sirenType)
    return setElsState(veh, "sirenType", sirenType)
end

-- az elérhető sziréna típusok kulcsai (ábécé sorrendben)
function getElsSirenTypes()
    local list = {}
    for key in pairs(sirenTypes) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end

-- az ELS állapota táblában (nil, ha nem ELS-es jármű)
function getElsState(veh)
    if not isSirenVehicle(veh) then return nil end
    local state = { extra = getElsExtra(veh) }
    for key in pairs(SIREN_DATA_KEYS) do
        state[key] = getElementData(veh, key)
    end
    return state
end

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
    if (seat == 0 or seat == 1) and isSirenVehicle(source) and getElementData(source, "sirenHorn") then
        setElementData(source, "sirenHorn", false)
    end
end)

addEventHandler("onElementModelChange", root, function()
    if getElementType(source) == "vehicle" then
        configured[source] = nil
        extraApplied[source] = nil
        -- az esemény a csere előtt fut, ezért kicsit később állítjuk be
        setTimer(prepareVehicle, 50, 1, source)
    end
end)

addEventHandler("onElementDestroy", root, function()
    configured[source] = nil
    extraApplied[source] = nil
end)

------------------------------------------------------------
-- EXTRA EXPORTOK
------------------------------------------------------------

-- exports.v_els:setElsExtra(vehicle, index | false): az index. extra felrakása,
-- false = levétel; true = az utoljára használt (alapból az 1.) extra.
-- Visszatérés: true ha sikerült, false ha a jármű nem extrás modell vagy érvénytelen index.
function setElsExtra(veh, index)
    local cfg = isElement(veh) and getElementType(veh) == "vehicle" and extraVehicles[getElementModel(veh)]
    if not cfg then return false end

    if index == false or index == nil then
        setExtra(veh, false)
        return true
    elseif index == true then
        setExtra(veh, true)
        return true
    end
    if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > cfg.count then
        return false
    end
    setExtra(veh, true, index)
    return true
end

-- a felrakott extra sorszáma, vagy false ha nincs rajta (nil: nem extrás jármű)
function getElsExtra(veh)
    if not isElement(veh) or not extraVehicles[getElementModel(veh)] then return nil end
    if getElementData(veh, "elsExtra") ~= true then return false end
    return getElementData(veh, "elsExtraIndex") or 1
end

-- a modellen választható extrák száma (0 = nem extrás)
function getElsExtraCount(model)
    local cfg = extraVehicles[model]
    return cfg and cfg.count or 0
end

------------------------------------------------------------
-- EXTRA PARANCS
------------------------------------------------------------

-- /elsextra [list|off|<n>]: a fényhíd extra fel- / levétele
--   (paraméter nélkül váltás az utoljára használt extrával, list = lehetőségek)
addCommandHandler("elsextra", function(player, _, arg)
    local veh = getPedOccupiedVehicle(player)
    local cfg = veh and extraVehicles[getElementModel(veh)]
    if not cfg or getVehicleController(veh) ~= player then
        outputChatBox(L.msg("v_els.extra.no_extra_vehicle"), player, 255, 200, 0)
        return
    end

    local mounted = getElementData(veh, "elsExtra") == true
    local current = getElementData(veh, "elsExtraIndex") or 1

    if arg == "list" then
        outputChatBox(L.msg("v_els.extra.list", { count = cfg.count,
            current = mounted and tostring(current) or "-" }), player, 255, 255, 255)
        return
    end

    local on, index = not mounted, nil
    if arg == "off" then
        on = false
    elseif arg ~= nil then
        index = tonumber(arg)
        if not index or index % 1 ~= 0 or index < 1 or index > cfg.count then
            outputChatBox(L.msg("v_els.extra.invalid", { count = cfg.count }), player, 255, 80, 80)
            return
        end
        on = true
    end

    setExtra(veh, on, index)
    if on then
        outputChatBox(L.msg("v_els.extra.mounted", { index = index or current }), player, 80, 255, 120)
    else
        outputChatBox(L.msg("v_els.extra.removed"), player, 80, 255, 120)
    end
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
    code3   = "code3_z3",
}

for command, sirenType in pairs(typeCommands) do
    addCommandHandler(command, function(player)
        local veh = getPedOccupiedVehicle(player)
        if isSirenVehicle(veh) and getVehicleController(veh) == player then
            setSirenType(veh, sirenType)
        end
    end)
end
