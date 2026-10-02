-- Scene files: scenes/<name>.json, listed in scenes/index.json.
--
-- On start every file is read once and only a short summary is kept in memory
-- (Storage.summary). The full data is read from the file again whenever a module
-- needs it (spawning, editing), so large scenes do not sit in memory.

Storage = {
    names = {},     -- ordered scene names (the index)
    summary = {},   -- [name] = { name, title, priority, center, interior, dimension, weight, enabled, peds, vehicles }
}

local FORMAT = 1

local function scenePath(name)
    return MSM.SCENE_DIR .. name .. ".json"
end

local function num(value, default)
    return tonumber(value) or default
end

local function vec3(value, default)
    if type(value) ~= "table" then return default end
    return { num(value[1] or value.x, 0), num(value[2] or value.y, 0), num(value[3] or value.z, 0) }
end

---------------------------------------------------------------- data shape

-- Returns a complete, valid scene table from anything decoded out of a file.
function Storage.normalize(data, name)
    data = type(data) == "table" and data or {}
    local erm = type(data.erm) == "table" and data.erm or {}
    local scene = {
        format = FORMAT,
        name = name or data.name,
        enabled = data.enabled ~= false,
        weight = math.max(0, num(data.weight, 1)),
        center = vec3(data.center, { 0, 0, 3 }),
        interior = math.floor(num(data.interior, 0)),
        dimension = math.floor(num(data.dimension, 0)),
        erm = {
            title = tostring(erm.title or MSM.DEFAULT_ERM.title),
            description = tostring(erm.description or MSM.DEFAULT_ERM.description),
            caller = tostring(erm.caller or MSM.DEFAULT_ERM.caller),
            priority = math.max(1, math.min(4, math.floor(num(erm.priority, MSM.DEFAULT_ERM.priority)))),
        },
        vehicles = {},
        peds = {},
    }

    local usedIds = {}
    local function uniqueId(prefix, id)
        id = tostring(id or "")
        if id == "" or usedIds[id] then
            local n = 1
            while usedIds[prefix .. n] do n = n + 1 end
            id = prefix .. n
        end
        usedIds[id] = true
        return id
    end

    for _, v in ipairs(type(data.vehicles) == "table" and data.vehicles or {}) do
        if type(v) == "table" and tonumber(v.model) then
            local entry = msmCopy(v)
            entry.id = uniqueId("v", v.id)
            entry.model = math.floor(tonumber(v.model))
            entry.pos = vec3(v.pos, { 0, 0, 3 })
            entry.rot = vec3(v.rot, { 0, 0, 0 })
            scene.vehicles[#scene.vehicles + 1] = entry
        end
    end

    for _, p in ipairs(type(data.peds) == "table" and data.peds or {}) do
        if type(p) == "table" then
            local entry = msmCopy(p)
            entry.id = uniqueId("p", p.id)
            entry.skin = math.floor(num(p.skin, 0))
            entry.pos = vec3(p.pos, { 0, 0, 3 })
            entry.rot = num(p.rot, 0)
            entry.anim = msmAnimById(p.anim) and p.anim or "none"
            entry.injuries = {}
            for _, inj in ipairs(type(p.injuries) == "table" and p.injuries or {}) do
                local sev = math.floor(num(inj.severity or inj[2], 0))
                local typ = inj.type or inj[1]
                if MSM_INJURIES and typ and sev >= 1 and sev <= 3 then
                    entry.injuries[#entry.injuries + 1] = { type = tostring(typ), severity = sev }
                end
            end
            entry.state = type(p.state) == "table" and p.state or {}
            scene.peds[#scene.peds + 1] = entry
        end
    end

    return scene
end

local function makeSummary(name, scene)
    return {
        name = name,
        title = scene.erm.title,
        priority = scene.erm.priority,
        center = { scene.center[1], scene.center[2], scene.center[3] },
        interior = scene.interior,
        dimension = scene.dimension,
        weight = scene.weight,
        enabled = scene.enabled,
        peds = #scene.peds,
        vehicles = #scene.vehicles,
    }
end

---------------------------------------------------------------- index

local function writeIndex()
    msmWriteFile(MSM.INDEX_FILE, msmEncodeJSON({ scenes = Storage.names }))
end

local function sortNames()
    table.sort(Storage.names, function(a, b) return a:lower() < b:lower() end)
end

-- Re-reads the index and every scene file (summaries only).
function Storage.reload()
    Storage.names, Storage.summary = {}, {}
    local index = msmDecodeJSON(msmReadFile(MSM.INDEX_FILE) or "")
    local list = index and (index.scenes or index) or {}
    local missing, formatted = 0, 0

    for _, name in ipairs(type(list) == "table" and list or {}) do
        name = tostring(name):gsub("%.json$", "")
        if msmValidName(name) and not Storage.summary[name] then
            local content = msmReadFile(scenePath(name))
            local data = msmDecodeJSON(content)
            if data then
                local scene = Storage.normalize(data, name)
                Storage.names[#Storage.names + 1] = name
                Storage.summary[name] = makeSummary(name, scene)
                -- older / hand-edited files are rewritten in the editor's format (key order, layout)
                local json = msmEncodeJSON(scene)
                if json and json ~= content then
                    msmWriteFile(scenePath(name), json)
                    formatted = formatted + 1
                end
            else
                missing = missing + 1
                msmLog("scene '%s' is listed in the index but %s could not be read", name, scenePath(name))
            end
        end
    end
    sortNames()
    -- reformat the index too, but never drop the entries of files that could not be read
    if not index or (missing == 0 and msmEncodeJSON({ scenes = Storage.names }) ~= msmReadFile(MSM.INDEX_FILE)) then
        writeIndex()
    end
    msmLog("%d scene(s) loaded%s%s", #Storage.names,
        formatted > 0 and (", " .. formatted .. " file(s) reformatted") or "",
        missing > 0 and (" (" .. missing .. " unreadable)") or "")
    return #Storage.names
end

function Storage.exists(name)
    return Storage.summary[name] ~= nil
end

function Storage.list()
    local out = {}
    for _, name in ipairs(Storage.names) do out[#out + 1] = Storage.summary[name] end
    return out
end

-- Full scene data straight from the file -> scene | nil, error
function Storage.load(name)
    if not msmValidName(name) then return nil, "Invalid scene name" end
    local data = msmDecodeJSON(msmReadFile(scenePath(name)))
    if not data then return nil, "Scene file not found or invalid: " .. scenePath(name) end
    return Storage.normalize(data, name)
end

-- Writes the scene file and updates the index + summary -> true | false, error
function Storage.save(name, scene)
    if not msmValidName(name) then return false, "Invalid name (letters, digits, _ and -, max " .. MSM.NAME_MAX .. ")" end
    scene = Storage.normalize(scene, name)
    local json = msmEncodeJSON(scene)
    if not json or not msmWriteFile(scenePath(name), json) then
        return false, "Could not write " .. scenePath(name)
    end
    if not Storage.summary[name] then
        Storage.names[#Storage.names + 1] = name
        sortNames()
    end
    Storage.summary[name] = makeSummary(name, scene)
    writeIndex()
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    Storage.reload()
end, true, "high")
