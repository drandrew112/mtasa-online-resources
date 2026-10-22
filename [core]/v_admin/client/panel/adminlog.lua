if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/adminlog.lua
--  Admin log page: every admin action from game and web (`admin_log`),
--  filtered by admin / target account / text.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { data = nil, page = 0, key = "", changedAt = 0 }

local function filterKey()
    return AP.trim(AP.fieldText("al_admin")) .. "\0" .. AP.trim(AP.fieldText("al_target")) .. "\0" .. AP.trim(AP.fieldText("al_text"))
end

local function load()
    st.key = filterKey()
    AP.call("adminlog", "list", { page = st.page, admin = AP.fieldText("al_admin"), target = AP.fieldText("al_target"),
        text = AP.fieldText("al_text") }, function(r) if r then st.data = r end end, true)
end

AP.addPage({
    id = "adminlog", category = "server", perm = "adminLog", order = 120,
    label = function() return L("v_admin.page.admin_log") end,
    onShow = function() st.page = 0; load() end,
    draw = function(x, y, w, h)
        local fw = S(260)
        local function reload() st.page = 0; load() end
        AP.field("al_admin", x, y, fw, S(40), { placeholder = L("v_admin.log.admin"), max = 64, onEnter = reload })
        AP.field("al_target", x + fw + S(10), y, fw, S(40), { placeholder = L("v_admin.log.target"), max = 64, onEnter = reload })
        AP.field("al_text", x + (fw + S(10)) * 2, y, fw * 1.4, S(40), { placeholder = L("v_admin.log.text"), max = 64, onEnter = reload })
        if filterKey() ~= st.key then
            if st.changedAt == 0 then st.changedAt = getTickCount() end
            if getTickCount() - st.changedAt > 450 then st.changedAt = 0; reload() end
        else
            st.changedAt = 0
        end
        AP.button(x + w - S(120), y, S(120), S(40), L("v_admin.accounts.reload"), load)

        local d = st.data
        local bh = S(52)
        AP.table("al_list", x, y + S(52), w, h - S(52) - bh, {
            { key = "ts", label = L("v_admin.accounts.col_date"), w = S(170), text = function(r) return AP.fmtDate(r.ts) end },
            { key = "server", label = L("v_admin.log.server"), w = S(80), align = "center",
              text = function(r) return r.server > 0 and ("#" .. r.server) or "-" end,
              color = function(r) return d and r.server ~= d.server and C.gold or C.dim end },
            { key = "admin", label = L("v_admin.accounts.col_admin"), w = S(170), bold = true },
            { key = "level", label = L("v_admin.log.level"), w = S(70), align = "right" },
            { key = "source", label = L("v_admin.log.source"), w = S(80), color = function(r) return r.source == "web" and C.head or C.dim end },
            { key = "action", label = L("v_admin.accounts.col_action") },
            { key = "target", label = L("v_admin.log.target"), w = S(170), color = function() return C.gold end },
        }, d and d.rows or {}, { rowH = S(36), empty = d and L("v_admin.page.no_rows") or L("common.loading"),
            onClick = function(r) if r.target and AP.can("accounts") then AP.setPage("accounts", r.target) end end })
        if d then
            local by = y + h - bh + S(10)
            AP.button(x, by, S(44), S(38), "<", function() st.page = st.page - 1; load() end, st.page > 0 and nil or "off")
            AP.text(tostring(st.page + 1), x + S(50), by, S(40), S(38), C.dim, 0.9, "default", "center")
            AP.button(x + S(96), by, S(44), S(38), ">", function() st.page = st.page + 1; load() end, d.more and nil or "off")
        end
    end,
})
