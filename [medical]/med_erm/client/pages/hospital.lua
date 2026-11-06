if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- "Kórház" (hospital) page: the hospitals with their ER status (staff on duty, free corridor places), the
-- message thread of this unit with the chosen hospital (med_hospitals er/server/comms.lua) and the
-- one-button parameter card (client/hospitalparams.lua).

local s = Gfx.s

Pages.hospital = { target = nil, thread = {} }

addEvent("erm:hospThread", true)
addEventHandler("erm:hospThread", resourceRoot, function(hid, msgs)
    if hid == Pages.hospital.target then Pages.hospital.thread = msgs or {} end
end)

local inputToken
addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= inputToken then return end
    inputToken = nil
    local hid = Pages.hospital.target
    if hid and text and text:gsub("%s", "") ~= "" then Tablet.send("erm:hospMessage", hid, text) end
end)

local function pick(hid)
    Pages.hospital.target = hid
    Pages.hospital.thread = {}
    Tablet.send("erm:hospThread", hid)
end

function Pages.hospital.draw(x, y, w, h)
    local pad = s(18)
    local ix, iw = x + pad, w - pad * 2
    Gfx.text(L("med_erm.hospital.page_title"), ix, y + s(12), iw, s(30), Theme.text, Gfx.font(15, true))
    local list = HospitalParams.hospitals or {}
    if not Pages.hospital.target then
        local _, nearest = HospitalParams.nearestStatus()
        if nearest then pick(nearest.id) end
    end
    -- hospitals with their status
    local hy = y + s(48)
    local hx = ix
    for _, hsp in ipairs(list) do
        local on = hsp.id == Pages.hospital.target
        local staffed = hsp.er and hsp.staff > 0
        local label = hsp.name .. (staffed and ("  ·  " .. L("med_erm.hospital.short_status", { n = hsp.staff, free = hsp.free, total = hsp.total })) or "")
        local bw = math.min(iw, L.width(label, 1, Gfx.font(9, true)) + s(20))
        if hx + bw > ix + iw then hx = ix hy = hy + s(32) end
        Gfx.button(hx, hy, bw, s(28), label, { color = on and { 56, 132, 244 } or (staffed and { 40, 70, 56 } or { 48, 56, 66 }), font = Gfx.font(9, true) }, function() pick(hsp.id) end)
        hx = hx + bw + s(6)
    end
    hy = hy + s(36)
    local tgt
    for _, hsp in ipairs(list) do if hsp.id == Pages.hospital.target then tgt = hsp end end
    local staffed = tgt and tgt.er and tgt.staff > 0
    Gfx.text(tgt and (staffed and L("med_erm.hospital.status_staff", { name = tgt.name, n = tgt.staff, free = tgt.free, total = tgt.total })
        or L("med_erm.hospital.status_none", { name = tgt.name })) or "", ix, hy, iw - s(200), s(24), staffed and Theme.text or Theme.faint, Gfx.font(10))
    Gfx.button(ix + iw - s(190), hy - s(2), s(190), s(28), L("med_erm.hospital.send_params"), { color = { 56, 132, 244 }, font = Gfx.font(9, true) }, function()
        HospitalParams.open()
    end)
    -- the thread
    local ly = hy + s(34)
    local inputH = s(38)
    local listH = y + h - ly - inputH - s(22)
    Gfx.round(ix, ly, iw, listH, s(8), Theme.panel)
    local msgs = Pages.hospital.thread or {}
    local my = ly + listH - s(8)
    for i = #msgs, 1, -1 do
        local m = msgs[i]
        local text = m.text
        if m.card then
            local parts = {}
            for _, it in ipairs(m.card) do parts[#parts + 1] = L("med_hospitals.comms.p_" .. it.key) .. " " .. tostring(it.value) end
            text = L("med_erm.hospital.params_card") .. ": " .. table.concat(parts, " · ")
        end
        local lines = Gfx.wrap(tostring(text or ""), iw * 0.7 - s(20), Gfx.font(9))
        local bh = s(20) + #lines * s(15)
        my = my - bh - s(6)
        if my < ly + s(4) then break end
        local mine = m.side == "ems"
        local bw = iw * 0.72
        local bx = mine and (ix + iw - bw - s(8)) or (ix + s(8))
        Gfx.round(bx, my, bw, bh, s(6), mine and tocolor(29, 58, 92) or Theme.panel2)
        local tm = getRealTime(m.at or 0)
        Gfx.text(("%s · %02d:%02d"):format(m.from or "?", tm.hour, tm.minute), bx + s(8), my + s(2), bw - s(16), s(16), Theme.dim, Gfx.font(8))
        for li, ln in ipairs(lines) do Gfx.text(ln, bx + s(8), my + s(16) + (li - 1) * s(15), bw - s(16), s(15), Theme.text, Gfx.font(9)) end
    end
    if #msgs == 0 then Gfx.text(L(staffed and "med_erm.hospital.no_messages" or "med_erm.hospital.no_staff_no_messages"), ix, ly + s(16), iw, s(24), Theme.faint, Gfx.font(10), "center") end
    Gfx.button(ix, y + h - inputH - s(14), iw, inputH, L("med_erm.hospital.write"), { color = { 48, 56, 66 }, align = "left", font = Gfx.font(10), disabled = not staffed }, function()
        local res = getResourceFromName("ui_core")
        if not res or getResourceState(res) ~= "running" then return end
        inputToken = exports.ui_core:openTextInput(L("med_erm.hospital.write_title", { name = tgt and tgt.name or "" }), 300, "")
    end)
end
