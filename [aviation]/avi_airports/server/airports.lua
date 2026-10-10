-- Airports (data/airports.json), keyed by ICAO code (SALS, SASF, SALV; the desert strip is left out).
--   arp {x, y, z}, elevation (ft), tower {x, y}
--   runways[] { id "09L/27R", width, use "arr"|"dep"|"both", ends[] { ident, x, y, z, hdg, final } }
--     an end is the threshold you land / take off FROM, hdg = the direction you roll; final = FIX id
--   taxiways[] { id, points[] {x, y} }   shared points are junctions
--   gates[] { id, x, y, hdg }
--   taxiDraw[] { x1, y1, x2, y2 }  generated: the taxiways as line pieces with rounded corners (scopes)

AIRPORTS = {}
local order = {}
local active = {}      -- [icao] = { arr = endIdent, dep = endIdent, manual = { arr = bool, dep = bool } }

addEvent("onAviRunwayChange")   -- source: resourceRoot, args: icao, use, ident

local function load()
    local f = fileOpen("data/airports.json", true)
    if not f then
        outputDebugString("[avi_airports] data/airports.json missing", 1)
        return
    end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    AIRPORTS, order = {}, {}
    for icao, a in pairs(data and data.airports or {}) do
        a.icao = icao
        for _, rw in ipairs(a.runways or {}) do
            for _, e in ipairs(rw.ends or {}) do
                e.runway = rw.id            -- an id, not the table: exports copy tables (no cycles)
                e.icao = icao
                e.hdg = tonumber(e.hdg) or 0
            end
        end
        a.taxiways = a.taxiways or {}
        a.gates = a.gates or {}
        AIRPORTS[icao] = a
        order[#order + 1] = icao
    end
    table.sort(order)
    buildTaxiGraphs()
    buildTaxiDraw()
    outputDebugString(("[avi_airports] %d airports: %s"):format(#order, table.concat(order, ", ")))
end

local function angleDiff(a, b)
    return math.abs((a - b + 180) % 360 - 180)
end

-- runway end with the most headwind among the runways usable for `use` ("arr" / "dep")
local function pickRunway(a, use)
    local best, bestScore
    for _, rw in ipairs(a.runways) do
        local fits = rw.use == use and 0 or (rw.use == "both" and 1 or nil)
        if fits then
            for _, e in ipairs(rw.ends) do
                local score = fits * 1000 + angleDiff(e.hdg, AP.WIND.dir)
                if not bestScore or score < bestScore then best, bestScore = e, score end
            end
        end
    end
    -- no runway marked for this use: any runway
    if not best then
        for _, rw in ipairs(a.runways) do
            for _, e in ipairs(rw.ends) do
                local score = angleDiff(e.hdg, AP.WIND.dir)
                if not bestScore or score < bestScore then best, bestScore = e, score end
            end
        end
    end
    return best
end

local function refreshActive()
    for _, icao in ipairs(order) do
        local a = AIRPORTS[icao]
        local s = active[icao] or { manual = {} }
        active[icao] = s
        for _, use in ipairs({ "arr", "dep" }) do
            if not s.manual[use] then
                local e = pickRunway(a, use)
                local ident = e and e.ident
                if ident ~= s[use] then
                    s[use] = ident
                    triggerEvent("onAviRunwayChange", resourceRoot, icao, use, ident)
                end
            end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    load()
    refreshActive()
end)

-- ---------------------------------------------------------------- exports
function getAirports()
    return AIRPORTS
end

function getAirport(icao)
    return icao and AIRPORTS[tostring(icao):upper()]
end

function getNearestAirport(x, y)
    local best, bestD
    for _, a in pairs(AIRPORTS) do
        local d = math.sqrt((a.arp[1] - x) ^ 2 + (a.arp[2] - y) ^ 2)
        if not bestD or d < bestD then best, bestD = a, d end
    end
    return best, bestD
end

function getRunwayEnd(icao, ident)
    local a = getAirport(icao)
    if not a then return end
    for _, rw in ipairs(a.runways) do
        for _, e in ipairs(rw.ends) do
            if e.ident == ident then return e end
        end
    end
end

-- the runway end in use for arrivals ("arr") or departures ("dep")
function getActiveRunway(icao, use)
    local s = active[icao and tostring(icao):upper()]
    if not s then return end
    return getRunwayEnd(icao, s[use == "dep" and "dep" or "arr"])
end

-- { [icao] = { arr = ident, dep = ident } }
function getActiveRunways()
    local out = {}
    for icao, s in pairs(active) do out[icao] = { arr = s.arr, dep = s.dep } end
    return out
end

-- ident nil = back to automatic (wind)
function setActiveRunway(icao, use, ident)
    icao = icao and tostring(icao):upper()
    local s = active[icao]
    if not s or (use ~= "arr" and use ~= "dep") then return false end
    if ident then
        if not getRunwayEnd(icao, ident) then return false end
        s.manual[use] = true
        s[use] = ident
        triggerEvent("onAviRunwayChange", resourceRoot, icao, use, ident)
    else
        s.manual[use] = nil
        refreshActive()
    end
    return true
end

function getWind()
    return { dir = AP.WIND.dir, speed = AP.WIND.speed }
end

function setWind(dir, speed)
    AP.WIND.dir = (tonumber(dir) or AP.WIND.dir) % 360
    AP.WIND.speed = tonumber(speed) or AP.WIND.speed
    refreshActive()
    return true
end

-- /aviwind <dir> [kts]  (admins)
addCommandHandler("aviwind", function(player, _, dir, speed)
    local res = getResourceFromName("avi_core")
    if not (res and getResourceState(res) == "running" and exports.avi_core:isAviationAdmin(player)) then return end
    if tonumber(dir) then setWind(dir, speed) end
    local parts = {}
    for _, icao in ipairs(order) do
        parts[#parts + 1] = ("%s arr %s dep %s"):format(icao, tostring(active[icao].arr), tostring(active[icao].dep))
    end
    triggerClientEvent(player, "avi:notify", root, "WIND",
        ("%03d/%d kt - %s"):format(AP.WIND.dir, AP.WIND.speed, table.concat(parts, ", ")))
end)
