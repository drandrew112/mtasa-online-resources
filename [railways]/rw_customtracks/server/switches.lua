-- Switches (server). Nobody throws them by hand: a train with a destination gets its route
-- reserved switch by switch ahead of it (the router), and an authority (ATP) up to the first
-- switch it could not get or to its destination. Reservations are released behind the train.
--
-- A switch (group) cannot be thrown while a train is on it / within LOCK_MARGIN, while another
-- owner holds it, or while it is damaged (trailed the wrong way; repaired after REPAIR_TIME).
-- Spring switches return to normal when released.

Switches = {}

local SW = NET.SWITCHES
local info = {}            -- [group] = { reserved = owner, damaged = tick | nil }
local owned = {}           -- [owner] = { [group] = true }
local lastSync, syncDirty = 0, true
local lastSent = {}
local log = NetServer.log

addEvent("onNetSwitchChange", false)     -- (group, state, reason, owner|nil)
addEvent("onNetSwitchRepaired", false)   -- (group)
addEvent("onNetTrainArrived", false)     -- (trainId)

local function inf(g)
    local i = info[g]
    if not i then i = {} info[g] = i end
    return i
end

-- ------------------------------------------------------------------ occupation

-- is the node within `margin` of the given spans { { seg, s1, s2 } }
local function nodeIn(node, spans)
    for _, ref in ipairs(Net.nodeEnds(node)) do
        local id, e = Net.parseRef(ref)
        local g = id and Net.segment(id)
        if g then
            local s = e == "a" and 0 or g.len
            for _, sp in ipairs(spans) do
                if sp[1] == id and s >= sp[2] - 0.01 and s <= sp[3] + 0.01 then return true end
            end
        end
    end
    return false
end

local function trainSpans(t, margin)
    return t.path:spans(t.u - t.length - margin, t.u + margin)
end

-- the train (or nil) occupying a switch group
function Switches.occupant(group)
    local grp = Net.group(group)
    if not grp then return nil end
    for _, t in pairs(Trains.all()) do
        local spans = trainSpans(t, SW.LOCK_MARGIN)
        for _, nid in ipairs(grp.nodes or {}) do
            if nodeIn(Net.node(nid), spans) then return t end
        end
    end
end

function Switches.isLocked(group) return Switches.occupant(group) ~= nil end

-- groups a train is on (within the lock margin)
local function groupsUnder(t)
    local spans = trainSpans(t, SW.LOCK_MARGIN)
    local res = {}
    for gid, grp in pairs(Net.groups()) do
        for _, nid in ipairs(grp.nodes or {}) do
            if nodeIn(Net.node(nid), spans) then res[gid] = true break end
        end
    end
    return res
end

-- ------------------------------------------------------------------ throwing

-- opts = { owner = reservation owner allowed to throw, force = admin override, reason }
function Switches.throw(group, state, opts)
    opts = opts or {}
    if not Net.group(group) then return false, "no such switch" end
    state = state == "reverse" and "reverse" or "normal"
    local i = inf(group)
    if opts.force and i.damaged then i.damaged = nil syncDirty = true end    -- forcing repairs it
    if Net.getState(group) == state then return true end
    if not opts.force then
        if i.reserved and i.reserved ~= opts.owner then return false, "reserved by " .. tostring(i.reserved) end
        if i.damaged then return false, "damaged" end
        if Switches.isLocked(group) then return false, "a train is on the switch" end
    end
    Net.setState(group, state)
    syncDirty = true
    Trains.onSwitchChanged(group)
    triggerEvent("onNetSwitchChange", resourceRoot, group, state, opts.reason or (opts.owner and "route") or "forced", opts.owner)
    return true
end

-- ------------------------------------------------------------------ reservations

-- all or nothing: settings = { [group] = state }
function Switches.reserve(owner, settings)
    for g, st in pairs(settings) do
        local i = inf(g)
        if not Net.group(g) then return false, g .. ": no such switch" end
        if i.reserved and i.reserved ~= owner then return false, g .. ": reserved by " .. tostring(i.reserved) end
        if i.damaged then return false, g .. ": damaged" end
        if Net.getState(g) ~= st and Switches.isLocked(g) then return false, g .. ": a train is on it" end
    end
    owned[owner] = owned[owner] or {}
    for g, st in pairs(settings) do
        inf(g).reserved = owner
        owned[owner][g] = true
        Switches.throw(g, st, { owner = owner })
    end
    syncDirty = true
    return true
end

function Switches.release(owner, group)
    local mine = owned[owner]
    if not mine then return end
    for g in pairs(mine) do
        if not group or g == group then
            mine[g] = nil
            local i = inf(g)
            if i.reserved == owner then i.reserved = nil end
            local grp = Net.group(g)
            -- spring points fall back to normal once nobody needs them
            if grp and grp.spring and Net.getState(g) ~= "normal" and not Switches.isLocked(g) then
                Switches.throw(g, "normal", { reason = "spring" })
            end
        end
    end
    if not next(mine) then owned[owner] = nil end
    syncDirty = true
end

function Switches.reservedBy(group) return info[group] and info[group].reserved end

-- a train ran through a switch set the other way (from Trains): the blades are pushed over to
-- the leg it came from, and the switch is damaged until REPAIR_TIME
function Switches.onTrailed(trainId, nodeId, fromRef)
    local node = Net.node(nodeId)
    if not node or not node.group then return end
    local i = inf(node.group)
    i.damaged = getTickCount()
    local st = fromRef == node.reverse and "reverse" or "normal"
    if Net.getState(node.group) ~= st then
        Net.setState(node.group, st)
        Trains.onSwitchChanged(node.group)
        triggerEvent("onNetSwitchChange", resourceRoot, node.group, st, "trailed")
    end
    log("switch %s trailed by train %d - pushed to %s, damaged", node.group, trainId, st)
    syncDirty = true
end

-- ------------------------------------------------------------------ router

local function ownerOf(t) return "train:" .. t.id end

-- where the train's leading end is and which way it runs -> seg, s, dir, u of that end, sign
local function leadingEnd(t)
    if t.rev >= 0 then
        local seg, s, dir = t.path:at(t.u)
        return seg, s, dir, t.u, 1
    end
    local uRear = t.u - t.length
    local seg, s, dir = t.path:at(uRear)
    return seg, s, -dir, uRear, -1
end

-- Stop points (red signals, from rw_signals through setNetStopPoints):
-- stops[seg] = { { s, dir, id } } - a train moving along the segment in `dir` stops before s.
local stops = {}

function Switches.getStops()
    local t = {}
    for seg, l in pairs(stops) do for _, p in ipairs(l) do t[#t + 1] = { seg = seg, s = p.s, dir = p.dir, id = p.id } end end
    return t
end

function Switches.setStops(list)
    stops = {}
    for _, p in ipairs(list or {}) do
        stops[p.seg] = stops[p.seg] or {}
        table.insert(stops[p.seg], p)
    end
end

-- a train without a destination: the way ahead with the current switch states, up to
-- SW.LOOKAHEAD metres -> pseudo route { length, steps, nodes, settings, deadEnd }
local function walkAhead(seg, s, dir)
    local steps, total = { { seg, dir } }, 0
    local g = Net.segment(seg)
    total = dir > 0 and g.len - s or s
    while total < SW.LOOKAHEAD do
        local e = dir > 0 and "b" or "a"
        local node = Net.node(dir > 0 and g.b or g.a)
        local nref = Net.continueEnd(node, seg .. "@" .. e)
        local nid, ne = Net.parseRef(nref)
        if not nid or not Net.segment(nid) then return { length = total, steps = steps, nodes = {}, settings = {}, deadEnd = true } end
        seg, dir, g = nid, ne == "a" and 1 or -1, Net.segment(nid)
        steps[#steps + 1] = { seg, dir }
        total = total + g.len
    end
    return { length = total, steps = steps, nodes = {}, settings = {} }
end

local function route(t)
    local d = t.dest
    local seg, s, dir, uLead, sgn = leadingEnd(t)
    local r
    if d then
        r = Net.findRoute(seg, s, dir, d.seg, d.s, d.dir)
        if not r then
            t.authority = { u = uLead, sign = sgn, reason = "no route" }
            return
        end
    else
        r = walkAhead(seg, s, dir)
    end
    -- distance from the leading end to every node on the route
    local g0 = Net.segment(seg)
    local dist = dir > 0 and g0.len - s or s
    local horizon = math.max(SW.HORIZON_MIN, t.v * t.v / (2 * NET.SIM.BRAKE) + SW.HORIZON_EXTRA)
    local owner = ownerOf(t)
    local want = {}
    local limit, reason = r.length - SW.DEST_GAP, "destination"
    if not d then
        if r.deadEnd then limit, reason = r.length - 2, "end of track"
        else limit, reason = r.length, "line" end
    end
    for i, nodeId in ipairs(r.nodes) do
        if i > 1 then dist = dist + Net.length(r.steps[i][1]) end
        local node = Net.node(nodeId)
        local g = node and node.group
        local st = g and r.settings[g]
        if st then
            if dist > horizon then
                limit, reason = math.min(limit, dist - SW.AUTHORITY_GAP), "horizon"
                break
            end
            local ok, err = true, nil
            if not (inf(g).reserved == owner and Net.getState(g) == st) then
                ok, err = Switches.reserve(owner, { [g] = st })
            end
            if not ok then
                limit, reason = math.min(limit, dist - SW.AUTHORITY_GAP), err
                break
            end
            want[g] = true
        end
    end
    -- moving block: never closer than TRAIN_GAP to another train on the route
    local base = 0
    for i, step in ipairs(r.steps) do
        local sid, sdir = step[1], step[2]
        local entry = i == 1 and s or (sdir > 0 and 0 or Net.length(sid))
        if base > limit then break end
        for _, p in ipairs(stops[sid] or {}) do
            local dd
            if p.dir == sdir and sdir > 0 and p.s >= entry then dd = base + p.s - entry
            elseif p.dir == sdir and sdir < 0 and p.s <= entry then dd = base + entry - p.s end
            if dd and dd - SW.STOP_GAP < limit then limit, reason = dd - SW.STOP_GAP, "signal " .. tostring(p.id) end
        end
        for _, o in pairs(Trains.all()) do
            if o ~= t and o.dim == t.dim then
                for _, sp in ipairs(o.path:spans(o.u - o.length, o.u)) do
                    if sp[1] == sid then
                        local d
                        if sdir > 0 and sp[3] >= entry then d = base + math.max(0, sp[2] - entry)
                        elseif sdir < 0 and sp[2] <= entry then d = base + math.max(0, entry - sp[3]) end
                        if d and d - SW.TRAIN_GAP < limit then limit, reason = d - SW.TRAIN_GAP, "train " .. o.id end
                    end
                end
            end
        end
        base = base + (sdir > 0 and Net.length(sid) - entry or entry)
    end

    t.authority = { u = uLead + sgn * math.max(0, limit), sign = sgn, reason = reason, remaining = limit, routeLength = r.length }

    -- release what is neither ahead on the route nor under the train
    local under = groupsUnder(t)
    for g in pairs(owned[owner] or {}) do
        if not want[g] and not under[g] then Switches.release(owner, g) end
    end
end

function Switches.setDestination(t, seg, s, dir)
    if seg then
        t.dest = { seg = seg, s = s, dir = dir }
        t.arrived = nil
        route(t)
    else
        t.dest, t.authority = nil, nil
        Switches.release(ownerOf(t))
    end
end

function Switches.onTrainRemoved(t)
    Switches.release(ownerOf(t))
end

setTimer(function()
    local now = getTickCount()
    for _, t in pairs(Trains.all()) do
        if t.dest or not t.noAtp then
            route(t)
            local a = t.authority
            if a and a.reason == "destination" and math.abs(t.v) < 0.05 and (a.remaining or 99) < 3 and not t.arrived then
                t.arrived = true
                log("train %d arrived at %s %.0f", t.id, t.dest.seg, t.dest.s)
                triggerEvent("onNetTrainArrived", resourceRoot, t.id)
            end
        end
    end
    -- automatic repair of trailed switches
    for g, i in pairs(info) do
        if i.damaged and now - i.damaged > SW.REPAIR_TIME * 1000 and not Switches.isLocked(g) then
            i.damaged = nil
            log("switch %s repaired", g)
            triggerEvent("onNetSwitchRepaired", resourceRoot, g)
            syncDirty = true
        end
    end
    -- client sync
    if now - lastSync >= SW.SYNC then
        lastSync = now
        local payload, changed = {}, syncDirty
        for gid in pairs(Net.groups()) do
            local i = info[gid] or {}
            local e = { Net.getState(gid), Switches.isLocked(gid), i.reserved or false, i.damaged and true or false }
            payload[gid] = e
            local o = lastSent[gid]
            if not o or o[1] ~= e[1] or o[2] ~= e[2] or o[3] ~= e[3] or o[4] ~= e[4] then changed = true end
        end
        if changed then
            lastSent = payload
            syncDirty = false
            triggerClientEvent(NetServer.readyPlayers(), "rw:net:switches", resourceRoot, payload)
        end
    end
end, SW.ROUTER_TICK, 0)

addEventHandler("rw:net:hello", resourceRoot, function()
    local p = client
    setTimer(function() if isElement(p) then triggerClientEvent(p, "rw:net:switches", resourceRoot, lastSent) end end, 1600, 1)
end)

-- ------------------------------------------------------------------ exports

-- { { id, name, state, locked, reserved, damaged, spring, nodes } }
function getNetSwitches()
    local t = {}
    for gid, grp in pairs(Net.groups()) do
        local i = info[gid] or {}
        t[#t + 1] = { id = gid, name = grp.name, state = Net.getState(gid), locked = Switches.isLocked(gid),
            reserved = i.reserved or false, damaged = i.damaged and true or false, spring = grp.spring or false, nodes = grp.nodes }
    end
    table.sort(t, function(a, b) return a.id < b.id end)
    return t
end

function findNetRoute(fromSeg, fromS, fromDir, toSeg, toS, toDir)
    local r, err = Net.findRoute(fromSeg, tonumber(fromS) or 0, tonumber(fromDir) or 1, toSeg, tonumber(toS) or 0, tonumber(toDir))
    if not r then return false, err end
    return r
end

function reserveNetRoute(owner, settings) return Switches.reserve(owner, settings) end
function releaseNetRoute(owner, group) Switches.release(owner, group) return true end

-- the train drives to (seg, s[, dir]); nil seg clears the destination
function setNetTrainDestination(id, seg, s, dir)
    local t = Trains.get(id)
    if not t then return false, "no such train" end
    if seg and not Net.segment(seg) then return false, "unknown segment" end
    Switches.setDestination(t, seg, tonumber(s) or 0, tonumber(dir))
    return t.authority and { reason = t.authority.reason, remaining = t.authority.remaining, routeLength = t.authority.routeLength } or true
end
