if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Small helpers shared by the server modules.

function vsmLog(fmt, ...)
    outputServerLog("[v_scenemanager] " .. string.format(fmt, ...))
end

-- ui_core notification on the player's screen. title / text: v_locals keys (+ params) or L.msg objects;
-- the console (no player) gets the English text in the server log.
function vsmNotify(player, title, text, params)
    if type(title) == "string" and title:find("^v_scenemanager%.") then title = L.msg(title) end
    if type(text) == "string" and text:find("^v_scenemanager%.") then text = L.msg(text, params) end
    if not isElement(player) then
        vsmLog("%s: %s", tostring(title), tostring(text))
        return
    end
    triggerClientEvent(player, "vsm:notify", resourceRoot, title, text)
end

-- admin command feedback (the chat box is hidden by v_chat: a notification)
function vsmSay(player, key, params)
    vsmNotify(player, "v_scenemanager.title", key, params)
end

function vsmResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- admin_level comes from the account store (v_mysql), not from element data
function vsmIsAllowed(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if getElementData(player, "isLogged") ~= true then return false end
    if not vsmResourceRunning("v_mysql") then return false end
    local level = tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    return level >= VSM.MIN_ADMIN_LEVEL
end

function vsmPlayerName(player)
    if not isElement(player) then return "console" end
    local d = getElementData(player, "displayName") or getPlayerName(player)
    return (tostring(d):gsub("#%x%x%x%x%x%x", ""))
end

function vsmAccount(player)
    local a = isElement(player) and getElementData(player, "accName")
    return type(a) == "string" and a ~= "" and a or (isElement(player) and getPlayerName(player) or "console")
end

function vsmRound(value, decimals)
    local m = 10 ^ (decimals or 3)
    return math.floor((tonumber(value) or 0) * m + 0.5) / m
end

function vsmCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = vsmCopy(v) end
    return out
end

function vsmNow()
    return getRealTime().timestamp
end

function vsmValidName(name)
    return type(name) == "string" and #name > 0 and #name <= VSM.NAME_MAX
        and name:match(VSM.NAME_PATTERN) ~= nil and name ~= "index" and name ~= "issues"
end

-- Valid category id, "" (none), or - when value is nil - the first category found in the name
function vsmCategory(value, name)
    if value == nil then
        name = tostring(name or ""):lower()
        for _, c in ipairs(VSM_CATEGORIES) do
            if name:find(c.id, 1, true) then return c.id end
        end
        return ""
    end
    for _, c in ipairs(VSM_CATEGORIES) do
        if c.id == value then return c.id end
    end
    return ""
end

-- Suggested location label for a position: "Los Santos", "San Fierro", "Las Venturas" or
-- the zone (village / area) name - human-readable, not a folder id. Only a suggestion -
-- the scene's stored "location" field decides its actual folder (vsmLocationFolder,
-- Storage.pathFor); this is offered by the editor and used as the fallback for scene
-- files saved before that field existed.
function vsmSuggestedLocation(center, interior)
    if (tonumber(interior) or 0) ~= 0 then return VSM.INTERIOR_FOLDER end
    local x, y, z = center[1], center[2], center[3]
    local city = getZoneName(x, y, z, true)
    local zone = tostring((VSM.CITY_FOLDERS[city] and city or getZoneName(x, y, z, false)) or "")
    return zone ~= "" and zone or "Unknown"
end

-- Folder-safe slug of a location label (scenes/<this>/[<category>/]<name>.json):
-- spaces -> _, apostrophes dropped, anything else -> _
function vsmLocationFolder(label)
    local folder = tostring(label or ""):gsub("'", ""):gsub("[^%w%-]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return folder ~= "" and folder or "Unknown"
end

-- Valid location label: short printable text (e.g. "San Fierro", "Lil' Probe Inn").
-- It is only turned into a folder name through vsmLocationFolder, so no character set
-- restriction is needed here.
function vsmValidLocation(value)
    return type(value) == "string" and value ~= "" and #value <= VSM.NAME_MAX and not value:find("%c")
end

-- text of a live player input: control characters out, trimmed, at most max characters (UTF-8)
function vsmCleanText(text, max)
    text = tostring(text or ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
    if utf8 and utf8.len(text) and utf8.len(text) > max then return utf8.sub(text, 1, max) end
    return text:sub(1, max)
end

function vsmTextLen(text)
    return (utf8 and utf8.len(text)) or #text
end

---------------------------------------------------------------- files

function vsmReadFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local content = fileRead(f, fileGetSize(f))
    fileClose(f)
    return content
end

function vsmWriteFile(path, content)
    if fileExists(path) then fileDelete(path) end
    local f = fileCreate(path)
    if not f then return false end
    fileWrite(f, content)
    fileClose(f)
    return true
end

-- Accepts a plain JSON object / array (MTA's fromJSON wants a top level array)
function vsmDecodeJSON(content)
    if type(content) ~= "string" then return nil end
    content = content:gsub("^\239\187\191", "") -- UTF-8 BOM
    local first = content:match("^%s*(.)")
    if first == "{" then content = "[" .. content .. "]" end
    local ok, value = pcall(fromJSON, content)
    if ok and type(value) == "table" then return value end
    return nil
end

---------------------------------------------------------------- task texts

local function localeEntry(entry)
    if type(entry) ~= "table" then return nil end
    local title = type(entry.title) == "string" and entry.title or ""
    local description = type(entry.description) == "string" and entry.description or ""
    if title == "" and description == "" then return nil end
    return { title = title, description = description }
end

-- agency block (decoded file or editor table) -> { en = { title, description }, hu = ... }. Accepts the old flat
-- title / description (becomes English). Languages with both fields empty are dropped; nothing is invented
-- (missing texts are reported by the validation).
function vsmNormalizeLocales(block)
    block = type(block) == "table" and block or {}
    local out = {}
    if type(block.locales) == "table" then
        for code, entry in pairs(block.locales) do
            if type(code) == "string" and code:match("^%l%l") then
                out[code] = localeEntry(entry)
            end
        end
    end
    if not out.en then
        out.en = localeEntry({ title = block.title, description = block.description })
    end
    return out
end

---------------------------------------------------------------- JSON writer

-- Key order of the written files (scene, agencies, vehicle, ped, injury, medical state, record, index).
-- Keys missing from the list follow in alphabetical order.
local KEY_ORDER = {
    "format", "name", "category", "location", "enabled", "weight", "center", "interior", "dimension", "safe",
    "agencies", "vehicles", "peds",
    "ems", "pd", "need", "priority", "caller", "lateJoin", "locales", "close",
    "en", "hu", "title", "description",
    "id", "model", "skin", "pos", "rot", "anim", "role", "frozen", "vehicle", "seat",
    "locked", "engine", "lightsOn", "sirens", "health", "colors", "paintjob", "plate", "variant",
    "upgrades", "doors", "panels", "lights", "wheels", "tow",
    "injuries", "type", "severity", "state", "ai", "record",
    "side", "targets", "weapon", "ammo", "accuracy", "start", "startRadius", "onPolice", "aggroRadius", "leash",
    "task", "surrenderHealth", "flee",
    "age", "birth", "flags", "licence", "bac", "drug", "past", "btk", "daysAgo", "warrants", "reasons",
    "announce", "persistent", "stolen", "owner", "inspection",
    "scenes", "seq", "issues",
}
for _, key in ipairs(VSM_STATE_ORDER) do KEY_ORDER[#KEY_ORDER + 1] = key end
local KEY_RANK = {}
for i, key in ipairs(KEY_ORDER) do
    if not KEY_RANK[key] then KEY_RANK[key] = i end
end

local EMPTY_OBJECTS = { state = true, agencies = true, flags = true } -- every other empty table is written as []
local ALWAYS_EXPANDED = { agencies = true, locales = true, record = true }  -- never on one line (long texts)
local EXPANDED_CHILDREN = { locales = true }                              -- ... and neither is each language inside locales
local INDENT = "    "
local INLINE_WIDTH = 100 -- containers of plain values up to this many characters stay on one line

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(value)
    return '"' .. value:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or ("\\u%04x"):format(c:byte())
    end) .. '"'
end

local function encodeNumber(value)
    if value ~= value or value == math.huge or value == -math.huge then return "0" end
    if value == math.floor(value) and math.abs(value) < 1e15 then return ("%d"):format(value) end
    return ("%.10g"):format(value)
end

local function isArray(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count == #t
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys, function(a, b)
        local ra, rb = KEY_RANK[a], KEY_RANK[b]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end
        return a < b
    end)
    return keys
end

local function encodeValue(value, depth, key, parent)
    local kind = type(value)
    if kind == "string" then return encodeString(value) end
    if kind == "number" then return encodeNumber(value) end
    if kind == "boolean" then return tostring(value) end
    if kind ~= "table" then return "null" end

    if next(value) == nil then return EMPTY_OBJECTS[key] and "{}" or "[]" end

    local array = isArray(value)
    local parts, plain = {}, true
    if array then
        for i, v in ipairs(value) do
            parts[i] = encodeValue(v, depth + 1)
            if type(v) == "table" then plain = false end
        end
    else
        for i, k in ipairs(sortedKeys(value)) do
            local v = value[k]
            if v == nil then v = value[tonumber(k)] end
            parts[i] = encodeString(k) .. ": " .. encodeValue(v, depth + 1, k, key)
            if type(v) == "table" then plain = false end
        end
    end
    local open, close = array and "[" or "{", array and "]" or "}"

    if plain and not ALWAYS_EXPANDED[key] and not EXPANDED_CHILDREN[parent] then
        local line = array and (open .. table.concat(parts, ", ") .. close)
            or (open .. " " .. table.concat(parts, ", ") .. " " .. close)
        if #line + #INDENT * depth <= INLINE_WIDTH then return line end
    end
    local pad = INDENT:rep(depth + 1)
    return open .. "\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. INDENT:rep(depth) .. close
end

-- Pretty JSON with a fixed key order (KEY_ORDER); short lists / objects stay on one line
function vsmEncodeJSON(value)
    return encodeValue(value, 0) .. "\n"
end
