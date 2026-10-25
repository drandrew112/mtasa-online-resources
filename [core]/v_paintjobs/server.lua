-- v_paintjobs (server): scans paintjobs/<model id>/, keeps meta.xml and manifest.json up to
-- date (/paintjobs update), sends clients the list and owns the paintjob of every vehicle.
--
-- The paintjob of a vehicle is the element data PAINTJOBS.DATA_KEY (= name). It is mirrored
-- into "customs:extras", so v_ownveh stores it with the vehicle and gives it back on spawn
-- (the extras change re-applies it here). Clients download a file the first time a vehicle
-- with that paintjob streams in.

local META, TEMPLATE, META_TMP = "meta.xml", "meta.changethis.xml", "meta.new.xml"
local FORMAT_RANK = {}
for i, ext in ipairs(PAINTJOBS.FORMATS) do FORMAT_RANK[ext] = i end

local served = {}           -- [model] = { t = texture pattern, j = { { n = name, l = label, p = path, f = texture format, s = size, h = md5 } } }
local byName = {}           -- [model][name] = entry of served[model].j
local scanErrors = {}
local lastServed = {}       -- [player] = tick of the last list sent

local function log(level, msg)
    outputServerLog("[paintjobs] " .. level .. ": " .. msg)
end

local function jsonString(s)
    s = tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("[%c]", " ")
    return '"' .. s .. '"'
end

local function readWhole(path)
    local ok, data = pcall(function()
        local f = fileOpen(path, true)
        if not f then return nil end
        local d = fileRead(f, fileGetSize(f))
        fileClose(f)
        return d
    end)
    if ok then return data end
end

-- ---------------------------------------------------------------------------
-- Image checks
-- ---------------------------------------------------------------------------

local function u32le(s, i) local a, b, c, d = s:byte(i, i + 3) return a + b * 256 + c * 65536 + d * 16777216 end
local function u32be(s, i) local a, b, c, d = s:byte(i, i + 3) return d + c * 256 + b * 65536 + a * 16777216 end
local function u16be(s, i) local a, b = s:byte(i, i + 1) return b + a * 256 end

local DDS_FORMATS = { DXT1 = "dxt1", DXT2 = "dxt3", DXT3 = "dxt3", DXT4 = "dxt5", DXT5 = "dxt5" }

--- Real format of the data (by its first bytes), its width / height and the dxCreateTexture
--- format the client loads it as (DDS keeps its compression, PNG may have alpha, JPEG has none).
local function imageInfo(data)
    if #data < 128 then return nil end
    if data:sub(1, 4) == "DDS " then
        return "dds", u32le(data, 17), u32le(data, 13), DDS_FORMATS[data:sub(85, 88)] or "argb"
    elseif data:sub(1, 8) == "\137PNG\r\n\26\n" then
        return "png", u32be(data, 17), u32be(data, 21), "dxt5"
    elseif data:sub(1, 3) == "\255\216\255" then
        -- walk the JPEG segments up to a start-of-frame marker
        local i = 3
        while i + 8 <= #data do
            if data:byte(i) ~= 255 then break end
            local marker = data:byte(i + 1)
            if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
                return "jpg", u16be(data, i + 7), u16be(data, i + 5), "dxt1"
            end
            i = i + 2 + u16be(data, i + 2)
        end
        return "jpg", nil, nil, "dxt1"
    end
end

local function isPow2(n)
    if not n or n < 1 then return false end
    while n % 2 == 0 do n = n / 2 end
    return n == 1
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

local function readModelConfig(dir)
    local path = dir .. "/_model.json"
    if not fileExists(path) then return {} end
    local text = readWhole(path)
    local data = text and fromJSON(text)
    if type(data) ~= "table" then
        log("ERROR", path .. ": not valid JSON - ignored")
        return {}
    end
    return data
end

--- Returns { models = { [id] = { texture, list = { {name, label, path} } } }, files = {paths}, errors = {} }
local function scan()
    local res = { models = {}, files = {}, errors = {} }
    local function err(msg) res.errors[#res.errors + 1] = msg; log("ERROR", msg) end

    local dirs = pathListDir and pathListDir(PAINTJOBS.FOLDER)
    if not dirs then
        err(("folder '%s' is missing or unreadable"):format(PAINTJOBS.FOLDER))
        return res
    end
    table.sort(dirs)
    for _, dirName in ipairs(dirs) do
        local dir = PAINTJOBS.FOLDER .. "/" .. dirName
        local id = tonumber(dirName)
        if dirName:sub(1, 1) == "." or not pathIsDirectory(dir) then
            -- stray file next to the model folders
        elseif not id or tostring(id) ~= dirName or id < 400 or id > 611 then
            err(dir .. ": ignored (the folder name must be a vehicle model ID, 400-611)")
        else
            local cfg = readModelConfig(dir)
            local names = type(cfg.names) == "table" and cfg.names or {}
            local best = {}     -- [name] = { path, rank }
            local files = pathListDir(dir) or {}
            table.sort(files)
            for _, fileName in ipairs(files) do
                local path = dir .. "/" .. fileName
                local name, ext = fileName:match("^(.+)%.(%w+)$")
                if fileName == "_model.json" or fileName:sub(1, 1) == "." then
                    -- config / hidden
                elseif not name or not FORMAT_RANK[ext] then
                    log("WARN", path .. ": ignored (extension must be lowercase " .. table.concat(PAINTJOBS.FORMATS, ", ") .. ")")
                elseif not name:match("^[a-z0-9_]+$") then
                    log("WARN", path .. ": ignored (name may only contain a-z, 0-9 and _)")
                else
                    local data = readWhole(path)
                    local real, w, h, texFormat = imageInfo(data or "")
                    if not real then
                        err(path .. ": not a DDS / PNG / JPEG image")
                    elseif w and (w > PAINTJOBS.MAX_SIZE or h > PAINTJOBS.MAX_SIZE) then
                        err(("%s: %dx%d is larger than %d"):format(path, w, h, PAINTJOBS.MAX_SIZE))
                    else
                        if real ~= ext then
                            log("WARN", ("%s: the file is a %s image - rename it to .%s"):format(path, real:upper(), real))
                        end
                        if w and not (isPow2(w) and isPow2(h)) then
                            log("WARN", ("%s: %dx%d is not a power of two"):format(path, w, h))
                        elseif w and (w > 1024 or h > 1024) then
                            log("INFO", ("%s: %dx%d (1024 is usually enough and 4x smaller)"):format(path, w, h))
                        end
                        local rank = FORMAT_RANK[ext]
                        if best[name] then
                            log("WARN", ("%s: '%s' exists in more formats, using .%s"):format(dir, name,
                                rank < best[name].rank and ext or best[name].path:match("%.(%w+)$")))
                        end
                        if not best[name] or rank < best[name].rank then
                            best[name] = { path = path, rank = rank, format = texFormat }
                        end
                    end
                end
            end

            local list = {}
            for name, b in pairs(best) do
                local label = names[name]
                list[#list + 1] = { name = name, label = type(label) == "string" and label ~= "" and label or name, path = b.path, format = b.format }
                res.files[#res.files + 1] = b.path
            end
            table.sort(list, function(a, b) return a.name < b.name end)
            if #list > 0 then
                res.models[id] = {
                    texture = type(cfg.texture) == "string" and cfg.texture ~= "" and cfg.texture or PAINTJOBS.DEFAULT_TEXTURE,
                    list = list,
                }
            end
        end
    end
    table.sort(res.files)
    return res
end

local function readMetaFiles()
    local root = xmlLoadFile(META)
    if not root then return nil end
    local set = {}
    for _, node in ipairs(xmlNodeGetChildren(root)) do
        if xmlNodeGetName(node) == "file" then
            local src = xmlNodeGetAttribute(node, "src")
            if src then set[src] = true end
        end
    end
    xmlUnloadFile(root)
    return set
end

-- ---------------------------------------------------------------------------
-- manifest.json (path -> size, md5); clients compare it with their downloads
-- ---------------------------------------------------------------------------

local function loadManifest()
    local text = fileExists(PAINTJOBS.MANIFEST_FILE) and readWhole(PAINTJOBS.MANIFEST_FILE)
    local data = text and text ~= "" and fromJSON(text)
    return type(data) == "table" and data or {}
end

local function saveManifest(manifest)
    local paths = {}
    for p in pairs(manifest) do paths[#paths + 1] = p end
    table.sort(paths)
    local out = { "{" }
    for i, p in ipairs(paths) do
        local e = manifest[p]
        out[#out + 1] = ('  %s: { "size": %d, "md5": %s }%s'):format(
            jsonString(p), tonumber(e.size) or 0, jsonString(e.md5 or ""), i < #paths and "," or "")
    end
    out[#out + 1] = "}"
    local f = fileCreate(PAINTJOBS.MANIFEST_FILE)
    if not f then log("ERROR", "cannot write " .. PAINTJOBS.MANIFEST_FILE); return end
    fileWrite(f, table.concat(out, "\n") .. "\n")
    fileClose(f)
end

--- rehash = hash every file (/paintjobs update), else only new files and changed sizes.
local function syncManifest(files, rehash)
    local manifest, changed, present = loadManifest(), false, {}
    for _, path in ipairs(files) do
        present[path] = true
        local e = manifest[path]
        local data = (not e or rehash or not e.md5 or e.md5 == "") and readWhole(path)
        if not data and e then
            local f = fileOpen(path, true)
            local size = f and fileGetSize(f)
            if f then fileClose(f) end
            if tonumber(e.size) ~= size then data = readWhole(path) end
        end
        if data then
            local hash = md5(data)
            if not e or e.md5 ~= hash or tonumber(e.size) ~= #data then
                manifest[path] = { size = #data, md5 = hash }
                changed = true
            end
        end
    end
    for path in pairs(manifest) do
        if not present[path] then manifest[path] = nil; changed = true end
    end
    if changed or not fileExists(PAINTJOBS.MANIFEST_FILE) then saveManifest(manifest) end
    return manifest
end

--- Rebuilds meta.xml from meta.changethis.xml + every valid paintjob. Returns ok, text.
local function rebuildMeta()
    local res = scan()
    local before = readMetaFiles() or {}

    local tpl = xmlLoadFile(TEMPLATE)
    if not tpl then return false, "cannot load " .. TEMPLATE end
    if fileExists(META_TMP) then fileDelete(META_TMP) end
    local root = xmlCopyFile(tpl, META_TMP)
    xmlUnloadFile(tpl)
    if not root then return false, "cannot create " .. META_TMP end

    for _, node in ipairs(xmlNodeGetChildren(root)) do
        if xmlNodeGetName(node) == "file" and (xmlNodeGetAttribute(node, "src") or ""):find("^" .. PAINTJOBS.FOLDER .. "/") then
            xmlDestroyNode(node)
        end
    end
    local now = {}
    for _, path in ipairs(res.files) do
        local node = xmlCreateChild(root, "file")
        xmlNodeSetAttribute(node, "src", path)
        xmlNodeSetAttribute(node, "download", "false")   -- the client asks for it (downloadFile)
        now[path] = true
    end
    xmlSaveFile(root)
    xmlUnloadFile(root)

    if not fileCopy(META_TMP, META, true) then return false, "cannot overwrite " .. META end
    fileDelete(META_TMP)

    local added, removed = 0, 0
    for p in pairs(now) do if not before[p] then added = added + 1 end end
    for p in pairs(before) do if not now[p] and p:find("^" .. PAINTJOBS.FOLDER .. "/") then removed = removed + 1 end end
    syncManifest(res.files, true)

    local text = ("meta.xml rebuilt: %d paintjob(s) (+%d / -%d), %d error(s). Restart the resource to apply."):format(
        #res.files, added, removed, #res.errors)
    log("INFO", text)
    return true, text
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    local res = scan()
    scanErrors = res.errors
    local inMeta = readMetaFiles() or {}
    local manifest = syncManifest(res.files, false)

    local total, pending = 0, 0
    for id, model in pairs(res.models) do
        local list = {}
        for _, pj in ipairs(model.list) do
            if inMeta[pj.path] then
                local e = manifest[pj.path] or {}
                list[#list + 1] = { n = pj.name, l = pj.label, p = pj.path, f = pj.format, s = tonumber(e.size) or 0, h = e.md5 or "" }
            else
                pending = pending + 1
            end
        end
        if #list > 0 then
            served[id] = { t = model.texture, j = list }
            byName[id] = {}
            for _, e in ipairs(list) do byName[id][e.n] = e end
            total = total + #list
        end
    end
    log("INFO", ("started: %d paintjob(s) active, %d pending (not in meta.xml), %d error(s)"):format(total, pending, #res.errors))
    if pending > 0 then log("WARN", "new paintjobs found - run /paintjobs update, then restart the resource") end

    -- vehicles that carry a paintjob from before a restart
    for _, veh in ipairs(getElementsByType("vehicle")) do
        local extras = getElementData(veh, "customs:extras")
        local name = getElementData(veh, PAINTJOBS.DATA_KEY) or (type(extras) == "table" and extras[PAINTJOBS.EXTRAS_KEY])
        if name then setVehicleCustomPaintjob(veh, name) end
    end
end)

-- ---------------------------------------------------------------------------
-- Vehicle paintjobs
-- ---------------------------------------------------------------------------

local function getExtras(veh)
    local t = getElementData(veh, "customs:extras")
    local copy = {}
    if type(t) == "table" then for k, v in pairs(t) do copy[k] = v end end
    return copy
end

--- Paintjobs of a model: { { name, label }, ... } sorted by name (empty when none).
function getPaintjobs(model)
    local out = {}
    local m = served[tonumber(model)]
    if m then
        for i, e in ipairs(m.j) do out[i] = { name = e.n, label = e.l } end
    end
    return out
end

function hasPaintjob(model, name)
    local m = byName[tonumber(model)]
    return m ~= nil and m[name] ~= nil
end

function getVehicleCustomPaintjob(veh)
    return isElement(veh) and getElementData(veh, PAINTJOBS.DATA_KEY) or false
end

--- name = paintjob of the vehicle's model, false / nil = remove. Returns true on success.
function setVehicleCustomPaintjob(veh, name)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return false end
    if name ~= nil and name ~= false and not hasPaintjob(getElementModel(veh), name) then return false end
    name = name or false

    local extras = getExtras(veh)
    local c = { getVehicleColor(veh, true) }
    if name then
        if PAINTJOBS.WHITE_PRIMARY and type(extras[PAINTJOBS.EXTRAS_COLOR]) ~= "table" then
            extras[PAINTJOBS.EXTRAS_COLOR] = { c[1], c[2], c[3] }
        end
        if PAINTJOBS.WHITE_PRIMARY and not (c[1] == 255 and c[2] == 255 and c[3] == 255) then
            c[1], c[2], c[3] = 255, 255, 255
            setVehicleColor(veh, unpack(c))
        end
        if getVehiclePaintjob(veh) ~= 3 then setVehiclePaintjob(veh, 3) end
        extras[PAINTJOBS.EXTRAS_KEY] = name
    else
        local old = extras[PAINTJOBS.EXTRAS_COLOR]
        if type(old) == "table" and tonumber(old[1]) then
            c[1], c[2], c[3] = tonumber(old[1]), tonumber(old[2]) or 0, tonumber(old[3]) or 0
            setVehicleColor(veh, unpack(c))
        end
        extras[PAINTJOBS.EXTRAS_KEY] = nil
        extras[PAINTJOBS.EXTRAS_COLOR] = nil
    end

    if getElementData(veh, PAINTJOBS.DATA_KEY) ~= name then
        setElementData(veh, PAINTJOBS.DATA_KEY, name or nil)
    end
    local cur = getElementData(veh, "customs:extras")
    local curName = type(cur) == "table" and cur[PAINTJOBS.EXTRAS_KEY] or false
    local curColor = type(cur) == "table" and cur[PAINTJOBS.EXTRAS_COLOR] or nil
    if curName ~= name or (curColor == nil) ~= (extras[PAINTJOBS.EXTRAS_COLOR] == nil) then
        setElementData(veh, "customs:extras", extras)   -- synced + captured by v_ownveh
    end
    return true
end

-- v_ownveh restores a stored vehicle by setting customs:extras (and firing
-- v_customs:applyExtras when v_customs runs): follow it
local function followExtras(veh, extras)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return end
    local name = type(extras) == "table" and extras[PAINTJOBS.EXTRAS_KEY] or false
    if name ~= (getElementData(veh, PAINTJOBS.DATA_KEY) or false) then
        if not setVehicleCustomPaintjob(veh, name) then setVehicleCustomPaintjob(veh, false) end
    end
end

addEventHandler("onElementDataChange", root, function(key, _, new)
    if key == "customs:extras" then followExtras(source, new) end
end)

addEvent("v_customs:applyExtras")
addEventHandler("v_customs:applyExtras", root, function(extras)
    followExtras(source, type(extras) == "table" and extras or getElementData(source, "customs:extras"))
end)

addEventHandler("onElementModelChange", root, function(_, newModel)
    if getElementType(source) ~= "vehicle" then return end
    local name = getElementData(source, PAINTJOBS.DATA_KEY)
    if name and not hasPaintjob(newModel, name) then setVehicleCustomPaintjob(source, false) end
end)

-- ---------------------------------------------------------------------------
-- Client sync
-- ---------------------------------------------------------------------------

addEvent("paintjobs:request", true)
addEventHandler("paintjobs:request", resourceRoot, function()
    local player = client
    if not isElement(player) then return end
    local now = getTickCount()
    if lastServed[player] and now - lastServed[player] < 5000 then return end
    lastServed[player] = now
    triggerClientEvent(player, "paintjobs:list", resourceRoot, served)
end)

addEventHandler("onPlayerQuit", root, function() lastServed[source] = nil end)

addEvent("paintjobs:report", true)
addEventHandler("paintjobs:report", resourceRoot, function(line)
    if isElement(client) and type(line) == "string" then
        log("ERROR", ("client %s: %s"):format(getPlayerName(client), line:sub(1, 200):gsub("[%c]", " ")))
    end
end)

-- ---------------------------------------------------------------------------
-- /paintjobs
-- ---------------------------------------------------------------------------

local function say(player, text)
    if isElement(player) then outputConsole("[paintjobs] " .. text, player) else outputServerLog("[paintjobs] " .. text) end
end

local function allowed(player)
    if not isElement(player) then return true end
    if getElementData(player, "isLogged") ~= true then return false end
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(level) or 0) >= PAINTJOBS.ADMIN_LEVEL
end

addCommandHandler("paintjobs", function(player, _, sub, arg)
    if not allowed(player) then return say(player, "Access denied.") end
    sub = tostring(sub or ""):lower()
    local veh = isElement(player) and getPedOccupiedVehicle(player)

    if sub == "update" then
        local _, text = rebuildMeta()
        say(player, text)
    elseif sub == "list" then
        local model = tonumber(arg) or (veh and getElementModel(veh))
        if not model then return say(player, "Usage: /paintjobs list <model> (or sit in a vehicle)") end
        local list = getPaintjobs(model)
        say(player, ("%d: %d paintjob(s), texture '%s'"):format(model, #list, served[model] and served[model].t or "-"))
        for _, pj in ipairs(list) do say(player, ("  %s (%s)"):format(pj.name, pj.label)) end
    elseif sub == "set" then
        if not veh then return say(player, "Sit in a vehicle first.") end
        local name = arg and arg ~= "none" and arg or false
        say(player, setVehicleCustomPaintjob(veh, name) and "Paintjob set." or "Unknown paintjob for this model (/paintjobs list).")
    elseif sub == "errors" then
        for _, line in ipairs(scanErrors) do say(player, line) end
        if #scanErrors == 0 then say(player, "No scan errors.") end
    else
        say(player, "Usage: /paintjobs update | list [model] | set <name|none> | errors")
    end
end)
