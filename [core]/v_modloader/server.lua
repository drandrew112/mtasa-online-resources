-- v_modloader (server): scans the model folders, validates the files, keeps meta.xml and
-- models.json up to date (/modloader update) and tells clients which mods to load.
-- One broken file never stops anything: it is logged, skipped and the rest goes on.

local META, TEMPLATE, META_TMP = "meta.xml", "meta.changethis.xml", "meta.new.xml"
local EXTS = { "dff", "txd", "col" }
local EXT_CODE = { dff = "d", txd = "t", col = "c" }

local served = {}           -- [category][id] = "dtc" subset, mods that are in meta.xml (downloaded by clients)
local pendingCount = 0      -- valid mods on disk that are not in meta.xml yet
local scanErrors = {}       -- last scan: error lines
local clientErrors = {}     -- [key] = { count = n, text = "..." }
local lastServed = {}       -- [player] = tick of last list sent

-- ---------------------------------------------------------------------------
-- Logging (console + logs/modloader.log)
-- ---------------------------------------------------------------------------

local logBuffer = {}

local function flushLog()
    if #logBuffer == 0 then return end
    local text = table.concat(logBuffer, "\n") .. "\n"
    logBuffer = {}
    pcall(function()
        local path = MODLOADER.LOG_FILE
        if fileExists(path) then
            local f = fileOpen(path)
            if f then
                local size = fileGetSize(f)
                fileClose(f)
                if size > MODLOADER.LOG_MAX then
                    if fileExists(path .. ".old") then fileDelete(path .. ".old") end
                    fileRename(path, path .. ".old")
                end
            end
        end
        local f = fileExists(path) and fileOpen(path) or fileCreate(path)
        if not f then return end
        fileSetPos(f, fileGetSize(f))
        fileWrite(f, text)
        fileClose(f)
    end)
end

local function log(level, msg)
    local t = getRealTime()
    logBuffer[#logBuffer + 1] = ("[%04d-%02d-%02d %02d:%02d:%02d] %-5s %s"):format(
        t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute, t.second, level, msg)
    outputServerLog("[modloader] " .. level .. ": " .. msg)
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

local function checkFile(path, ext)
    local ok, a, b = pcall(function()
        local f = fileOpen(path, true)
        if not f then return false, "cannot open file" end
        local size = fileGetSize(f)
        local head = size >= 4 and fileRead(f, 4) or ""
        fileClose(f)
        if size < 12 then return false, ("file too small (%d bytes)"):format(size) end
        if ext == "dff" and head ~= "\16\0\0\0" then return false, "not a valid DFF (bad header)" end
        if ext == "txd" and head ~= "\22\0\0\0" then return false, "not a valid TXD (bad header)" end
        if ext == "col" and head:sub(1, 3) ~= "COL" then return false, "not a valid COL (bad header)" end
        return true
    end)
    if not ok then return false, "check crashed: " .. tostring(a) end
    return a, b
end

--- Reads every category folder. Returns { mods = {[cat][id] = {dff=path,...}}, files = {paths}, errors = {}, warnings = {} }
local function scan()
    local res = { mods = {}, files = {}, errors = {}, warnings = {} }
    local function err(msg) res.errors[#res.errors + 1] = msg; log("ERROR", msg) end
    local function warn(msg) res.warnings[#res.warnings + 1] = msg; log("WARN", msg) end

    for _, cat in ipairs(MODLOADER.categories) do
        res.mods[cat.name] = {}
        local list = pathListDir and pathListDir(cat.name)
        if not list then
            err(("folder '%s' is missing or unreadable"):format(cat.name))
        else
            table.sort(list)
            for _, name in ipairs(list) do
                if name:sub(1, 1) ~= "." then
                    local path = cat.name .. "/" .. name
                    local num, ext = name:match("^(%d+)%.(%w+)$")
                    local id = tonumber(num)
                    if not id then
                        warn(path .. ": ignored (name must be <id>.dff / <id>.txd / <id>.col)")
                    elseif ext:lower() ~= ext or not EXT_CODE[ext] then
                        warn(path .. ": ignored (extension must be lowercase dff, txd or col)")
                    elseif tostring(id) ~= num then
                        warn(path .. ": ignored (remove the leading zeros from the ID)")
                    elseif id < cat.min or id > cat.max then
                        err(("%s: ID %d is outside the %s range (%d-%d)"):format(path, id, cat.name, cat.min, cat.max))
                    else
                        local ok, why = checkFile(path, ext)
                        if not ok then
                            err(path .. ": " .. why)
                        else
                            res.mods[cat.name][id] = res.mods[cat.name][id] or {}
                            res.mods[cat.name][id][ext] = path
                            res.files[#res.files + 1] = path
                        end
                    end
                end
            end
        end
    end
    return res
end

--- The <file src> entries of the current meta.xml as a set (nil when unreadable).
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
-- models.json (id -> readable name; GTA names are pre-filled, edit freely)
-- ---------------------------------------------------------------------------

local function jsonString(s)
    s = tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("[%c]", " ")
    return '"' .. s .. '"'
end

local function loadNames()
    if not fileExists(MODLOADER.NAMES_FILE) then return {} end
    local f = fileOpen(MODLOADER.NAMES_FILE, true)
    if not f then return nil end
    local text = fileRead(f, fileGetSize(f))
    fileClose(f)
    if text == "" then return {} end
    local data = fromJSON(text)
    if type(data) ~= "table" then return nil end
    local names = {}
    for cat, entries in pairs(data) do
        if type(entries) == "table" then
            names[cat] = {}
            for id, name in pairs(entries) do
                if tonumber(id) then names[cat][tostring(tonumber(id))] = tostring(name) end
            end
        end
    end
    return names
end

--- Adds every mod without an entry (GTA name when known); existing names are never touched.
local function syncNames(mods)
    local names = loadNames()
    if not names then
        log("ERROR", MODLOADER.NAMES_FILE .. " is not valid JSON - left untouched, fix it and run /modloader update again")
        return false
    end
    local added = 0
    for _, cat in ipairs(MODLOADER.categories) do
        names[cat.name] = names[cat.name] or {}
        for id in pairs(mods[cat.name] or {}) do
            local key = tostring(id)
            if names[cat.name][key] == nil then
                names[cat.name][key] = (GTA_NAMES[cat.name] and GTA_NAMES[cat.name][id]) or ""
                added = added + 1
            end
        end
    end

    local out = { "{" }
    for ci, cat in ipairs(MODLOADER.categories) do
        local ids = {}
        for key in pairs(names[cat.name]) do ids[#ids + 1] = tonumber(key) end
        table.sort(ids)
        out[#out + 1] = ("  %s: {"):format(jsonString(cat.name))
        for i, id in ipairs(ids) do
            out[#out + 1] = ("    %s: %s%s"):format(jsonString(id), jsonString(names[cat.name][tostring(id)]), i < #ids and "," or "")
        end
        out[#out + 1] = "  }" .. (ci < #MODLOADER.categories and "," or "")
    end
    out[#out + 1] = "}"

    local f = fileCreate(MODLOADER.NAMES_FILE)
    if not f then log("ERROR", "cannot write " .. MODLOADER.NAMES_FILE); return false end
    fileWrite(f, table.concat(out, "\n") .. "\n")
    fileClose(f)
    if added > 0 then log("INFO", ("%s: %d new model(s) added"):format(MODLOADER.NAMES_FILE, added)) end
    return true, added
end

-- ---------------------------------------------------------------------------
-- meta.xml regeneration
-- ---------------------------------------------------------------------------

--- Rebuilds meta.xml from meta.changethis.xml + every valid file on disk. Returns ok, text.
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
        if xmlNodeGetName(node) == "file" then xmlDestroyNode(node) end
    end
    local now = {}
    for _, path in ipairs(res.files) do
        local node = xmlCreateChild(root, "file")
        xmlNodeSetAttribute(node, "src", path)
        now[path] = true
    end
    xmlSaveFile(root)
    xmlUnloadFile(root)

    if not fileCopy(META_TMP, META, true) then return false, "cannot overwrite " .. META end
    fileDelete(META_TMP)

    local added, removed = 0, 0
    for p in pairs(now) do if not before[p] then added = added + 1 end end
    for p in pairs(before) do if not now[p] then removed = removed + 1 end end

    syncNames(res.mods)
    log("INFO", ("meta.xml rebuilt: %d file(s) (+%d / -%d), %d error(s), %d warning(s)"):format(
        #res.files, added, removed, #res.errors, #res.warnings))
    flushLog()
    return true, ("meta.xml rebuilt: %d file(s) (+%d / -%d), %d error(s), %d warning(s). Restart the resource to apply."):format(
        #res.files, added, removed, #res.errors, #res.warnings)
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    local res = scan()
    scanErrors = res.errors

    local inMeta = readMetaFiles()
    if not inMeta then
        log("ERROR", "cannot read meta.xml - no mods will be sent to clients")
        inMeta = {}
    end

    local total = 0
    for _, cat in ipairs(MODLOADER.categories) do
        served[cat.name] = {}
        for id, files in pairs(res.mods[cat.name]) do
            local codes, complete = "", true
            for _, ext in ipairs(EXTS) do
                if files[ext] then
                    if inMeta[files[ext]] then codes = codes .. EXT_CODE[ext] else complete = false end
                end
            end
            if complete then
                served[cat.name][id] = codes
                total = total + 1
            else
                pendingCount = pendingCount + 1
            end
        end
    end

    local valid = {}
    for _, p in ipairs(res.files) do valid[p] = true end
    for src in pairs(inMeta) do
        if (src:match("^%a+/%d+%.%a+$")) and not valid[src] then
            log("WARN", src .. " is listed in meta.xml but is missing/invalid on disk - run /modloader update")
        end
    end

    log("INFO", ("started: %d mod(s) active, %d pending (not in meta.xml), %d error(s)"):format(total, pendingCount, #res.errors))
    if pendingCount > 0 then
        log("WARN", "new mods found - run /modloader update, then restart the resource")
    end
    if not fileExists(MODLOADER.NAMES_FILE) then syncNames(res.mods) end
    flushLog()
end)

addEventHandler("onResourceStop", resourceRoot, flushLog)

-- ---------------------------------------------------------------------------
-- Client sync
-- ---------------------------------------------------------------------------

addEvent("modloader:request", true)
addEventHandler("modloader:request", resourceRoot, function()
    local player = client
    if not isElement(player) then return end
    local now = getTickCount()
    if lastServed[player] and now - lastServed[player] < 5000 then return end
    lastServed[player] = now
    triggerClientEvent(player, "modloader:mods", resourceRoot, served)
end)

addEventHandler("onPlayerQuit", root, function() lastServed[source] = nil end)

addEvent("modloader:report", true)
addEventHandler("modloader:report", resourceRoot, function(errors)
    local player = client
    if not isElement(player) or type(errors) ~= "table" then return end
    local name = getPlayerName(player)
    for i = 1, math.min(#errors, 200) do
        local line = errors[i]
        if type(line) == "string" then
            line = line:sub(1, 200):gsub("[%c]", " ")
            local entry = clientErrors[line]
            if entry then
                entry.count = entry.count + 1
            else
                clientErrors[line] = { count = 1 }
                log("ERROR", ("client %s: %s"):format(name, line))
            end
        end
    end
    flushLog()
end)

-- ---------------------------------------------------------------------------
-- /modloader
-- ---------------------------------------------------------------------------

local function say(player, text)
    if isElement(player) then outputConsole("[modloader] " .. text, player) else outputServerLog("[modloader] " .. text) end
end

local function allowed(player)
    if not isElement(player) then return true end
    if getElementData(player, "isLogged") ~= true then return false end
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(level) or 0) >= MODLOADER.ADMIN_LEVEL
end

addCommandHandler("modloader", function(player, _, sub)
    if not allowed(player) then return say(player, "Access denied.") end
    sub = tostring(sub or ""):lower()

    if sub == "update" then
        local ok, text = rebuildMeta()
        say(player, text)
    elseif sub == "status" then
        for _, cat in ipairs(MODLOADER.categories) do
            local n = 0
            for _ in pairs(served[cat.name] or {}) do n = n + 1 end
            say(player, ("%s (%d-%d): %d active"):format(cat.name, cat.min, cat.max, n))
        end
        local ce = 0
        for _ in pairs(clientErrors) do ce = ce + 1 end
        say(player, ("%d pending (not in meta.xml), %d scan error(s), %d distinct client error(s)"):format(pendingCount, #scanErrors, ce))
    elseif sub == "errors" then
        local shown = 0
        for _, line in ipairs(scanErrors) do say(player, line); shown = shown + 1 end
        for line, e in pairs(clientErrors) do say(player, ("client (x%d): %s"):format(e.count, line)); shown = shown + 1 end
        if shown == 0 then say(player, "No errors. Full history: " .. MODLOADER.LOG_FILE) end
    else
        say(player, "Usage: /modloader update | status | errors")
    end
end)
