if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_modloader (client): the server's manifest, the options (Settings > Models) and the
-- local registry of the downloaded "manual" files.
--
--   Mods       [category][id] = { c = "dtc", f = { { p = path, s = size, h = md5 } }, n = name, a = added }
--   registry   [path] = md5 of the copy on this PC (LOCAL_FILE, private). A "manual" file is
--              current when it exists and its registry md5 equals the server's. Files that exist
--              without a registry entry (downloaded before the registry) are hashed once.
--   Options    [setting id] = bool, saved values (ui_pause / the server); nil = config default

Mods = nil
Options = {}

local registry = {}
local registryDirty = false
local verifyQueue = nil       -- { file, ... } still to hash; nil = done
local statusCache = nil       -- [category] = summary (getModelStatus)

addEvent("onClientModelStatusChange")   -- local; the download state changed (source = localPlayer)

-- ---------------------------------------------------------------------------
-- options
-- ---------------------------------------------------------------------------

local ALWAYS = {}
for _, id in ipairs(MODLOADER.ALWAYS_LOAD_OBJECTS or {}) do ALWAYS[tonumber(id)] = true end

local function settingDefault(id)
    if id == MODLOADER.AUTOUPDATE_SETTING then return MODLOADER.AUTOUPDATE_DEFAULT end
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

-- ---------------------------------------------------------------------------
-- registry (LOCAL_FILE)
-- ---------------------------------------------------------------------------

local function loadRegistry()
    registry = {}
    if not fileExists(MODLOADER.LOCAL_FILE) then return end
    local ok, data = pcall(function()
        local f = fileOpen(MODLOADER.LOCAL_FILE, true)
        if not f then return nil end
        local text = fileRead(f, fileGetSize(f))
        fileClose(f)
        return fromJSON(text)
    end)
    if ok and type(data) == "table" then
        for p, h in pairs(data) do
            if type(p) == "string" and type(h) == "string" then registry[p] = h end
        end
    end
end

function saveRegistry()
    if not registryDirty then return end
    registryDirty = false
    pcall(function()
        if fileExists(MODLOADER.LOCAL_FILE) then fileDelete(MODLOADER.LOCAL_FILE) end
        local f = fileCreate(MODLOADER.LOCAL_FILE)
        if not f then return end
        fileWrite(f, toJSON(registry, true))
        fileClose(f)
    end)
end

function registerDownloaded(path, hash)
    registry[path] = hash
    registryDirty = true
    statusCache = nil
end

local function isManual(catName)
    local cat = modloaderCategory(catName)
    return cat and cat.download == "manual"
end

-- "ok" | "outdated" | "missing" of one file
function fileState(catName, file)
    if not fileExists(file.p) then return "missing" end
    if not isManual(catName) then return "ok" end      -- MTA keeps the "auto" files current
    local h = registry[file.p]
    if not h then return "missing" end                  -- not verified (yet)
    return h == file.h and "ok" or "outdated"
end

-- every file of the model is on this PC (maybe an older version: still loadable)
function isModelPresent(catName, id)
    local mod = Mods and Mods[catName] and Mods[catName][id]
    if not mod then return false end
    for _, file in ipairs(mod.f or {}) do
        if not fileExists(file.p) then return false end
    end
    return true
end

-- files of a category that are not current: { { p, s, h }, ... }, bytes
function pendingFiles(catName)
    local out, bytes = {}, 0
    local ids = {}
    for id in pairs(Mods and Mods[catName] or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        for _, file in ipairs(Mods[catName][id].f or {}) do
            if fileState(catName, file) ~= "ok" then
                out[#out + 1] = file
                bytes = bytes + (tonumber(file.s) or 0)
            end
        end
    end
    return out, bytes
end

-- ---------------------------------------------------------------------------
-- status
-- ---------------------------------------------------------------------------

local function buildStatus(catName)
    local s = { ok = 0, total = 0, new = 0, outdated = 0, bytes = 0, totalBytes = 0, names = {}, checking = verifyQueue ~= nil }
    local ids = {}
    for id in pairs(Mods and Mods[catName] or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local ma, mb = Mods[catName][a], Mods[catName][b]
        if (ma.a or 0) ~= (mb.a or 0) then return (ma.a or 0) > (mb.a or 0) end -- newest first
        return a < b
    end)
    for _, id in ipairs(ids) do
        local mod = Mods[catName][id]
        s.total = s.total + 1
        local state = "ok"
        for _, file in ipairs(mod.f or {}) do
            s.totalBytes = s.totalBytes + (tonumber(file.s) or 0)
            local fs = fileState(catName, file)
            if fs ~= "ok" then
                s.bytes = s.bytes + (tonumber(file.s) or 0)
                if fs == "missing" then state = "missing" elseif state == "ok" then state = "outdated" end
            end
        end
        if state == "ok" then
            s.ok = s.ok + 1
        else
            if state == "missing" then s.new = s.new + 1 else s.outdated = s.outdated + 1 end
            s.names[#s.names + 1] = mod.n or (catName == "vehicles" and getVehicleNameFromModel(id)) or tostring(id)
        end
    end
    return s
end

--- { ok, total, new, outdated, bytes, totalBytes, names = {...}, checking } of a category (cached).
function getModelStatus(catName)
    if not statusCache then
        statusCache = {}
        for _, cat in ipairs(MODLOADER.categories) do statusCache[cat.name] = buildStatus(cat.name) end
    end
    return statusCache[catName] or buildStatus(catName)
end

--- Sum of the not current models of every "manual" category: count, bytes, checking.
function getMissingModels()
    local count, bytes = 0, 0
    for _, cat in ipairs(MODLOADER.categories) do
        if cat.download == "manual" then
            local s = getModelStatus(cat.name)
            count = count + s.new + s.outdated
            bytes = bytes + s.bytes
        end
    end
    return count, bytes, verifyQueue ~= nil
end

local reportTimer
function statusChanged()
    statusCache = nil
    triggerEvent("onClientModelStatusChange", localPlayer)
    if isTimer(reportTimer) then killTimer(reportTimer) end
    reportTimer = setTimer(function()
        local out = {}
        for _, cat in ipairs(MODLOADER.categories) do
            local s = getModelStatus(cat.name)
            out[cat.name] = { ok = s.ok, total = s.total }
        end
        triggerServerEvent("modloader:status", resourceRoot, out)
    end, 1000, 1)
end

-- ---------------------------------------------------------------------------
-- one-time hash of the "manual" files that exist without a registry entry
-- ---------------------------------------------------------------------------

local function verifyStep()
    local file = verifyQueue and table.remove(verifyQueue, 1)
    if not file then
        verifyQueue = nil
        saveRegistry()
        statusChanged()
        onVerifyDone()
        return
    end
    local ok, hash = pcall(function()
        local f = fileOpen(file.p, true)
        if not f then return nil end
        local data = fileRead(f, fileGetSize(f))
        fileClose(f)
        return md5(data)
    end)
    if ok and hash then registerDownloaded(file.p, hash) end
    setTimer(verifyStep, 50, 1)
end

local function startVerify()
    local queue = {}
    for _, cat in ipairs(MODLOADER.categories) do
        if cat.download == "manual" then
            for _, mod in pairs(Mods[cat.name] or {}) do
                for _, file in ipairs(mod.f or {}) do
                    if not registry[file.p] and fileExists(file.p) then queue[#queue + 1] = file end
                end
            end
        end
    end
    if #queue == 0 then
        verifyQueue = nil
        statusChanged()
        onVerifyDone()
        return
    end
    verifyQueue = queue
    statusChanged()
    verifyStep()
end

function isVerifying() return verifyQueue ~= nil end

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
    statusCache = nil
    startVerify()
    onModsReceived()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadRegistry()
    triggerServerEvent("modloader:request", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, saveRegistry)
