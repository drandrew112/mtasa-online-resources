if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Blood sampling: T = tourniquet, hold the left mouse button on the arm to palpate the vein, mouse
-- wheel = needle angle, click on the vein to puncture, click a tube in the rack to attach it, hold
-- SPACE to fill it to the mark, T again to release the tourniquet.

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function veinY(g, x)
    local u = (x - g.arm[1]) / g.arm[3]
    return g.arm[2] + g.arm[4] * (0.52 + 0.12 * math.sin(u * 3.1 + g.vp) - 0.08 * u)
end

local function onVein(g, x, y, tol)
    return x >= g.arm[1] + g.arm[3] * 0.25 and x <= g.arm[1] + g.arm[3] * 0.97 and math.abs(y - veinY(g, x)) <= tol
end

local function tourniquetTime(g)
    if not g.tqOn then return 0 end
    return ((g.tqOff or g.now or g.tqOn) - g.tqOn) / 1000
end

local function filledCount(g)
    local n = 0
    for _, id in ipairs(g.options.tubes) do if g.fill[id] and g.fill[id].done then n = n + 1 end end
    return n
end

local function rackPos(g, i)
    local r = g.rack
    local w = r[3] / #g.rackOrder
    return r[1] + (i - 1) * w + w * 0.25, r[2], w * 0.5, r[4]
end

local function finishTube(g)
    local id = g.current
    if not id then return end
    local level = g.fill[id].level
    g.fill[id].done = true
    if id == "citrate" and level < BLOOD.FILL_OK[1] then g.citrate = true
    elseif level < 0.7 then g.underfill = g.underfill + 1 end
    g.current = nil
end

GAME = {
    cursor = true,

    init = function(g)
        local ax, ay, aw, ah = MGK.area()
        g.arm = { ax + sc(10), ay + ah * 0.28, aw * 0.62, ah * 0.36 }
        g.rack = { ax + aw * 0.68, ay + sc(30), aw * 0.30, sc(120) }
        g.tube = { ax + aw * 0.79, ay + sc(190), sc(34), sc(170) }
        g.vp = math.random() * 6
        g.stage = "tourniquet"
        g.angle, g.attempts, g.palp = BLOOD.START_ANGLE, 0, 0
        g.fill, g.underfill, g.orderErrors = {}, 0, 0
        g.hematomas = {}
        -- the rack shows the needed tubes in a random order: the player has to know the order of draw
        g.rackOrder = {}
        for _, id in ipairs(g.options.tubes) do table.insert(g.rackOrder, math.random(1, #g.rackOrder + 1), id) end
    end,

    key = function(g, key, press)
        if key == BLOOD.KEY_TOURNIQUET then
            if press then
                if g.stage == "tourniquet" then g.tqOn, g.stage = g.now, "palpate"
                elseif g.tqOn and not g.tqOff and g.stage ~= "palpate" and g.stage ~= "puncture" then g.tqOff = g.now end
            end
            return true
        end
        if key == BLOOD.KEY_FILL then
            if not press and g.current then finishTube(g) end
            return true
        end
        return false
    end,

    wheel = function(g, dir)
        if g.stage == "puncture" then g.angle = clamp(g.angle - dir * BLOOD.WHEEL_DEG, 5, 60) end
    end,

    click = function(g, button, state, cx, cy)
        if button ~= "left" or state ~= "down" then return end
        if g.stage == "puncture" and MGK.inRect(cx, cy, g.arm[1], g.arm[2], g.arm[3], g.arm[4]) then
            local good = onVein(g, cx, cy, sc(9)) and g.angle >= BLOOD.ANGLE[1] and g.angle <= BLOOD.ANGLE[2]
            g.attempts = g.attempts + 1
            if good then
                g.stage, g.site = "tubes", { cx, cy }
            else
                g.hematomas[#g.hematomas + 1] = { cx, cy }
                g.msg = { g.now, (not onVein(g, cx, cy, sc(9)) and "missed") or (g.angle > BLOOD.ANGLE[2] and "too_steep") or "too_flat" }
                if g.attempts >= BLOOD.MAX_ATTEMPTS then g.gaveUp = true end
            end
        elseif g.stage == "tubes" and not g.current then
            for i, id in ipairs(g.rackOrder) do
                local x, y, w, h = rackPos(g, i)
                if MGK.inRect(cx, cy, x, y, w, h) and not (g.fill[id] and g.fill[id].done) then
                    -- order of draw: an EDTA tube before a needed citrate / serum / heparin tube carries K-EDTA over
                    for _, other in ipairs(BLOOD.ORDER) do
                        if other == id then break end
                        for _, need in ipairs(g.options.tubes) do
                            if need == other and not (g.fill[other] and g.fill[other].done) then
                                if id == "edta" then g.edta = true else g.orderErrors = g.orderErrors + 1 end
                            end
                        end
                    end
                    g.current = id
                    g.fill[id] = { level = 0 }
                    return
                end
            end
        end
    end,

    update = function(g, dt)
        local cx, cy = MGK.cursor()
        if g.stage == "palpate" and cx and MGK.isDown("left") and onVein(g, cx, cy, sc(16)) then
            g.palp = g.palp + dt
            if g.palp >= BLOOD.PALPATE_TIME then g.stage = "puncture" end
        end
        if g.stage == "tubes" then
            if g.current and getKeyState(BLOOD.KEY_FILL) then
                local f = g.fill[g.current]
                f.level = math.min(1, f.level + BLOOD.FILL_RATE * dt * (g.tqOff and 0.4 or 1))
            end
            if filledCount(g) >= #g.options.tubes then g.stage = "release" end
        end
    end,

    done = function(g)
        return g.gaveUp or (filledCount(g) >= #g.options.tubes and g.tqOff ~= nil)
    end,

    score = function(g)
        local tq = tourniquetTime(g)
        local hemolysis = tq > BLOOD.TOURNIQUET_MAX or g.attempts >= 2
        local filled = filledCount(g)
        local total = #g.options.tubes
        local p = 100 - (g.edta and 25 or 0) - (g.citrate and 20 or 0) - (hemolysis and 20 or 0)
            - math.max(0, g.attempts - 1) * 10 - g.orderErrors * 8 - g.underfill * 6 - (1 - filled / total) * 100
        if not g.tqOff then p = p - 10 end
        return p, { hemolysis = hemolysis, edta = g.edta == true, citrate = g.citrate == true, attempts = g.attempts,
                    tubes = total, filled = filled, tourniquet = math.floor(tq) }
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local a = g.arm
        MGK.round(a[1], a[2], a[3], a[4], a[4] / 2, COL.skin)
        -- vein: faint until palpated
        local alpha = (g.stage == "tourniquet" or g.stage == "palpate") and (25 + 160 * clamp(g.palp / BLOOD.PALPATE_TIME, 0, 1)) or 190
        local px, py
        for x = a[1] + a[3] * 0.25, a[1] + a[3] * 0.97, sc(6) do
            local y = veinY(g, x)
            if px then MGK.line(px, py, x, y, tocolor(58, 100, 168, alpha), sc(g.tqOn and 7 or 5)) end
            px, py = x, y
        end
        for _, hm in ipairs(g.hematomas) do MGK.circle(hm[1], hm[2], sc(12), tocolor(110, 50, 120, 150)) end
        -- tourniquet + its timer
        local tqx = a[1] + a[3] * 0.12
        if g.tqOn and not g.tqOff then
            dxDrawRectangle(tqx, a[2] - sc(4), sc(18), a[4] + sc(8), COL.accent)
            local tq = tourniquetTime(g)
            MGK.text(("%d:%02d"):format(tq / 60, tq % 60), tqx - sc(30), a[2] - sc(34), sc(78), sc(26),
                tq > BLOOD.TOURNIQUET_MAX and COL.bad or COL.text, 1.1, "center")
        end
        -- needle
        local cx, cy = MGK.cursor()
        if g.site then
            MGK.line(g.site[1] + sc(70), g.site[2] - sc(28), g.site[1], g.site[2], tocolor(233, 237, 242, 255), sc(3))
        elseif g.stage == "puncture" and cx then
            local r = math.rad(g.angle)
            MGK.line(cx + math.cos(r) * sc(90), cy - math.sin(r) * sc(90), cx, cy, tocolor(233, 237, 242, 255), sc(3))
            MGK.text(("%d°"):format(g.angle), cx + sc(20), cy - sc(60), sc(60), sc(24),
                (g.angle >= BLOOD.ANGLE[1] and g.angle <= BLOOD.ANGLE[2]) and COL.good or COL.warn, 1.1)
        end
        if g.msg and now - g.msg[1] < 1200 then
            MGK.text(L("mg_blooddraw.client." .. g.msg[2]), a[1], a[2] + a[4] + sc(10), a[3], sc(30), COL.bad, 1.2, "center")
        end
        -- rack
        MGK.text(L("mg_blooddraw.client.rack"), g.rack[1], g.rack[2] - sc(28), g.rack[3], sc(24), COL.dim, 1.0, "center")
        for i, id in ipairs(g.rackOrder) do
            local x, y, w, h = rackPos(g, i)
            local c = BLOOD.COLORS[id]
            local used = g.fill[id] and g.fill[id].done
            MGK.round(x, y, w, h, sc(4), tocolor(c[1], c[2], c[3], used and 70 or 255))
            if g.current == id then MGK.ring(x + w / 2, y - sc(12), sc(5), COL.white, 2) end
            MGK.text(L("mg_blooddraw.tube." .. id), x - w * 0.6, y + h + sc(4), w * 2.2, sc(22), COL.dim, 0.85, "center")
        end
        -- the tube being filled
        local t = g.tube
        if g.current then
            local c = BLOOD.COLORS[g.current]
            local level = g.fill[g.current].level
            MGK.round(t[1], t[2], t[3], t[4], sc(5), tocolor(30, 36, 43, 255))
            dxDrawRectangle(t[1], t[2], t[3], sc(22), tocolor(c[1], c[2], c[3], 255))
            local inner = t[4] - sc(26)
            dxDrawRectangle(t[1] + sc(3), t[2] + t[4] - sc(3) - inner * level, t[3] - sc(6), inner * level, tocolor(156, 32, 32, 255))
            local markY = t[2] + t[4] - sc(3) - inner * BLOOD.FILL_OK[1]
            MGK.line(t[1] - sc(8), markY, t[1] + t[3] + sc(8), markY, COL.white, 1)
            MGK.text(L("mg_blooddraw.client.fill_to_mark"), t[1] + t[3] + sc(14), markY - sc(12), sc(150), sc(24), COL.dim, 0.9)
        end
        -- steps
        local steps = { "tourniquet", "palpate", "puncture", "tubes", "release" }
        local sx, sy = ax + sc(10), ay + ah - sc(36)
        local reached = true
        for i, st in ipairs(steps) do
            local cur = g.stage == st
            local col = cur and COL.accent or (reached and COL.good or COL.dim)
            if cur then reached = false end
            MGK.text(("%d. %s"):format(i, L("mg_blooddraw.step." .. st)), sx + (i - 1) * aw / 5, sy, aw / 5, sc(30), col, 1.0)
        end
    end,

    title = function(g) return L("mg_blooddraw.client.title") end,
    status = function(g) return L("mg_blooddraw.client.tubes", { n = filledCount(g), total = #g.options.tubes }) end,
    hint = function(g) return L("mg_blooddraw.hint." .. g.stage) end,
}

---------------------------------------------------------------- exports

function startBloodDrawGame(ped, options) return MGK.begin(ped, options, nil) end
function stopBloodDrawGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isBloodDrawGameActive() return MGK.active() end
