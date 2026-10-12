-- sanandreascontrol.eu: the ATC website. Over HTTP at /avi_web/, in game as a ui_browser (CEF) site
-- served through web_api. The page calls the http="true" exports below (OSA.api().call).
--   documents : Markdown files in docs/, listed in docs/index.json (read here, never sent as files);
--               figures in web/img: jpg / png are client files, svg are sent by sacGetImage
--   status    : open positions, runways in use, wind, traffic counts (live)
--   nav       : airspaces, nav points, procedures, airports for the procedure lists and the map

local SITE = {
    title = "San Andreas Control",
    site = "sanandreascontrol.eu",
    category = "services",
    description = "San Andreas air traffic control: letters of agreement, procedures, airspace map and live ATC status.",
}

local DOCS, DOC_BY_ID = {}, {}

local function readFile(path)
    local f = fileExists(path) and fileOpen(path, true)
    if not f then return nil end
    local content = fileRead(f, fileGetSize(f))
    fileClose(f)
    return content
end

-- exports of another avi_* resource; nil when it is not running or the call fails
local function call(resName, fn, ...)
    local res = getResourceFromName(resName)
    if not res or getResourceState(res) ~= "running" then return nil end
    local ok, a = pcall(function(...) return exports[resName][fn](exports[resName], ...) end, ...)
    if not ok then
        outputDebugString(("[avi_web] %s:%s failed: %s"):format(resName, fn, tostring(a)), 2)
        return nil
    end
    return a
end

local function loadDocs()
    DOCS, DOC_BY_ID = {}, {}
    local data = fromJSON(readFile("docs/index.json") or "")
    for _, d in ipairs(data and data.documents or {}) do
        if d.id and d.file then
            DOCS[#DOCS + 1] = d
            DOC_BY_ID[d.id] = d
        end
    end
    outputDebugString(("[avi_web] %d documents"):format(#DOCS))
end

-- ---------------------------------------------------------------- web API
-- the document list (without the text)
function sacGetDocuments()
    local out = {}
    for _, d in ipairs(DOCS) do
        out[#out + 1] = { id = d.id, title = d.title, code = d.code, category = d.category,
            version = d.version, updated = d.updated, summary = d.summary }
    end
    return out
end

-- one document: its list entry + the Markdown text (read every time, so an edit shows after a reload)
function sacGetDocument(id)
    local d = DOC_BY_ID[tostring(id or "")]
    if not d then return false end
    return { id = d.id, title = d.title, code = d.code, category = d.category, version = d.version,
        updated = d.updated, summary = d.summary, text = readFile(d.file) or "" }
end

-- an SVG figure of the documents (web/img/<name>.svg) as text: MTA serves files as
-- application/octet-stream, which browsers do not show as an SVG image, so the page inlines it
function sacGetImage(name)
    name = tostring(name or "")
    if not name:match("^[%w%-_]+%.svg$") then return false end
    return readFile("web/img/" .. name) or false
end

function sacGetStatus()
    local staffed = call("avi_controller", "getStaffedPositions") or {}
    local positions = {}
    for _, p in ipairs(call("avi_controller", "getPositions") or {}) do
        positions[#positions + 1] = { id = p.id, type = p.type, name = p.name, airport = p.airport,
            controller = staffed[p.id] or false }
    end

    local active = call("avi_airports", "getActiveRunways") or {}
    local airports = {}
    for icao, a in pairs(call("avi_airports", "getAirports") or {}) do
        local s = active[icao] or {}
        airports[#airports + 1] = { icao = icao, name = a.name, city = a.city, elevation = a.elevation,
            arr = s.arr or false, dep = s.dep or false, arrivals = 0, departures = 0, ground = 0 }
    end
    table.sort(airports, function(a, b) return a.icao < b.icao end)
    local byIcao = {}
    for _, a in ipairs(airports) do byIcao[a.icao] = a end

    -- traffic: per airport inbound / outbound, overall airborne / on the ground
    local total, airborne, overflights = 0, 0, 0
    for _, ac in ipairs(call("avi_traffic", "getTrafficSnapshot") or {}) do
        total = total + 1
        if not ac.gnd then airborne = airborne + 1 end
        local da, aa = byIcao[ac.dep], byIcao[ac.arr]
        -- outbound until it has landed somewhere, inbound unless it is still on the ground at its origin
        if da and not (ac.gnd and ac.dir == "arr") then da.departures = da.departures + 1 end
        if aa and not (ac.gnd and ac.dir == "dep") then aa.arrivals = aa.arrivals + 1 end
        if ac.gnd and byIcao[ac.apt] then byIcao[ac.apt].ground = byIcao[ac.apt].ground + 1 end
        if not da and not aa then overflights = overflights + 1 end
    end

    local wind = call("avi_airports", "getWind") or {}
    return {
        time = getRealTime().timestamp,
        wind = { dir = wind.dir or 0, speed = wind.speed or 0 },
        positions = positions,
        airports = airports,
        traffic = { total = total, airborne = airborne, ground = total - airborne, overflights = overflights },
    }
end

function sacGetNav()
    local airports = {}
    for icao, a in pairs(call("avi_airports", "getAirports") or {}) do
        local rws = {}
        for _, rw in ipairs(a.runways or {}) do
            local ends = {}
            for _, e in ipairs(rw.ends or {}) do
                ends[#ends + 1] = { ident = e.ident, x = e.x, y = e.y, hdg = e.hdg, final = e.final }
            end
            rws[#rws + 1] = { id = rw.id, use = rw.use, width = rw.width, ends = ends }
        end
        airports[#airports + 1] = { icao = icao, name = a.name, city = a.city, short = a.short,
            elevation = a.elevation, arp = a.arp, runways = rws }
    end
    table.sort(airports, function(a, b) return a.icao < b.icao end)

    local airspaces = {}
    for _, s in ipairs(call("avi_airspace", "getAirspaces") or {}) do
        airspaces[#airspaces + 1] = { id = s.id, type = s.type, name = s.name, airport = s.airport or false,
            floor = s.floor, ceiling = s.ceiling, polygon = s.polygon }
    end
    local centre = call("avi_airspace", "getCentreSectors") or {}

    local points = {}
    for _, p in ipairs(call("avi_nav", "getNavPoints") or {}) do
        points[#points + 1] = { id = p.id, x = p.x, y = p.y, type = p.type, kind = p.kind, name = p.name,
            freq = p.freq, airport = p.airport, runway = p.runway, role = p.role }
    end
    local procedures = {}
    for _, p in ipairs(call("avi_nav", "getProcedures") or {}) do
        procedures[#procedures + 1] = { id = p.id, type = p.type, airport = p.airport, fix = p.fix, runways = p.runways }
    end
    return { airports = airports, airspaces = airspaces, centre = { split = centre.split, line = centre.line },
        points = points, procedures = procedures }
end

-- ---------------------------------------------------------------- in-game site (ui_browser, CEF)
local function registerSite()
    exports.web_api:registerApp(SITE)
end

addEventHandler("onResourceStart", resourceRoot, function()
    loadDocs()
    registerSite()
end)
addEventHandler("onWebApiStart", root, registerSite)   -- web_api restarted
