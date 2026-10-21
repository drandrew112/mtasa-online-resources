if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/achievements.lua
--  Achievements page: every achievement (v_achievements) and giving one
--  to an account. An account's own list (give / reset) is the
--  Achievements tab of the Accounts page. /ach still works as before.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { list = nil, sel = nil }

AP.addPage({
    id = "achievements", category = "content", perm = "panel", order = 330,
    label = function() return L("v_admin.page.achievements") end,
    onShow = function()
        AP.call("achievements", "list", {}, function(r) if r then st.list = r.list end end, true)
    end,
    draw = function(x, y, w, h)
        local bh = S(60)
        AP.table("ach_list", x, y, w, h - bh, {
            { key = "id", label = "ID", w = S(200), color = function() return C.dim end },
            { key = "name", label = L("v_admin.accounts.col_achievement"), w = S(320), bold = true },
            { key = "desc", label = L("v_admin.ach.description") },
            { key = "category", label = L("v_admin.accounts.col_category"), w = S(160) },
            { key = "goal", label = L("v_admin.ach.goal"), w = S(90), align = "right" },
            { key = "xp", label = "XP", w = S(90), align = "right", color = function() return C.warn end },
        }, st.list or {}, { rowH = S(36), selected = function(a) return st.sel == a.id end, onClick = function(a) st.sel = a.id end,
            empty = st.list and L("v_admin.page.no_rows") or L("common.loading") })

        local by = y + h - bh + S(14)
        AP.text(st.sel and L("v_admin.ach.selected", { id = st.sel }) or L("v_admin.ach.pick"), x, by, S(420), S(44), C.dim, 0.9)
        if not AP.can("achievements") then return end
        AP.field("ach_account", x + w - S(560), by, S(330), S(44), { placeholder = L("v_admin.ach.account"), max = 64 })
        AP.button(x + w - S(220), by, S(220), S(44), L("v_admin.ach.give"), function()
            if not st.sel then return AP.notify(L("v_admin.ach.pick")) end
            AP.call("achievements", "give", { name = AP.trim(AP.fieldText("ach_account")), id = st.sel })
        end, st.sel and "active" or "off")
    end,
})
