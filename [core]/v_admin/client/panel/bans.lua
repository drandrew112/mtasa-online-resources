if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/bans.lua
--  Bans & mutes page: the `bans` table (active or every ban, searchable)
--  on the left; the online players who are muted or in admin jail on
--  the right (from the player list the panel already has).
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { data = nil, active = true, page = 0, search = "", searchAt = 0, sel = nil }

local function load()
    AP.call("bans", "list", { search = st.search, active = st.active, page = st.page }, function(r)
        if r then st.data = r end
    end, true)
end

local function fmtLeft(sec)
    sec = math.max(0, math.floor(sec or 0))
    local m = math.floor(sec / 60)
    if m >= 60 then return ("%dh %02dm"):format(math.floor(m / 60), m % 60) end
    return ("%dm"):format(m)
end

AP.addPage({
    id = "bans", category = "players", perm = "panel", order = 50,
    label = function() return L("v_admin.page.bans") end,
    onShow = load,
    draw = function(x, y, w, h)
        local lw = w * 0.64
        -- search + mode
        AP.field("bn_search", x, y, S(340), S(40), { placeholder = L("v_admin.bans.search"), max = 64,
            onEnter = function(t) st.search, st.page = AP.trim(t), 0; load() end })
        local text = AP.trim(AP.fieldText("bn_search"))
        if text ~= st.search then
            if st.searchAt == 0 then st.searchAt = getTickCount() end
            if getTickCount() - st.searchAt > 450 then st.search, st.searchAt, st.page = text, 0, 0; load() end
        else
            st.searchAt = 0
        end
        AP.button(x + S(350), y, S(150), S(40), L("v_admin.bans.active_only"), function() st.active, st.page = true, 0; load() end,
            st.active and "active" or nil)
        AP.button(x + S(508), y, S(150), S(40), L("v_admin.bans.all"), function() st.active, st.page = false, 0; load() end,
            not st.active and "active" or nil)

        local d = st.data
        local bh = S(52)
        AP.table("bn_list", x, y + S(52), lw, h - S(52) - bh, {
            { key = "at", label = L("v_admin.accounts.col_date"), w = S(150), text = function(b) return AP.fmtDate(b.at) end },
            { key = "account", label = L("v_admin.accounts.col_account"), w = S(170), bold = true },
            { key = "reason", label = L("v_admin.players.reason") },
            { key = "admin", label = L("v_admin.accounts.col_admin"), w = S(130) },
            { key = "lifted", label = L("v_admin.accounts.col_status"), w = S(150),
              text = function(b) return b.lifted > 0 and L("v_admin.accounts.lifted_by", { admin = b.liftedBy or "?" }) or L("v_admin.accounts.active") end,
              color = function(b) return b.lifted > 0 and C.dim or C.bad end },
        }, d and d.rows or {}, { rowH = S(36), selected = function(b) return st.sel == b.id end,
            onClick = function(b) st.sel = b.id end, empty = d and L("v_admin.page.no_rows") or L("common.loading") })

        local sel
        for _, b in ipairs(d and d.rows or {}) do if b.id == st.sel then sel = b end end
        local by = y + h - bh + S(10)
        if d then
            AP.button(x, by, S(44), S(38), "<", function() st.page = st.page - 1; load() end, st.page > 0 and nil or "off")
            AP.text(tostring(st.page + 1), x + S(50), by, S(40), S(38), C.dim, 0.9, "default", "center")
            AP.button(x + S(96), by, S(44), S(38), ">", function() st.page = st.page + 1; load() end, d.more and nil or "off")
        end
        if sel then
            AP.text(L("v_admin.bans.serial_ip", { serial = sel.serial or "-", ip = sel.ip or "-" }), x + S(160), by, lw - S(560), S(38),
                C.dim, 0.75, "default", "left", "center", true)
            if sel.account then
                AP.button(x + lw - S(390), by, S(180), S(38), L("v_admin.page.open_account"), function() AP.setPage("accounts", sel.account) end,
                    AP.can("accounts") and nil or "off")
            end
            if sel.lifted == 0 and sel.account then
                AP.button(x + lw - S(200), by, S(200), S(38), L("v_admin.players.unban_account"), function()
                    AP.call("bans", "unban", { name = sel.account }, function() load() end)
                end, AP.can("ban") and "active" or "off")
            end
        end

        -- muted / jailed online players
        local rx, rw = x + lw + S(24), w - lw - S(24)
        local rows = {}
        for _, p in ipairs(AP.players) do
            if p.muted then rows[#rows + 1] = { p = p, kind = L("v_admin.accounts.muted"), left = fmtLeft(p.muteLeft), reason = p.muteReason, admin = p.muteAdmin } end
            if p.jailed then rows[#rows + 1] = { p = p, kind = L("v_admin.accounts.jailed"), left = p.jailLeft .. "m", reason = p.jailReason, admin = p.jailAdmin } end
        end
        AP.text(L("v_admin.bans.online_sanctions"):upper(), rx, y, rw, S(40), C.head, 0.8, "default-bold")
        AP.table("bn_online", rx, y + S(52), rw, h - S(52), {
            { key = "name", label = L("common.name"), bold = true, text = function(r) return r.p.name .. " (" .. r.p.id .. ")" end },
            { key = "kind", label = L("v_admin.bans.kind"), w = S(90), color = function() return C.warn end },
            { key = "left", label = L("v_admin.bans.left"), w = S(90) },
            { key = "reason", label = L("v_admin.players.reason"), text = function(r) return (r.reason or "?") .. "  (" .. (r.admin or "?") .. ")" end },
        }, rows, { rowH = S(36), onClick = function() AP.setPage("players") end })
    end,
})
