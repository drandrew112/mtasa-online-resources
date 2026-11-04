if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Supervisor page (SUP units only): pick a signed-in unit, fine it for one of Config.FINES and look at its fines
-- of the current shift. The data comes from the server (server/fines.lua), refreshed while the page is open.

local s = Gfx.s

Pages.supervisor = { units = {}, selected = nil, lastRequest = 0 }
local P = Pages.supervisor

addEvent("erm:supUnits", true)
addEventHandler("erm:supUnits", resourceRoot, function(list)
    P.units = type(list) == "table" and list or {}
end)

local function selectedUnit()
    for _, u in ipairs(P.units) do
        if u.id == P.selected then return u end
    end
end

local function refresh(force)
    local t = getTickCount()
    if force or t - P.lastRequest > 3000 then
        P.lastRequest = t
        triggerServerEvent("erm:supList", resourceRoot)
    end
end

local function typeColor(unitType)
    return unitType == "SUP" and { 150, 110, 230 } or { 56, 132, 244 }
end

function P.draw(x, y, w, h)
    if not State.unit or State.unit.type ~= "SUP" then Tablet.setPage("home") return end
    refresh(false)

    local pad = s(18)
    local ix, iw = x + pad, w - pad * 2
    local cy = y + s(14)
    Gfx.text(L("med_erm.supervisor.title"), ix, cy, iw, s(26), Theme.text, Gfx.font(15, true))
    cy = cy + s(34)

    local bodyH = y + h - cy - s(14)
    local lw = s(200)
    local rx, rw = ix + lw + s(12), iw - lw - s(12)

    -- unit list ---------------------------------------------------------------
    Gfx.round(ix, cy, lw, bodyH, s(8), Theme.panel)
    local units = P.units
    if #units == 0 then
        Gfx.text(L("med_erm.supervisor.no_units"), ix + s(10), cy, lw - s(20), bodyH, Theme.faint, Gfx.font(9), "center", "center", true)
    else
        local rowH = s(46)
        local visible = math.floor((bodyH - s(8)) / rowH)
        local offset = Gfx.getScroll("sup_units", #units - visible)
        Gfx.scrollArea("sup_units", ix, cy, lw, bodyH)
        for i = 1 + offset, math.min(#units, offset + visible) do
            local u = units[i]
            local ry = cy + s(4) + (i - 1 - offset) * rowH
            local sel = u.id == P.selected
            local hov = Gfx.hover(ix + s(4), ry, lw - s(8), rowH)
            if sel or hov then Gfx.round(ix + s(4), ry, lw - s(8), rowH - s(2), s(6), sel and Theme.panel2 or tocolor(255, 255, 255, 10)) end
            if sel then dxDrawRectangle(ix + s(4), ry + s(8), s(3), rowH - s(18), Theme.accent) end
            Gfx.text(u.callsign, ix + s(14), ry + s(2), lw - s(70), s(22), Theme.text, Gfx.font(11, true))
            Gfx.text(Gfx.fit(table.concat(u.crew, ", "), lw - s(28), Gfx.font(8)), ix + s(14), ry + s(22), lw - s(28), s(18), Theme.dim, Gfx.font(8))
            if #u.fines > 0 then
                local label = tostring(#u.fines)
                Gfx.round(ix + lw - s(40), ry + s(6), s(28), s(18), s(9), Gfx.rgb({ 200, 50, 45 }))
                Gfx.text(label, ix + lw - s(40), ry + s(6), s(28), s(18), Theme.text, Gfx.font(8, true), "center")
            end
            Gfx.hit(ix + s(4), ry, lw - s(8), rowH, function() P.selected = u.id end)
        end
    end

    -- selected unit -----------------------------------------------------------
    Gfx.round(rx, cy, rw, bodyH, s(8), Theme.panel)
    local u = selectedUnit()
    if not u then
        Gfx.text(L("med_erm.supervisor.select_unit"), rx, cy, rw, bodyH, Theme.faint, Gfx.font(10), "center")
        return
    end

    local px = rx + s(12)
    local pw = rw - s(24)
    Gfx.text(u.callsign .. "  ·  " .. u.type .. "  ·  " .. u.plate, px, cy + s(8), pw, s(22), Theme.text, Gfx.font(11, true))
    Gfx.label(L("med_erm.supervisor.issue"), px, cy + s(32), pw)

    -- fine buttons: two columns
    local gap = s(6)
    local bw = (pw - gap) / 2
    local bh = s(30)
    local by = cy + s(52)
    for i, f in ipairs(Config.FINES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local bx, byy = px + col * (bw + gap), by + row * (bh + gap)
        Gfx.button(bx, byy, bw, bh, "", { color = { 48, 56, 66 } }, function()
            Tablet.confirm = {
                title = L("med_erm.supervisor.confirm_title", { callsign = u.callsign }),
                text = L("med_erm.supervisor.confirm_text", { reason = L(f.label), amount = f.amount }),
                label = L("med_erm.supervisor.confirm_button"),
                action = function()
                    triggerServerEvent("erm:supFine", resourceRoot, u.id, f.id)
                    P.lastRequest = getTickCount()
                end,
            }
        end)
        Gfx.text(Gfx.fit(L(f.label), bw - s(70), Gfx.font(8)), bx + s(8), byy, bw - s(70), bh, Theme.text, Gfx.font(8))
        Gfx.text(f.amount .. " €", bx, byy, bw - s(8), bh, Gfx.rgb({ 240, 120, 100 }), Gfx.font(9, true), "right")
    end

    -- history -----------------------------------------------------------------
    local hy = by + 4 * (bh + gap) + s(4)
    Gfx.label(L("med_erm.supervisor.history", { count = #u.fines, total = u.total }), px, hy, pw)
    hy = hy + s(20)
    local listH = cy + bodyH - hy - s(8)
    if #u.fines == 0 then
        Gfx.text(L("med_erm.supervisor.no_fines"), px, hy, pw, math.max(s(20), listH), Theme.faint, Gfx.font(9), "center")
        return
    end
    local rowH = s(22)
    local visible = math.max(1, math.floor(listH / rowH))
    local offset = Gfx.getScroll("sup_fines", #u.fines - visible)
    Gfx.scrollArea("sup_fines", px, hy, pw, listH)
    for i = 1 + offset, math.min(#u.fines, offset + visible) do
        local f = u.fines[#u.fines - i + 1]   -- newest first
        local ry = hy + (i - 1 - offset) * rowH
        local def = Config.FINE_BY_ID[f.id]
        if (i - offset) % 2 == 0 then Gfx.rect(px, ry, pw, rowH, tocolor(255, 255, 255, 6)) end
        Gfx.text(State.formatClock(f.at), px + s(4), ry, s(44), rowH, Theme.dim, Gfx.font(8, true))
        Gfx.text(Gfx.fit(def and L(def.label) or f.id, pw - s(190), Gfx.font(8)), px + s(52), ry, pw - s(190), rowH, Theme.text, Gfx.font(8))
        Gfx.text(f.by, px, ry, pw - s(66), rowH, Theme.dim, Gfx.font(8), "right")
        Gfx.text(f.amount .. " €", px, ry, pw - s(4), rowH, Gfx.rgb({ 240, 120, 100 }), Gfx.font(8, true), "right")
    end
end

-- opened from the menu: fresh data at once
local setPage = Tablet.setPage
function Tablet.setPage(page)
    setPage(page)
    if page == "supervisor" then P.lastRequest = 0 end
end
