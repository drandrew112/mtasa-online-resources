-- Data for the simulation: the flight database (data/flights.json) and cached copies of the other
-- avi_* resources (airports, nav points, airspaces). The caches refresh when those resources
-- (re)start or the nav data changes. Never keep an exports table in a local: a restarted
-- resource gets a new one.

DB = { flights = {}, types = {}, airlines = {}, externals = {}, byCallsign = {} }
WORLD = { airports = {}, nav = {}, airspaces = {}, procs = {}, centre = { split = 20500, sectors = {} } }

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

function callExport(resName, fn, ...)
    if not running(resName) then return nil end
    local ok, a, b = pcall(function(...) return exports[resName][fn](exports[resName], ...) end, ...)
    if not ok then
        outputDebugString(("[avi_traffic] %s:%s failed: %s"):format(resName, fn, tostring(a)), 2)
        return nil
    end
    return a, b
end

local function loadFlights()
    local f = fileOpen("data/flights.json", true)
    if not f then
        outputDebugString("[avi_traffic] data/flights.json missing", 1)
        return
    end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    DB.types = data and data.types or {}
    DB.airlines = data and data.airlines or {}
    DB.externals = data and data.externals or {}
    DB.flights, DB.byCallsign = {}, {}
    for _, fl in ipairs(data and data.flights or {}) do
        if fl.callsign and fl.type and fl.dep and fl.arr and type(fl.route) == "table" then
            fl.callsign = tostring(fl.callsign):upper()
            -- cruise levels are always whole thousands (8000, not 8500)
            fl.cruise = math.max(1000, math.floor((tonumber(fl.cruise) or 6000) / 1000 + 0.5) * 1000)
            fl.period = tonumber(fl.period) or 60
            fl.offset = tonumber(fl.offset) or 0
            DB.flights[#DB.flights + 1] = fl
            DB.byCallsign[fl.callsign] = fl
        end
    end
    outputDebugString(("[avi_traffic] %d flights in the database"):format(#DB.flights))
end

function refreshAirports()
    WORLD.airports = callExport("avi_airports", "getAirports") or {}
end

function refreshNav()
    WORLD.nav, WORLD.procs = {}, {}
    for _, p in ipairs(callExport("avi_nav", "getNavPoints") or {}) do WORLD.nav[p.id] = p end
    for _, p in ipairs(callExport("avi_nav", "getProcedures") or {}) do WORLD.procs[p.id] = p end
end

function refreshAirspaces()
    WORLD.airspaces = callExport("avi_airspace", "getAirspaces") or {}
    WORLD.centre = callExport("avi_airspace", "getCentreSectors") or { split = 20500, sectors = {} }
    WORLD.centre.sectors = WORLD.centre.sectors or {}
    -- every centre position (they appear in the sector chains) + the base one
    CENTER_POSITIONS = { [TR.CENTER_POSITION] = true }
    UPPER_POSITIONS = {}
    local lower = {}
    for _, s in ipairs(WORLD.centre.sectors) do
        for _, pos in ipairs(s.chain or {}) do
            CENTER_POSITIONS[pos] = true
            if s.upper then UPPER_POSITIONS[pos] = true else lower[pos] = true end
        end
    end
    for pos in pairs(lower) do UPPER_POSITIONS[pos] = nil end
end

CENTER_POSITIONS = { [TR.CENTER_POSITION] = true }
UPPER_POSITIONS = {}     -- centre positions that own only upper sectors (SACC_U_CTR, SACC_NU_CTR, SACC_SU_CTR)

-- SACC_CTR and its split positions (north / south / upper ...)
function isCenterPosition(pos)
    return pos ~= nil and CENTER_POSITIONS[pos] == true
end

-- centre sector (avi_airspace `centre`) at the point: upper above the split level
function centreSectorAt(x, y, alt)
    local upper = alt > (tonumber(WORLD.centre.split) or 20500)
    for _, s in ipairs(WORLD.centre.sectors) do
        if (s.upper and true or false) == upper and pointInPolygon(x, y, s.polygon) then return s end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    loadFlights()
    refreshAirports()
    refreshNav()
    refreshAirspaces()
end)

addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if name == "avi_airports" then refreshAirports()
    elseif name == "avi_nav" then refreshNav()
    elseif name == "avi_airspace" then refreshAirspaces() end
end)

addEvent("onAviNavChange")
addEventHandler("onAviNavChange", root, refreshNav)

-- ---------------------------------------------------------------- lookups
function navPoint(id)
    return id and WORLD.nav[id]
end

function airport(icao)
    return icao and WORLD.airports[icao]
end

function typeInfo(t)
    return DB.types[t] or { wake = "M", cruise = 280, approach = 140, climb = 2000, descent = 1800 }
end

function pointInPolygon(x, y, poly)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

-- most specific airspace at the point (the list is sorted CTR > TMA > CTA by avi_airspace)
function airspaceAt(x, y, alt)
    for _, a in ipairs(WORLD.airspaces) do
        if alt >= (a.floor or 0) and alt <= (a.ceiling or 99999) and pointInPolygon(x, y, a.polygon) then return a end
    end
end

function insideCTA(x, y, margin)
    for _, a in ipairs(WORLD.airspaces) do
        if a.type == "CTA" then
            local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
            for _, p in ipairs(a.polygon) do
                minx, maxx = math.min(minx, p[1]), math.max(maxx, p[1])
                miny, maxy = math.min(miny, p[2]), math.max(maxy, p[2])
            end
            return x >= minx - margin and x <= maxx + margin and y >= miny - margin and y <= maxy + margin
        end
    end
    return math.abs(x) < 6000 + margin and math.abs(y) < 6000 + margin
end

-- bounding box of the CTA (minx, miny, maxx, maxy)
function ctaBox()
    for _, a in ipairs(WORLD.airspaces) do
        if a.type == "CTA" then
            local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
            for _, p in ipairs(a.polygon) do
                minx, maxx = math.min(minx, p[1]), math.max(maxx, p[1])
                miny, maxy = math.min(miny, p[2]), math.max(maxy, p[2])
            end
            return minx, miny, maxx, maxy
        end
    end
    return -6000, -6000, 6000, 6000
end

-- ---------------------------------------------------------------- procedures (SID / STAR of avi_nav)
function procedure(id)
    return id and WORLD.procs[tostring(id):upper()]
end

-- the procedure lists the fix as fly-over (`flyover` = { fixId, ... }; every other fix is fly-by)
function isFlyover(procId, fixId)
    local p = procedure(procId)
    if not (p and p.flyover and fixId) then return false end
    for _, f in ipairs(p.flyover) do
        if tostring(f):upper() == fixId then return true end
    end
    return false
end

-- fix list of a procedure for a runway end (a copy), nil when it has no such runway
function procedureRoute(id, ident)
    local p = procedure(id)
    if not p or not ident then return nil end
    ident = tostring(ident):upper()
    for k, r in pairs(p.runways or {}) do
        if tostring(k):upper() == ident or (tonumber(k) and tonumber(k) == tonumber(ident)) then
            local out = {}
            for i, f in ipairs(r) do out[i] = tostring(f):upper() end
            return out
        end
    end
end

-- go-around procedure of the runway end (fix list copy + procedure id), nil when there is none
function goAroundRoute(icao, ident)
    for _, p in pairs(WORLD.procs) do
        if p.type == "GA" and p.airport == icao then
            local r = procedureRoute(p.id, ident)
            if r then return r, p.id end
        end
    end
end

-- the procedure of `ptype` ("SID" / "STAR") at icao whose entry / exit fix is in the list:
-- SID = the first such fix, STAR = the last one
function procedureFor(icao, ptype, fixes)
    local best
    for i, f in ipairs(fixes or {}) do
        for _, p in pairs(WORLD.procs) do
            if p.airport == icao and p.type == ptype and p.fix == f then
                if ptype == "SID" then return p, i end
                best = { p, i }
            end
        end
    end
    if best then return best[1], best[2] end
end
