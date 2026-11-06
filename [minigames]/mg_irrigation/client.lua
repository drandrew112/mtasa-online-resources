if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Irrigation: hold the left mouse button to spray where the cursor is. Debris inside the stream
-- shrinks; the pressure (mouse wheel up / down) drifts while spraying and has to stay in the green band.

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function inWound(g, x, y)
    local w = g.wound
    return ((x - w.x) / w.rx) ^ 2 + ((y - w.y) / w.ry) ^ 2 <= 1
end

local function cleanPercent(g)
    local left = 0
    for _, d in ipairs(g.debris) do left = left + math.max(0, d.hp) end
    return clamp((1 - left / #g.debris) * 100, 0, 100)
end

GAME = {
    cursor = true,

    init = function(g)
        local ax, ay, aw, ah = MGK.area()
        g.skin = { ax + sc(20), ay + sc(20), aw - sc(40), ah - sc(110) }
        g.wound = { x = ax + aw * 0.45, y = g.skin[2] + g.skin[4] / 2, rx = aw * 0.26, ry = g.skin[4] * 0.28 }
        g.debris = {}
        for i = 1, g.options.debris do
            local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * 0.82
            g.debris[i] = { x = g.wound.x + math.cos(a) * r * g.wound.rx, y = g.wound.y + math.sin(a) * r * g.wound.ry,
                            hp = 1, size = sc(math.random(4, 8)) }
        end
        g.pressure, g.damage, g.spraying = IRRIG.START_PRESSURE, 0, false
        g.nozzle = { ax + aw * 0.86, g.skin[2] + sc(10) }
        g.drift = 0
    end,

    wheel = function(g, dir) g.pressure = clamp(g.pressure - dir * IRRIG.WHEEL_STEP, 0, 1) end,

    update = function(g, dt)
        local cx, cy = MGK.cursor()
        g.spraying = cx ~= nil and MGK.isDown("left") and MGK.inRect(cx, cy, g.skin[1], g.skin[2], g.skin[3], g.skin[4])
        if not g.spraying then return end
        -- the pressure wanders: a slowly turning random walk the player corrects with the wheel
        g.drift = clamp(g.drift + (math.random() - 0.5) * 4 * dt, -1, 1)
        g.pressure = clamp(g.pressure + g.drift * IRRIG.DRIFT * dt, 0, 1)
        local p, b1, b2 = g.pressure, IRRIG.BAND[1], IRRIG.BAND[2]
        local rate = (p < b1 and IRRIG.LOW_RATE * (p / b1)) or (p <= b2 and IRRIG.CLEAN_RATE) or IRRIG.HIGH_RATE
        if p > b2 and inWound(g, cx, cy) then
            g.damage = clamp(g.damage + IRRIG.DAMAGE_RATE * dt * (0.4 + (p - b2) / (1 - b2)), 0, 1)
        end
        local r = sc(IRRIG.RADIUS)
        for _, d in ipairs(g.debris) do
            if d.hp > 0 and MGK.dist(d.x, d.y, cx, cy) <= r then d.hp = d.hp - rate * dt end
        end
    end,

    done = function(g)
        for _, d in ipairs(g.debris) do if d.hp > 0 then return false end end
        return true
    end,

    score = function(g)
        local clean = cleanPercent(g)
        local damage = math.floor(g.damage * 100)
        return clean - damage * 0.5, { clean = math.floor(clean), damage = damage }
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local s, w = g.skin, g.wound
        MGK.round(s[1], s[2], s[3], s[4], sc(18), COL.skin)
        dxDrawCircle(w.x, w.y, w.rx, 0, 360, tocolor(156, 43, 43, 255), tocolor(156, 43, 43, 255), 40, w.ry / w.rx)
        dxDrawCircle(w.x, w.y, w.rx * 0.8, 0, 360, tocolor(185, 65, 59, 255), tocolor(185, 65, 59, 255), 40, w.ry / w.rx)
        -- damaged tissue darkens
        if g.damage > 0 then
            dxDrawCircle(w.x, w.y, w.rx * 0.8, 0, 360, tocolor(80, 10, 10, 160 * g.damage), tocolor(80, 10, 10, 160 * g.damage), 40, w.ry / w.rx)
        end
        for _, d in ipairs(g.debris) do
            if d.hp > 0 then MGK.circle(d.x, d.y, d.size * (0.35 + 0.65 * d.hp), tocolor(91, 70, 50, 255)) end
        end
        -- syringe + stream
        local cx, cy = MGK.cursor()
        MGK.round(g.nozzle[1] - sc(14), g.nozzle[2] - sc(10), sc(40), sc(20), sc(4), tocolor(233, 237, 242, 255))
        if g.spraying and cx then
            local spread = sc(4)
            for i = -1, 1 do
                MGK.line(g.nozzle[1], g.nozzle[2] + i * sc(2), cx + i * spread, cy + i * spread * 0.5, tocolor(159, 214, 255, 200), sc(2))
            end
            for i = 1, 6 do
                local a = math.random() * math.pi * 2
                local r = math.random() * sc(IRRIG.RADIUS) * 0.8
                MGK.circle(cx + math.cos(a) * r, cy + math.sin(a) * r, sc(2), tocolor(200, 230, 255, 170))
            end
        end
        if cx then MGK.ring(cx, cy, sc(IRRIG.RADIUS), tocolor(159, 214, 255, 120), 1.5, true) end
        -- pressure gauge
        local gy = s[2] + s[4] + sc(36)
        local p = g.pressure
        local inBand = p >= IRRIG.BAND[1] and p <= IRRIG.BAND[2]
        MGK.gauge(ax + sc(130), gy, aw * 0.5, sc(14), p, IRRIG.BAND[1], IRRIG.BAND[2], L("mg_irrigation.client.pressure"))
        local label = (p < IRRIG.BAND[1] and L("mg_irrigation.client.too_low")) or (p > IRRIG.BAND[2] and L("mg_irrigation.client.too_high")) or L("mg_irrigation.client.good")
        MGK.text(label, ax + sc(145) + aw * 0.5, gy - sc(5), sc(160), sc(24), inBand and COL.good or COL.warn, 1.05)
        if g.damage > 0 then
            MGK.text(L("mg_irrigation.client.damage", { n = math.floor(g.damage * 100) }), ax + aw * 0.72, gy - sc(5), aw * 0.28, sc(24),
                g.damage * 100 > IRRIG.PASS_DAMAGE and COL.bad or COL.warn, 1.0, "right")
        end
    end,

    title = function(g)
        local part = g.options.part ~= "" and (" · " .. g.options.part) or ""
        return L("mg_irrigation.client.title", { part = part })
    end,
    status = function(g) return L("mg_irrigation.client.clean", { n = math.floor(cleanPercent(g)) }) end,
    hint = function(g) return L("mg_irrigation.client.hint") end,
}

---------------------------------------------------------------- exports

function startIrrigationGame(ped, options) return MGK.begin(ped, options, nil) end
function stopIrrigationGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isIrrigationGameActive() return MGK.active() end
