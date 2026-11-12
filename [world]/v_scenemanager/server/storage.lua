-- Scene files: scenes/<Location folder>/[<category>/]<name>.json, listed in scenes/index.json
-- as paths relative to scenes/ without .json (e.g. "Los_Santos/heartattack/ls_heartattack1").
-- Scene names stay unique over all folders. The location folder is a slug (vsmLocationFolder)
-- of the scene's human-readable "location" key (e.g. "San Fierro", chosen in the editor,
-- suggested from the centre - vsmSuggestedLocation), the category from its "category" key;
-- both are applied on save, so a scene moves to its new folder when either changes.
--
-- Format 2 (2026-11-02): the old "erm" block became agencies.ems (need 2); agencies.pd is new. Format 1 files are
-- converted on load (and rewritten in format 2 by Storage.reload, like every differently formatted file).
--
-- On start every file is read once and only a short summary is kept in memory
-- (Storage.summary). The full data is read from the file again whenever a module
-- needs it (spawning, editing), so large scenes do not sit in memory.

Storage = {
    names = {},     -- ordered scene names (the index)
    summary = {},   -- [name] = { name, path, category, location, title, priority, center, interior, dimension, weight,
                    --            enabled, peds, vehicles, needs = { ems, pd }, safe, valid, errors, warnings }
    paths = {},     -- [name] = path relative to scenes/, without .json
}

local FORMAT = 2

local function filePath(path)
    return VSM.SCENE_DIR .. path .. ".json"
end

-- Index entry -> path, scene name | nil. Every folder must be a plain name (no "..").
local function parseEntry(entry)
    local path = tostring(entry):gsub("\\", "/"):gsub("%.json$", "")
    if path:sub(1, 1) == "/" or path:sub(-1) == "/" or path:find("//", 1, true) then return nil end
    local name
    for part in path:gmatch("[^/]+") do
        if not part:match(VSM.NAME_PATTERN) then return nil end
        name = part
    end
    if not vsmValidName(name) then return nil end
    return path, name
end

-- Where a scene belongs: <Location folder>/[<category>/]<name>
function Storage.pathFor(name, scene)
    local folder = (tonumber(scene.interior) or 0) ~= 0 and VSM.INTERIOR_FOLDER or vsmLocationFolder(scene.location)
    if scene.category ~= "" then folder = folder .. "/" .. scene.category end
    return folder .. "/" .. name
end

local function num(value, default)
    return tonumber(value) or default
end

local function int(value, default, lo, hi)
    local n = math.floor(num(value, default))
    if lo and n < lo then n = lo end
    if hi and n > hi then n = hi end
    return n
end

local function vec3(value, default)
    if type(value) ~= "table" then return default end
    return { num(value[1] or value.x, 0), num(value[2] or value.y, 0), num(value[3] or value.z, 0) }
end

local function oneOf(value, list, default)
    for _, v in ipairs(list) do
        if v == value then return value end
    end
    return default
end

-- number or { min, max } (sorted, clamped) -> number | { a, b } | nil
local function range(value, lo, hi, decimals)
    local a, b
    if type(value) == "table" then a, b = tonumber(value[1]), tonumber(value[2] or value[1])
    else a = tonumber(value); b = a end
    if not a then return nil end
    a, b = math.max(lo, math.min(hi, a)), math.max(lo, math.min(hi, b))
    if a > b then a, b = b, a end
    a, b = vsmRound(a, decimals or 0), vsmRound(b, decimals or 0)
    if a == b then return a end
    return { a, b }
end

local function bool(value, default)
    if value == nil then return default end
    return value == true
end

---------------------------------------------------------------- agencies

local function normalizeAgency(id, block, legacy)
    block = type(block) == "table" and block or {}
    local default = legacy and 2 or 0
    local out = {
        need = int(block.need, default, 0, 2),
        priority = int(block.priority, VSM.DEFAULT_PRIORITY, 1, 4),
        lateJoin = block.lateJoin ~= false,
        locales = vsmNormalizeLocales(block),
    }
    if id == "ems" then out.caller = tostring(block.caller or VSM.DEFAULT_CALLER) end
    if id == "pd" and type(block.close) == "table" then
        local close = {}
        for _, k in ipairs(VSM_PD_CLOSE) do
            if block.close[k] == true then close[k] = true end
        end
        if next(close) then out.close = close end
    end
    -- a not needed agency without texts stays a one-liner in the file
    if out.need == 0 and not next(out.locales) then return { need = 0 } end
    return out
end

-- complete agencies table (every id of VSM.AGENCY_ORDER) from a decoded file
local function normalizeAgencies(data)
    local src = type(data.agencies) == "table" and data.agencies or {}
    local out = {}
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        local legacy = id == "ems" and src.ems == nil and type(data.erm) == "table"
        out[id] = normalizeAgency(id, legacy and data.erm or src[id], legacy)
    end
    return out
end

-- full block of an agency (defaults filled in, also for a { need = 0 } one-liner)
function Storage.agency(scene, id)
    local b = scene.agencies and scene.agencies[id] or {}
    return {
        need = b.need or 0, priority = b.priority or VSM.DEFAULT_PRIORITY, caller = b.caller or VSM.DEFAULT_CALLER,
        lateJoin = b.lateJoin ~= false, locales = b.locales or {}, close = b.close or {},
    }
end

---------------------------------------------------------------- peds / vehicles

local function normalizeAI(role, ai)
    ai = type(ai) == "table" and ai or {}
    local weapons = VSM_WEAPONS
    if role == "fighter" then
        return {
            side = oneOf(ai.side, { "a", "b" }, "a"),
            weapon = oneOf(int(ai.weapon, 0), weapons, 0),
            start = oneOf(ai.start, VSM_FIGHT_START, "unit_near"),
            startRadius = int(ai.startRadius, VSM.NPC.FIGHT_START_RADIUS, 20, 500),
            onPolice = oneOf(ai.onPolice, VSM_ON_POLICE, "flee"),
        }
    elseif role == "hostile" then
        return {
            targets = oneOf(ai.targets, VSM_TARGETS, "police"),
            weapon = oneOf(int(ai.weapon, 22), weapons, 22),
            ammo = int(ai.ammo, 60, 0, 9999),
            accuracy = vsmRound(math.max(0, math.min(1, num(ai.accuracy, 0.35))), 2),
            aggroRadius = int(ai.aggroRadius, 35, 5, 200),
            leash = int(ai.leash, 40, 5, 300),
            task = oneOf(ai.task, VSM_HOSTILE_TASKS, "guard"),
            surrenderHealth = int(ai.surrenderHealth, 30, 0, 99),
            flee = vsmRound(math.max(0, math.min(1, num(ai.flee, 0))), 2),
        }
    elseif role == "hostage" then
        return { pose = oneOf(ai.pose, VSM_HOSTAGE_POSES, "cower") }
    elseif role == "suspect" then
        return {
            weapon = oneOf(int(ai.weapon, 0), weapons, 0),
            ammo = int(ai.ammo, 0, 0, 9999),
            flee = vsmRound(math.max(0, math.min(1, num(ai.flee, 0.5))), 2),
        }
    end
    return nil
end

local function normalizeDescription(d)
    local out = {}
    if type(d) == "string" and d ~= "" then out.en = d end
    if type(d) == "table" then
        for code, text in pairs(d) do
            if type(code) == "string" and code:match("^%l%l") and type(text) == "string" and text ~= "" then out[code] = text end
        end
    end
    return out
end

local function normalizeRecord(r)
    if type(r) ~= "table" then return nil end
    local out = {}
    if type(r.name) == "string" and r.name ~= "" then out.name = vsmCleanText(r.name, 48) end
    if type(r.birth) == "string" and r.birth:match("^%d%d%d%d%-%d%d%-%d%d$") then out.birth = r.birth
    else out.age = range(r.age, 18, 90) end
    local f = type(r.flags) == "table" and r.flags or {}
    local flags = {}
    if f.licence ~= nil then flags.licence = oneOf(f.licence, VSM_LICENCES, "valid") end
    local bac = range(f.bac, 0, VSM_BAC_MAX, 2)
    if bac and bac ~= 0 then flags.bac = bac end
    if f.drug and vsmDrugById(f.drug) then flags.drug = f.drug end
    if f.flee ~= nil then flags.flee = f.flee == true end
    if next(flags) then out.flags = flags end
    local past = {}
    for _, p in ipairs(type(r.past) == "table" and r.past or {}) do
        if type(p) == "table" and type(p.btk) == "string" and (p.type == "fine" or p.type == "warning") then
            past[#past + 1] = { type = p.type, btk = p.btk, daysAgo = range(p.daysAgo, 1, 3650) or { 10, 400 } }
        end
    end
    if #past > 0 then out.past = past end
    local warrants = {}
    for _, w in ipairs(type(r.warrants) == "table" and r.warrants or {}) do
        if type(w) == "table" and type(w.reasons) == "table" and #w.reasons > 0 then
            local reasons = {}
            for _, id in ipairs(w.reasons) do reasons[#reasons + 1] = tostring(id) end
            warrants[#warrants + 1] = { reasons = reasons, description = normalizeDescription(w.description) }
        end
    end
    if #warrants > 0 then out.warrants = warrants end
    if r.announce == true then out.announce = true end
    if r.persistent == true then out.persistent = true end
    if not next(out) then return nil end
    return out
end

local function normalizeVehicleRecord(r)
    if type(r) ~= "table" then return nil end
    local out = {}
    if r.stolen == true then out.stolen = true end
    if type(r.owner) == "string" and r.owner ~= "" and r.owner ~= "random" then out.owner = r.owner end
    if r.inspection == "expired" then out.inspection = "expired" end
    if not next(out) then return nil end
    return out
end

-- the role of a ped entry: stored, else from its medical data (patient / bystander)
local function pedRole(p)
    if vsmRoleById(p.role) then return p.role end
    if (type(p.injuries) == "table" and #p.injuries > 0) or (type(p.state) == "table" and next(p.state)) then return "patient" end
    return "bystander"
end

---------------------------------------------------------------- data shape

-- Returns a complete, valid scene table from anything decoded out of a file.
function Storage.normalize(data, name)
    data = type(data) == "table" and data or {}
    local center = vec3(data.center, { 0, 0, 3 })
    local interior = math.floor(num(data.interior, 0))
    -- older files (saved before "location" existed) fall back to the centre's zone
    local location = vsmValidLocation(data.location) and data.location or vsmSuggestedLocation(center, interior)
    local scene = {
        format = FORMAT,
        name = name or data.name,
        category = vsmCategory(data.category, name or data.name),
        location = location,
        enabled = data.enabled ~= false,
        weight = math.max(0, num(data.weight, 1)),
        center = center,
        interior = interior,
        dimension = math.floor(num(data.dimension, 0)),
        safe = data.safe ~= false,
        agencies = normalizeAgencies(data),
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
            local entry = vsmCopy(v)
            entry.id = uniqueId("v", v.id)
            entry.model = math.floor(tonumber(v.model))
            entry.pos = vec3(v.pos, { 0, 0, 3 })
            entry.rot = vec3(v.rot, { 0, 0, 0 })
            entry.tow = v.tow == true or nil
            entry.record = normalizeVehicleRecord(v.record)
            scene.vehicles[#scene.vehicles + 1] = entry
        end
    end

    for _, p in ipairs(type(data.peds) == "table" and data.peds or {}) do
        if type(p) == "table" then
            local entry = vsmCopy(p)
            entry.id = uniqueId("p", p.id)
            entry.skin = math.floor(num(p.skin, 0))
            entry.pos = vec3(p.pos, { 0, 0, 3 })
            entry.rot = num(p.rot, 0)
            entry.anim = vsmAnimById(p.anim) and p.anim or "none"
            entry.injuries = {}
            for _, inj in ipairs(type(p.injuries) == "table" and p.injuries or {}) do
                local sev = math.floor(num(inj.severity or inj[2], 0))
                local typ = inj.type or inj[1]
                if typ and sev >= 1 and sev <= 3 then
                    -- body part + side (medsys shared/body.lua), kept when valid
                    local part = VSM_PART_BY_ID[inj.part] and inj.part or nil
                    local side = part and VSM_PART_BY_ID[part].sided and (inj.side == "left" or inj.side == "right") and inj.side or nil
                    entry.injuries[#entry.injuries + 1] = { type = tostring(typ), severity = sev, part = part, side = side }
                end
            end
            entry.state = type(p.state) == "table" and p.state or {}
            entry.role = pedRole(p)
            entry.ai = normalizeAI(entry.role, p.ai)
            entry.record = normalizeRecord(p.record)
            scene.peds[#scene.peds + 1] = entry
        end
    end

    -- vehicle owners that are no scene ped any more
    for _, v in ipairs(scene.vehicles) do
        if v.record and v.record.owner and v.record.owner ~= "none" and not usedIds[v.record.owner] then
            v.record.owner = nil
            if not next(v.record) then v.record = nil end
        end
    end
    return scene
end

---------------------------------------------------------------- validation

-- -> { { level = "error" | "warning", key = v_locals key, params }, ... }. Errors keep a scene from the generator
-- and from being saved in the editor; warnings are only shown.
function Storage.validate(scene)
    local out = {}
    local function add(level, key, params) out[#out + 1] = { level = level, key = "v_scenemanager.valid." .. key, params = params or {} } end
    local needs, any = {}, false
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        local b = Storage.agency(scene, id)
        needs[id] = b.need
        if b.need > 0 then
            any = true
            for _, lang in ipairs(VSM.LANGS) do
                local e = b.locales[lang]
                if not e or (e.title or "") == "" then
                    add("error", "missing_title", { agency = id:upper(), lang = lang:upper() })
                elseif (e.description or "") == "" then
                    add("warning", "missing_description", { agency = id:upper(), lang = lang:upper() })
                end
            end
        end
    end
    if not any then add("error", "no_agency") end
    -- not safe: EMS 2 + PD 2, or (hostage situations, 2026-11-12) PD 2 with EMS 1 at least
    if scene.safe == false and not (needs.pd == 2 and needs.ems >= 1) then add("error", "unsafe_needs_both") end

    local sides, threats, hostages, hostiles = {}, 0, 0, 0
    for _, p in ipairs(scene.peds) do
        local role = vsmRoleById(p.role)
        if role and role.threat then threats = threats + 1 end
        if p.role == "hostage" then
            hostages = hostages + 1
            if needs.pd ~= 2 then add("error", "hostage_needs_pd", { id = p.id }) end
        end
        if p.role == "hostile" then
            hostiles = hostiles + 1
            if needs.pd ~= 2 then add("error", "hostile_needs_pd", { id = p.id }) end
            if p.ai and p.ai.targets == "all" and scene.safe ~= false then add("error", "hostile_all_needs_unsafe", { id = p.id }) end
        elseif p.role == "fighter" and p.ai then
            sides[p.ai.side] = (sides[p.ai.side] or 0) + 1
        end
        if p.role ~= "patient" and p.role ~= "bystander" and p.vehicle then add("warning", "ai_ped_seated", { id = p.id }) end
        local r = p.record
        for _, w in ipairs(r and r.warrants or {}) do
            for _, reason in ipairs(w.reasons) do
                if not Storage.isWarrantReason(reason) then add("error", "bad_warrant_reason", { id = p.id, reason = reason }) end
            end
            for _, lang in ipairs(VSM.LANGS) do
                if (w.description[lang] or "") == "" then add("warning", "missing_warrant_text", { id = p.id, lang = lang:upper() }) end
            end
        end
        for _, past in ipairs(r and r.past or {}) do
            if not Storage.isPenalItem(past.btk) then add("error", "bad_penal_item", { id = p.id, item = past.btk }) end
        end
    end
    if (sides.a or 0) + (sides.b or 0) > 0 and ((sides.a or 0) == 0 or (sides.b or 0) == 0) then add("error", "fight_one_side") end
    if scene.safe == false and threats == 0 then add("warning", "unsafe_without_threat") end
    if hostages > 0 and hostiles == 0 then add("error", "hostage_without_hostile") end
    if hostages > 0 and scene.safe ~= false then add("error", "hostage_needs_unsafe") end
    for _, v in ipairs(scene.vehicles) do
        if v.tow and needs.pd == 0 then add("warning", "tow_without_pd", { id = v.id }) end
        if v.record and v.record.stolen and v.record.owner and v.record.owner ~= "none" then
            add("error", "stolen_own_vehicle", { id = v.id })
        end
    end
    return out
end

-- penal code lookups of police_system (shared btk.json); without police_system every id is accepted
local penal
local function loadPenal()
    if penal then return penal end
    if not vsmResourceRunning(VSM.POLICE) then return nil end
    local ok, list = pcall(function() return exports[VSM.POLICE]:getPenalItems() end)
    if ok and type(list) == "table" then penal = list end
    return penal
end

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == VSM.POLICE then penal = nil end
end)

function Storage.isWarrantReason(id)
    local p = loadPenal()
    if not p then return true end
    return p.warrant[id] == true
end

function Storage.isPenalItem(id)
    local p = loadPenal()
    if not p then return true end
    return p.items[id] ~= nil
end

function Storage.countIssues(list)
    local errors, warnings = 0, 0
    for _, i in ipairs(list) do
        if i.level == "error" then errors = errors + 1 else warnings = warnings + 1 end
    end
    return errors, warnings
end

---------------------------------------------------------------- summaries

local function firstTitle(scene, lang)
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        local b = scene.agencies[id]
        if b and b.need and b.need > 0 and b.locales and b.locales[lang] and (b.locales[lang].title or "") ~= "" then
            return b.locales[lang].title
        end
    end
    local ems = scene.agencies.ems
    return ems and ems.locales and ems.locales[lang] and ems.locales[lang].title or ""
end

local function makeSummary(name, scene)
    local needs, priority = {}, nil
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        local b = Storage.agency(scene, id)
        needs[id] = b.need
        if b.need > 0 and (not priority or b.priority < priority) then priority = b.priority end
    end
    local errors, warnings = Storage.countIssues(Storage.validate(scene))
    local threats = 0
    for _, p in ipairs(scene.peds) do
        local role = vsmRoleById(p.role)
        if role and role.threat then threats = threats + 1 end
    end
    return {
        name = name,
        path = Storage.paths[name],
        category = scene.category,
        location = scene.location,
        title = firstTitle(scene, "en"),
        titles = { en = firstTitle(scene, "en"), hu = firstTitle(scene, "hu") },
        priority = priority or VSM.DEFAULT_PRIORITY,
        center = { scene.center[1], scene.center[2], scene.center[3] },
        interior = scene.interior,
        dimension = scene.dimension,
        weight = scene.weight,
        enabled = scene.enabled,
        peds = #scene.peds,
        vehicles = #scene.vehicles,
        threats = threats,
        needs = needs,
        safe = scene.safe ~= false,
        valid = errors == 0,
        errors = errors,
        warnings = warnings,
    }
end

-- summary of a scene for a language ("en" | "hu"): title of that language
function Storage.title(summary, lang)
    local t = summary.titles and summary.titles[lang]
    return (t and t ~= "") and t or summary.title or ""
end

---------------------------------------------------------------- index

local function indexJSON()
    local paths = {}
    for i, name in ipairs(Storage.names) do paths[i] = Storage.paths[name] end
    table.sort(paths, function(a, b) return a:lower() < b:lower() end)
    return vsmEncodeJSON({ scenes = paths })
end

local function writeIndex()
    vsmWriteFile(VSM.INDEX_FILE, indexJSON())
end

local function sortNames()
    table.sort(Storage.names, function(a, b) return a:lower() < b:lower() end)
end

-- Re-reads the index and every scene file (summaries only).
function Storage.reload()
    Storage.names, Storage.summary, Storage.paths = {}, {}, {}
    local index = vsmDecodeJSON(vsmReadFile(VSM.INDEX_FILE) or "")
    local list = index and (index.scenes or index) or {}
    local missing, formatted, invalid = 0, 0, 0

    for _, entry in ipairs(type(list) == "table" and list or {}) do
        local path, name = parseEntry(entry)
        if not path then
            vsmLog("invalid index entry '%s' skipped", tostring(entry))
        elseif Storage.summary[name] then
            vsmLog("duplicate scene name '%s': %s skipped", name, filePath(path))
        else
            local content = vsmReadFile(filePath(path))
            local data = vsmDecodeJSON(content)
            if data then
                local scene = Storage.normalize(data, name)
                Storage.names[#Storage.names + 1] = name
                Storage.paths[name] = path
                Storage.summary[name] = makeSummary(name, scene)
                if not Storage.summary[name].valid then invalid = invalid + 1 end
                -- older / hand-edited files are rewritten in the editor's format (key order, layout, format 2)
                local json = vsmEncodeJSON(scene)
                if json and json ~= content then
                    vsmWriteFile(filePath(path), json)
                    formatted = formatted + 1
                end
            else
                missing = missing + 1
                vsmLog("scene '%s' is listed in the index but %s could not be read", name, filePath(path))
            end
        end
    end
    sortNames()
    -- reformat the index too, but never drop the entries of files that could not be read
    if not index or (missing == 0 and indexJSON() ~= vsmReadFile(VSM.INDEX_FILE)) then
        writeIndex()
    end
    vsmLog("%d scene(s) loaded%s%s%s", #Storage.names,
        formatted > 0 and (", " .. formatted .. " file(s) reformatted") or "",
        invalid > 0 and (", " .. invalid .. " with validation errors (not used by the generator)") or "",
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
-- interior folder; a new one is free text, see vsmValidLocation).
function Storage.locations()
    local set = {}
    for _, s in pairs(Storage.summary) do set[s.location] = true end
    local list = {}
    for folder in pairs(set) do list[#list + 1] = folder end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

-- Full scene data straight from the file -> scene | nil, error (v_locals message)
function Storage.load(name)
    if not vsmValidName(name) then return nil, L.msg("v_scenemanager.err.invalid_name") end
    local path = Storage.paths[name]
    if not path then return nil, L.msg("v_scenemanager.err.unknown_scene", { name = name }) end
    local data = vsmDecodeJSON(vsmReadFile(filePath(path)))
    if not data then return nil, L.msg("v_scenemanager.err.file_invalid", { file = filePath(path) }) end
    return Storage.normalize(data, name)
end

-- File of a loaded scene (scenes/.../<name>.json) or nil
function Storage.file(name)
    return Storage.paths[name] and filePath(Storage.paths[name])
end

-- Writes the scene file into its settlement / category folder (the old file is removed
-- when that changed) and updates the index + summary -> true, file | false, error
function Storage.save(name, scene)
    if not vsmValidName(name) then return false, L.msg("v_scenemanager.err.invalid_name_rules", { max = VSM.NAME_MAX }) end
    scene = Storage.normalize(scene, name)
    local path = Storage.pathFor(name, scene)
    local json = vsmEncodeJSON(scene)
    if not json or not vsmWriteFile(filePath(path), json) then
        return false, L.msg("v_scenemanager.err.write_failed", { file = filePath(path) })
    end
    local old = Storage.paths[name]
    if old and old ~= path and fileExists(filePath(old)) then
        fileDelete(filePath(old))
        vsmLog("scene '%s' moved: %s -> %s", name, filePath(old), filePath(path))
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
