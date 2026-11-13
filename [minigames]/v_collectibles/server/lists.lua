-- Collectible lists: one JSON file per list in data/lists/<id>.json.
--
-- {
--   "id": "hidden_packages",          file name without .json ([a-z0-9_], max 32)
--   "name": "Hidden Packages",        shown in the banner and in the ui_inac Collectibles menu
--   "models": [1276, 954],            HEADER: object models the items of this list may use
--   "event": false,                   true = only active while an events_core event switches it on
--   "enabled": true,                  false = never active (work in progress)
--   "spin": true,                     the objects turn slowly
--   "reward": 2000,                   money (euro, cash) for every item picked up (default COLLECT.DEFAULT_REWARD, 0 = none)
--   "nextId": 3,                      next item id (ids are never reused, the collected state refers to them)
--   "items": [ { "id": 1, "model": 1276, "x": 0, "y": 0, "z": 3, "rx": 0, "ry": 0, "rz": 0, "int": 0, "dim": 0 }, ... ]
-- }
--
-- The editor (/collecteditor) writes these files; hand edits are fine too (restart v_collectibles).

Lists = {}          -- [id] = list (sanitized, items + byId)
ListOrder = {}      -- ids, sorted by name

local function log(text) outputServerLog("[v_collectibles] " .. text) end

local function readFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local s = fileRead(f, fileGetSize(f))
    fileClose(f)
    return s
end

local function writeFile(path, text)
    if fileExists(path) then fileDelete(path) end
    local f = fileCreate(path)
    if not f then return false end
    fileWrite(f, text)
    fileClose(f)
    return true
end

local function num(v, def)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return def end
    return v
end

local function round(v, d)
    local m = 10 ^ (d or 3)
    return math.floor(v * m + 0.5) / m
end

function isValidListId(id)
    return type(id) == "string" and #id > 0 and #id <= COLLECT.ID_MAX and id:match(COLLECT.ID_PATTERN) ~= nil
end

function cleanName(name, fallback)
    name = type(name) == "string" and name:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then name = fallback or "?" end
    if #name > COLLECT.NAME_MAX then name = name:sub(1, COLLECT.NAME_MAX) end
    return name
end

--- validated copy of a decoded list (also used for hand-edited files)
function sanitizeList(id, t)
    t = type(t) == "table" and t or {}
    local list = {
        id = id,
        name = cleanName(t.name, id),
        event = t.event == true,
        enabled = t.enabled ~= false,
        spin = t.spin == true,
        reward = math.max(0, math.min(COLLECT.MAX_REWARD, math.floor(num(t.reward, COLLECT.DEFAULT_REWARD)))),
        models = {},
        items = {},
        byId = {},
        nextId = math.max(1, math.floor(num(t.nextId, 1))),
    }
    local seenModel = {}
    for _, m in ipairs(type(t.models) == "table" and t.models or {}) do
        m = math.floor(num(m, -1))
        if m >= 0 and m <= 65535 and not seenModel[m] and #list.models < COLLECT.MAX_MODELS then
            seenModel[m] = true
            list.models[#list.models + 1] = m
        end
    end
    for _, it in ipairs(type(t.items) == "table" and t.items or {}) do
        local itemId = math.floor(num(type(it) == "table" and it.id, 0))
        if itemId > 0 and not list.byId[itemId] and #list.items < COLLECT.MAX_ITEMS then
            local item = {
                id = itemId,
                model = math.floor(num(it.model, list.models[1] or 1276)),
                x = round(num(it.x, 0)), y = round(num(it.y, 0)), z = round(num(it.z, 0)),
                rx = round(num(it.rx, 0), 1), ry = round(num(it.ry, 0), 1), rz = round(num(it.rz, 0), 1),
                int = math.floor(num(it.int, 0)), dim = math.floor(num(it.dim, 0)),
            }
            list.items[#list.items + 1] = item
            list.byId[itemId] = item
            if itemId >= list.nextId then list.nextId = itemId + 1 end
        end
    end
    return list
end

-- what goes into the file (no byId)
local function serialize(list)
    local items = {}
    for i, it in ipairs(list.items) do
        items[i] = { id = it.id, model = it.model, x = it.x, y = it.y, z = it.z,
            rx = it.rx, ry = it.ry, rz = it.rz, int = it.int, dim = it.dim }
    end
    return (toJSON({
        id = list.id, name = list.name, models = list.models,
        event = list.event, enabled = list.enabled, spin = list.spin,
        reward = list.reward, nextId = list.nextId, items = items,
    }, false, "spaces"):sub(2, -2))   -- toJSON wraps the value in [ ]
end

local function sortOrder()
    ListOrder = {}
    for id in pairs(Lists) do ListOrder[#ListOrder + 1] = id end
    table.sort(ListOrder, function(a, b)
        local na, nb = Lists[a].name:lower(), Lists[b].name:lower()
        if na == nb then return a < b end
        return na < nb
    end)
end

local function saveIndex()
    writeFile(COLLECT.INDEX, toJSON(ListOrder, false, "spaces"))   -- [ [ ids ] ]: fromJSON gives the table back
end

local function listFileIds()
    local ids, seen = {}, {}
    local function add(id)
        if isValidListId(id) and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    local dir = pathListDir and pathListDir(COLLECT.FOLDER:sub(1, -2))
    if type(dir) == "table" then
        for _, name in ipairs(dir) do
            local id = tostring(name):match("^(.+)%.json$")
            if id then add(id) end
        end
    end
    local idx = fromJSON(readFile(COLLECT.INDEX) or "")
    if type(idx) == "table" then
        for _, id in ipairs(idx) do add(tostring(id)) end
    end
    return ids
end

--- (re)loads every list file
function loadAllLists()
    Lists = {}
    for _, id in ipairs(listFileIds()) do
        local text = readFile(COLLECT.FOLDER .. id .. ".json")
        if text then
            local t = fromJSON(text)
            if type(t) == "table" then
                Lists[id] = sanitizeList(id, t)
            else
                log("list " .. id .. ".json is not valid JSON, skipped")
            end
        end
    end
    sortOrder()
    saveIndex()
    log(("%d list(s) loaded"):format(#ListOrder))
end

function saveList(list)
    Lists[list.id] = list
    sortOrder()
    local ok = writeFile(COLLECT.FOLDER .. list.id .. ".json", serialize(list))
    saveIndex()
    if not ok then log("could not write " .. list.id .. ".json") end
    return ok
end

function deleteListFile(id)
    Lists[id] = nil
    sortOrder()
    local path = COLLECT.FOLDER .. id .. ".json"
    if fileExists(path) then fileDelete(path) end
    saveIndex()
end
