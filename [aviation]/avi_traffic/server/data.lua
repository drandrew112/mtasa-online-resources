-- Data for the simulation: the flight database (data/flights.json) and cached copies of the other
-- avi_* resources (airports, nav points, airspaces). The caches refresh when those resources
-- (re)start or the nav data changes. Never keep an exports table in a local: a restarted
-- resource gets a new one.

DB = { flights = {}, types = {}, airlines = {}, externals = {}, byCallsign = {} }
WORLD = { airports = {}, nav = {}, airspaces = {} }

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
            fl.cruise = tonumber(fl.cruise) or 6000
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
    WORLD.nav = {}
    for _, p in ipairs(callExport("avi_nav", "getNavPoints") or {}) do WORLD.nav[p.id] = p end
end

function refreshAirspaces()
    WORLD.airspaces = callExport("avi_airspace", "getAirspaces") or {}
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
    return math.abs(x) < 3500 + margin and math.abs(y) < 3500 + margin
end
