-- EMS tablet: hospital status line + the parameter card picker (server/hospitalparams.lua).
-- Pulse, SpO2 and BP are ticked by default; only measured values can be ticked.

HospitalParams = { data = nil, picked = {}, target = nil, hospitals = {} }
local s = Gfx.s

addEvent("erm:hospitalStatus", true)
addEventHandler("erm:hospitalStatus", resourceRoot, function(list) HospitalParams.hospitals = list or {} end)

addEvent("erm:paramsData", true)
addEventHandler("erm:paramsData", resourceRoot, function(d)
    HospitalParams.data = d
    HospitalParams.hospitals = d.hospitals or HospitalParams.hospitals
    HospitalParams.target = d.target
    HospitalParams.picked = {}
    for _, it in ipairs(d.items or {}) do if it.default and it.measured then HospitalParams.picked[it.key] = true end end
end)

local function statusText(h)
    if not h then return "" end
    if not h.er or h.staff == 0 then return L("med_erm.hospital.status_none", { name = h.name }) end
    return L("med_erm.hospital.status_staff", { name = h.name, n = h.staff, free = h.free, total = h.total })
end

-- the nearest hospital's status (case page)
function HospitalParams.nearestStatus()
    local px, py = getElementPosition(localPlayer)
    local best, bestD
    for _, h in ipairs(HospitalParams.hospitals) do
        local d = getDistanceBetweenPoints2D(px, py, h.x, h.y)
        if not bestD or d < bestD then best, bestD = h, d end
    end
    return best and statusText(best) or nil, best
end

function HospitalParams.open()
    HospitalParams.data = nil
    Tablet.send("erm:paramsRequest")
    Tablet.picker = HospitalParams.draw
end

function HospitalParams.draw(sx, sy, sw, sh)
    Gfx.hits = {}
    dxDrawRectangle(sx, sy, sw, sh, Theme.shade)
    local w, h = s(560), s(400)
    local x, y = sx + (sw - w) / 2, sy + (sh - h) / 2
    Gfx.round(x, y, w, h, s(10), Theme.bg)
    Gfx.text(L("med_erm.hospital.params_title"), x + s(20), y + s(12), w - s(40), s(26), Theme.text, Gfx.font(13, true))
    local d = HospitalParams.data
    if not d then
        Gfx.text(L("med_erm.hospital.loading"), x, y, w, h, Theme.dim, Gfx.font(10), "center")
        Gfx.hit(x, y, w, h, function() end)
        return
    end
    -- target hospital
    local hy = y + s(44)
    local hx = x + s(20)
    for _, hsp in ipairs(d.hospitals or {}) do
        local on = HospitalParams.target == hsp.id
        local label = hsp.name .. ((hsp.er and hsp.staff > 0) and (" · " .. hsp.staff .. "/" .. hsp.free) or "")
        local bw = math.min(s(250), L.width(label, 1, Gfx.font(8, true)) + s(16))
        if hx + bw > x + w - s(20) then hx = x + s(20) hy = hy + s(28) end
        Gfx.button(hx, hy, bw, s(24), label, { color = on and { 56, 132, 244 } or { 48, 56, 66 }, font = Gfx.font(8, true) },
            function() HospitalParams.target = hsp.id end)
        hx = hx + bw + s(6)
    end
    local tgt
    for _, hsp in ipairs(d.hospitals or {}) do if hsp.id == HospitalParams.target then tgt = hsp end end
    Gfx.text(statusText(tgt), x + s(20), hy + s(28), w - s(40), s(20), (tgt and tgt.staff > 0) and Theme.text or Theme.faint, Gfx.font(9))
    -- items
    local iy = hy + s(54)
    if not d.patient then
        Gfx.text(L("med_erm.hospital.no_patient"), x + s(20), iy, w - s(40), s(24), Theme.faint, Gfx.font(10))
    end
    local colW = (w - s(50)) / 2
    for i, it in ipairs(d.items or {}) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local bx, by = x + s(20) + col * (colW + s(10)), iy + row * s(30)
        local on = HospitalParams.picked[it.key]
        local label = ("%s  %s"):format(on and "☑" or "☐", L("med_hospitals.comms.p_" .. it.key))
        Gfx.button(bx, by, colW, s(26), label .. "   " .. (it.measured and tostring(it.value) or L("med_erm.hospital.not_measured")),
            { color = on and { 40, 90, 150 } or { 38, 44, 52 }, disabled = not it.measured, align = "left", font = Gfx.font(9) },
            function() HospitalParams.picked[it.key] = not HospitalParams.picked[it.key] or nil end)
    end
    local bw = (w - s(50)) / 2
    Gfx.button(x + s(20), y + h - s(52), bw, s(36), L("med_erm.hospital.send"), { color = { 56, 132, 244 }, disabled = not d.patient or not HospitalParams.target },
        function()
            local keys = {}
            for k in pairs(HospitalParams.picked) do keys[#keys + 1] = k end
            Tablet.send("erm:paramsSend", HospitalParams.target, keys)
            Tablet.picker = nil
        end)
    Gfx.button(x + s(30) + bw, y + h - s(52), bw, s(36), L("common.cancel"), {}, function() Tablet.picker = nil end)
end
