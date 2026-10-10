-- Navigation points (data/nav.json):
--   fixes: { id, x, y, kind = "cta" | "tma" | "enroute" | "final", airport?, runway? }
--   ndbs:  { id, name, freq, x, y, z?, object? }
--   vors:  { id, name, freq, x, y, z, object? = { model, rz } }
--   procedures: { id, type = "SID" | "STAR", airport, fix, runways = { [ident] = { fixId, ... } } }
--     STAR <FIX>1A: entry fix -> (downwind) -> base fix abeam the final fix -> final fix of the runway
--     SID  <FIX>1D: climb-out fix on the centre line -> (turn fix) -> exit fix
-- FIXes sit on the airspace boundaries, on the en-route network and on every runway final.
-- VORs are placed in game (/avinav, editor.lua); their ground object is created here.
-- Ids are unique across all three kinds (flight plans reference them by id).

NAV = { fixes = {}, ndbs = {}, vors = {}, procedures = {} }
local byId = {}
local procById = {}
local objects = {}

addEvent("onAviNavChange")   -- source: resourceRoot (the data changed, consumers re-read it)

local KINDS = { fixes = "FIX", ndbs = "NDB", vors = "VOR" }

local function index()
    byId = {}
    for key, kind in pairs(KINDS) do
        for _, p in ipairs(NAV[key]) do
            p.type = kind
            if byId[p.id] then
                outputDebugString("[avi_nav] duplicate nav id " .. tostring(p.id), 2)
            end
            byId[p.id] = p
        end
    end
end

local function destroyObjects()
    for _, o in pairs(objects) do if isElement(o) then destroyElement(o) end end
    objects = {}
end

-- ground objects of VORs / NDBs (object = { model, rz }, z = ground level of the point)
function refreshNavObjects()
    destroyObjects()
    for _, key in ipairs({ "vors", "ndbs" }) do
        for _, p in ipairs(NAV[key]) do
            local o = p.object
            if type(o) == "table" and tonumber(o.model) and tonumber(o.model) > 0 and p.z then
                local obj = createObject(tonumber(o.model), p.x, p.y, p.z, 0, 0, tonumber(o.rz) or 0)
                if obj then
                    setElementFrozen(obj, true)
                    objects[p.id] = obj
                else
                    outputDebugString("[avi_nav] could not create object " .. tostring(o.model) .. " for " .. p.id, 2)
                end
            end
        end
    end
end

function loadNav()
    local f = fileOpen("data/nav.json", true)
    if not f then
        outputDebugString("[avi_nav] data/nav.json missing", 1)
        return false
    end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    NAV = { fixes = {}, ndbs = {}, vors = {}, procedures = {}, _about = data and data._about }
    for key in pairs(KINDS) do
        for _, p in ipairs(data and data[key] or {}) do
            if p.id and tonumber(p.x) and tonumber(p.y) then
                p.x, p.y, p.z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
                NAV[key][#NAV[key] + 1] = p
            end
        end
    end
    procById = {}
    for _, p in ipairs(data and data.procedures or {}) do
        if p.id and (p.type == "SID" or p.type == "STAR") and p.airport and type(p.runways) == "table" then
            p.id = tostring(p.id):upper()
            NAV.procedures[#NAV.procedures + 1] = p
            procById[p.id] = p
        end
    end
    index()
    refreshNavObjects()
    outputDebugString(("[avi_nav] %d fixes, %d NDBs, %d VORs, %d procedures"):format(#NAV.fixes, #NAV.ndbs, #NAV.vors, #NAV.procedures))
    return true
end

-- write NAV back to data/nav.json (editor). toJSON wraps the value in [ ], strip that.
function saveNav()
    local out = { _about = NAV._about, fixes = {}, ndbs = {}, vors = {}, procedures = NAV.procedures }
    for key in pairs(KINDS) do
        for _, p in ipairs(NAV[key]) do
            local c = {}
            for k, v in pairs(p) do if k ~= "type" then c[k] = v end end
            out[key][#out[key] + 1] = c
        end
    end
    local json = toJSON(out, false, "spaces")
    if not json then return false end
    json = json:gsub("^%s*%[", ""):gsub("%]%s*$", "")
    local f = fileCreate("data/nav.json")
    if not f then return false end
    fileWrite(f, json)
    fileClose(f)
    index()
    refreshNavObjects()
    triggerEvent("onAviNavChange", resourceRoot)
    return true
end

addEventHandler("onResourceStart", resourceRoot, loadNav)
addEventHandler("onResourceStop", resourceRoot, destroyObjects)

-- ---------------------------------------------------------------- exports
function getNavData()
    return NAV
end

function getNavPoint(id)
    return id and byId[tostring(id):upper()]
end

-- flat list of every point { id, type, x, y, ... }
function getNavPoints()
    local list = {}
    for _, p in pairs(byId) do list[#list + 1] = p end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function getNearestNavPoint(x, y, typeFilter)
    local best, bestD
    for _, p in pairs(byId) do
        if not typeFilter or p.type == typeFilter then
            local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    return best, bestD and math.sqrt(bestD)
end

-- used by editor.lua
function navKeyOf(kind)
    for key, k in pairs(KINDS) do if k == kind then return key end end
end

-- ---------------------------------------------------------------- procedures (SID / STAR)
-- airport + type filter optional
function getProcedures(icao, ptype)
    local out = {}
    for _, p in ipairs(NAV.procedures) do
        if (not icao or p.airport == icao) and (not ptype or p.type == ptype) then out[#out + 1] = p end
    end
    return out
end

function getProcedure(id)
    return id and procById[tostring(id):upper()]
end

-- fix list of a procedure for a runway end (nil when the procedure has no such runway)
function getProcedureRoute(id, ident)
    local p = getProcedure(id)
    if not p then return nil end
    ident = tostring(ident or ""):upper()
    local r
    for k, v in pairs(p.runways) do
        if tostring(k):upper() == ident or (tonumber(k) and tonumber(k) == tonumber(ident)) then r = v end
    end
    if not r then return nil end
    local out = {}
    for i, f in ipairs(r) do out[i] = f end
    return out
end
