if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/resources.lua
--  Resources page: every resource with its state; start / stop / restart
--  through v_main (it holds the ACL rights; protected ones only start).
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { list = nil, sel = nil, filter = "all" }

local function load()
    AP.call("resources", "list", {}, function(r) if r then st.list = r.list end end, true)
end

local function act(name, action)
    AP.call("resources", "action", { name = name, action = action }, function() setTimer(load, 800, 1) end)
end

local STATE_COLOR = { running = "good", loaded = "dim", ["failed to load"] = "bad", starting = "warn", stopping = "warn" }

AP.addPage({
    id = "resources", category = "server", perm = "resources", order = 110,
    label = function() return L("v_admin.page.resources") end,
    onShow = load,
    draw = function(x, y, w, h)
        AP.field("rs_search", x, y, S(320), S(40), { placeholder = L("v_admin.res.search"), max = 64 })
        local modes = { { "all", L("v_admin.res.all") }, { "running", L("v_admin.res.running") },
                        { "stopped", L("v_admin.res.stopped") }, { "failed", L("v_admin.res.failed") } }
        local bx = x + S(330)
        for _, m in ipairs(modes) do
            AP.button(bx, y, S(130), S(40), m[2], function() st.filter = m[1] end, st.filter == m[1] and "active" or nil)
            bx = bx + S(138)
        end
        AP.button(x + w - S(120), y, S(120), S(40), L("v_admin.accounts.reload"), load)

        local needle = AP.trim(AP.fieldText("rs_search")):lower()
        local rows = {}
        for _, r in ipairs(st.list or {}) do
            local keep = needle == "" or r.name:lower():find(needle, 1, true) or r.group:lower():find(needle, 1, true)
            if keep and st.filter == "running" then keep = r.state == "running"
            elseif keep and st.filter == "stopped" then keep = r.state == "loaded"
            elseif keep and st.filter == "failed" then keep = r.state == "failed to load" end
            if keep then rows[#rows + 1] = r end
        end
        local bh = S(52)
        AP.table("rs_list", x, y + S(52), w, h - S(52) - bh, {
            { key = "name", label = L("v_admin.res.name"), bold = true,
              text = function(r) return r.name .. (r.protected and ("  [" .. L("v_admin.res.protected") .. "]") or "") end },
            { key = "group", label = L("v_admin.res.group"), w = S(240) },
            { key = "state", label = L("v_admin.accounts.col_status"), w = S(180),
              color = function(r) return C[STATE_COLOR[r.state] or "dim"] end },
        }, rows, { rowH = S(34), selected = function(r) return st.sel == r.name end, onClick = function(r) st.sel = r.name end,
            empty = st.list and L("v_admin.page.no_rows") or L("common.loading"),
            footer = L("v_admin.res.count", { n = #rows, all = st.list and #st.list or 0 }) })

        local sel
        for _, r in ipairs(st.list or {}) do if r.name == st.sel then sel = r end end
        if not sel then return end
        local by = y + h - bh + S(10)
        AP.text(sel.name, x, by, w - S(620), S(38), C.text, 1.0, "default-bold")
        if sel.state ~= "running" then
            AP.button(x + w - S(200), by, S(200), S(38), L("v_admin.res.start"), function() act(sel.name, "start") end, "active")
        elseif not sel.protected then
            AP.button(x + w - S(410), by, S(200), S(38), L("v_admin.res.restart"), function() act(sel.name, "restart") end, "active")
            AP.confirmButton("rs_stop", x + w - S(200), by, S(200), S(38), L("v_admin.res.stop"), L("v_admin.page.click_again"),
                function() act(sel.name, "stop") end)
        end
    end,
})
