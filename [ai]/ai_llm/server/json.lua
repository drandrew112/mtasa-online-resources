-- ai_llm / server/json.lua
-- Small JSON encoder for the request bodies. MTA's toJSON wraps the root in [ ] and turns empty
-- tables into arrays, which the Gemini API rejects; this one gives exact control:
--   a table with t[1] ~= nil (or AI.json.array(t)) -> JSON array, any other table -> object,
--   AI.json.null -> null. Decoding uses MTA's fromJSON.

AI = AI or {}
AI.json = {}

local ARRAY_MARK = {}
AI.json.null = setmetatable({}, { __tostring = function() return "null" end })

-- marks an (also empty) table as a JSON array
function AI.json.array(t)
    t = t or {}
    return setmetatable(t, { [ARRAY_MARK] = true })
end

local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESC[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function isArray(t)
    local mt = getmetatable(t)
    if mt and mt[ARRAY_MARK] then return true end
    return t[1] ~= nil
end

local encode
encode = function(v, depth)
    depth = depth or 0
    if depth > 32 then error("json: too deep") end
    local tv = type(v)
    if v == nil or v == AI.json.null then return "null" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.14g", v)
    end
    if tv == "string" then return encodeString(v) end
    if tv == "table" then
        local out = {}
        if isArray(v) then
            for i = 1, #v do out[i] = encode(v[i], depth + 1) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = tostring(k) end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            out[#out + 1] = encodeString(k) .. ":" .. encode(val, depth + 1)
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

function AI.json.encode(v)
    local ok, res = pcall(encode, v, 0)
    if ok then return res end
    return nil, res
end

-- fromJSON returns several values for a root array; the API always answers an object
function AI.json.decode(s)
    if type(s) ~= "string" or s == "" then return nil end
    local ok, res = pcall(fromJSON, s)
    if ok then return res end
    return nil
end

-- Extracts the first JSON object of a model answer (it may come in ``` fences or with text around it).
function AI.json.extractObject(text)
    if type(text) ~= "string" then return nil end
    local direct = AI.json.decode(text)
    if type(direct) == "table" then return direct end
    local s = text:find("{", 1, true)
    if not s then return nil end
    local depth, inStr, esc = 0, false, false
    for i = s, #text do
        local c = text:sub(i, i)
        if inStr then
            if esc then esc = false
            elseif c == "\\" then esc = true
            elseif c == '"' then inStr = false end
        elseif c == '"' then inStr = true
        elseif c == "{" then depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then
                local obj = AI.json.decode(text:sub(s, i))
                if type(obj) == "table" then return obj end
                return nil
            end
        end
    end
    return nil
end
