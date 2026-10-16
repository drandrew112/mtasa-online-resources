-- Network data for other resources (the public transport website pt_web draws its map and
-- live train list from these). Plain server exports, no web code here.

local function clean(name) return (name or ""):gsub("#%x%x%x%x%x%x", "") end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

-- static geometry, built once (tracks never change while running)
local geometryCache
local function buildGeometry()
    -- every segment of the rw_customtracks network (lines, crossovers, yards, station tracks)
    local tracks = {}
    local net = exports.rw_customtracks
    for _, sg in ipairs(net:netListSegments() or {}) do
        local pts = {}
        local len = sg.len
        local n = math.max(1, math.ceil(len / 15))
        for k = 0, n do
            local p = net:netPointAt(sg.id, len * k / n)
            if p then pts[#pts + 1] = { r1(p.x), r1(p.y) } end
        end
        tracks[#tracks + 1] = { id = sg.id, name = sg.name or sg.id, kind = sg.kind, closed = false, points = pts }
    end
    return tracks
end

-- -> { company, short, tracks = { { id, name, kind, points = { {x, y} } } }, switches = { {id, name, x, y} } }
function getNetworkGeometry()
    if not geometryCache then
        local ok, tracks = pcall(buildGeometry)
        if not ok then return false end
        geometryCache = tracks
    end
    local sw = {}
    for _, s in ipairs(getSwitches()) do sw[#sw + 1] = { id = s.id, name = s.name, x = s.x, y = s.y } end
    return { company = RW.COMPANY, short = RW.COMPANY_SHORT, tracks = geometryCache, switches = sw }
end

-- -> { consists = { ... }, switches = { {id, state, locked} } } - every train on the network,
-- names resolved (no elements), for maps / lists
function getNetworkTrains()
    local consists = {}
    for _, c in ipairs(getConsists()) do
        local rz = 0
        if isElement(c.lead) then local _, _, z = getElementRotation(c.lead) rz = z end
        local types = {}
        for _, t in ipairs(c.types) do types[#types + 1] = RW.VEHICLES[t] and RW.VEHICLES[t].name or t end
        consists[#consists + 1] = {
            id = c.id, number = c.number, label = c.label, x = r1(c.x), y = r1(c.y), rz = math.floor(rz), track = c.track,
            trackName = RW.TRACK_NAMES[c.track] or tostring(c.track),
            speed = math.floor(c.speed + 0.5), moving = c.moveDir ~= 0,
            driver = c.auto and "Automatic" or (c.driver and clean(getPlayerName(c.driver)) or false),
            auto = c.auto,
            loco = RW.VEHICLES[c.loco] and RW.VEHICLES[c.loco].name or c.loco,
            vehicles = types, carriages = c.carriages, seats = c.seats,
        }
    end
    local switches = {}
    for _, s in ipairs(getSwitches()) do switches[#switches + 1] = { id = s.id, state = s.state, locked = s.locked } end
    return { consists = consists, switches = switches }
end
