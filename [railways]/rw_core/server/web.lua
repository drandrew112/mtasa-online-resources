-- Network map web API. The same two functions serve the HTTP page (POST /rw_core/call/<fn>,
-- exports with http="true") and the in-game ui_browser page (mta.triggerEvent bridge,
-- client/webpage.lua -> "rw:web:call"). Read-only, no login.
-- Stations / trips come from rw_timetable and signals from rw_signals when they run (no hard
-- dependency: they include rw_core, not the other way round).

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function call(res, fn, ...)
    if not running(res) then return nil end
    local ok, a = pcall(function(...) return exports[res][fn](exports[res], ...) end, ...)
    if ok then return a end
    return nil
end

local function clean(name) return (name or ""):gsub("#%x%x%x%x%x%x", "") end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

-- static data, built once (tracks never change while running)
local networkCache
local function buildNetwork()
    -- every segment of the rw_customtracks network (lines, crossovers, yards, station tracks)
    local tracks = {}
    for _, sg in ipairs(call("rw_customtracks", "netListSegments") or {}) do
        local pts = {}
        local len = sg.len
        local n = math.max(1, math.ceil(len / 15))
        for k = 0, n do
            local p = call("rw_customtracks", "netPointAt", sg.id, len * k / n)
            if p then pts[#pts + 1] = { r1(p.x), r1(p.y) } end
        end
        tracks[#tracks + 1] = { id = sg.id, name = sg.name or sg.id, kind = sg.kind, closed = false, points = pts }
    end
    return { company = RW.COMPANY, short = RW.COMPANY_SHORT, tracks = tracks }
end

function rwGetNetwork()
    networkCache = networkCache or buildNetwork()
    local net = {}
    for k, v in pairs(networkCache) do net[k] = v end
    net.stations = call("rw_timetable", "getStations") or {}
    net.signals = call("rw_signals", "getSignalList") or {}
    local sw = {}
    for _, s in ipairs(getSwitches()) do sw[#sw + 1] = { id = s.id, name = s.name, x = s.x, y = s.y } end
    net.switches = sw
    return net
end

function rwGetState()
    local rt = getRealTime()
    local consists = {}
    for _, c in ipairs(getConsists()) do
        local rz = 0
        if isElement(c.lead) then local _, _, z = getElementRotation(c.lead) rz = z end
        local svc = call("rw_timetable", "getConsistService", c.id)
        local types = {}
        for _, t in ipairs(c.types) do types[#types + 1] = RW.VEHICLES[t] and RW.VEHICLES[t].name or t end
        consists[#consists + 1] = {
            id = c.id, label = c.label, x = r1(c.x), y = r1(c.y), rz = math.floor(rz), track = c.track,
            trackName = RW.TRACK_NAMES[c.track] or tostring(c.track),
            speed = math.floor(c.speed + 0.5), moving = c.moveDir ~= 0,
            driver = c.auto and "Automatic" or (c.driver and clean(getPlayerName(c.driver)) or false),
            auto = c.auto,
            loco = RW.VEHICLES[c.loco] and RW.VEHICLES[c.loco].name or c.loco,
            vehicles = types, carriages = c.carriages, seats = c.seats,
            service = svc or false,
        }
    end
    local switches = {}
    for _, s in ipairs(getSwitches()) do switches[#switches + 1] = { id = s.id, state = s.state, locked = s.locked } end
    return {
        ok = true,
        time = rt.hour * 3600 + rt.minute * 60 + rt.second,
        consists = consists,
        switches = switches,
        aspects = call("rw_signals", "getSignalAspects") or {},
        trips = call("rw_timetable", "getTripsOverview") or {},
    }
end

-- departure / arrival boards of every station (the station panel on the right)
local BOARD_ROWS = 12
function rwGetBoards()
    return { ok = true, boards = call("rw_timetable", "getStationBoards", BOARD_ROWS) or {} }
end

-- in-game page bridge
local ALLOWED = { rwGetNetwork = true, rwGetState = true, rwGetBoards = true }
addEvent("rw:web:call", true)
addEventHandler("rw:web:call", resourceRoot, function(localId, fn)
    local player = client
    if not isElement(player) or not ALLOWED[fn] then return end
    local ok, result = pcall(_G[fn])
    if not ok then
        outputDebugString("[rw_core] web " .. tostring(fn) .. ": " .. tostring(result), 1)
        result = { ok = false, error = "Server error" }
    end
    triggerLatentClientEvent(player, "rw:web:result", 200000, false, resourceRoot, localId, result)
end)
