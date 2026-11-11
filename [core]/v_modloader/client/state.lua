if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_modloader (client): the server's mod list and the options (Settings > Models).
-- Every model file is a normal meta.xml file: MTA downloads all of them automatically when
-- the resource starts, there is nothing to download or check here.
--
--   Mods       [category][id] = { c = "dtc", f = { { p = path, s = size, h = md5 } }, n = name, a = added }
--   Options    [setting id] = bool, saved values (ui_pause / the server); nil = config default

Mods = nil
Options = {}

-- ---------------------------------------------------------------------------
-- options
-- ---------------------------------------------------------------------------

local ALWAYS = {}
for _, id in ipairs(MODLOADER.ALWAYS_LOAD_OBJECTS or {}) do ALWAYS[tonumber(id)] = true end

local function settingDefault(id)
    for _, cat in ipairs(MODLOADER.categories) do
        if cat.setting == id then return cat.default end
    end
end

function isKnownSetting(id)
    return settingDefault(id) ~= nil
end

function optionValue(id)
    local v = Options[id]
    if v == nil then v = settingDefault(id) end
    return v == true
end

function isAlwaysLoaded(catName, id)
    return catName == "objects" and ALWAYS[id] == true
end

-- every file of the model is on this PC
function isModelPresent(catName, id)
    local mod = Mods and Mods[catName] and Mods[catName][id]
    if not mod then return false end
    for _, file in ipairs(mod.f or {}) do
        if not fileExists(file.p) then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- exports: options (ui_pause Settings > Models)
-- ---------------------------------------------------------------------------

function getModelOption(id)
    if not isKnownSetting(id) then return nil end
    return optionValue(id)
end

function setModelOption(id, value)
    if not isKnownSetting(id) then return false end
    local before = optionValue(id)
    Options[id] = value == true
    if before ~= optionValue(id) then onOptionChanged(id) end
    return true
end

-- ---------------------------------------------------------------------------
-- server sync
-- ---------------------------------------------------------------------------

addEvent("modloader:mods", true)
addEventHandler("modloader:mods", resourceRoot, function(list, saved)
    if type(list) ~= "table" then return end
    Mods = list
    -- saved account options (the server reads them for a restart of this resource; ui_pause
    -- pushes them too after the login)
    if type(saved) == "table" then
        for id, v in pairs(saved) do
            if isKnownSetting(id) and Options[id] == nil then Options[id] = v == true end
        end
    end
    onModsReceived()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("modloader:request", resourceRoot)
end)
