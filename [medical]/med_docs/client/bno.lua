-- BNO names and search on the client (server/bno.lua answers). Other resources:
--   exports.med_docs:getBNOName(code [, lang]) -> name (the code itself until it arrived)
--   exports.med_docs:getBNOCode(code) -> "S06.4" style code (the raw code until it arrived)
--   exports.med_docs:searchBNO(query, token [, filter]) -> the result comes as the client event
--       "onClientBNOResults" (token, results = { { code, fmt, name, flag } }) on root

local names = {}       -- code -> { hu, en, fmt, flag } | false (unknown) | true (asked)
local queue, queued = {}, false

local function flush()
    queued = false
    if #queue == 0 then return end
    local list = queue
    queue = {}
    triggerServerEvent("bno:names", resourceRoot, list)
end

local function ask(code)
    if names[code] ~= nil then return end
    names[code] = true
    queue[#queue + 1] = code
    if not queued then queued = true setTimer(flush, 80, 1) end
end

addEvent("bno:names", true)
addEventHandler("bno:names", resourceRoot, function(map)
    for code, v in pairs(map or {}) do names[code] = v end
end)

function getBNOName(code, lang)
    code = tostring(code or "")
    local v = names[code]
    if type(v) == "table" then return (lang or L.lang()) == "en" and v[2] or v[1] end
    ask(code)
    return code
end

function getBNOCode(code)
    code = tostring(code or "")
    local v = names[code]
    if type(v) == "table" then return v[3] end
    ask(code)
    return code
end

function getBNOFlag(code)
    local v = names[tostring(code or "")]
    return type(v) == "table" and v[4] or ""
end

function searchBNO(query, token, filter)
    if type(query) ~= "string" or query == "" then return false end
    triggerServerEvent("bno:search", resourceRoot, query:sub(1, 60), L.lang(), token, filter)
    return true
end

addEvent("onClientBNOResults")
addEvent("bno:results", true)
addEventHandler("bno:results", resourceRoot, function(token, results)
    for _, r in ipairs(results or {}) do
        if names[r.code] == nil or names[r.code] == true then names[r.code] = nil end
    end
    triggerEvent("onClientBNOResults", root, token, results or {})
end)
