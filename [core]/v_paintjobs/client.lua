-- v_paintjobs (client): puts the paintjob of every streamed-in vehicle on it.
--
-- One texture + one shader per paintjob file, shared by every vehicle that wears it; the
-- shader is applied to the model's remap texture of that one vehicle only
-- (engineApplyShaderToWorldTexture with a target element), so two cars of the same model
-- can wear different paintjobs. A file is downloaded (downloadFile) the first time a
-- vehicle with it streams in; a texture nothing uses is freed after PAINTJOBS.TEXTURE_TTL.
--
-- Exports: getPaintjobs(model) -> { { name, label } }   (same order as the server's)
--          previewPaintjob(vehicle, name | false | nil)  local look only; nil ends the preview

local List = nil        -- [model] = { t = pattern, j = { entries }, byName = { [name] = entry } }
local registry = {}     -- [path] = md5 of the copy on this PC (LOCAL_FILE)
local inflight = {}     -- [path] = { md5, tries }
local items = {}        -- [path] = { texture, shader, refs, timer }
local applied = {}      -- [vehicle] = { path, pattern, shader }
local preview = {}      -- [vehicle] = name | false

-- ---------------------------------------------------------------------------
-- registry (LOCAL_FILE)
-- ---------------------------------------------------------------------------

local function loadRegistry()
    registry = {}
    if not fileExists(PAINTJOBS.LOCAL_FILE) then return end
    local ok, data = pcall(function()
        local f = fileOpen(PAINTJOBS.LOCAL_FILE, true)
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

local function saveRegistry()
    pcall(function()
        if fileExists(PAINTJOBS.LOCAL_FILE) then fileDelete(PAINTJOBS.LOCAL_FILE) end
        local f = fileCreate(PAINTJOBS.LOCAL_FILE)
        if not f then return end
        fileWrite(f, toJSON(registry, true))
        fileClose(f)
    end)
end

--- The current copy of the entry is on this PC. A file without a registry entry is hashed once.
local function isPresent(entry)
    if not fileExists(entry.p) then return false end
    if registry[entry.p] == entry.h then return true end
    if registry[entry.p] == nil then
        local ok, hash = pcall(function()
            local f = fileOpen(entry.p, true)
            local data = fileRead(f, fileGetSize(f))
            fileClose(f)
            return md5(data)
        end)
        if ok and hash then
            registry[entry.p] = hash:upper() == entry.h:upper() and entry.h or hash
            saveRegistry()
            return registry[entry.p] == entry.h
        end
    end
    return false
end

local function report(line)
    outputDebugString("[paintjobs] " .. line, 1)
    triggerServerEvent("paintjobs:report", resourceRoot, line)
end

-- ---------------------------------------------------------------------------
-- textures + shaders (shared per file)
-- ---------------------------------------------------------------------------

local function freeItem(path)
    local item = items[path]
    if not item or item.refs > 0 then return end
    items[path] = nil
    if isElement(item.shader) then destroyElement(item.shader) end
    if isElement(item.texture) then destroyElement(item.texture) end
end

local function acquire(entry)
    local item = items[entry.p]
    if not item then
        local texture = dxCreateTexture(entry.p, entry.f or "dxt5", true)
        if not texture then
            report(entry.p .. ": cannot create the texture")
            return nil
        end
        local shader = dxCreateShader("paintjob.fx", 0, 0, false, "vehicle")
        if not shader then
            destroyElement(texture)
            report("paintjob.fx: cannot create the shader")
            return nil
        end
        dxSetShaderValue(shader, "gTexture", texture)
        item = { texture = texture, shader = shader, refs = 0 }
        items[entry.p] = item
    end
    if item.timer and isTimer(item.timer) then killTimer(item.timer) end
    item.timer = nil
    item.refs = item.refs + 1
    return item.shader
end

local function release(path)
    local item = items[path]
    if not item then return end
    item.refs = math.max(0, item.refs - 1)
    if item.refs == 0 and not item.timer then
        item.timer = setTimer(function()
            if items[path] then items[path].timer = nil end
            freeItem(path)
        end, PAINTJOBS.TEXTURE_TTL, 1)
    end
end

-- ---------------------------------------------------------------------------
-- vehicles
-- ---------------------------------------------------------------------------

--- The entry and texture pattern the vehicle should wear now (nil = none).
local function wanted(veh)
    if not List or not isElement(veh) or not isElementStreamedIn(veh) then return nil end
    local name = preview[veh]
    if name == nil then name = getElementData(veh, PAINTJOBS.DATA_KEY) end
    if not name then return nil end
    local model = List[getElementModel(veh)]
    local entry = model and model.byName[name]
    if entry then return entry, model.t end
end

local function unapply(veh)
    local cur = applied[veh]
    if not cur then return end
    applied[veh] = nil
    if isElement(cur.shader) then
        if isElement(veh) then engineRemoveShaderFromWorldTexture(cur.shader, cur.pattern, veh) end
    end
    release(cur.path)
end

local function download(entry)
    if inflight[entry.p] then return end
    inflight[entry.p] = { md5 = entry.h, tries = 0 }
    if not downloadFile(entry.p) then
        inflight[entry.p] = nil
        report(entry.p .. ": downloadFile refused")
    end
end

local function refresh(veh)
    local entry, pattern = wanted(veh)
    local cur = applied[veh]
    if cur and (not entry or cur.path ~= entry.p or cur.pattern ~= pattern) then
        unapply(veh)
        cur = nil
    end
    if not entry or cur then return end
    if not isPresent(entry) then return download(entry) end
    local shader = acquire(entry)
    if not shader then return end
    if engineApplyShaderToWorldTexture(shader, pattern, veh) then
        applied[veh] = { path = entry.p, pattern = pattern, shader = shader }
    else
        release(entry.p)
        report(("%s: cannot apply to texture '%s'"):format(entry.p, pattern))
    end
end

local function refreshAll()
    for veh in pairs(applied) do
        if not isElement(veh) then applied[veh] = nil; preview[veh] = nil end
    end
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do refresh(veh) end
    for veh in pairs(applied) do refresh(veh) end
end

local function isVehicle(element)
    return isElement(element) and getElementType(element) == "vehicle"
end

addEventHandler("onClientElementStreamIn", root, function()
    if isVehicle(source) then refresh(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if isVehicle(source) then unapply(source) end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == PAINTJOBS.DATA_KEY and isVehicle(source) then refresh(source) end
end)

addEventHandler("onClientElementModelChange", root, function()
    if isVehicle(source) then refresh(source) end
end)

addEventHandler("onClientElementDestroy", root, function()
    if applied[source] or preview[source] ~= nil then
        preview[source] = nil
        unapply(source)
    end
end)

addEventHandler("onClientFileDownloadComplete", resourceRoot, function(fileName, success)
    fileName = tostring(fileName or ""):gsub("\\", "/")
    local path, info
    for p, i in pairs(inflight) do
        if fileName == p or fileName:sub(-#p - 1) == "/" .. p then path, info = p, i break end
    end
    if not path then return end
    if not success then
        if info.tries < 1 and downloadFile(path) then
            info.tries = info.tries + 1
            return
        end
        inflight[path] = nil
        return report(path .. ": download failed")
    end
    inflight[path] = nil
    registry[path] = info.md5
    saveRegistry()
    -- every vehicle that waits for it
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do refresh(veh) end
end)

-- ---------------------------------------------------------------------------
-- list + exports
-- ---------------------------------------------------------------------------

addEvent("paintjobs:list", true)
addEventHandler("paintjobs:list", resourceRoot, function(list)
    List = {}
    for model, m in pairs(type(list) == "table" and list or {}) do
        local byName = {}
        for _, e in ipairs(m.j or {}) do byName[e.n] = e end
        List[tonumber(model)] = { t = m.t, j = m.j or {}, byName = byName }
    end
    refreshAll()
end)

function getPaintjobs(model)
    local out = {}
    local m = List and List[tonumber(model)]
    if m then
        for i, e in ipairs(m.j) do out[i] = { name = e.n, label = e.l } end
    end
    return out
end

function previewPaintjob(veh, name)
    if not isVehicle(veh) then return false end
    if name ~= nil and name ~= false and type(name) ~= "string" then return false end
    preview[veh] = name
    refresh(veh)
    return true
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadRegistry()
    triggerServerEvent("paintjobs:request", resourceRoot)
end)
