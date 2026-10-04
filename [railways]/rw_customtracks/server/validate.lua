-- Network validation: references, gaps and kinks at nodes, tight curves, steep gradients,
-- dangling ends. netValidate() -> { errors, warnings, infos, issues = { { level, code, ref, msg, x, y, z } } }

local V = NET.VALIDATE

local function angle(ax, ay, az, bx, by, bz)
    local d = ax * bx + ay * by + az * bz
    if d > 1 then d = 1 elseif d < -1 then d = -1 end
    return math.deg(math.acos(d))
end

-- direction of travel when leaving a segment end into the node / entering from it
local function endDir(ref, leaving)
    local id, e = Net.parseRef(ref)
    local g = id and Net.segment(id)
    if not g then return nil end
    local s = e == "a" and 0 or g.len
    local _, _, _, tx, ty, tz = Net.pointAt(id, s)
    -- leaving through `b` = +tangent; leaving through `a` = -tangent; entering = the opposite
    local sign = (e == "b") == leaving and 1 or -1
    return tx * sign, ty * sign, tz * sign
end

function netValidate()
    local issues = {}
    local function add(level, code, ref, msg, x, y, z)
        issues[#issues + 1] = { level = level, code = code, ref = ref, msg = msg, x = x, y = y, z = z }
    end

    local nodes = Net.nodes()
    local roleOf = {}     -- [ref] = node id that lists it

    for id, n in pairs(nodes) do
        local ends = Net.nodeEnds(n)
        if n.type == "link" and #ends ~= 2 then add("error", "link_ends", id, "link needs 2 ends, has " .. #ends, n.x, n.y, n.z) end
        if n.type == "buffer" and #ends ~= 1 then add("error", "buffer_ends", id, "buffer needs 1 end, has " .. #ends, n.x, n.y, n.z) end
        if n.type == "switch" then
            for _, k in ipairs({ "trunk", "normal", "reverse" }) do
                if not n[k] then add("error", "switch_leg", id, "switch has no " .. k, n.x, n.y, n.z) end
            end
            if not n.group then add("warning", "switch_group", id, "switch has no lever group", n.x, n.y, n.z) end
        end
        for _, ref in ipairs(ends) do
            local sid, e = Net.parseRef(ref)
            local g = sid and Net.segment(sid)
            if not g then
                add("error", "bad_ref", id, "unknown segment end " .. tostring(ref), n.x, n.y, n.z)
            else
                if (e == "a" and g.a or g.b) ~= id then
                    add("error", "ref_mismatch", id, ref .. " belongs to node " .. tostring(e == "a" and g.a or g.b), n.x, n.y, n.z)
                end
                if roleOf[ref] then add("error", "ref_twice", id, ref .. " also used by " .. roleOf[ref], n.x, n.y, n.z) end
                roleOf[ref] = id
            end
        end

        -- all ends meet in one point
        local x0, y0, z0
        for _, ref in ipairs(ends) do
            local x, y, z = Net.endPoint(ref)
            if x then
                if not x0 then x0, y0, z0 = x, y, z
                else
                    local d = getDistanceBetweenPoints3D(x, y, z, x0, y0, z0)
                    if d > V.GAP then add("error", "gap", id, string.format("%s is %.2f m from %s", ref, d, ends[1]), x, y, z) end
                end
            end
        end

        -- direction continuity for every way through the node
        local pairs_ = {}
        if n.type == "link" and #ends == 2 then pairs_ = { { ends[1], ends[2] } }
        elseif n.type == "switch" and n.trunk then
            if n.normal then pairs_[#pairs_ + 1] = { n.trunk, n.normal } end
            if n.reverse then pairs_[#pairs_ + 1] = { n.trunk, n.reverse } end
        end
        for _, p in ipairs(pairs_) do
            local ax, ay, az = endDir(p[1], true)
            local bx, by, bz = endDir(p[2], false)
            if ax and bx then
                local a = angle(ax, ay, az, bx, by, bz)
                if a > V.KINK then
                    add(a > 20 and "error" or "warning", "kink", id, string.format("%.1f° between %s and %s", a, p[1], p[2]), x0, y0, z0)
                end
            end
        end
    end

    for _, id in ipairs(Net.segmentIds()) do
        local g = Net.segment(id)
        for _, e in ipairs({ "a", "b" }) do
            local ref = id .. "@" .. e
            local nid = e == "a" and g.a or g.b
            if not nid or not nodes[nid] then
                local x, y, z = Net.endPoint(ref)
                add("warning", "open_end", ref, "end has no node (trains stop here)", x, y, z)
            elseif not roleOf[ref] then
                add("error", "not_listed", ref, "node " .. nid .. " does not list this end", nodes[nid].x, nodes[nid].y, nodes[nid].z)
            end
        end
        if g.len < V.MIN_LENGTH then add("warning", "short", id, string.format("only %.2f m long", g.len)) end

        -- tightest curve / steepest gradient, sampled every 2 m
        local minR, minS, maxG, maxS = math.huge, 0, 0, 0
        for s = 0, g.len, 2 do
            local r = Net.radiusAt(id, s, 5)
            if r < minR then minR, minS = r, s end
            local gr = math.abs(Net.gradeAt(id, s, 5))
            if gr > maxG then maxG, maxS = gr, s end
        end
        local geoLevel = V.GTA_KINDS[g.kind] and "info" or "warning"
        if minR < V.MIN_RADIUS then
            local x, y, z = Net.pointAt(id, minS)
            add(geoLevel, "radius", id, string.format("radius %.0f m at s %.0f", minR, minS), x, y, z)
        end
        if maxG > V.MAX_GRADE then
            local x, y, z = Net.pointAt(id, maxS)
            add(geoLevel, "grade", id, string.format("gradient %.1f %% at s %.0f", maxG * 100, maxS), x, y, z)
        end
    end

    for gid, grp in pairs(Net.groups()) do
        for _, nid in ipairs(grp.nodes or {}) do
            if not nodes[nid] then add("error", "group_node", gid, "group lists unknown node " .. tostring(nid)) end
        end
    end
    for _, c in ipairs(Net.crossings()) do
        if not c.sa then add("warning", "crossing", c.a .. "/" .. c.b, "segments do not intersect") end
    end

    local count = { error = 0, warning = 0, info = 0 }
    for _, i in ipairs(issues) do count[i.level] = count[i.level] + 1 end
    local rank = { error = 1, warning = 2, info = 3 }
    table.sort(issues, function(a, b)
        if a.level ~= b.level then return rank[a.level] < rank[b.level] end
        return (a.ref or "") < (b.ref or "")
    end)
    return { errors = count.error, warnings = count.warning, infos = count.info, issues = issues }
end
