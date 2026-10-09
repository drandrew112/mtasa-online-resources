-- Scene files: scenes/<Location folder>/[<category>/]<name>.json, listed in scenes/index.json
-- as paths relative to scenes/ without .json (e.g. "Los_Santos/heartattack/ls_heartattack1").
-- Scene names stay unique over all folders. The location folder is a slug (msmLocationFolder)
-- of the scene's human-readable "location" key (e.g. "San Fierro", chosen in the editor,
-- suggested from the centre - msmSuggestedLocation), the category from its "category" key;
-- both are applied on save, so a scene moves to its new folder when either changes.
--
-- On start every file is read once and only a short summary is kept in memory
-- (Storage.summary). The full data is read from the file again whenever a module
-- needs it (spawning, editing), so large scenes do not sit in memory.

Storage = {
    names = {},     -- ordered scene names (the index)
    summary = {},   -- [name] = { name, path, category, location, title, priority, center, interior, dimension, weight, enabled, peds, vehicles }
    paths = {},     -- [name] = path relative to scenes/, without .json
}

local FORMAT = 1

local function filePath(path)
    return MSM.SCENE_DIR .. path .. ".json"
end

-- Index entry -> path, scene name | nil. Every folder must be a plain name (no "..").
local function parseEntry(entry)
    local path = tostring(entry):gsub("\\", "/"):gsub("%.json$", "")
    if path:sub(1, 1) == "/" or path:sub(-1) == "/" or path:find("//", 1, true) then return nil end
    local name
    for part in path:gmatch("[^/]+") do
        if not part:match(MSM.NAME_PATTERN) then return nil end
        name = part
    end
    if not msmValidName(name) then return nil end
    return path, name
end

-- Where a scene belongs: <Location folder>/[<category>/]<name>
function Storage.pathFor(name, scene)
    local folder = (tonumber(scene.interior) or 0) ~= 0 and MSM.INTERIOR_FOLDER or msmLocationFolder(scene.location)
    if scene.category ~= "" then folder = folder .. "/" .. scene.category end
    return folder .. "/" .. name
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
    local center = vec3(data.center, { 0, 0, 3 })
    local interior = math.floor(num(data.interior, 0))
    -- older files (saved before "location" existed) fall back to the centre's zone
    local location = msmValidLocation(data.location) and data.location or msmSuggestedLocation(center, interior)
    local scene = {
        format = FORMAT,
        name = name or data.name,
        category = msmCategory(data.category, name or data.name),
        location = location,
        enabled = data.enabled ~= false,
        weight = math.max(0, num(data.weight, 1)),
        center = center,
        interior = interior,
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
        path = Storage.paths[name],
        category = scene.category,
        location = scene.location,
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

local function indexJSON()
    local paths = {}
    for i, name in ipairs(Storage.names) do paths[i] = Storage.paths[name] end
    table.sort(paths, function(a, b) return a:lower() < b:lower() end)
    return msmEncodeJSON({ scenes = paths })
end

local function writeIndex()
    msmWriteFile(MSM.INDEX_FILE, indexJSON())
end

local function sortNames()
    table.sort(Storage.names, function(a, b) return a:lower() < b:lower() end)
end

-- Re-reads the index and every scene file (summaries only).
function Storage.reload()
    Storage.names, Storage.summary, Storage.paths = {}, {}, {}
    local index = msmDecodeJSON(msmReadFile(MSM.INDEX_FILE) or "")
    local list = index and (index.scenes or index) or {}
    local missing, formatted = 0, 0

    for _, entry in ipairs(type(list) == "table" and list or {}) do
        local path, name = parseEntry(entry)
        if not path then
            msmLog("invalid index entry '%s' skipped", tostring(entry))
        elseif Storage.summary[name] then
            msmLog("duplicate scene name '%s': %s skipped", name, filePath(path))
        else
            local content = msmReadFile(filePath(path))
            local data = msmDecodeJSON(content)
            if data then
                local scene = Storage.normalize(data, name)
                Storage.names[#Storage.names + 1] = name
                Storage.paths[name] = path
                Storage.summary[name] = makeSummary(name, scene)
                -- older / hand-edited files are rewritten in the editor's format (key order, layout)
                local json = msmEncodeJSON(scene)
                if json and json ~= content then
                    msmWriteFile(filePath(path), json)
                    formatted = formatted + 1
                end
            else
                missing = missing + 1
                msmLog("scene '%s' is listed in the index but %s could not be read", name, filePath(path))
            end
        end
    end
    sortNames()
    -- reformat the index too, but never drop the entries of files that could not be read
    if not index or (missing == 0 and indexJSON() ~= msmReadFile(MSM.INDEX_FILE)) then
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

-- Every location folder currently in use, for the editor's picker (existing ones + the
-- interior folder; a new one is free text, see msmValidLocation).
function Storage.locations()
    local set = {}
    for _, s in pairs(Storage.summary) do set[s.location] = true end
    local list = {}
    for folder in pairs(set) do list[#list + 1] = folder end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

-- Full scene data straight from the file -> scene | nil, error
function Storage.load(name)
    if not msmValidName(name) then return nil, "Invalid scene name" end
    local path = Storage.paths[name]
    if not path then return nil, "Unknown scene: " .. name end
    local data = msmDecodeJSON(msmReadFile(filePath(path)))
    if not data then return nil, "Scene file not found or invalid: " .. filePath(path) end
    return Storage.normalize(data, name)
end

-- File of a loaded scene (scenes/.../<name>.json) or nil
function Storage.file(name)
    return Storage.paths[name] and filePath(Storage.paths[name])
end

-- Writes the scene file into its settlement / category folder (the old file is removed
-- when that changed) and updates the index + summary -> true, file | false, error
function Storage.save(name, scene)
    if not msmValidName(name) then return false, "Invalid name (letters, digits, _ and -, max " .. MSM.NAME_MAX .. ")" end
    scene = Storage.normalize(scene, name)
    local path = Storage.pathFor(name, scene)
    local json = msmEncodeJSON(scene)
    if not json or not msmWriteFile(filePath(path), json) then
        return false, "Could not write " .. filePath(path)
    end
    local old = Storage.paths[name]
    if old and old ~= path and fileExists(filePath(old)) then
        fileDelete(filePath(old))
        msmLog("scene '%s' moved: %s -> %s", name, filePath(old), filePath(path))
    end
    Storage.paths[name] = path
    if not Storage.summary[name] then
        Storage.names[#Storage.names + 1] = name
        sortNames()
    end
    Storage.summary[name] = makeSummary(name, scene)
    writeIndex()
    return true, filePath(path)
end

addEventHandler("onResourceStart", resourceRoot, function()
    Storage.reload()
end, true, "high")
