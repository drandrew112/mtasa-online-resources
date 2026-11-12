-- maps_loader (server): reads every map of maps/index.json once, drops duplicates, sends the maps to
-- the clients (they create the objects themselves, see client/main.lua) and keeps the list of extra
-- dimensions a map is loaded in (exports loadMapInDimension / unloadMapFromDimension).
--
-- Object record sent to the clients (array, booleans as 1 / 0, -1 = not set in the .map):
--   { model, x, y, z, rx, ry, rz, interior, dimension, scale, alpha, collisions, doublesided,
--     breakable, frozen, zone, keep }
--   zone = index of the settings.json "indoor" box the object is in (0 = none), keep = 1: always exists

local LOG_PREFIX = "[maps_loader] "
local maps = {}            -- array of { name, objects, removes, markers, zones, lod, bbox, stats }
local mapByName = {}
local payload = nil        -- what the clients get
local copies = {}          -- [name][dim] = { mode = "all" | "interior", users = { [owner] = count } }
local eventOn = {}         -- [name] = true: event map (settings.json "event") currently switched on

local function log(msg) outputServerLog(LOG_PREFIX .. msg) end

---------------------------------------------------------------------------- reading files

local function readText(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local text = fileRead(f, fileGetSize(f))
    fileClose(f)
    return text
end

local function flag(v)
    if v == nil then return -1 end
    return (v == "true" or v == "1") and 1 or 0
end

local function num(v, default)
    return tonumber(v) or default
end

local function inBox(z, x, y, h)
    return x >= z.min[1] and x <= z.max[1] and y >= z.min[2] and y <= z.max[2] and h >= z.min[3] and h <= z.max[3]
end

local function readSettings(name)
    local text = readText(MAPLOADER.MAPS_DIR .. "/" .. name .. "/settings.json")
    if not text then return {} end
    local data = fromJSON(text)
    if type(data) ~= "table" then
        log(name .. "/settings.json is not valid JSON - ignored")
        return {}
    end
    return data
end

-- -> map table, or nil + error
local function parseMap(name)
    local path = MAPLOADER.MAPS_DIR .. "/" .. name .. "/" .. name .. ".map"
    if not fileExists(path) then return nil, path .. " is missing" end
    local root = xmlLoadFile(path, true)
    if not root then return nil, path .. " is not valid XML" end

    local settings = readSettings(name)
    local zones = {}
    for i, z in ipairs(type(settings.indoor) == "table" and settings.indoor or {}) do
        if type(z.min) == "table" and type(z.max) == "table" then
            local keep = {}
            for _, m in ipairs(type(z.keep) == "table" and z.keep or {}) do keep[tonumber(m)] = true end
            zones[#zones + 1] = {
                name = tostring(z.name or ("zone " .. i)),
                min = { math.min(z.min[1], z.max[1]), math.min(z.min[2], z.max[2]), math.min(z.min[3], z.max[3]) },
                max = { math.max(z.min[1], z.max[1]), math.max(z.min[2], z.max[2]), math.max(z.min[3], z.max[3]) },
                margin = tonumber(z.margin) or MAPLOADER.INDOOR_MARGIN,
                keep = keep,
            }
        end
    end

    local m = { name = name, objects = {}, removes = {}, markers = {}, zones = zones,
                lod = settings.lod == "none" and "none" or "auto", disabled = settings.disabled == true,
                event = settings.event == true,
                stats = { objects = 0, removes = 0, markers = 0, indoor = 0, moving = 0, unknown = {} } }
    local bx1, by1, bx2, by2 = math.huge, math.huge, -math.huge, -math.huge
    local function grow(x, y)
        if x < bx1 then bx1 = x end
        if y < by1 then by1 = y end
        if x > bx2 then bx2 = x end
        if y > by2 then by2 = y end
    end

    for _, node in ipairs(xmlNodeGetChildren(root)) do
        local tag = xmlNodeGetName(node)
        local a = xmlNodeGetAttributes(node)
        if tag == "object" then
            local model = tonumber(a.model)
            local x, y, z = num(a.posX), num(a.posY), num(a.posZ)
            if model and x and y and z then
                if a.moveX or a.moveY or a.moveZ then m.stats.moving = m.stats.moving + 1 end
                local zoneIndex, keep = 0, 0
                local int = num(a.interior, 0)
                if int == 0 then
                    for i, zn in ipairs(zones) do
                        if inBox(zn, x, y, z) then
                            zoneIndex = i
                            keep = zn.keep[model] and 1 or 0
                            break
                        end
                    end
                end
                if zoneIndex > 0 and keep == 0 then m.stats.indoor = m.stats.indoor + 1 end
                m.objects[#m.objects + 1] = {
                    model, x, y, z, num(a.rotX, 0), num(a.rotY, 0), num(a.rotZ, 0),
                    int, num(a.dimension, 0), num(a.scale, 1), num(a.alpha, 255),
                    flag(a.collisions), flag(a.doublesided), flag(a.breakable), flag(a.frozen),
                    zoneIndex, keep,
                }
                grow(x, y)
            end
        elseif tag == "removeWorldObject" then
            local model = tonumber(a.model)
            if model then
                m.removes[#m.removes + 1] = { model, num(a.lodModel, 0), num(a.radius, 1), num(a.posX, 0),
                    num(a.posY, 0), num(a.posZ, 0), num(a.interior, -1) }
            end
        elseif tag == "marker" then
            local x, y, z = num(a.posX), num(a.posY), num(a.posZ)
            if x and y and z then
                m.markers[#m.markers + 1] = { tostring(a.type or "cylinder"), x, y, z, num(a.size, 1),
                    tostring(a.color or "#FFFFFFFF"), num(a.interior, 0), num(a.dimension, 0) }
                grow(x, y)
            end
        else
            m.stats.unknown[tag] = (m.stats.unknown[tag] or 0) + 1
        end
    end
    xmlUnloadFile(root)
    m.bbox = bx1 <= bx2 and { bx1, by1, bx2, by2 } or { 0, 0, 0, 0 }
    m.stats.removes, m.stats.markers = #m.removes, #m.markers
    return m
end

---------------------------------------------------------------------------- index

local function folderMaps()
    local list = pathListDir and pathListDir(MAPLOADER.MAPS_DIR)
    if not list then return nil end
    local out = {}
    for _, name in ipairs(list) do
        if name:sub(1, 1) ~= "." and name:match("^[%w_%-]+$")
            and fileExists(MAPLOADER.MAPS_DIR .. "/" .. name .. "/" .. name .. ".map") then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

local function readIndex()
    local text = readText(MAPLOADER.INDEX_FILE)
    local data = text and fromJSON(text)
    if type(data) ~= "table" or type(data.maps) ~= "table" then return nil end
    return data.maps
end

local function writeIndex(names)
    local parts = {}
    for i, n in ipairs(names) do parts[i] = '    "' .. n .. '"' end
    local text = '{\n  "generated": "' .. os.date("%Y-%m-%d %H:%M") .. '",\n  "maps": [\n' ..
        table.concat(parts, ",\n") .. '\n  ]\n}\n'
    if fileExists(MAPLOADER.INDEX_FILE) then fileDelete(MAPLOADER.INDEX_FILE) end
    local f = fileCreate(MAPLOADER.INDEX_FILE)
    if not f then return false end
    fileWrite(f, text)
    fileClose(f)
    return true
end

---------------------------------------------------------------------------- duplicates

local function round(v, step) return math.floor(v / step + 0.5) end

local function objectKey(o)
    return table.concat({ o[1], round(o[2], MAPLOADER.DUP_POS), round(o[3], MAPLOADER.DUP_POS), round(o[4], MAPLOADER.DUP_POS),
        round(o[5] % 360, MAPLOADER.DUP_ROT), round(o[6] % 360, MAPLOADER.DUP_ROT), round(o[7] % 360, MAPLOADER.DUP_ROT),
        o[8], o[9] }, ",")
end

-- removes objects that an earlier object (this map or an earlier map) already has. -> report lines
local function dropDuplicates(list)
    local seen, report = {}, {}
    for _, m in ipairs(list) do
        local kept, dups = {}, {}
        for _, o in ipairs(m.objects) do
            local k = objectKey(o)
            local owner = seen[k]
            if owner then
                dups[owner] = (dups[owner] or 0) + 1
            else
                seen[k] = m.name
                kept[#kept + 1] = o
            end
        end
        m.objects = kept
        m.stats.objects = #kept
        for owner, n in pairs(dups) do
            report[#report + 1] = ("%s: %d object(s) skipped, already in %s"):format(m.name, n, owner == m.name and "the same map" or owner)
        end
    end
    return report
end

---------------------------------------------------------------------------- loading

-- reads the given maps. -> list, problems (array of lines)
local function loadAll(names)
    local list, problems = {}, {}
    for _, name in ipairs(names) do
        local m, err = parseMap(name)
        if not m then
            problems[#problems + 1] = name .. ": " .. err
        elseif m.disabled then
            problems[#problems + 1] = name .. ": disabled in settings.json"
        else
            if m.stats.moving > 0 then
                problems[#problems + 1] = ("%s: %d moving object(s) (moveX/Y/Z) are placed static"):format(name, m.stats.moving)
            end
            for tag, n in pairs(m.stats.unknown) do
                problems[#problems + 1] = ("%s: %d <%s> element(s) ignored"):format(name, n, tag)
            end
            list[#list + 1] = m
        end
    end
    for _, line in ipairs(dropDuplicates(list)) do problems[#problems + 1] = line end
    return list, problems
end

local function buildPayload()
    local out = {}
    for i, m in ipairs(maps) do
        local zones = {}
        for j, z in ipairs(m.zones) do zones[j] = { z.min, z.max, z.margin } end
        out[i] = { name = m.name, event = m.event or nil, lod = m.lod, bbox = m.bbox, objects = m.objects, removes = m.removes,
                   markers = m.markers, zones = zones }
    end
    payload = { maps = out }
end

local function publishDims()
    local dims = {}
    for name, byDim in pairs(copies) do
        for dim, c in pairs(byDim) do
            dims[name] = dims[name] or {}
            dims[name][dim] = c.mode
        end
    end
    setElementData(resourceRoot, DATA_DIMS, dims)
end

local function publishEvents()
    setElementData(resourceRoot, DATA_EVENTS, eventOn)
end

local occlusionsWereOn = nil

addEventHandler("onResourceStop", resourceRoot, function()
    if occlusionsWereOn then setOcclusionsEnabled(true) end
end)

addEvent("onMapsLoaderStart")

addEventHandler("onResourceStart", resourceRoot, function()
    if MAPLOADER.DISABLE_OCCLUSIONS then
        occlusionsWereOn = getOcclusionsEnabled()
        setOcclusionsEnabled(false)
    end
    local names = readIndex()
    if not names then
        names = folderMaps() or {}
        writeIndex(names)
        log("maps/index.json was missing - created from the maps folder (" .. #names .. " map(s))")
    end
    local problems
    maps, problems = loadAll(names)
    mapByName = {}
    local total = 0
    for _, m in ipairs(maps) do
        mapByName[m.name] = m
        total = total + #m.objects
    end
    for _, line in ipairs(problems) do log("WARN " .. line) end
    local onDisk = folderMaps()
    if onDisk then
        local listed = {}
        for _, n in ipairs(names) do listed[n] = true end
        for _, n in ipairs(onDisk) do
            if not listed[n] then log("NEW map folder not loaded yet: " .. n .. " (run /maploader update, then restart)") end
        end
    end
    buildPayload()
    publishDims()
    eventOn = {}
    publishEvents()
    log(("%d map(s), %d object(s) loaded"):format(#maps, total))
end)

addEvent(EV_REQUEST, true)
addEventHandler(EV_REQUEST, resourceRoot, function()
    if not client or not payload then return end
    triggerClientEvent(client, EV_DATA, resourceRoot, payload)
end)

---------------------------------------------------------------------------- dimension copies (exports)

local function ownerOf()
    return sourceResource and getResourceName(sourceResource) or "maps_loader"
end

-- Loads a map in another dimension too (e.g. a tutorial). Reference counted per calling resource:
-- the same map + dimension asked twice needs two unloads. opts.interiorOnly: only the objects that
-- are in a game interior (interior ~= 0). -> true | false
function loadMapInDimension(name, dimension, opts)
    local dim = tonumber(dimension)
    if not mapByName[name] or not dim or dim == 0 then return false end
    local mode = type(opts) == "table" and opts.interiorOnly and "interior" or "all"
    copies[name] = copies[name] or {}
    local c = copies[name][dim]
    if not c then
        c = { mode = mode, users = {} }
        copies[name][dim] = c
    elseif mode == "all" then
        c.mode = "all"
    end
    local owner = ownerOf()
    c.users[owner] = (c.users[owner] or 0) + 1
    publishDims()
    return true
end

-- -> true when the copy is gone (no other user keeps it)
function unloadMapFromDimension(name, dimension)
    local dim = tonumber(dimension)
    local c = copies[name] and dim and copies[name][dim]
    if not c then return true end
    local owner = ownerOf()
    if c.users[owner] then
        c.users[owner] = c.users[owner] - 1
        if c.users[owner] <= 0 then c.users[owner] = nil end
    end
    if next(c.users) then return false end
    copies[name][dim] = nil
    if not next(copies[name]) then copies[name] = nil end
    publishDims()
    return true
end

-- copies of a stopping resource are released
addEventHandler("onResourceStop", root, function(res)
    local owner = getResourceName(res)
    local changed = false
    for name, byDim in pairs(copies) do
        for dim, c in pairs(byDim) do
            if c.users[owner] then
                c.users[owner] = nil
                if not next(c.users) then byDim[dim] = nil end
                changed = true
            end
        end
        if not next(byDim) then copies[name] = nil end
    end
    if changed then publishDims() end
end)

-- -> { name, ... }
function getLoadedMaps()
    local out = {}
    for i, m in ipairs(maps) do out[i] = m.name end
    return out
end

function isMapLoaded(name)
    return mapByName[name] ~= nil
end

-- -> { [dimension] = "all" | "interior" } of a map
function getMapDimensions(name)
    local out = {}
    for dim, c in pairs(copies[name] or {}) do out[dim] = c.mode end
    return out
end

---------------------------------------------------------------------------- event maps (exports)

-- Event maps (settings.json "event": true) are known to the clients but not built until switched on,
-- e.g. by event_core: exports.maps_loader:setEventMapEnabled("ls_xmas_tree", true).
-- The state is not saved: a restart of maps_loader switches every event map off again
-- (listen to onMapsLoaderStart on root to switch them back on).

-- -> true | false (unknown map or not an event map)
function setEventMapEnabled(name, enabled)
    local m = mapByName[name]
    if not m or not m.event then return false end
    enabled = enabled and true or nil
    if eventOn[name] == enabled then return true end
    eventOn[name] = enabled
    publishEvents()
    log(("event map %s %s by %s"):format(name, enabled and "ON" or "OFF", ownerOf()))
    return true
end

function isEventMapEnabled(name)
    return eventOn[name] == true
end

-- -> { { name = , enabled = }, ... } of every event map
function getEventMaps()
    local out = {}
    for _, m in ipairs(maps) do
        if m.event then out[#out + 1] = { name = m.name, enabled = eventOn[m.name] == true } end
    end
    return out
end

addEventHandler("onResourceStart", resourceRoot, function()
    triggerEvent("onMapsLoaderStart", root)
end)

---------------------------------------------------------------------------- /maploader

local function say(player, text)
    if isElement(player) then outputConsole("[maploader] " .. text, player) else outputServerLog("[maploader] " .. text) end
end

local function allowed(player)
    if not isElement(player) then return true end
    if getElementData(player, "isLogged") ~= true then return false end
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(level) or 0) >= MAPLOADER.ADMIN_LEVEL
end

addCommandHandler("maploader", function(player, _, sub, arg1, arg2)
    if not allowed(player) then return say(player, "Access denied.") end
    sub = tostring(sub or ""):lower()
    if sub == "update" then
        local names = folderMaps()
        if not names then return say(player, "cannot list the maps folder (pathListDir)") end
        local list, problems = loadAll(names)
        if not writeIndex(names) then return say(player, "cannot write " .. MAPLOADER.INDEX_FILE) end
        local loadedNow = {}
        for _, m in ipairs(maps) do loadedNow[m.name] = true end
        local total, added = 0, 0
        for _, m in ipairs(list) do
            total = total + #m.objects
            if not loadedNow[m.name] then added = added + 1 end
            say(player, ("%-22s %4d object(s), %2d indoor, %2d removal(s), %2d marker(s)"):format(
                m.name, #m.objects, m.stats.indoor, m.stats.removes, m.stats.markers))
        end
        for _, line in ipairs(problems) do say(player, "WARN " .. line) end
        say(player, ("index.json: %d map(s), %d object(s), %d new. Restart maps_loader to apply."):format(#names, total, added))
        log(("index updated by %s: %d map(s), %d new"):format(isElement(player) and getPlayerName(player) or "console", #names, added))
    elseif sub == "status" then
        for _, m in ipairs(maps) do
            local dims = {}
            for dim, c in pairs(copies[m.name] or {}) do dims[#dims + 1] = dim .. (c.mode == "interior" and "i" or "") end
            say(player, ("%-22s %4d object(s)%s%s"):format(m.name, #m.objects, m.event and (eventOn[m.name] and " | EVENT on" or " | EVENT off") or "", #dims > 0 and (" | dims " .. table.concat(dims, ",")) or ""))
        end
    elseif sub == "event" then
        local name, state = tostring(arg1 or ""), tostring(arg2 or ""):lower()
        if state ~= "on" and state ~= "off" then return say(player, "Usage: /maploader event <map> on|off") end
        say(player, setEventMapEnabled(name, state == "on") and (name .. " event " .. state) or (name .. " is not an event map"))
    else
        say(player, "Usage: /maploader update | status | event <map> on|off")
    end
end)
