if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Fracture reduction: hold the left mouse button and drag (down = traction, sideways = shift), turn
-- with the wheel under traction. Pain grows with every movement; a full meter makes the patient jerk.

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function rnd(a, b) return a + math.random() * (b - a) end
local function sign() return math.random() < 0.5 and -1 or 1 end

local function aligned(g)
    return math.abs(g.angle) < REDUCTION.GOAL_ANGLE and math.abs(g.shift) < REDUCTION.GOAL_SHIFT
end

local function painFactor(g) return g.options.analgesia and REDUCTION.ANALGESIA_FACTOR or 1 end

-- the rotated rectangle of a bone fragment as 4 corner lines
local function drawBone(cx, cy, len, width, angleDeg, color, fracTop)
    local a = math.rad(angleDeg)
    local dx, dy = math.sin(a), math.cos(a)     -- along the bone (downwards)
    local nx, ny = dy, -dx                       -- across
    for k = -width / 2, width / 2, 1.5 do
        local x1, y1 = cx + nx * k, cy + ny * k
        MGK.line(x1, y1, x1 + dx * len, y1 + dy * len, color, 2)
    end
    -- jagged fracture edge
    local px, py = cx - nx * width / 2, cy - ny * width / 2
    for i = 1, 6 do
        local t = i / 6
        local j = (i % 2 == 0 and 1 or -1) * sc(4) * (fracTop and -1 or 1)
        local x, y = cx + nx * (t * width - width / 2) + dx * j, cy + ny * (t * width - width / 2) + dy * j
        MGK.line(px, py, x, y, tocolor(5, 6, 7, 255), sc(3))
        px, py = x, y
    end
end

GAME = {
    cursor = true,

    init = function(g)
        g.angle = sign() * rnd(REDUCTION.ANGLE[1], REDUCTION.ANGLE[2])
        g.shift = sign() * rnd(REDUCTION.SHIFT[1], REDUCTION.SHIFT[2])
        g.traction, g.pain, g.attempts, g.hold, g.reduced = 0, 0, 0, 0, false
    end,

    click = function(g, button, state, cx, cy)
        if button == "left" and state == "down" then g.last = { cx, cy } end
        if button == "left" and state == "up" then g.last = nil end
    end,

    wheel = function(g, dir)
        if g.reduced then return end
        if g.traction < REDUCTION.TRACTION_MIN then
            g.lockMsg = g.now
            g.pain = g.pain + REDUCTION.PAIN_PER_TICK * 2 * painFactor(g)
            return
        end
        g.angle = g.angle + dir * REDUCTION.WHEEL_DEG
        g.pain = g.pain + REDUCTION.PAIN_PER_TICK * painFactor(g)
    end,

    update = function(g, dt)
        if g.reduced then return end
        local pxmm = sc(REDUCTION.PX_PER_MM)
        local cx, cy = MGK.cursor()
        if g.last and cx and MGK.isDown("left") then
            local dx, dy = cx - g.last[1], cy - g.last[2]
            g.last = { cx, cy }
            local mx, my = dx / pxmm, dy / pxmm
            g.shift = g.shift + mx
            g.traction = clamp(g.traction + my, 0, REDUCTION.TRACTION_MAX)
            g.pain = g.pain + (math.abs(mx) + math.abs(my)) * REDUCTION.PAIN_PER_MM * painFactor(g)
        else
            g.last = nil
            g.traction = math.max(0, g.traction - 12 * dt)   -- the muscles pull it back together
        end
        g.pain = math.max(0, g.pain - REDUCTION.PAIN_DECAY * dt)
        if g.pain >= 1 then
            -- the patient jerks the limb: the fragment slips back
            g.angle = g.angle + sign() * rnd(6, 12)
            g.shift = g.shift + sign() * rnd(2, 5)
            g.traction, g.pain, g.hold, g.last = 0, 0.3, 0, nil
            g.attempts = g.attempts + 1
            g.jerk = g.now
            return
        end
        if aligned(g) and g.traction >= REDUCTION.TRACTION_MIN then
            g.hold = g.hold + dt
            if g.hold >= REDUCTION.HOLD then g.reduced = true end
        else
            g.hold = 0
        end
    end,

    done = function(g) return g.reduced end,

    score = function(g)
        local details = { reduced = g.reduced, angle = math.floor(math.abs(g.angle) * 10) / 10,
                          shift = math.floor(math.abs(g.shift) * 10) / 10, attempts = g.attempts }
        if g.reduced then
            local used = clamp((g.t or 0) / g.options.time, 0, 1)
            return 100 - g.attempts * REDUCTION.ATTEMPT_PENALTY - used * 20, details
        end
        return math.max(0, 40 - math.abs(g.angle) * 2 - math.abs(g.shift) * 3), details
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local pxmm = sc(REDUCTION.PX_PER_MM)
        local r = ah * 0.46
        local cx, cy = ax + aw * 0.33, ay + ah * 0.5
        dxDrawCircle(cx, cy, r + sc(4), 0, 360, tocolor(44, 52, 60, 255), tocolor(44, 52, 60, 255), 48)
        dxDrawCircle(cx, cy, r, 0, 360, tocolor(5, 6, 7, 255), tocolor(14, 16, 18, 255), 48)
        local shake = (g.jerk and now - g.jerk < 400) and sc(6) * math.sin(now / 20) or 0
        local bw = sc(46)
        -- proximal fragment (fixed), upwards from the fracture
        drawBone(cx + shake, cy - r * 0.92, r * 0.92, bw, 0, tocolor(207, 213, 218, 255), false)
        -- distal fragment: shifted, pulled down, angulated
        drawBone(cx + g.shift * pxmm + shake, cy + g.traction * pxmm, r * 0.80, bw, g.angle, tocolor(207, 213, 218, 255), true)
        -- readouts
        local rx, ry, rw = ax + aw * 0.66, ay + sc(20), aw * 0.32
        local function row(label, value, ok, i)
            local y = ry + (i - 1) * sc(46)
            MGK.text(label, rx, y, rw * 0.55, sc(36), COL.dim, 1.05)
            MGK.text(value, rx + rw * 0.55, y, rw * 0.45, sc(36), ok and COL.good or COL.text, 1.3, "right")
        end
        row(L("mg_reduction.client.angulation"), ("%.1f°"):format(math.abs(g.angle)), math.abs(g.angle) < REDUCTION.GOAL_ANGLE, 1)
        row(L("mg_reduction.client.displacement"), ("%.1f mm"):format(math.abs(g.shift)), math.abs(g.shift) < REDUCTION.GOAL_SHIFT, 2)
        row(L("mg_reduction.client.traction"), ("%.1f mm"):format(g.traction), g.traction >= REDUCTION.TRACTION_MIN, 3)
        MGK.text(L("mg_reduction.client.goal", { angle = REDUCTION.GOAL_ANGLE, shift = REDUCTION.GOAL_SHIFT }), rx, ry + sc(140), rw, sc(30), COL.dim, 0.95)
        MGK.text(L("mg_reduction.client.pain"), rx, ry + sc(190), rw, sc(24), COL.dim, 1.0)
        MGK.bar(rx, ry + sc(218), rw, sc(14), g.pain, g.pain > 0.7 and COL.bad or COL.warn)
        if g.attempts > 0 then
            MGK.text(L("mg_reduction.client.attempts", { n = g.attempts }), rx, ry + sc(244), rw, sc(24), COL.bad, 1.0)
        end
        if g.hold > 0 and not g.reduced then
            MGK.text(L("mg_reduction.client.hold"), rx, ry + sc(280), rw, sc(24), COL.good, 1.1)
            MGK.bar(rx, ry + sc(308), rw, sc(10), g.hold / REDUCTION.HOLD, COL.good)
        end
        if g.lockMsg and now - g.lockMsg < 900 then
            MGK.text(L("mg_reduction.client.pull_first"), ax, ay + ah - sc(34), aw * 0.66, sc(30), COL.warn, 1.1, "center")
        end
        if g.jerk and now - g.jerk < 1200 then
            MGK.shadowText(L("mg_reduction.client.jerked"), ax, cy - sc(20), aw * 0.66, sc(40), COL.bad, 1.6)
        end
    end,

    title = function(g)
        local part = g.options.part ~= "" and (" · " .. g.options.part) or ""
        return L("mg_reduction.client.title", { part = part })
    end,
    status = function(g) return g.options.analgesia and L("mg_reduction.client.analgesia_on") or L("mg_reduction.client.analgesia_off") end,
    hint = function(g) return L("mg_reduction.client.hint") end,
}

---------------------------------------------------------------- exports

function startReductionGame(ped, options) return MGK.begin(ped, options, nil) end
function stopReductionGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isReductionGameActive() return MGK.active() end
