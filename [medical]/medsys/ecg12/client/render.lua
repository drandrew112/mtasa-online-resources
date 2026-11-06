-- 12-lead ECG renderer. A 3D heart dipole (P, Q, R, S, T as Gaussian bumps along fixed directions, an ST
-- injury vector during the plateau) is projected onto the 12 lead axes, so all leads agree with each other:
-- an ST elevation gets its reciprocal depression automatically. The curves are drawn once per spec into a
-- render target (paper grid, 25 mm/s, 10 mm/mV, 3 x 4 leads of 2.5 s + a 10 s lead II rhythm strip).
--   drawECG12(spec, x, y, w, h)  (export) draws the cached sheet; ECG12.open(target, spec) the viewer

ECG12 = { cache = {}, order = {} }

local RT_W, RT_H = 1000, 560
local PX_S, PX_MV = 100, 40          -- 25 mm/s with 4 px/mm, 10 mm/mV

-- lead axes: x = patient's left, y = inferior, z = anterior
local function frontal(deg) local r = math.rad(deg) return { math.cos(r), math.sin(r), 0 } end
local function norm(v) local l = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2) return { v[1] / l, v[2] / l, v[3] / l } end
local LEADS = {
    I = frontal(0), II = frontal(60), III = frontal(120), aVR = frontal(-150), aVL = frontal(-30), aVF = frontal(90),
    V1 = norm({ -0.55, 0.05, 0.85 }), V2 = norm({ -0.2, 0.05, 1 }), V3 = norm({ 0.2, 0.08, 0.95 }),
    V4 = norm({ 0.6, 0.12, 0.8 }), V5 = norm({ 0.85, 0.12, 0.5 }), V6 = norm({ 1, 0.12, 0.15 }),
}
local GRID = { { "I", "aVR", "V1", "V4" }, { "II", "aVL", "V2", "V5" }, { "III", "aVF", "V3", "V6" } }

-- ST injury vectors per territory (anterior LAD, inferior RCA, lateral Cx, left main)
local INJURY = {
    anterior = norm({ 0.1, -0.35, 0.95 }), inferior = norm({ -0.25, 1, -0.05 }),
    lateral = norm({ 1, -0.35, 0.1 }), lm = norm({ -0.8, -0.55, 0.05 }),
}

local function rng(seed)
    local s = seed % 2147483647
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

local function G(t, c, sd) local d = (t - c) / sd return math.exp(-0.5 * d * d) end
local function sig(x) return 1 / (1 + math.exp(-x)) end

-- beat onsets over 10 s (+ the independent P waves of a complete AV block)
local function beats(spec, rnd)
    local out, pOnly = {}, {}
    local rate = spec.rate
    if spec.rhythm == "ASYSTOLE" or spec.rhythm == "VF" or spec.rhythm == "ADENOSINE_PAUSE" or rate <= 0 then return out, pOnly end
    local rr = 60 / math.max(rate, 20)
    local t = -0.3 + rnd() * 0.2
    while t < 10.2 do
        out[#out + 1] = t
        local step = rr
        if spec.rhythm == "AFIB" then step = rr * (0.62 + rnd() * 0.76) end
        t = t + step
    end
    if spec.rhythm == "AVB3" then
        local pt = -0.2
        while pt < 10.2 do pOnly[#pOnly + 1] = pt pt = pt + 0.8 end
    end
    return out, pOnly
end

-- the dipole at time t (s) for the beat starting at t0
local function dipole(spec, t, t0, beatIndex, hv)
    local k = spec.qrs / 0.09
    local pr = (spec.noP or spec.rhythm == "AVB3") and 0.04 or spec.pr
    local x, y, z = 0, 0, 0
    local function add(v, a) x, y, z = x + v[1] * a, y + v[2] * a, z + v[3] * a end
    local dt = t - t0
    if dt < -0.1 or dt > 0.75 then return 0, 0, 0 end
    local hyper = spec.k or 4.2
    local alt = spec.alternans and ((beatIndex % 2 == 0) and 1.25 or 0.75) or 1
    if not spec.noP and spec.rhythm ~= "AVB3" then
        add({ 0.45, 0.75, 0.15 }, 0.17 * (hyper >= 6.5 and 0.3 or 1) * G(dt, 0.06, 0.022))
    end
    local inj = spec.stemi and INJURY[spec.stemi.territory]
    local stage = spec.stemi and spec.stemi.stage or nil
    -- QRS
    add({ -0.55, -0.1, 0.55 }, 0.22 * G(dt, pr + 0.012 * k, 0.006 * k))
    add({ 0.62, 0.72, -0.25 }, 1.35 * alt * G(dt, pr + 0.040 * k, 0.011 * k))
    add({ -0.25, -0.45, -0.75 }, 0.55 * alt * G(dt, pr + 0.068 * k, 0.010 * k))
    if inj and stage == "evolved" then add(inj, -0.55 * G(dt, pr + 0.022 * k, 0.012 * k)) end   -- pathological Q
    -- ST plateau + T
    local stStart, tC = pr + spec.qrs - 0.005, pr + spec.qrs + 0.19
    if inj then
        local amp = stage == "evolved" and 0.12 or (stage == "reperfused" and 0.04 or 0.28)
        add(inj, amp * sig((dt - stStart) / 0.008) * (1 - sig((dt - (stStart + 0.26)) / 0.03)))
    end
    local tv, ta, ts = { 0.55, 0.62, 0.05 }, 0.38, 0.05
    if hyper >= 6.0 then ta, ts = 0.38 * (1 + (hyper - 5.5) * 0.9), 0.026 end
    if inj and stage == "hyperacute" then add(inj, 0.45 * G(dt, tC, 0.055)) end
    if inj and stage == "evolved" then tv, ta = { -inj[1], -inj[2], -inj[3] }, 0.3 end
    if spec.qrs >= 0.14 and not inj then tv, ta = { -0.62, -0.72, 0.25 }, 0.5 end   -- wide QRS: discordant T
    add(tv, ta * G(dt, tC, ts))
    return x, y, z
end

local function leadValue(spec, lead, t, beatsList, pOnly, rnd2, hv)
    local name = lead
    if spec.swapRALA then
        if name == "I" then return -leadValue(spec, "I_raw", t, beatsList, pOnly, rnd2, hv)
        elseif name == "II" then name = "III" elseif name == "III" then name = "II"
        elseif name == "aVR" then name = "aVL" elseif name == "aVL" then name = "aVR" end
    end
    if name == "I_raw" then name = "I" end
    if (spec.wrongV or 0) >= 1 then
        if name == "V2" then name = "V4" elseif name == "V4" then name = "V2" end
    end
    if (spec.wrongV or 0) >= 2 then
        if name == "V3" then name = "V5" elseif name == "V5" then name = "V3" end
    end
    local axis = LEADS[name]
    local v = 0
    if spec.rhythm == "VF" then
        local ph = (axis[1] * 1.3 + axis[2] * 0.7 + axis[3]) * 2
        v = 0.45 * math.sin(2 * math.pi * 4.6 * t + ph) * (0.6 + 0.4 * math.sin(2 * math.pi * 0.4 * t))
            + 0.22 * math.sin(2 * math.pi * 7.3 * t + ph * 1.7)
    elseif spec.k and spec.k >= 8 and spec.rhythm ~= "ASYSTOLE" then
        local ph = axis[1] + axis[2] * 0.6
        v = 0.75 * math.sin(2 * math.pi * (math.max(spec.rate, 40) / 60) * t + ph)   -- sine wave
    else
        for i, t0 in ipairs(beatsList) do
            if t - t0 > -0.1 and t - t0 < 0.8 then
                local x, y, z = dipole(spec, t, t0, i, hv)
                v = v + x * axis[1] + y * axis[2] + z * axis[3]
            end
        end
        for _, t0 in ipairs(pOnly) do
            local d = t - t0
            if d > -0.05 and d < 0.15 then v = v + 0.17 * G(d, 0.06, 0.022) * (0.45 * axis[1] + 0.75 * axis[2] + 0.15 * axis[3]) end
        end
        if spec.rhythm == "AFIB" then v = v + 0.04 * math.sin(2 * math.pi * 6.3 * t + axis[2] * 3) + 0.03 * math.sin(2 * math.pi * 8.1 * t + axis[1]) end
    end
    if spec.lowVoltage then v = v * 0.45 end
    return v + 0.012 * math.sin(2 * math.pi * 0.23 * t + axis[1] * 2)   -- slight baseline wander
end

local function render(spec)
    local rt = dxCreateRenderTarget(RT_W, RT_H, false)
    if not rt then return nil end
    local rnd = rng(spec.seed or 1)
    local list, pOnly = beats(spec, rnd)
    dxSetRenderTarget(rt, true)
    dxDrawRectangle(0, 0, RT_W, RT_H, tocolor(255, 246, 246))
    for x = 0, RT_W, 4 do dxDrawLine(x, 0, x, RT_H, x % 20 == 0 and tocolor(240, 160, 160) or tocolor(250, 215, 215), 1) end
    for y = 0, RT_H, 4 do dxDrawLine(0, y, RT_W, y, y % 20 == 0 and tocolor(240, 160, 160) or tocolor(250, 215, 215), 1) end
    local ink = tocolor(15, 15, 20)
    local rowH = RT_H / 4
    local function strip(lead, t0, t1, x0, y0)
        local px, py
        for px2 = 0, math.floor((t1 - t0) * PX_S), 2 do
            local t = t0 + px2 / PX_S
            local v = leadValue(spec, lead, t, list, pOnly)
            local sx, sy = x0 + px2, y0 - v * PX_MV
            if px then dxDrawLine(px, py, sx, sy, ink, 1.6) end
            px, py = sx, sy
        end
        dxDrawText(lead, x0 + 4, y0 - rowH / 2 + 4, x0 + 60, y0, ink, 1, "default-bold")
    end
    for r, row in ipairs(GRID) do
        for c, lead in ipairs(row) do
            strip(lead, (c - 1) * 2.5, c * 2.5, (c - 1) * 250, (r - 0.5) * rowH)
        end
    end
    strip("II", 0, 10, 0, 3.5 * rowH)
    -- calibration pulse (1 mV)
    dxDrawLine(RT_W - 18, 3.5 * rowH, RT_W - 18, 3.5 * rowH - PX_MV, ink, 2)
    dxSetRenderTarget()
    return rt
end

local function sheet(spec)
    local key = tostring(spec.id or spec.seed)
    local rt = ECG12.cache[key]
    if rt and isElement(rt) then return rt end
    rt = render(spec)
    if rt then
        ECG12.cache[key] = rt
        ECG12.order[#ECG12.order + 1] = key
        if #ECG12.order > 8 then
            local old = table.remove(ECG12.order, 1)
            if isElement(ECG12.cache[old]) then destroyElement(ECG12.cache[old]) end
            ECG12.cache[old] = nil
        end
    end
    return rt
end

addEventHandler("onClientRestore", root, function()
    for k, rt in pairs(ECG12.cache) do if isElement(rt) then destroyElement(rt) end end
    ECG12.cache, ECG12.order = {}, {}
end)

-- export: draws the 12-lead sheet of a spec into a rectangle (keeps the aspect ratio)
function drawECG12(spec, x, y, w, h)
    if type(spec) ~= "table" then return false end
    local rt = sheet(spec)
    if not rt then return false end
    local sc = math.min(w / RT_W, h / RT_H)
    dxDrawImage(x + (w - RT_W * sc) / 2, y + (h - RT_H * sc) / 2, RT_W * sc, RT_H * sc, rt)
    return true
end

-- export: the rendered 12-lead sheet of a spec (a render target) and its size, for a caller that
-- draws it into its own render target (med_docs paper): get it before setting the target, since the
-- first call renders the sheet
function getECG12Sheet(spec)
    if type(spec) ~= "table" then return false end
    local rt = sheet(spec)
    if not rt then return false end
    return rt, RT_W, RT_H
end

-- the measurement line and the machine interpretation of a spec, in the player's language
function getECG12Text(spec)
    if type(spec) ~= "table" then return "", "" end
    local m = L("medsys.ecg12.measure", { hr = spec.hr or "-", pr = spec.prMs or "-", qrs = spec.qrsMs or "-", qt = spec.qt or "-", qtc = spec.qtc or "-", axis = spec.axis or "-" })
    local parts = {}
    for _, key in ipairs(spec.interp or {}) do parts[#parts + 1] = L("medsys.ecg12.int_" .. key) end
    return m, table.concat(parts, " · ") .. "  (" .. L("medsys.ecg12.unconfirmed") .. ")"
end

---------------------------------------------------------------- viewer (Lifepak 12-LEAD) with PRINT

local view = nil
addEvent("medic:ecg12", true)
addEventHandler("medic:ecg12", resourceRoot, function(target, spec) view = { target = target, spec = spec } showCursor(true) end)

function ECG12.request(target) triggerServerEvent("medic:ecg12Request", resourceRoot, target) end

local SX, SY = guiGetScreenSize()
local function box()
    local w = math.min(SX - 40, 1100)
    local h = w * 0.62
    return (SX - w) / 2, (SY - h) / 2, w, h
end

addEventHandler("onClientRender", root, function()
    if not view then return end
    local x, y, w, h = box()
    dxDrawRectangle(x - 6, y - 6, w + 12, h + 12, tocolor(20, 22, 26, 245))
    local m, interp = getECG12Text(view.spec)
    dxDrawText("12 ELV. EKG  ·  " .. m, x + 10, y + 4, x + w - 220, y + 26, tocolor(235, 240, 245), 1, "default-bold")
    dxDrawText(interp, x + 10, y + 26, x + w - 220, y + 48, tocolor(255, 200, 120), 1, "default", "left", "top", true)
    drawECG12(view.spec, x, y + 52, w, h - 56)
    local bw = 96
    local cx, cy = getCursorPosition()
    cx, cy = (cx or 0) * SX, (cy or 0) * SY
    for i, b in ipairs({ { "PRINT", { 46, 140, 80 } }, { "X", { 120, 40, 44 } } }) do
        local bx = x + w - (bw + 8) * (3 - i)
        local hov = cx >= bx and cx <= bx + bw and cy >= y + 6 and cy <= y + 40
        dxDrawRectangle(bx, y + 6, bw, 34, tocolor(b[2][1] + (hov and 25 or 0), b[2][2] + (hov and 25 or 0), b[2][3] + (hov and 25 or 0)))
        dxDrawText(b[1], bx, y + 6, bx + bw, y + 40, tocolor(255, 255, 255), 1, "default-bold", "center", "center")
    end
end)

addEventHandler("onClientClick", root, function(button, state, cx, cy)
    if not view or button ~= "left" or state ~= "down" then return end
    local x, y, w = box()
    local bw = 96
    for i = 1, 2 do
        local bx = x + w - (bw + 8) * (3 - i)
        if cx >= bx and cx <= bx + bw and cy >= y + 6 and cy <= y + 40 then
            if i == 1 then triggerServerEvent("medic:ecg12Print", resourceRoot, view.target, view.spec) end
            view = nil
            if not (isExaminationOpen and isExaminationOpen()) then showCursor(false) end
            return
        end
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if view and press and key == "escape" then
        cancelEvent()
        view = nil
        if not (isExaminationOpen and isExaminationOpen()) then showCursor(false) end
    end
end)
