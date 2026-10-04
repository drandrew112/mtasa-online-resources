-- The route a train occupies (server + client): a list of whole segments, each with the direction
-- the train runs on it, laid out on one continuous coordinate u ("odometer", metres). The head of
-- the train is at uHead, every car / bogie at uHead - offset. The route grows forwards through the
-- nodes (switch states) as the head advances and backwards when the train reverses, and is
-- trimmed behind the train, so the rear cars always follow the way the front took.
--
-- piece = { seg, dir, u0, len }: covers u in [u0, u0 + len]; s on seg = (dir > 0 and 0 or len) + dir * (u - u0)

TrainPath = {}
TrainPath.__index = TrainPath

-- a route covering one whole segment; the train runs on it in direction dir. Returns path, u of s.
function TrainPath.new(seg, s, dir)
    local len = Net.length(seg)
    local p = setmetatable({ pieces = { { seg = seg, dir = dir, u0 = 0, len = len } }, frontEnd = nil, backEnd = nil }, TrainPath)
    local u = dir > 0 and s or len - s
    return p, u
end

-- rebuilds a path from its serialised pieces (snapshot from the server)
function TrainPath.from(pieces)
    local p = setmetatable({ pieces = {} }, TrainPath)
    for i, pc in ipairs(pieces) do p.pieces[i] = { seg = pc[1], dir = pc[2], u0 = pc[3], len = pc[4] } end
    return p
end

function TrainPath:serialise()
    local t = {}
    for i, pc in ipairs(self.pieces) do t[i] = { pc.seg, pc.dir, pc.u0, pc.len } end
    return t
end

function TrainPath:firstU() return self.pieces[1].u0 end
function TrainPath:lastU() local l = self.pieces[#self.pieces] return l.u0 + l.len end

-- appends pieces until the route reaches uTarget (or a dead end) -> reached, passed nodes
function TrainPath:extendFront(uTarget, stateOf)
    local passed
    for _ = 1, 200 do
        local last = self.pieces[#self.pieces]
        if last.u0 + last.len >= uTarget then return true, passed end
        local g = Net.segment(last.seg)
        if not g then return false, passed end
        local e = last.dir > 0 and "b" or "a"
        local nodeId = last.dir > 0 and g.b or g.a
        local nref, trailed = Net.continueEnd(Net.node(nodeId), last.seg .. "@" .. e, stateOf)
        local nid, ne = Net.parseRef(nref)
        if not nid or not Net.segment(nid) then
            self.frontEnd = last.u0 + last.len
            return false, passed
        end
        passed = passed or {}
        passed[#passed + 1] = { node = nodeId, from = last.seg .. "@" .. e, to = nref, trailed = trailed, u = last.u0 + last.len }
        self.pieces[#self.pieces + 1] = { seg = nid, dir = ne == "a" and 1 or -1, u0 = last.u0 + last.len, len = Net.length(nid) }
        self.frontEnd = nil
    end
    return false, passed
end

-- prepends pieces until the route reaches back to uTarget (or a dead end)
function TrainPath:extendBack(uTarget, stateOf)
    for _ = 1, 200 do
        local first = self.pieces[1]
        if first.u0 <= uTarget then return true end
        local g = Net.segment(first.seg)
        if not g then return false end
        -- the route enters `first` through this end
        local e = first.dir > 0 and "a" or "b"
        local nodeId = first.dir > 0 and g.a or g.b
        local nref = Net.continueEnd(Net.node(nodeId), first.seg .. "@" .. e, stateOf)
        local nid, ne = Net.parseRef(nref)
        if not nid or not Net.segment(nid) then
            self.backEnd = first.u0
            return false
        end
        -- the new piece runs towards the node: arriving at its `ne` end
        local len = Net.length(nid)
        table.insert(self.pieces, 1, { seg = nid, dir = ne == "b" and 1 or -1, u0 = first.u0 - len, len = len })
        self.backEnd = nil
    end
    return false
end

-- drops pieces entirely outside [uMin, uMax]
function TrainPath:trim(uMin, uMax)
    while #self.pieces > 1 and self.pieces[1].u0 + self.pieces[1].len < uMin do table.remove(self.pieces, 1) end
    while #self.pieces > 1 and self.pieces[#self.pieces].u0 > uMax do table.remove(self.pieces) end
end

-- u -> seg, s, dir (clamped to the route)
function TrainPath:at(u)
    local ps = self.pieces
    local pc = ps[1]
    if u >= pc.u0 then
        for i = #ps, 1, -1 do
            if u >= ps[i].u0 then pc = ps[i] break end
        end
    end
    local d = u - pc.u0
    if d < 0 then d = 0 elseif d > pc.len then d = pc.len end
    local s = pc.dir > 0 and d or pc.len - d
    return pc.seg, s, pc.dir
end

-- world point at u -> x, y, z, and the unit direction of increasing u
function TrainPath:point(u)
    local seg, s, dir = self:at(u)
    local x, y, z, tx, ty, tz = Net.pointAt(seg, s)
    return x, y, z, tx * dir, ty * dir, tz * dir
end

-- the occupied spans between u1 < u2 -> { { seg, sMin, sMax }, ... }
function TrainPath:spans(u1, u2)
    local t = {}
    for _, pc in ipairs(self.pieces) do
        local a, b = math.max(u1, pc.u0), math.min(u2, pc.u0 + pc.len)
        if b > a then
            local s1 = pc.dir > 0 and a - pc.u0 or pc.len - (a - pc.u0)
            local s2 = pc.dir > 0 and b - pc.u0 or pc.len - (b - pc.u0)
            if s1 > s2 then s1, s2 = s2, s1 end
            t[#t + 1] = { pc.seg, s1, s2 }
        end
    end
    return t
end

-- gradient along increasing u at u (dz/du)
function TrainPath:grade(u)
    local seg, s, dir = self:at(u)
    return Net.gradeAt(seg, s, 5) * dir
end

-- Pose of a car whose centre is at u: centre x, y, z (rail level) and the unit forward vector
-- (front bogie - rear bogie, i.e. towards increasing u)
function TrainPath:carPose(u, bogie)
    local h = bogie / 2
    local ax, ay, az = self:point(u + h)
    local bx, by, bz = self:point(u - h)
    local fx, fy, fz = ax - bx, ay - by, az - bz
    local l = math.sqrt(fx * fx + fy * fy + fz * fz)
    if l < 0.001 then
        local _, _, _, tx, ty, tz = self:point(u)
        fx, fy, fz, l = tx, ty, tz, 1
    end
    return (ax + bx) / 2, (ay + by) / 2, (az + bz) / 2, fx / l, fy / l, fz / l
end
