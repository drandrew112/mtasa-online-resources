if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Suturing: press the left mouse button on one wound edge, drag the needle across and release on
-- the other edge. The dashed circles show where the next bites would be ideal. A stitch has to cross
-- the wound; its score is the bite depth (3-6 mm), the same depth on both sides and how straight it
-- crosses; at the end the spacing along the wound is scored too.

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function woundY(g, x)
    local u = (x - g.x0) / (g.x1 - g.x0)
    return g.cy + g.a1 * math.sin(u * g.k1 + g.p1) + g.a2 * math.sin(u * g.k2 + g.p2)
end

local function shake(g)
    if g.options.tremor <= 0 or not g.t or g.t < 0 then return 0, 0 end
    local a = sc(SUTURE.TREMOR_PX) * g.options.tremor
    return a * math.sin(g.t * 13.1) * math.sin(g.t * 2.3), a * math.cos(g.t * 11.7) * math.sin(g.t * 1.9 + 1)
end

local function stitchScore(g, x1, y1, x2, y2)
    local d1, d2 = math.abs(y1 - woundY(g, x1)), math.abs(y2 - woundY(g, x2))
    local function depthOk(d)
        if d >= g.dmin and d <= g.dmax then return 1 end
        local off = d < g.dmin and (g.dmin - d) or (d - g.dmax)
        return clamp(1 - off / g.dmin, 0, 1)
    end
    local depth = (depthOk(d1) + depthOk(d2)) / 2
    local sym = clamp(1 - math.abs(d1 - d2) / (0.5 * g.dideal), 0, 1)
    local straight = clamp(1 - math.abs(x1 - x2) / (0.7 * g.dideal), 0, 1)
    return depth, sym, straight
end

local function spacingScore(g)
    local xs = {}
    for _, s in ipairs(g.stitches) do xs[#xs + 1] = (s.x1 + s.x2) / 2 end
    table.sort(xs)
    if #xs == 0 then return 0 end
    local ideal = (g.x1 - g.x0) / g.options.stitches
    local total, n = 0, 0
    local function gap(d, want) total = total + clamp(1 - math.abs(d - want) / want, 0, 1) n = n + 1 end
    gap(xs[1] - g.x0, ideal / 2)
    for i = 2, #xs do gap(xs[i] - xs[i - 1], ideal) end
    gap(g.x1 - xs[#xs], ideal / 2)
    return total / n
end

GAME = {
    cursor = true,

    init = function(g)
        local ax, ay, aw, ah = MGK.area()
        g.skin = { ax + sc(20), ay + sc(30), aw - sc(40), ah - sc(110) }
        g.x0, g.x1 = ax + aw * 0.13, ax + aw * 0.87
        g.cy = g.skin[2] + g.skin[4] / 2
        g.a1, g.k1, g.p1 = sc(math.random(6, 14)), math.random(2, 4), math.random() * 6.28
        g.a2, g.k2, g.p2 = sc(math.random(2, 6)), math.random(5, 9), math.random() * 6.28
        g.mmPerPx = g.options.length * 10 / (g.x1 - g.x0)
        g.dmin = clamp(SUTURE.DEPTH_MM[1] / g.mmPerPx, sc(SUTURE.DEPTH_PX[1]), sc(SUTURE.DEPTH_PX[2]) * 0.6)
        g.dmax = clamp(SUTURE.DEPTH_MM[2] / g.mmPerPx, g.dmin * 1.6, sc(SUTURE.DEPTH_PX[2]))
        g.dideal = (g.dmin + g.dmax) / 2
        g.stitches, g.misses, g.flash = {}, 0, nil
    end,

    click = function(g, button, state, cx, cy)
        if button ~= "left" then return end
        local ox, oy = shake(g)
        local lx, ly = cx - ox, cy - oy
        if state == "down" then
            local s = g.skin
            if MGK.inRect(lx, ly, s[1], s[2], s[3], s[4]) then g.drag = { lx, ly } end
            return
        end
        local d = g.drag
        g.drag = nil
        if not d or #g.stitches >= g.options.stitches then return end
        local side1 = d[2] - woundY(g, d[1])
        local side2 = ly - woundY(g, lx)
        if side1 * side2 >= 0 or MGK.dist(d[1], d[2], lx, ly) < sc(10) then
            g.misses = g.misses + 1
            g.flash = { g.now, false }
            return
        end
        local depth, sym, straight = stitchScore(g, d[1], d[2], lx, ly)
        local q = depth * 0.47 + sym * 0.26 + straight * 0.27
        g.stitches[#g.stitches + 1] = { x1 = d[1], y1 = d[2], x2 = lx, y2 = ly, q = q, depth = depth, straight = straight }
        g.flash = { g.now, q >= 0.6 }
    end,

    done = function(g) return #g.stitches >= g.options.stitches end,

    score = function(g)
        local n = g.options.stitches
        local sumQ, sumD, sumA = 0, 0, 0
        for _, s in ipairs(g.stitches) do sumQ, sumD, sumA = sumQ + s.q, sumD + s.depth, sumA + s.straight end
        local placed = #g.stitches
        local spacing = spacingScore(g)
        local avg = placed > 0 and sumQ / placed or 0
        local percent = (avg * 0.75 + spacing * 0.25) * 100 * (placed / n) - g.misses * SUTURE.MISS_PENALTY
        return percent, {
            stitches = n, placed = placed, misses = g.misses,
            depth = placed > 0 and math.floor(sumD / placed * 100) or 0,
            spacing = math.floor(spacing * 100), angle = placed > 0 and math.floor(sumA / placed * 100) or 0,
        }
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local ox, oy = shake(g)
        local s = g.skin
        MGK.round(s[1] + ox, s[2] + oy, s[3], s[4], sc(18), COL.skin)
        -- wound
        local step = sc(6)
        local px, py
        for x = g.x0, g.x1, step do
            local y = woundY(g, x)
            local taper = math.sin((x - g.x0) / (g.x1 - g.x0) * math.pi)
            if px then
                MGK.line(px + ox, py + oy, x + ox, y + oy, tocolor(110, 23, 23, 255), sc(3) + sc(7) * taper)
            end
            px, py = x, y
        end
        -- ideal bites of the next stitch (dashed circles)
        local n = g.options.stitches
        if #g.stitches < n then
            local ideal = (g.x1 - g.x0) / n
            local placedX = {}
            for _, st in ipairs(g.stitches) do placedX[#placedX + 1] = (st.x1 + st.x2) / 2 end
            for k = 1, n do
                local x = g.x0 + ideal * (k - 0.5)
                local taken = false
                for _, sx in ipairs(placedX) do if math.abs(sx - x) < ideal * 0.5 then taken = true end end
                if not taken then
                    local y = woundY(g, x)
                    local c = tocolor(255, 255, 255, 120)
                    MGK.ring(x + ox, y - g.dideal + oy, sc(7), c, 1.5, true)
                    MGK.ring(x + ox, y + g.dideal + oy, sc(7), c, 1.5, true)
                end
            end
        end
        -- stitches
        for _, st in ipairs(g.stitches) do
            local c = st.q >= 0.6 and COL.accent or COL.warn
            MGK.line(st.x1 + ox, st.y1 + oy, st.x2 + ox, st.y2 + oy, c, sc(3))
            MGK.circle(st.x1 + ox, st.y1 + oy, sc(3), c)
            MGK.circle(st.x2 + ox, st.y2 + oy, sc(3), c)
        end
        -- the needle being pulled across
        local cx, cy = MGK.cursor()
        if g.drag and cx then
            local d = g.drag
            local mx, my = (d[1] + cx - ox) / 2, (d[2] + cy - oy) / 2
            local bx, by = mx + (cy - oy - d[2]) * 0.25, my - (cx - ox - d[1]) * 0.25
            local lx, ly = d[1], d[2]
            for i = 1, 12 do
                local t = i / 12
                local x = (1 - t) ^ 2 * d[1] + 2 * (1 - t) * t * bx + t * t * (cx - ox)
                local y = (1 - t) ^ 2 * d[2] + 2 * (1 - t) * t * by + t * t * (cy - oy)
                MGK.line(lx + ox, ly + oy, x + ox, y + oy, tocolor(233, 237, 242, 230), sc(2))
                lx, ly = x, y
            end
            MGK.circle(d[1] + ox, d[2] + oy, sc(3), COL.white)
        end
        if cx then MGK.ring(cx, cy, sc(9), tocolor(233, 237, 242, 200), 1.5) end
        -- flash of the last stitch
        if g.flash and now - g.flash[1] < 300 then
            dxDrawRectangle(s[1], s[2], s[3], s[4], g.flash[2] and tocolor(63, 179, 122, 40) or tocolor(224, 82, 70, 55))
        end
        -- accuracy bar
        local placed = #g.stitches
        local sum = 0
        for _, st in ipairs(g.stitches) do sum = sum + st.q end
        local acc = placed > 0 and sum / placed or 0
        local by2 = s[2] + s[4] + sc(36)
        MGK.bar(ax + sc(130), by2, aw * 0.45, sc(12), acc, acc >= 0.6 and COL.good or COL.warn)
        MGK.text(L("mg_suture.client.accuracy"), ax, by2 - sc(6), sc(120), sc(24), COL.dim, 1.0, "right")
        MGK.text(("%d%%"):format(acc * 100), ax + sc(140) + aw * 0.45, by2 - sc(6), sc(80), sc(24), COL.text, 1.1)
        if g.misses > 0 then
            MGK.text(L("mg_suture.client.misses", { n = g.misses }), ax + aw * 0.7, by2 - sc(6), aw * 0.3, sc(24), COL.bad, 1.0, "right")
        end
    end,

    title = function(g)
        local part = g.options.part ~= "" and (" · " .. g.options.part) or ""
        return L("mg_suture.client.title", { part = part, length = g.options.length })
    end,
    status = function(g) return L("mg_suture.client.stitch_count", { n = #g.stitches, total = g.options.stitches }) end,
    hint = function(g)
        return g.options.tremor > 0 and L("mg_suture.client.hint_tremor") or L("mg_suture.client.hint")
    end,
}

---------------------------------------------------------------- exports

-- Local game, the server is not involved. ped is optional. options: see shared.lua
function startSutureGame(ped, options) return MGK.begin(ped, options, nil) end
function stopSutureGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isSutureGameActive() return MGK.active() end
