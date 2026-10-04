-- Route finding on the network (server + client): the shortest way from a position to a target
-- without reversing, and the switch settings it needs.
--
-- Net.findRoute(fromSeg, fromS, fromDir, toSeg, toS, toDir, opts) ->
--   { length, settings = { [group] = "normal" | "reverse" }, steps = { { seg, dir }, ... },
--     nodes = { nodeId, ... } } or nil, reason
-- toDir (optional) = the direction the train must run on toSeg when it gets there.
-- opts.maxLength (default 30 km), opts.avoid = { [group] = true } groups that must not be used,
-- opts.switchPenalty (default 300 m): extra cost of taking a diverging leg, so trains keep to their
-- track instead of hopping over to a slightly shorter parallel one.

local function legOptions(node, ref)
    -- -> { { ref, group, state } } ways on from `ref` through `node`
    if not node then return {} end
    if node.type == "link" then
        local e = node.ends or {}
        local other = e[1] == ref and e[2] or (e[2] == ref and e[1] or nil)
        return other and { { other } } or {}
    elseif node.type == "switch" then
        if ref == node.trunk then
            return { { node.normal, node.group, "normal" }, { node.reverse, node.group, "reverse" } }
        elseif ref == node.normal then
            return { { node.trunk, (not node.spring) and node.group or nil, "normal" } }
        elseif ref == node.reverse then
            return { { node.trunk, (not node.spring) and node.group or nil, "reverse" } }
        end
    end
    return {}
end

-- small binary heap on .d
local function push(h, item)
    h[#h + 1] = item
    local i = #h
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p].d <= h[i].d then break end
        h[p], h[i] = h[i], h[p]
        i = p
    end
end

local function pop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, m = i * 2, i * 2 + 1, i
            if h[l] and h[l].d < h[m].d then m = l end
            if h[r] and h[r].d < h[m].d then m = r end
            if m == i then break end
            h[i], h[m] = h[m], h[i]
            i = m
        end
    end
    return top
end

function Net.findRoute(fromSeg, fromS, fromDir, toSeg, toS, toDir, opts)
    opts = opts or {}
    local maxLength = opts.maxLength or 30000
    local avoid = opts.avoid or {}
    local penalty = opts.switchPenalty or 300
    if not Net.segment(fromSeg) or not Net.segment(toSeg) then return nil, "unknown segment" end
    fromDir = fromDir == -1 and -1 or 1

    -- target on the start segment, straight ahead
    if fromSeg == toSeg and (not toDir or toDir == fromDir) and (toS - fromS) * fromDir >= 0 then
        return { length = math.abs(toS - fromS), settings = {}, steps = { { fromSeg, fromDir } }, nodes = {} }
    end

    local heap = {}
    local best = {}                  -- ["seg|dir"] = distance at the start of that segment
    push(heap, { seg = fromSeg, dir = fromDir, d = 0, start = fromS, settings = {}, steps = { { fromSeg, fromDir } }, nodes = {} })

    while #heap > 0 do
        local cur = pop(heap)
        if cur.goal then return cur.result end
        local g = Net.segment(cur.seg)
        -- distance from where we are on this segment to its far end (real length / cost)
        local s0 = cur.start or (cur.dir > 0 and 0 or g.len)
        local toEnd = cur.dir > 0 and g.len - s0 or s0
        local dEnd = (cur.len or cur.d) + toEnd
        local cEnd = cur.d + toEnd
        if dEnd <= maxLength then
            local e = cur.dir > 0 and "b" or "a"
            local nodeId = cur.dir > 0 and g.b or g.a
            local node = Net.node(nodeId)
            for _, opt in ipairs(legOptions(node, cur.seg .. "@" .. e)) do
                local nid, ne = Net.parseRef(opt[1])
                local grp, st = opt[2], opt[3]
                local ok = nid and Net.segment(nid) and not (grp and avoid[grp])
                if ok and grp and cur.settings[grp] and cur.settings[grp] ~= st then ok = false end
                if ok then
                    local ndir = ne == "a" and 1 or -1
                    local cost = cEnd + (st == "reverse" and penalty or 0)
                    local settings = cur.settings
                    if grp and not settings[grp] then
                        settings = {}
                        for k, v in pairs(cur.settings) do settings[k] = v end
                        settings[grp] = st
                    end
                    local steps = {}
                    for i, s in ipairs(cur.steps) do steps[i] = s end
                    steps[#steps + 1] = { nid, ndir }
                    local nodes = {}
                    for i, n in ipairs(cur.nodes) do nodes[i] = n end
                    nodes[#nodes + 1] = nodeId

                    if nid == toSeg and (not toDir or toDir == ndir) then
                        -- reaching the target: queue it so a cheaper way found later still wins
                        local entry = ndir > 0 and 0 or Net.length(nid)
                        local total = dEnd + math.abs(toS - entry)
                        push(heap, { goal = true, d = cost + math.abs(toS - entry),
                            result = { length = total, settings = settings, steps = steps, nodes = nodes } })
                    end
                    local key = nid .. "|" .. ndir
                    if not best[key] or cost < best[key] then
                        best[key] = cost
                        push(heap, { seg = nid, dir = ndir, d = cost, len = dEnd, settings = settings, steps = steps, nodes = nodes })
                    end
                end
            end
        end
    end
    return nil, "no route"
end
