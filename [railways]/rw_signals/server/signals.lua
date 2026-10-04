-- Block signalling (both tracks, both directions; the main line all the way round).
--
-- Every signalled stretch is cut into blocks at fixed boundaries (stations, junction areas)
-- plus automatic ones. Each boundary has a signal for each direction, protecting the block
-- in front of it:
--   RED     the block is occupied (a reversed crossover links the blocks on both tracks),
--           or its direction-lock section is claimed by a train coming the other way
--   YELLOW  the next signal in the same direction is red (or the stretch ends there)
--   GREEN   otherwise
-- Direction lock: the blocks between two stations form a section. The first train inside
-- (or approaching within SIG.APPROACH) claims its direction, so two trains can never enter
-- a single line from both ends - neither head-on nor rear-end collisions are possible as
-- long as drivers obey the signals. Passing a red signal fires onRailSignalPassedAtDanger.
--
-- A loop route (the main line) has no ends: the last block wraps over the track start, so
-- block / section ranges may run past the track length (L). Positions are compared with
-- the wrap in mind (overlap tests try +-L, distances use rel()).

-- looked up on every call: a reloaded rw_core is a new resource and a cached exports table
-- would keep calling the old one (everything froze after rw_core reloaded)
local core = setmetatable({}, { __index = function(_, fn) return function(_, ...) return exports.rw_core[fn](nil, ...) end end })
local A = SIG.ASPECT

Routes = {}
Signals = {}          -- [id] = signal
local byTrack = {}    -- [track] = { signals sorted by tp }
local memory = {}     -- [consistId] = { head, lastDir, track }
local clientsReady = {}

addEvent("onRailSignalPassedAtDanger")   -- source: lead vehicle, (consistId, signalId, signalName)
addEvent("onRailSignalChange")           -- source: resourceRoot, (signalId, aspect, previous aspect|nil, signalName)

local function proj(track, x, y, maxD)
    local t, tp = core:projectToTrack(x, y, track, maxD or 40)
    if t then return tp end
end

local function routeOfTrack(track)
    for _, r in ipairs(Routes) do if r.track == track then return r end end
end

-- signed shortest distance a -> b on the route's track
local function rel(route, a, b)
    local d = b - a
    if route.loop then
        local L = route.L
        d = d % L
        if d > L / 2 then d = d - L end
    end
    return d
end

-- does [lo, hi] (raw) touch [a, b] (raw), wrap-aware on loops
local function touches(route, lo, hi, a, b)
    if hi >= a and lo <= b then return true end
    if route.loop then
        local L = route.L
        if hi + L >= a and lo + L <= b then return true end
        if hi - L >= a and lo - L <= b then return true end
    end
    return false
end

local function blockAt(route, tp)
    for i, b in ipairs(route.blocks) do
        if (tp >= b.lo and tp < b.hi) or (route.loop and tp + route.L >= b.lo and tp + route.L < b.hi) then return i, b end
    end
end

------------------------------------------------------------------------- build

local function addBoundary(list, tp, name, kind)
    for _, b in ipairs(list) do
        if math.abs(b.tp - tp) < 40 then
            if kind == "station" then b.kind = "station" b.name = name end
            return
        end
    end
    list[#list + 1] = { tp = tp, name = name, kind = kind }
end

local function buildRoute(def)
    local route = { track = def.track, prefix = def.prefix, loop = def.loop and true or false, blocks = {}, sections = {} }
    local bounds = {}
    local from, to
    if route.loop then
        route.L = core:getTrackLength(def.track)
        from, to = 0, route.L
    else
        from, to = proj(def.track, def.from.x, def.from.y), proj(def.track, def.to.x, def.to.y)
        if not from or not to then
            outputDebugString("[rw_signals] route on track " .. def.track .. ": endpoints off the track", 2)
            return
        end
        if from > to then from, to = to, from end
        addBoundary(bounds, from, def.prefix .. " start", "end")
        addBoundary(bounds, to, def.prefix .. " end", "end")
    end
    for _, b in ipairs(SIG.BOUNDARIES) do
        local tp = proj(def.track, b.x, b.y, 15)
        if tp and (route.loop or (tp > from + 20 and tp < to - 20)) then addBoundary(bounds, tp, b.name, b.type) end
    end
    table.sort(bounds, function(a, b) return a.tp < b.tp end)
    if #bounds < 2 then return end

    -- loops: rotate so the list starts at a station (sections are built from there)
    if route.loop then
        for i, b in ipairs(bounds) do
            if b.kind == "station" then
                local rot = {}
                for k = 0, #bounds - 1 do
                    local o = bounds[(i - 1 + k) % #bounds + 1]
                    local tp = o.tp
                    if k > 0 and tp < bounds[i].tp then tp = tp + route.L end   -- unwrap
                    rot[#rot + 1] = { tp = tp, name = o.name, kind = o.kind }
                end
                bounds = rot
                break
            end
        end
    end

    -- automatic blocks (for loops including the gap back to the first boundary)
    local filled = {}
    local n0 = #bounds
    for i = 1, n0 do
        local b = bounds[i]
        filled[#filled + 1] = b
        local nb = bounds[i + 1]
        local nbTp = nb and nb.tp or (route.loop and bounds[1].tp + route.L or nil)
        if nbTp then
            local gap = nbTp - b.tp
            local n = math.floor(gap / SIG.AUTO_BLOCK + 0.5)
            for k = 1, n - 1 do
                filled[#filled + 1] = { tp = b.tp + gap * k / n, name = "Block", kind = "block" }
            end
        end
    end
    route.bounds = filled

    local nb = #filled
    local blockCount = route.loop and nb or nb - 1
    local section = { first = 1 }
    for i = 1, blockCount do
        local lo = filled[i].tp
        local hi = filled[i + 1] and filled[i + 1].tp or (filled[1].tp + route.L)
        route.blocks[i] = { lo = lo, hi = hi, occ = false, section = #route.sections + 1 }
        local nextB = filled[i + 1] or filled[1]
        if nextB.kind ~= "block" or i == blockCount then
            section.last = i
            section.lo, section.hi = filled[section.first].tp, hi
            route.sections[#route.sections + 1] = section
            section = { first = i + 1 }
        end
    end
    Routes[#Routes + 1] = route
    return route
end

-- side of the track away from the other tracks (a pole must never stand between them)
local function poleSide(track, tp, tx, ty)
    local x, y = core:getTrackPoint(track, tp)
    local rx, ry = ty, -tx
    for _, r in ipairs(Routes) do
        if r.track ~= track then
            local t = proj(r.track, x + rx * 4, y + ry * 4, 2.6)
            if t then return -1 end
        end
    end
    return 1
end

local nextId = 0
local function addSignal(route, boundIndex, dir, block)
    local b = route.bounds[boundIndex]
    local tp = route.loop and (b.tp % route.L) or b.tp
    -- the pole stands a little before the boundary, so the two directions never share a spot
    local x, y, z, dx, dy = core:getTrackPoint(route.track, tp - dir * 4)
    local tx, ty = dx * dir, dy * dir               -- travel direction
    local side = poleSide(route.track, tp, tx, ty)
    local rx, ry = ty * side, -tx * side
    nextId = nextId + 1
    local s = {
        id = nextId, track = route.track, tp = tp, dir = dir, block = block, route = route,
        name = ("%s%d%s"):format(route.prefix, boundIndex, dir > 0 and "W" or "E"),
        place = b.name, kind = b.kind,
        x = x + rx * SIG.LATERAL, y = y + ry * SIG.LATERAL, z = z,
        fx = -tx, fy = -ty,                         -- the head faces oncoming trains
        aspect = A.RED, prevAspect = A.RED,
    }
    local sc = SIG.POLE_SCALE
    s.pole = createObject(SIG.POLE_MODEL, s.x, s.y, s.z)
    if s.pole then
        setObjectScale(s.pole, sc[1], sc[2], sc[3])
        setElementFrozen(s.pole, true)
        setElementData(s.pole, "rw.signal", s.id, false)
    end
    Signals[s.id] = s
    byTrack[route.track] = byTrack[route.track] or {}
    table.insert(byTrack[route.track], s)
    return s
end

------------------------------------------------------------------------- single track

-- SIG.SINGLE: stretches on both lines at once. Positions per line: ranges[track] = { lo, hi,
-- sign } (sign = +1 when the line's +tp runs from a to b), claims in "a -> b" terms (+1 / -1).
Singles = {}

local function addSingleSignal(sg, track, tp, dir, endName)
    local x, y, z, dx, dy = core:getTrackPoint(track, tp)
    local tx, ty = dx * dir, dy * dir
    local side = poleSide(track, tp, tx, ty)
    local rx, ry = ty * side, -tx * side
    nextId = nextId + 1
    local s = {
        id = nextId, track = track, tp = tp, dir = dir, single = sg,
        abDir = dir * sg.ranges[track].sign,          -- the way a train passing it goes (a -> b = +1)
        name = ("%s%s%s"):format(sg.prefix, track == 0 and "M" or "S", endName),
        place = sg.name, kind = "single",
        x = x + rx * SIG.LATERAL, y = y + ry * SIG.LATERAL, z = z,
        fx = -tx, fy = -ty,
        aspect = A.RED, prevAspect = A.RED,
    }
    local sc = SIG.POLE_SCALE
    s.pole = createObject(SIG.POLE_MODEL, s.x, s.y, s.z)
    if s.pole then
        setObjectScale(s.pole, sc[1], sc[2], sc[3])
        setElementFrozen(s.pole, true)
        setElementData(s.pole, "rw.signal", s.id, false)
    end
    Signals[s.id] = s
    byTrack[track] = byTrack[track] or {}
    table.insert(byTrack[track], s)
    sg.signals[#sg.signals + 1] = s
end

function buildSingles()
    for _, def in ipairs(SIG.SINGLE or {}) do
        local sg = { name = def.name, prefix = def.prefix, ranges = {}, signals = {}, claim = nil }
        for _, track in ipairs(SIG.SINGLE_TRACKS) do
            local ta, tb = proj(track, def.a.x, def.a.y, 15), proj(track, def.b.x, def.b.y, 15)
            if ta and tb then
                local d = core:getTrackDelta(track, ta, tb)
                local sign = d >= 0 and 1 or -1
                local lo = sign > 0 and ta or tb
                sg.ranges[track] = { lo = lo, hi = lo + math.abs(d), sign = sign, L = core:getTrackLength(track) }
            else
                outputDebugString(("[rw_signals] single track %s: not on track %d"):format(def.name, track), 2)
            end
        end
        Singles[#Singles + 1] = sg
        for track, r in pairs(sg.ranges) do
            local E = SIG.SINGLE_ENTRY
            addSingleSignal(sg, track, (r.lo - E) % r.L, 1, r.sign > 0 and "A" or "B")
            addSingleSignal(sg, track, (r.hi + E) % r.L, -1, r.sign > 0 and "B" or "A")
        end
    end
end

-- distance on a loop track from a to b going in direction dir (>= 0)
local function ahead(L, a, b, dir)
    return ((b - a) * dir) % L
end

local function computeSingles(consists)
    for _, sg in ipairs(Singles) do
        sg.occ = false
        local insideDir, approach, approachDist, keepPrev = nil, nil, math.huge, false
        for _, c in ipairs(consists) do
            local r = sg.ranges[c.track]
            if r then
                local mem = memory[c.id]
                local dir = c.moveDir ~= 0 and c.moveDir or (mem and mem.lastDir) or 0
                local L = r.L
                -- overlap of the train [c.lo, c.hi] with the stretch [r.lo, r.hi] (wrap-aware)
                local inside = false
                for _, k in ipairs({ 0, L, -L }) do
                    if c.hi + k >= r.lo and c.lo + k <= r.hi then inside = true end
                end
                if inside then
                    sg.occ = true
                    if dir ~= 0 then insideDir = insideDir or dir * r.sign end
                elseif c.moveDir ~= 0 then
                    local dist = c.moveDir > 0 and ahead(L, c.hi, r.lo, 1) or ahead(L, c.lo, r.hi, -1)
                    local abDir = c.moveDir * r.sign
                    if dist < SIG.APPROACH then
                        if sg.claim == abDir then keepPrev = true end
                        if dist < approachDist then approach, approachDist = abDir, dist end
                    end
                end
            end
        end
        if insideDir then sg.claim = insideDir
        elseif keepPrev then -- the claim stays with the train that made it
        elseif approach then sg.claim = approach
        else sg.claim = nil end
        for _, s in ipairs(sg.signals) do
            s.red = sg.occ or (sg.claim ~= nil and sg.claim ~= s.abDir)
        end
    end
end

local function buildAll()
    for _, def in ipairs(SIG.ROUTES) do buildRoute(def) end
    for _, route in ipairs(Routes) do
        local nb = #route.bounds
        for i = 1, #route.blocks do
            local nextIndex = (i % nb) + 1
            addSignal(route, i, 1, i)              -- facing increasing tp, protects block i
            addSignal(route, nextIndex, -1, i)     -- facing decreasing tp, protects block i
        end
    end
    buildSingles()
    for _, list in pairs(byTrack) do table.sort(list, function(a, b) return a.tp < b.tp end) end
    local n = 0
    for _ in pairs(Signals) do n = n + 1 end
    outputDebugString(("[rw_signals] %d signals on %d stretch(es)"):format(n, #Routes))
end

------------------------------------------------------------------------- logic

local function computeOccupancy(consists, switches)
    for _, r in ipairs(Routes) do for _, b in ipairs(r.blocks) do b.occ = false end end
    for _, c in ipairs(consists) do
        local r = routeOfTrack(c.track)
        if r then
            for _, b in ipairs(r.blocks) do
                if touches(r, c.lo, c.hi, b.lo, b.hi) then b.occ = true end
            end
        end
    end
    -- a reversed crossover joins the blocks it connects
    for _, w in ipairs(switches) do
        if w.state == "reverse" and w.a and w.b then
            local ra, rb = routeOfTrack(w.a.track), routeOfTrack(w.b.track)
            local _, ba = ra and blockAt(ra, w.a.tp)
            local _, bb = rb and blockAt(rb, w.b.tp)
            if ba and bb and (ba.occ or bb.occ) then ba.occ = true bb.occ = true end
        end
    end
end

local function computeClaims(consists)
    for _, r in ipairs(Routes) do
        for _, s in ipairs(r.sections) do
            local insideDir, approach, approachDist = nil, nil, math.huge
            local keepPrev = false
            for _, c in ipairs(consists) do
                if c.track == r.track then
                    local mem = memory[c.id]
                    local dir = c.moveDir ~= 0 and c.moveDir or (mem and mem.lastDir) or 0
                    if touches(r, c.lo, c.hi, s.lo, s.hi) then
                        if dir ~= 0 then insideDir = insideDir or dir end
                    elseif c.moveDir ~= 0 then
                        local dist
                        if c.moveDir > 0 then dist = rel(r, c.hi, s.lo) else dist = rel(r, s.hi, c.lo) end
                        if dist > 0 and dist < SIG.APPROACH then
                            if s.claim == c.moveDir then keepPrev = true end
                            if dist < approachDist then approach, approachDist = c.moveDir, dist end
                        end
                    end
                end
            end
            if insideDir then s.claim = insideDir
            elseif keepPrev then -- the claim stays with the train that made it
            elseif approach then s.claim = approach
            else s.claim = nil end
        end
    end
end

-- the next signal of the same direction and route (wraps round on loops)
local function nextSignal(s)
    local list = byTrack[s.track]
    local n = #list
    for i, o in ipairs(list) do
        if o == s then
            for step = 1, n - 1 do
                local k = i + s.dir * step
                if s.route.loop then k = (k - 1) % n + 1
                elseif k < 1 or k > n then return nil end
                local c = list[k]
                if c.dir == s.dir and c.route == s.route then return c end
            end
        end
    end
end

-- red signals are stop points for the trains' ATP (rw_customtracks): a train never runs past one
local stopsSent, lastStopPush = false, 0
function pushStops()
    lastStopPush = getTickCount()
    local list = {}
    for id, s in pairs(Signals) do
        if s.aspect == A.RED then list[#list + 1] = { line = s.track, tp = s.tp, dir = s.dir, id = id } end
    end
    local res = getResourceFromName("rw_customtracks")
    if res and getResourceState(res) == "running" then
        exports.rw_customtracks:setNetStopPoints(list)
        stopsSent = true
    end
end

local function computeAspects()
    for _, s in pairs(Signals) do
        if not s.single then
            local b = s.route.blocks[s.block]
            local sec = s.route.sections[b.section]
            s.red = b.occ or (sec.claim ~= nil and sec.claim == -s.dir)
        end
    end
    local changes, any = {}, false
    for id, s in pairs(Signals) do
        local a
        if s.red then a = A.RED
        elseif s.single then a = A.GREEN
        else
            if s.next == nil then s.next = nextSignal(s) or false end
            if not s.next or s.next.red then a = A.YELLOW else a = A.GREEN end
        end
        s.prevAspect = s.aspect
        if a ~= s.aspect then
            s.aspect = a
            changes[id] = a
            any = true
            triggerEvent("onRailSignalChange", resourceRoot, id, a, s.prevAspect, s.name)
        end
    end
    -- on change, and every few seconds (rw_customtracks may have restarted)
    if any or not stopsSent or getTickCount() - lastStopPush > 5000 then pushStops() end
    return any and changes
end

-- trains passing a signal that showed red at the previous tick (their own block entry is not
-- counted: the head was still in front of the signal then)
local function checkPassing(consists)
    local seen = {}
    for _, c in ipairs(consists) do
        seen[c.id] = true
        local mem = memory[c.id]
        if not mem then mem = {} memory[c.id] = mem end
        if c.moveDir ~= 0 then mem.lastDir = c.moveDir end
        local head = (c.moveDir >= 0) and c.hi or c.lo
        local r = routeOfTrack(c.track)
        if r and mem.head and mem.track == c.track and c.moveDir ~= 0 and math.abs(rel(r, mem.head, head)) < 100 then
            for _, s in ipairs(byTrack[c.track] or {}) do
                if s.dir == c.moveDir then
                    local before = rel(r, s.tp, mem.head) * s.dir < 0
                    local after = rel(r, s.tp, head) * s.dir >= 0
                    if before and after and s.prevAspect == A.RED and isElement(c.lead) then
                        triggerEvent("onRailSignalPassedAtDanger", c.lead, c.id, s.id, s.name)
                    end
                end
            end
        end
        mem.head, mem.track = head, c.track
    end
    for id in pairs(memory) do if not seen[id] then memory[id] = nil end end
end

local function tick()
    local ok, consists = pcall(function() return core:getConsists() end)
    if not ok or type(consists) ~= "table" then return end
    local switches = {}
    pcall(function() switches = core:getSwitches() or {} end)
    computeOccupancy(consists, switches)
    computeClaims(consists)
    computeSingles(consists)
    local changes = computeAspects()
    checkPassing(consists)
    if changes then
        local list = {}
        for p in pairs(clientsReady) do if isElement(p) then list[#list + 1] = p else clientsReady[p] = nil end end
        if #list > 0 then triggerClientEvent(list, "rw:sig:aspects", resourceRoot, changes) end
    end
end

------------------------------------------------------------------------- exports

function getSignalList()
    local t = {}
    for id, s in pairs(Signals) do
        t[#t + 1] = { id = id, name = s.name, x = math.floor(s.x * 10) / 10, y = math.floor(s.y * 10) / 10, dir = s.dir, track = s.track }
    end
    table.sort(t, function(a, b) return a.id < b.id end)
    return t
end

function getSignalAspects()
    local t = {}
    for id, s in pairs(Signals) do t[tostring(id)] = s.aspect end
    return t
end

function getSignal(id)
    local s = Signals[id]
    if not s then return false end
    return { id = s.id, name = s.name, place = s.place, track = s.track, tp = s.tp, dir = s.dir, aspect = s.aspect, x = s.x, y = s.y, z = s.z }
end

-- next signal in front of a consist (its moving direction, or the way it faces when standing)
function getSignalAhead(consistId)
    local c = core:getConsist(consistId)
    if not c then return false end
    local r = routeOfTrack(c.track)
    if not r then return false end
    local dir = c.moveDir ~= 0 and c.moveDir or c.dir
    local head = dir > 0 and c.hi or c.lo
    local best, bestD
    for _, s in ipairs(byTrack[c.track] or {}) do
        if s.dir == dir then
            local d = (s.tp - head) * dir
            if r.loop then d = d % r.L end
            if d >= -2 and (not bestD or d < bestD) then best, bestD = s, d end
        end
    end
    if not best then return false end
    return { id = best.id, name = best.name, aspect = best.aspect, distance = math.max(0, bestD) }
end

------------------------------------------------------------------------- clients

local function clientList()
    local t = {}
    for id, s in pairs(Signals) do
        t[#t + 1] = { id, s.name, s.track, s.tp, s.dir, s.x, s.y, s.z, s.fx, s.fy, s.aspect }
    end
    local loops = {}
    for _, r in ipairs(Routes) do if r.loop then loops[r.track] = r.L end end
    return t, loops
end

addEvent("rw:sig:request", true)
addEventHandler("rw:sig:request", resourceRoot, function()
    clientsReady[client] = true
    local list, loops = clientList()
    triggerClientEvent(client, "rw:sig:list", resourceRoot, list, loops)
end)

addEventHandler("onPlayerQuit", root, function() clientsReady[source] = nil end)

addEventHandler("onResourceStart", resourceRoot, function()
    buildAll()
    tick()
    setTimer(tick, SIG.TICK, 0)
end)
