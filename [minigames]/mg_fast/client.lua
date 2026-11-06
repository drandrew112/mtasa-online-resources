if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- FAST ultrasound: hold the left mouse button to put the probe down, move it into a window and keep it
-- there; tilt with the mouse wheel until the live picture on the right clears.

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- window positions on the torso drawing (0-1 of the torso box); the patient's right is on the screen's left
local POS = {
    ruq = { 0.30, 0.50 }, luq = { 0.70, 0.46 }, pelvis = { 0.50, 0.86 }, cardiac = { 0.50, 0.30 },
    lung_r = { 0.33, 0.14 }, lung_l = { 0.67, 0.14 },
}

local function windowAt(g, x, y)
    for _, w in ipairs(g.windows) do
        if MGK.dist(x, y, w.x, w.y) <= sc(FAST.RADIUS) then return w end
    end
end

local function clarity(g, w) return clamp(1 - math.abs(g.tilt - w.tilt) / FAST.TILT_FALLOFF, 0, 1) end

local function evaluated(g)
    local n = 0
    for _, w in ipairs(g.windows) do if w.result then n = n + 1 end end
    return n
end

GAME = {
    cursor = true,

    init = function(g)
        local ax, ay, aw, ah = MGK.area()
        g.torso = { ax + aw * 0.06, ay + sc(10), aw * 0.42, ah - sc(30) }
        g.screen = { ax + aw * 0.55, ay + sc(10), aw * 0.43, ah - sc(30) }
        g.windows = {}
        for _, id in ipairs(FAST.windowList(g.options)) do
            local p = POS[id]
            g.windows[#g.windows + 1] = { id = id, x = g.torso[1] + g.torso[3] * p[1], y = g.torso[2] + g.torso[4] * p[2],
                tilt = (math.random() * 2 - 1) * FAST.TILT_RANGE, hold = 0 }
        end
        g.tilt = 0
        g.speckle = {}
        for i = 1, 260 do g.speckle[i] = { math.random(), math.random(), math.random() } end
    end,

    wheel = function(g, dir) g.tilt = clamp(g.tilt - dir * FAST.WHEEL_DEG, -45, 45) end,

    update = function(g, dt)
        local cx, cy = MGK.cursor()
        g.on = nil
        if not cx or not MGK.isDown("left") then return end
        local w = windowAt(g, cx, cy)
        g.on = w
        if w and not w.result then
            if clarity(g, w) >= FAST.CLEAR then
                w.hold = w.hold + dt
                if w.hold >= FAST.HOLD then w.result = g.options.positives[w.id] and "pos" or "neg" end
            end
        end
    end,

    done = function(g) return evaluated(g) >= #g.windows end,

    score = function(g)
        local res = {}
        for _, w in ipairs(g.windows) do res[w.id] = w.result or "na" end
        local n = evaluated(g)
        return n / #g.windows * 100, { windows = res, evaluated = n, total = #g.windows }
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local t = g.torso
        -- torso outline
        local tx, ty, tw, th = t[1], t[2], t[3], t[4]
        MGK.round(tx + tw * 0.08, ty, tw * 0.84, th, sc(40), tocolor(42, 50, 59, 255))
        MGK.round(tx + tw * 0.11, ty + sc(4), tw * 0.78, th - sc(8), sc(36), tocolor(52, 61, 71, 255))
        MGK.line(tx + tw * 0.5, ty + th * 0.08, tx + tw * 0.5, ty + th * 0.36, tocolor(70, 80, 92, 255), sc(2))
        for _, w in ipairs(g.windows) do
            local col = (w.result == "pos" and COL.warn) or (w.result == "neg" and COL.good) or tocolor(120, 132, 145, 255)
            MGK.ring(w.x, w.y, sc(FAST.RADIUS), col, 2, w.result == nil)
            MGK.text(L("mg_fast.window_short." .. w.id), w.x - sc(60), w.y + sc(FAST.RADIUS) + sc(2), sc(120), sc(20), COL.dim, 0.85, "center")
            if w.hold > 0 and not w.result then MGK.bar(w.x - sc(26), w.y - sc(FAST.RADIUS) - sc(12), sc(52), sc(6), w.hold / FAST.HOLD, COL.accent) end
        end
        local cx, cy = MGK.cursor()
        if cx and MGK.inRect(cx, cy, tx, ty, tw, th) then
            local down = MGK.isDown("left")
            local a = math.rad(g.tilt)
            local pw, ph = sc(16), sc(30)
            local dx, dy = math.sin(a), math.cos(a)
            MGK.line(cx - dx * ph / 2, cy - dy * ph / 2, cx + dx * ph / 2, cy + dy * ph / 2, down and COL.white or tocolor(233, 237, 242, 140), pw)
        end
        -- live ultrasound picture
        local s = g.screen
        dxDrawRectangle(s[1], s[2], s[3], s[4], tocolor(5, 6, 8, 255))
        local fx, fy = s[1] + s[3] / 2, s[2] + sc(20)
        local fanH = s[4] - sc(80)
        local w = g.on
        local clear = w and clarity(g, w) or 0
        for _, p in ipairs(g.speckle) do
            local u, v = p[1] * 2 - 1, p[2]
            local x, y = fx + u * v * s[3] * 0.45, fy + v * fanH
            local b = (w and (60 + 140 * clear) or 25) * (0.5 + p[3] * 0.5)
            if w and w.result ~= "neg" and g.options.positives[w.id] and clear > 0.5 and math.abs(u) < 0.35 and v > 0.45 and v < 0.62 then b = 8 end
            dxDrawRectangle(x, y, sc(4), sc(3), tocolor(b, b, b, 255))
        end
        if w and clear > 0.5 then
            -- organ outline + free fluid band (anechoic stripe) when positive
            local oy = fy + fanH * 0.5
            dxDrawCircle(fx, oy, s[3] * 0.16, 200, 340, tocolor(150, 150, 150, 120 * clear), tocolor(0, 0, 0, 0), 20)
            if g.options.positives[w.id] then
                MGK.line(fx - s[3] * 0.15, oy + sc(6), fx + s[3] * 0.15, oy + sc(4), tocolor(0, 0, 0, 255 * clear), sc(9))
            end
        end
        MGK.text(w and L("mg_fast.window." .. w.id) or L("mg_fast.client.no_contact"), s[1], s[2] + s[4] - sc(56), s[3], sc(24), COL.text, 1.05, "center")
        if w then
            local label = w.result and L("mg_fast.client.result_" .. w.result) or L("mg_fast.client.clarity", { n = math.floor(clear * 100) })
            local col = (w.result == "pos" and COL.warn) or (w.result == "neg" and COL.good) or (clear >= FAST.CLEAR and COL.good or COL.dim)
            MGK.text(label, s[1], s[2] + s[4] - sc(30), s[3], sc(24), col, 1.0, "center")
        end
        MGK.text(("%+d°"):format(g.tilt), s[1] + s[3] - sc(70), s[2] + sc(6), sc(64), sc(22), COL.dim, 0.95, "right")
    end,

    title = function(g) return L(g.options.efast and "mg_fast.client.title_efast" or "mg_fast.client.title") end,
    status = function(g) return L("mg_fast.client.windows", { n = evaluated(g), total = #g.windows }) end,
    hint = function(g) return L("mg_fast.client.hint") end,
}

---------------------------------------------------------------- exports

function startFastGame(ped, options) return MGK.begin(ped, options, nil) end
function stopFastGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isFastGameActive() return MGK.active() end
