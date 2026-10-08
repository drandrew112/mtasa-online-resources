-- Small helpers shared by the server modules.

function msmLog(fmt, ...)
    outputServerLog("[med_scenemanager] " .. string.format(fmt, ...))
end

function msmSay(player, text)
    if not isElement(player) then
        msmLog("%s", (text:gsub("#%x%x%x%x%x%x", "")))
        return
    end
    outputChatBox("#ff5a5a[SCENE] #ffffff" .. text, player, 255, 255, 255, true)
end

-- ui_core notification on the player's screen
function msmNotify(player, title, text)
    if isElement(player) then
        triggerClientEvent(player, "msm:notify", resourceRoot, title, text)
    end
end

function msmResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- admin_level comes from the account store (v_mysql), not from element data
function msmIsAllowed(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if getElementData(player, "isLogged") ~= true then return false end
    if not msmResourceRunning("v_mysql") then return false end
    local level = tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    return level >= MSM.MIN_ADMIN_LEVEL
end

function msmRound(value, decimals)
    local m = 10 ^ (decimals or 3)
    return math.floor((tonumber(value) or 0) * m + 0.5) / m
end

function msmCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = msmCopy(v) end
    return out
end

function msmValidName(name)
    return type(name) == "string" and #name > 0 and #name <= MSM.NAME_MAX
        and name:match(MSM.NAME_PATTERN) ~= nil and name ~= "index"
end

-- Valid category id, "" (none), or - when value is nil - the first category found in the name
function msmCategory(value, name)
    if value == nil then
        name = tostring(name or ""):lower()
        for _, c in ipairs(MSM_CATEGORIES) do
            if name:find(c.id, 1, true) then return c.id end
        end
        return ""
    end
    for _, c in ipairs(MSM_CATEGORIES) do
        if c.id == value then return c.id end
    end
    return ""
end

-- Suggested location label for a position: "Los Santos", "San Fierro", "Las Venturas" or
-- the zone (village / area) name - human-readable, not a folder id. Only a suggestion -
-- the scene's stored "location" field decides its actual folder (msmLocationFolder,
-- Storage.pathFor); this is offered by the editor and used as the fallback for scene
-- files saved before that field existed.
function msmSuggestedLocation(center, interior)
    if (tonumber(interior) or 0) ~= 0 then return MSM.INTERIOR_FOLDER end
    local x, y, z = center[1], center[2], center[3]
    local city = getZoneName(x, y, z, true)
    local zone = tostring((MSM.CITY_FOLDERS[city] and city or getZoneName(x, y, z, false)) or "")
    return zone ~= "" and zone or "Unknown"
end

-- Folder-safe slug of a location label (scenes/<this>/[<category>/]<name>.json):
-- spaces -> _, apostrophes dropped, anything else -> _
function msmLocationFolder(label)
    local folder = tostring(label or ""):gsub("'", ""):gsub("[^%w%-]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return folder ~= "" and folder or "Unknown"
end

-- Valid location label: short printable text (e.g. "San Fierro", "Lil' Probe Inn").
-- It is only turned into a folder name through msmLocationFolder, so no character set
-- restriction is needed here.
function msmValidLocation(value)
    return type(value) == "string" and value ~= "" and #value <= MSM.NAME_MAX and not value:find("%c")
end

---------------------------------------------------------------- files

function msmReadFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local content = fileRead(f, fileGetSize(f))
    fileClose(f)
    return content
end

function msmWriteFile(path, content)
    if fileExists(path) then fileDelete(path) end
    local f = fileCreate(path)
    if not f then return false end
    fileWrite(f, content)
    fileClose(f)
    return true
end

-- Accepts a plain JSON object / array (MTA's fromJSON wants a top level array)
function msmDecodeJSON(content)
    if type(content) ~= "string" then return nil end
    content = content:gsub("^\239\187\191", "") -- UTF-8 BOM
    local first = content:match("^%s*(.)")
    if first == "{" then content = "[" .. content .. "]" end
    local ok, value = pcall(fromJSON, content)
    if ok and type(value) == "table" then return value end
    return nil
end

---------------------------------------------------------------- JSON writer

-- Key order of the written files (scene, erm, vehicle, ped, injury, medical state, index).
-- Keys missing from the list follow in alphabetical order.
local KEY_ORDER = {
    "format", "name", "category", "location", "enabled", "weight", "center", "interior", "dimension", "erm", "vehicles", "peds",
    "title", "description", "caller", "priority",
    "id", "model", "skin", "pos", "rot", "anim", "frozen", "vehicle", "seat",
    "locked", "engine", "lightsOn", "sirens", "health", "colors", "paintjob", "plate", "variant",
    "upgrades", "doors", "panels", "lights", "wheels",
    "injuries", "type", "severity", "state",
    "scenes",
}
for _, key in ipairs(MSM_STATE_ORDER) do KEY_ORDER[#KEY_ORDER + 1] = key end
local KEY_RANK = {}
for i, key in ipairs(KEY_ORDER) do
    if not KEY_RANK[key] then KEY_RANK[key] = i end
end

local EMPTY_OBJECTS = { state = true } -- every other empty table is written as []
local ALWAYS_EXPANDED = { erm = true }  -- never on one line (its description is often long)
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

local function encodeValue(value, depth, key)
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
            parts[i] = encodeString(k) .. ": " .. encodeValue(v, depth + 1, k)
            if type(v) == "table" then plain = false end
        end
    end
    local open, close = array and "[" or "{", array and "]" or "}"

    if plain and not ALWAYS_EXPANDED[key] then
        local line = array and (open .. table.concat(parts, ", ") .. close)
            or (open .. " " .. table.concat(parts, ", ") .. " " .. close)
        if #line + #INDENT * depth <= INLINE_WIDTH then return line end
    end
    local pad = INDENT:rep(depth + 1)
    return open .. "\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. INDENT:rep(depth) .. close
end

-- Pretty JSON with a fixed key order (KEY_ORDER); short lists / objects stay on one line
function msmEncodeJSON(value)
    return encodeValue(value, 0) .. "\n"
end
