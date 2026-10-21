if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/dashboard.lua
--  Dashboard page: players / reports / bans / accounts counters, the
--  running week, admins online, resources that failed to load and the
--  latest admin actions (server/pages/misc.lua "dashboard").
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { data = nil }

local function load()
    AP.call("dashboard", "summary", {}, function(r) if r then st.data = r end end, true)
end

local function tile(x, y, w, h, label, value, color, onClick)
    dxDrawRectangle(x, y, w, h, onClick and AP.hovered(x, y, w, h) and C.rowHot or C.side)
    AP.text(label:upper(), x + S(18), y + S(12), w - S(36), S(24), C.off, 0.75, "default-bold", "left", "top")
    AP.text(tostring(value), x + S(18), y + S(36), w - S(36), h - S(48), color or C.text, 1.9, "default-bold")
    if onClick then AP.area(x, y, w, h, onClick) end
end

AP.addPage({
    id = "dashboard", category = "overview", perm = "panel", order = 10,
    label = function() return L("v_admin.page.dashboard") end,
    onShow = load,
    onRefresh = load,
    draw = function(x, y, w, h)
        local d = st.data
        if not d then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 1.0) end

        -- counters
        local gap = S(16)
        local tw, th = (w - gap * 4) / 5, S(120)
        tile(x, y, tw, th, L("v_admin.dash.online"), d.online .. " / " .. d.maxPlayers, C.good, function() AP.setPage("players") end)
        tile(x + (tw + gap), y, tw, th, L("v_admin.dash.reports"), d.reportsWaiting .. " / " .. d.reports,
            d.reportsWaiting > 0 and C.bad or C.text, function() AP.setPage("reports") end)
        tile(x + (tw + gap) * 2, y, tw, th, L("v_admin.dash.active_bans"), AP.fmtInt(d.activeBans), nil, function() AP.setPage("bans") end)
        tile(x + (tw + gap) * 3, y, tw, th, L("v_admin.dash.accounts"), d.accounts and AP.fmtInt(d.accounts) or "-", nil,
            AP.can("accounts") and function() AP.setPage("accounts") end or nil)
        tile(x + (tw + gap) * 4, y, tw, th, L("v_admin.dash.muted_jailed"), d.muted .. " / " .. d.jailed, (d.muted + d.jailed) > 0 and C.warn or nil)

        local cy = y + th + gap
        local colW = (w - gap * 2) / 3
        local ch = h - th - gap

        -- week + server
        local ix, iy, iw = AP.card(x, cy, colW, ch, L("v_admin.dash.this_week"))
        local wk = d.week
        if wk then
            AP.text(wk.from .. "  –  " .. wk.to, ix, iy, iw, S(28), C.dim, 0.85)
            iy = iy + S(36)
            AP.text(L("v_admin.dash.time_trial"), ix, iy, iw, S(26), C.off, 0.8, "default-bold")
            AP.text(wk.timetrial or "-", ix, iy + S(26), iw, S(28), C.text, 0.95)
            iy = iy + S(64)
            AP.text(L("v_admin.dash.login_bonus"), ix, iy, iw, S(26), C.off, 0.8, "default-bold")
            local b = wk.loginBonus
            AP.text(b and ("€" .. AP.fmtInt(b.money) .. "  +  " .. AP.fmtInt(b.xp) .. " XP") or "-", ix, iy + S(26), iw, S(28), C.good, 0.95)
            iy = iy + S(64)
            AP.text(L("v_admin.dash.job_bonus"), ix, iy, iw, S(26), C.off, 0.8, "default-bold")
            iy = iy + S(28)
            if #wk.jobs == 0 then AP.text("-", ix, iy, iw, S(28), C.dim, 0.9) end
            for _, j in ipairs(wk.jobs) do
                if iy + S(28) > cy + ch - S(70) then break end
                AP.text(j, ix, iy, iw, S(28), C.text, 0.9)
                iy = iy + S(28)
            end
        else
            AP.text("-", ix, iy, iw, S(28), C.dim, 0.9)
        end
        if d.instance then AP.text(L("v_admin.dash.instance", { name = d.instance }), ix, cy + ch - S(44), iw, S(28), C.off, 0.8) end

        -- admins online + failed resources
        local ax = x + colW + gap
        ix, iy, iw = AP.card(ax, cy, colW, ch, L("v_admin.panel.admins_online_2"))
        if #d.admins == 0 then AP.text("-", ix, iy, iw, S(28), C.dim, 0.9) end
        for _, a in ipairs(d.admins) do
            if iy + S(32) > cy + ch * 0.6 then break end
            AP.text(a.name .. "  (" .. tostring(a.id) .. ")", ix, iy, iw * 0.6, S(32), C.text, 0.9)
            AP.text(AP.rankName(a.level), ix + iw * 0.6, iy, iw * 0.4, S(32), C.gold, 0.85, "default-bold", "right")
            iy = iy + S(32)
        end
        local fy = cy + ch * 0.62
        AP.text(L("v_admin.dash.failed_resources"):upper(), ix, fy, iw, S(28), C.head, 0.8, "default-bold")
        fy = fy + S(30)
        if #d.failed == 0 then AP.text(L("v_admin.dash.none"), ix, fy, iw, S(28), C.good, 0.9) end
        for _, n in ipairs(d.failed) do
            if fy + S(28) > cy + ch - S(10) then break end
            AP.text(n, ix, fy, iw, S(28), C.bad, 0.9)
            fy = fy + S(28)
        end

        -- latest admin actions
        local lx = x + (colW + gap) * 2
        ix, iy, iw = AP.card(lx, cy, colW, ch, L("v_admin.dash.latest_actions"))
        AP.table("dash_log", ix, iy, iw, cy + ch - iy - S(16), {
            { key = "ts", label = L("v_admin.accounts.col_date"), w = S(90), text = function(r) return AP.ago(r.ts, d.now) end },
            { key = "admin", label = L("v_admin.accounts.col_admin"), w = S(110) },
            { key = "action", label = L("v_admin.accounts.col_action") },
        }, d.log or {}, { rowH = S(34), onClick = AP.can("adminLog") and function() AP.setPage("adminlog") end or nil })
    end,
})
