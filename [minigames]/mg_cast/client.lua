if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Plaster cast: the mouse (left / right) sets the overlap of the next turn, SPACE rolls it on when
-- the rhythm dot is inside the window. Each layer runs along the limb; three layers.

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function rhythm(g, t) return 0.5 + 0.5 * math.sin(t * g.options.speed * CAST.RHYTHM_HZ * 2 * math.pi) end

local function overlapFromMouse(g)
    local cx = MGK.cursor()
    if not cx then return g.overlap end
    local x0, w = g.slider[1], g.slider[3]
    return clamp((cx - x0) / w, 0, 1)
end

GAME = {
    cursor = true,

    init = function(g)
        local ax, ay, aw, ah = MGK.area()
        g.limb = { ax + aw * 0.08, ay + ah * 0.30, aw * 0.80, ah * 0.22 }
        g.slider = { ax + sc(130), ay + ah - sc(84), aw * 0.5, sc(14) }
        g.rbar = { ax + sc(130), ay + ah - sc(46), aw * 0.5, sc(14) }
        g.layer, g.pos = 1, 0          -- pos: covered part of the current layer (0-1)
        g.turns = {}                   -- { layer, from, to, kind }
        g.wrinkles, g.gaps, g.tight, g.good = 0, 0, 0, 0
        g.overlap = 0.5
    end,

    update = function(g, dt) g.overlap = overlapFromMouse(g) end,

    key = function(g, key, press)
        if key ~= CAST.KEY then return false end
        if not press or g.layer > CAST.LAYERS then return true end
        local r = rhythm(g, g.t)
        local onBeat = math.abs(r - 0.5) <= CAST.RHYTHM_WINDOW
        local ov = g.overlap
        local kind = "good"
        if not onBeat then kind = "wrinkle" g.wrinkles = g.wrinkles + 1
        elseif ov < CAST.GAP_BELOW then kind = "gap" g.gaps = g.gaps + 1
        elseif ov > CAST.TIGHT_ABOVE then kind = "tight" g.tight = g.tight + 1
        elseif ov < CAST.OVERLAP_BAND[1] or ov > CAST.OVERLAP_BAND[2] then kind = "ok"
        else g.good = g.good + 1 end
        if kind == "ok" then g.good = g.good + 0.6 end
        local from = g.pos
        local adv = CAST.WRAP_W * (1 - clamp(ov, 0, 0.92))
        if g.pos == 0 then adv = CAST.WRAP_W end
        g.pos = g.pos + adv
        g.turns[#g.turns + 1] = { layer = g.layer, from = math.max(0, g.pos - CAST.WRAP_W), to = math.min(1, g.pos), kind = kind, gap = kind == "gap" and from or nil }
        g.flash = { g.now, kind }
        if g.pos >= 1 then g.layer, g.pos = g.layer + 1, 0 end
        return true
    end,

    done = function(g) return g.layer > CAST.LAYERS end,

    score = function(g)
        local n = #g.turns
        local percent = n > 0 and (g.good / n * 100) or 0
        percent = percent - g.tight * 8
        return percent, { turns = n, wrinkles = g.wrinkles, gaps = g.gaps, tight = g.tight, layers = math.min(CAST.LAYERS, g.layer - 1) }
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local l = g.limb
        MGK.round(l[1], l[2], l[3], l[4], l[4] / 2, COL.skin)
        -- turns (later layers on top, older ones greyer)
        for _, tn in ipairs(g.turns) do
            local x1, x2 = l[1] + l[3] * tn.from, l[1] + l[3] * tn.to
            local shade = 255 - (CAST.LAYERS - tn.layer) * 18
            local c = tocolor(shade, shade, shade - 4, 250)
            if tn.kind == "wrinkle" then c = tocolor(220, 214, 196, 250) elseif tn.kind == "tight" then c = tocolor(236, 210, 210, 250) end
            local skew = (x2 - x1) * 0.35
            for k = 0, 3 do
                local yy = l[2] + l[4] * k / 4
                MGK.line(x1 + skew * k / 4, yy, x2 + skew * k / 4, yy, c, l[4] / 4 + 1)
            end
            MGK.line(x2, l[2], x2 + skew, l[2] + l[4], tocolor(196, 203, 209, 255), 1)
            if tn.kind == "wrinkle" then MGK.line(x1 + (x2 - x1) * 0.3, l[2] + l[4] * 0.2, x1 + (x2 - x1) * 0.6, l[2] + l[4] * 0.8, tocolor(150, 140, 120, 255), sc(2)) end
        end
        -- the roll at the current position
        if g.layer <= CAST.LAYERS then
            local rx = l[1] + l[3] * math.min(1, g.pos + CAST.WRAP_W * 0.5)
            MGK.round(rx - sc(12), l[2] - sc(10), sc(24), l[4] + sc(20), sc(5), tocolor(244, 246, 247, 255))
            MGK.line(rx, l[2] - sc(10), rx, l[2] + l[4] + sc(10), tocolor(196, 203, 209, 255), 1)
        end
        -- flash
        if g.flash and now - g.flash[1] < 350 then
            local k = g.flash[2]
            local col = (k == "good" and COL.good) or (k == "ok" and COL.accent) or COL.bad
            MGK.text(L("mg_cast.client.turn_" .. k), l[1], l[2] - sc(46), l[3], sc(30), col, 1.4, "center")
        end
        -- overlap slider + rhythm bar
        local sl, rb = g.slider, g.rbar
        MGK.gauge(sl[1], sl[2], sl[3], sl[4], g.overlap, CAST.OVERLAP_BAND[1], CAST.OVERLAP_BAND[2], L("mg_cast.client.overlap"))
        MGK.text(("%d%%"):format(g.overlap * 100), sl[1] + sl[3] + sc(14), sl[2] - sc(5), sc(80), sc(24), COL.text, 1.05)
        MGK.round(rb[1], rb[2], rb[3], rb[4], rb[4] / 2, COL.panel2)
        dxDrawRectangle(rb[1] + rb[3] * (0.5 - CAST.RHYTHM_WINDOW), rb[2], rb[3] * CAST.RHYTHM_WINDOW * 2, rb[4], tocolor(40, 86, 63, 255))
        if g.t and g.t >= 0 and g.layer <= CAST.LAYERS then
            MGK.circle(rb[1] + rb[3] * rhythm(g, g.t), rb[2] + rb[4] / 2, sc(8), COL.accent)
        end
        MGK.text(L("mg_cast.client.rhythm"), rb[1] - sc(110), rb[2] - sc(4), sc(100), rb[4] + sc(8), COL.dim, 0.95, "right")
        if g.tight > 0 then
            MGK.text(L("mg_cast.client.tight_count", { n = g.tight, max = CAST.TIGHT_FAIL }), ax + aw * 0.72, rb[2] - sc(5), aw * 0.28, sc(24),
                g.tight >= CAST.TIGHT_FAIL - 1 and COL.bad or COL.warn, 1.0, "right")
        end
    end,

    title = function(g)
        local part = g.options.part ~= "" and (" · " .. g.options.part) or ""
        return L("mg_cast.client.title", { part = part })
    end,
    status = function(g) return L("mg_cast.client.layer", { n = math.min(g.layer, CAST.LAYERS), total = CAST.LAYERS }) end,
    hint = function(g) return L("mg_cast.client.hint", { key = CAST.KEY:upper() }) end,
}

---------------------------------------------------------------- exports

function startCastGame(ped, options) return MGK.begin(ped, options, nil) end
function stopCastGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isCastGameActive() return MGK.active() end
