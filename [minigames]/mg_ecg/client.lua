if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- 12-lead ECG: drag the electrodes from the tray onto the patient (front view: the patient's right is
-- on the screen's left), then Record. The preview draws lead I, II and V1-V6 from the placement.

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local R_PROG = { 0.15, 0.3, 0.55, 0.9, 1.0, 0.8 }   -- normal R amplitude V1-V6
local S_PROG = { 0.95, 0.9, 0.6, 0.35, 0.15, 0.08 }

local function isLimb(id) return #id == 2 and id:sub(1, 1) ~= "V" end

local function tolerance(id) return sc(isLimb(id) and ECG.LIMB_TOL or ECG.V_TOL) end

local function near(g, id, x, y) local t = g.targets[id] return MGK.dist(x, y, t[1], t[2]) <= tolerance(id) end

local function placedCount(g)
    local n = 0
    for _, id in ipairs(ECG.ELECTRODES) do if g.pos[id] then n = n + 1 end end
    return n
end

local function evaluate(g)
    local correct, wrongLimb, wrongV = 0, 0, 0
    for _, id in ipairs(ECG.ELECTRODES) do
        local p = g.pos[id]
        if p and near(g, id, p[1], p[2]) then correct = correct + 1
        elseif isLimb(id) then wrongLimb = wrongLimb + 1 else wrongV = wrongV + 1 end
    end
    local ra, la = g.pos.RA, g.pos.LA
    local swap = ra ~= nil and la ~= nil and near(g, "LA", ra[1], ra[2]) and near(g, "RA", la[1], la[2])
    return correct, swap, wrongLimb, wrongV
end

-- the amplitude a V electrode records: its own position, or the nearest target's lead when misplaced
local function vAmplitude(g, k)
    local p = g.pos["V" .. k]
    if not p then return nil end
    local best, bestD = k, math.huge
    for j = 1, 6 do
        local t = g.targets["V" .. j]
        local d = MGK.dist(p[1], p[2], t[1], t[2])
        if d < bestD then best, bestD = j, d end
    end
    local off = clamp(bestD / sc(60), 0, 1)
    return R_PROG[best] * (1 - off * 0.6), S_PROG[best] * (1 - off * 0.3), off
end

local function drawTrace(x, y, w, h, r, s, noise, invert, now)
    local beat = w / 2.2
    local px, py
    for i = 0, w, 2 do
        local u = ((i + now / 8) % beat) / beat
        local v = 0
        if u > 0.10 and u < 0.18 then v = 0.12 * math.sin((u - 0.10) / 0.08 * math.pi) end           -- P
        if u > 0.24 and u < 0.27 then v = -0.1 end                                                     -- Q
        if u >= 0.27 and u < 0.31 then v = r end                                                       -- R
        if u >= 0.31 and u < 0.35 then v = -s end                                                      -- S
        if u > 0.45 and u < 0.62 then v = 0.22 * math.sin((u - 0.45) / 0.17 * math.pi) end            -- T
        if invert then v = -v end
        if noise > 0 then v = v + (math.random() - 0.5) * noise * 0.4 end
        local yy = y + h / 2 - v * h * 0.45
        if px then dxDrawLine(px, py, x + i, yy, tocolor(63, 200, 122, 255), 1.5) end
        px, py = x + i, yy
    end
end

GAME = {
    cursor = true,

    init = function(g)
        local ax, ay, aw, ah = MGK.area()
        local bw, bh = aw * 0.36, ah * 0.62
        local bx, by = ax + aw * 0.14, ay + sc(16)
        g.body = { bx, by, bw, bh }
        g.armW, g.armGap = aw * 0.09, aw * 0.015
        local cxm = bx + bw / 2
        local ics = function(k) return by + bh * (0.08 + (k - 1) * 0.11) end
        g.ics = ics
        local sternum = bw * 0.06
        local raX = bx - g.armGap - g.armW / 2
        local laX = bx + bw + g.armGap + g.armW / 2
        g.targets = {
            RA = { raX, by + bh * 0.62 }, LA = { laX, by + bh * 0.62 },
            RL = { cxm - bw * 0.22, by + bh + ah * 0.13 }, LL = { cxm + bw * 0.22, by + bh + ah * 0.13 },
            V1 = { cxm - sternum - sc(8), ics(4) }, V2 = { cxm + sternum + sc(8), ics(4) },
            V4 = { cxm + bw * 0.26, ics(5) }, V5 = { cxm + bw * 0.38, ics(5) }, V6 = { cxm + bw * 0.50, ics(5) },
        }
        g.targets.V3 = { (g.targets.V2[1] + g.targets.V4[1]) / 2, (g.targets.V2[2] + g.targets.V4[2]) / 2 }
        g.tray = {}
        local ty = ay + ah - sc(32)
        g.dropMaxY = ay + ah - sc(66)   -- below this is the tray: dropping there puts the electrode back
        for i, id in ipairs(ECG.ELECTRODES) do g.tray[id] = { ax + sc(40) + (i - 1) * sc(60), ty } end
        g.preview = { ax + aw * 0.66, ay + sc(10), aw * 0.33, ah - sc(80) }
        g.button = { ax + aw * 0.66, ay + ah - sc(62), aw * 0.33, sc(44) }
        g.pos = {}
    end,

    click = function(g, button, state, cx, cy)
        if button ~= "left" then return end
        if state == "down" then
            local b = g.button
            if MGK.inRect(cx, cy, b[1], b[2], b[3], b[4]) and placedCount(g) == #ECG.ELECTRODES then g.recorded = true return end
            -- pick up: from the body first (placed ones), then the tray
            for _, id in ipairs(ECG.ELECTRODES) do
                local p = g.pos[id]
                if p and MGK.dist(cx, cy, p[1], p[2]) <= sc(ECG.R_PLACED + 2) then g.drag = id g.pos[id] = nil return end
            end
            for _, id in ipairs(ECG.ELECTRODES) do
                local p = g.tray[id]
                if not g.pos[id] and MGK.dist(cx, cy, p[1], p[2]) <= sc(ECG.R_TRAY + 2) then g.drag = id return end
            end
        elseif g.drag then
            local id = g.drag
            g.drag = nil
            local b = g.body
            -- anywhere on the patient (body or limbs area) counts as placed
            if cx > b[1] - MGK.W * 0.18 and cx < b[1] + b[3] + MGK.W * 0.18 and cy > b[2] - sc(10) and cy < g.dropMaxY then
                g.pos[id] = { cx, cy }
            end
        end
    end,

    key = function(g, key, press)
        if key == ECG.KEY_RECORD or key == "num_enter" then
            if press and placedCount(g) == #ECG.ELECTRODES then g.recorded = true end
            return true
        end
        return false
    end,

    done = function(g) return g.recorded == true end,

    score = function(g)
        local correct, swap, wrongLimb, wrongV = evaluate(g)
        return correct * 10, { correct = correct, swapRALA = swap, wrongLimb = wrongLimb, wrongV = wrongV, placed = placedCount(g) }
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local b = g.body
        -- limbs + torso
        local armY, armH = b[2] + sc(10), b[4] * 0.75
        MGK.round(b[1] - g.armGap - g.armW, armY, g.armW, armH, sc(24), COL.skin)
        MGK.round(b[1] + b[3] + g.armGap, armY, g.armW, armH, sc(24), COL.skin)
        MGK.round(b[1] + b[3] * 0.12, b[2] + b[4] - sc(10), b[3] * 0.30, ah * 0.20, sc(24), COL.skin)
        MGK.round(b[1] + b[3] * 0.58, b[2] + b[4] - sc(10), b[3] * 0.30, ah * 0.20, sc(24), COL.skin)
        MGK.round(b[1], b[2], b[3], b[4], sc(30), COL.skin)
        local cxm = b[1] + b[3] / 2
        dxDrawRectangle(cxm - b[3] * 0.06, b[2] + b[4] * 0.05, b[3] * 0.12, b[4] * 0.52, COL.skinDark)
        for k = 1, 7 do
            local y = g.ics(k) + b[4] * 0.055
            MGK.line(b[1] + sc(14), y, cxm - b[3] * 0.07, y + sc(6), tocolor(181, 131, 95, 160), sc(2))
            MGK.line(cxm + b[3] * 0.07, y + sc(6), b[1] + b[3] - sc(14), y, tocolor(181, 131, 95, 160), sc(2))
        end
        local lw = g.armW + sc(60)
        MGK.text(L("mg_ecg.client.patient_right"), b[1] - g.armGap - g.armW / 2 - lw / 2, b[2] - sc(14), lw, sc(20), COL.dim, 0.85, "center")
        MGK.text(L("mg_ecg.client.patient_left"), b[1] + b[3] + g.armGap + g.armW / 2 - lw / 2, b[2] - sc(14), lw, sc(20), COL.dim, 0.85, "center")
        -- the label with a dark outline: readable on every electrode colour and on the skin
        local function label(id, x, y, size, color)
            local w, h = sc(48), sc(24)
            for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                MGK.text(id, x - w / 2 + o[1], y - h / 2 + o[2], w, h, tocolor(0, 0, 0, 200), size, "center")
            end
            MGK.text(id, x - w / 2, y - h / 2, w, h, color or COL.white, size, "center")
        end
        -- guide (Nurse / Resident): every target spot dashed + labelled, the one of the electrode in
        -- hand pulsing in its colour
        if g.options.guide then
            for _, id in ipairs(ECG.ELECTRODES) do
                local t = g.targets[id]
                if not g.pos[id] and g.drag ~= id then
                    MGK.ring(t[1], t[2], sc(ECG.R_PLACED), tocolor(255, 255, 255, 170), 1.5, true)
                    label(id, t[1], t[2], 0.8, tocolor(255, 255, 255, 200))
                end
            end
            if g.drag then
                local t, c = g.targets[g.drag], ECG.COLORS[g.drag]
                local pulse = (math.sin(now / 160) + 1) / 2
                local r = sc(ECG.R_PLACED + 4 + pulse * 7)
                MGK.circle(t[1], t[2], r, tocolor(c[1], c[2], c[3], 60 + pulse * 50))
                MGK.ring(t[1], t[2], r, tocolor(math.min(255, c[1] + 60), math.min(255, c[2] + 60), math.min(255, c[3] + 60), 255), 3)
                label(g.drag, t[1], t[2], 0.9)
            end
        end
        -- electrodes (tray + placed + dragged)
        local function electrode(id, x, y, alpha, r, size)
            local c = ECG.COLORS[id]
            MGK.circle(x, y, r, tocolor(c[1], c[2], c[3], alpha or 255))
            MGK.ring(x, y, r, tocolor(230, 235, 240, alpha or 255), 2)
            label(id, x, y, size)
        end
        for _, id in ipairs(ECG.ELECTRODES) do
            local p = g.tray[id]
            if g.pos[id] or g.drag == id then MGK.ring(p[1], p[2], sc(ECG.R_TRAY), tocolor(80, 90, 100, 255), 1.5, true)
            else electrode(id, p[1], p[2], 255, sc(ECG.R_TRAY), 1.1) end
        end
        for _, id in ipairs(ECG.ELECTRODES) do
            local p = g.pos[id]
            if p then electrode(id, p[1], p[2], 255, sc(ECG.R_PLACED), 0.95) end
        end
        local cx, cy = MGK.cursor()
        if g.drag and cx then electrode(g.drag, cx, cy, 230, sc(ECG.R_TRAY), 1.1) end
        -- preview
        local pv = g.preview
        dxDrawRectangle(pv[1], pv[2], pv[3], pv[4], tocolor(5, 8, 6, 255))
        local rows = { "I", "II", "V1", "V2", "V3", "V4", "V5", "V6" }
        local rh = pv[4] / #rows
        local limbsOn = g.pos.RA and g.pos.LA and g.pos.LL and g.pos.RL
        local _, swap = evaluate(g)
        for i, lead in ipairs(rows) do
            local y = pv[2] + (i - 1) * rh
            MGK.text(lead, pv[1] + sc(6), y, sc(30), rh, COL.dim, 0.85)
            local x, w = pv[1] + sc(36), pv[3] - sc(44)
            if lead == "I" or lead == "II" then
                if limbsOn then
                    local limbOk = true
                    for _, id in ipairs({ "RA", "LA", "LL" }) do if not near(g, id, g.pos[id][1], g.pos[id][2]) then limbOk = false end end
                    drawTrace(x, y, w, rh, lead == "I" and 0.6 or 1.0, 0.15, (limbOk or swap) and 0 or 0.6, lead == "I" and swap, now)
                else
                    MGK.line(x, y + rh / 2, x + w, y + rh / 2, tocolor(63, 200, 122, 120), 1)
                end
            else
                local r, s, off = vAmplitude(g, tonumber(lead:sub(2)))
                if r then drawTrace(x, y, w, rh, r, s, off > 0.5 and 0.3 or 0, false, now)
                else MGK.line(x, y + rh / 2, x + w, y + rh / 2, tocolor(63, 200, 122, 120), 1) end
            end
        end
        local bt = g.button
        local ready = placedCount(g) == #ECG.ELECTRODES
        MGK.round(bt[1], bt[2], bt[3], bt[4], sc(6), ready and COL.accent or COL.panel2)
        MGK.text(L("mg_ecg.client.record"), bt[1], bt[2], bt[3], bt[4], ready and COL.white or COL.dim, 1.2, "center")
    end,

    title = function(g) return L("mg_ecg.client.title") end,
    status = function(g) return L("mg_ecg.client.placed", { n = placedCount(g), total = #ECG.ELECTRODES }) end,
    hint = function(g) return L("mg_ecg.client.hint") end,
}

---------------------------------------------------------------- exports

function startEcgGame(ped, options) return MGK.begin(ped, options, nil) end
function stopEcgGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isEcgGameActive() return MGK.active() end
