if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/resources.lua
--  Resources page, two tabs:
--    Resources - every resource with its state; start / stop / restart
--                through v_main (it holds the ACL rights; protected ones only start)
--    Updates   - the GitHub update check (checkupdates) and the update itself
--                (updateresources) of v_main, with the lines of the last run
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { list = nil, sel = nil, filter = "all", tab = "list", report = nil, which = "check" }

local function load()
    AP.call("resources", "list", {}, function(r) if r then st.list = r.list end end, true)
end

local function loadReport()
    AP.call("resources", "updates", {}, function(r)
        if type(r) ~= "table" then return end
        st.report = r
        -- show the run that happened last
        local c, u = r.check, r.update
        if r.updateRunning or (u and (not c or (u.at or 0) > (c.at or 0))) then st.which = "update" end
        if r.checkRunning then st.which = "check" end
    end, true)
end

local function act(name, action)
    AP.call("resources", "action", { name = name, action = action }, function() setTimer(load, 800, 1) end)
end

local STATE_COLOR = { running = "good", loaded = "dim", ["failed to load"] = "bad", starting = "warn", stopping = "warn" }
local EVENT_COLOR = { outdated = "warn", missing = "bad", error = "bad", complete = "good", notinst = "dim", loose = "dim" }

local function drawList(x, y, w, h)
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
end

local function drawUpdates(x, y, w, h)
    local r = st.report or {}
    local busy = r.checkRunning or r.updateRunning
    AP.button(x, y, S(260), S(44), L("v_admin.res.check_updates"), function()
        AP.call("resources", "checkupdates", {}, function() st.which = "check" loadReport() end)
    end, busy and "off" or "active")
    AP.confirmButton("rs_update", x + S(270), y, S(300), S(44), L("v_admin.res.install_updates"), L("v_admin.page.click_again"),
        function() AP.call("resources", "updateresources", {}, function() st.which = "update" loadReport() end) end,
        busy and "off" or "danger")
    AP.button(x + w - S(120), y, S(120), S(44), L("v_admin.accounts.reload"), loadReport)
    local hint = AP.wrap(L("v_admin.res.update_hint"), w - S(720), 0.8)
    for i, line in ipairs(hint) do
        if i > 2 then break end
        AP.text(line, x + S(590), y + (i - 1) * S(22), w - S(720), S(22), C.dim, 0.8)
    end

    local ty = y + S(56)
    local th = AP.tabs(x, ty, w, {
        { id = "check", label = L("v_admin.res.last_check") .. (r.checkRunning and " ..." or "") },
        { id = "update", label = L("v_admin.res.last_update") .. (r.updateRunning and " ..." or "") },
    }, st.which, function(id) st.which = id end)
    ty = ty + th
    local rep = r[st.which]
    if not rep then
        return AP.text(st.report and L("v_admin.res.no_run_yet") or L("common.loading"), x, ty, w, S(40), C.dim, 0.95)
    end
    AP.text(L("v_admin.res.run_info", { date = AP.fmtDate(rep.at), by = rep.by or "-", n = #(rep.lines or {}) }), x, ty, w, S(28), C.dim, 0.85)
    local rows = {}
    for i, l in ipairs(rep.lines or {}) do
        local t = l.time and getRealTime(l.time)
        rows[i] = { i = i, time = t and ("%02d:%02d"):format(t.hour, t.minute) or "-", event = l.event or "status", text = tostring(l.text or "") }
    end
    AP.table("rs_lines", x, ty + S(34), w, y + h - ty - S(34), {
        { key = "time", label = L("v_admin.res.time"), w = S(90) },
        { key = "event", label = L("v_admin.res.event"), w = S(130), color = function(l) return C[EVENT_COLOR[l.event] or "text"] end },
        { key = "text", label = L("v_admin.res.line") },
    }, rows, { rowH = S(30), onClick = function(l) setClipboard(l.text) AP.notify(L("v_admin.players.copied_to_clipboard", { label = l.event })) end })
end

AP.addPage({
    id = "resources", category = "server", perm = "resources", order = 110,
    label = function() return L("v_admin.page.resources") end,
    onShow = function() load() loadReport() end,
    -- a running check / update fills its lines while the page is open
    onRefresh = function()
        if st.tab == "updates" and st.report and (st.report.checkRunning or st.report.updateRunning) then loadReport() end
    end,
    draw = function(x, y, w, h)
        local th = AP.tabs(x, y, w, {
            { id = "list", label = L("v_admin.page.resources") },
            { id = "updates", label = L("v_admin.res.updates") },
        }, st.tab, function(id) st.tab = id if id == "updates" then loadReport() end end)
        if st.tab == "list" then drawList(x, y + th, w, h - th) else drawUpdates(x, y + th, w, h - th) end
    end,
})
