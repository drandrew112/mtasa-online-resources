if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/accounts.lua
--  Accounts page: every account, filtered / sorted / paged by the server
--  (server/pages/accounts.lua), and the chosen account on the right with
--  its tabs (Overview, Stats, Vehicles, Mails, Punishments, Achievements,
--  Inventory, Social, Notes) and actions.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

--- "online · #2 · ID 5" (long: with the instance name); o = row.onServer { server, serverName, id }
local function onServerText(o, long)
    if long and o.serverName then
        return L("v_admin.accounts.online_server_long", { server = o.server, name = o.serverName, id = o.id })
    end
    return L("v_admin.accounts.online_server", { server = o.server, id = o.id })
end

--- "12 h 05 min" from seconds
local function fmtDuration(sec)
    local m = math.floor((tonumber(sec) or 0) / 60)
    if m < 60 then return L("v_admin.accounts.duration_m", { m = m }) end
    return L("v_admin.accounts.duration_hm", { h = math.floor(m / 60), m = ("%02d"):format(m % 60) })
end

--- a stat / achievement value by its unit: "s" = time, otherwise rounded (1 decimal below 100)
local function fmtValue(v, unit)
    v = tonumber(v) or 0
    if unit == "s" then return fmtDuration(v) end
    local t
    if v ~= math.floor(v) and math.abs(v) < 100 then
        t = (("%.1f"):format(v):gsub("%.0$", ""))
    else
        t = AP.fmtInt(math.floor(v + 0.5))
    end
    return (unit and unit ~= "") and (t .. " " .. unit) or t
end

local st = {
    args     = { admin = "any", status = "any", registered = "any", email = "any", updates = "any",
                 conds = {}, sort = "name", dir = "asc", page = 0 },
    data     = nil,      -- last list result
    loading  = false,
    sel      = nil,      -- account name
    detail   = nil,
    tab      = "overview",
    tabData  = {},       -- [tab] = result
    tabSel   = {},       -- [tab] = selected row key
    form     = nil,      -- { what, label, numeric, value, extra }
    search   = "",
    searchAt = 0,
    mail     = nil,      -- opened mail text
    filters  = {},       -- saved filters { { name, filter } }
}

local function reqList(refresh)
    st.loading = true
    local args = {}
    for k, v in pairs(st.args) do args[k] = v end
    args.search = st.search
    args.refresh = refresh == true
    AP.call("accounts", "list", args, function(r)
        st.loading = false
        if r then st.data = r end
    end)
end

-- the current filter as it is saved / applied
local function currentFilter()
    local f = {}
    for k, v in pairs(st.args) do
        if k ~= "page" and k ~= "conds" then f[k] = v end
    end
    f.conds = {}
    for i, c in ipairs(st.args.conds) do f.conds[i] = { key = c.key, op = c.op, value = c.value } end
    f.search = st.search
    return f
end

local function saveFilter()
    local name = AP.trim(AP.fieldText("acc_filtername"))
    if name == "" then
        AP.setFocus("acc_filtername")
        return AP.notify(L("v_admin.accounts.filter_name_missing"))
    end
    AP.call("accounts", "savefilter", { name = name, filter = currentFilter() }, function(r)
        if type(r) == "table" then
            st.filters = r.list or {}
            AP.setField("acc_filtername", "")
        end
    end)
end

local function applySaved(sf)
    local f = sf.filter or {}
    st.args = { admin = f.admin or "any", status = f.status or "any", registered = f.registered or "any",
                email = f.email or "any", updates = f.updates or "any", conds = {}, sort = f.sort or "name",
                dir = f.dir or "asc", page = 0 }
    for i, c in ipairs(type(f.conds) == "table" and f.conds or {}) do
        st.args.conds[i] = { key = c.key, op = c.op or ">=", value = tostring(c.value or "") }
        AP.setField("acc_cond" .. i, st.args.conds[i].value)
    end
    st.search = f.search or ""
    AP.setField("acc_search", st.search)
    reqList()
end

local function loadTab(tab)
    if tab == "overview" or tab == "notes" or not st.sel then return end
    st.tabData[tab] = nil
    local name = st.sel
    AP.call("accounts", "tab", { name = name, tab = tab }, function(r)
        if r and st.sel == name then st.tabData[tab] = r end
    end, true)
end

local function loadDetail()
    if not st.sel then return end
    local name = st.sel
    AP.call("accounts", "detail", { name = name }, function(r)
        if st.sel ~= name then return end
        st.detail = r or false
    end)
    loadTab(st.tab)
end

local function selectAccount(name)
    if st.sel == name then return end
    st.sel, st.detail, st.tabData, st.tabSel, st.form, st.mail = name, nil, {}, {}, nil, nil
    loadDetail()
end

local function edit(what, extra)
    local args = { name = st.sel, what = what }
    for k, v in pairs(extra or {}) do args[k] = v end
    AP.call("accounts", "edit", args, function(ok)
        if ok then
            loadDetail()
            reqList(true)
        end
    end)
end

--------------------------------------------------------------------------------
-- filters
--------------------------------------------------------------------------------

local FILTERS = {
    { key = "admin", label = function() return L("v_admin.accounts.f_admin") end, values = function()
        local t = { { "any", L("v_admin.accounts.any") }, { "admins", L("v_admin.accounts.admins_only") } }
        for lvl = 0, ADMIN.maxLevel do t[#t + 1] = { tostring(lvl), lvl .. "  " .. AP.rankName(lvl) } end
        return t
    end },
    { key = "status", label = function() return L("v_admin.accounts.f_status") end, values = function()
        return { { "any", L("v_admin.accounts.any") }, { "online", L("v_admin.accounts.online") },
                 { "offline", L("v_admin.accounts.offline") }, { "banned", L("v_admin.accounts.banned") },
                 { "muted", L("v_admin.accounts.muted") }, { "jailed", L("v_admin.accounts.jailed") } }
    end },
    { key = "registered", label = function() return L("v_admin.accounts.f_registered") end, values = function()
        return { { "any", L("v_admin.accounts.any") }, { "1", L("v_admin.accounts.last_days", { n = 1 }) },
                 { "7", L("v_admin.accounts.last_days", { n = 7 }) }, { "30", L("v_admin.accounts.last_days", { n = 30 }) },
                 { "365", L("v_admin.accounts.last_days", { n = 365 }) } }
    end },
    { key = "email", label = function() return L("v_admin.accounts.f_email") end, values = function()
        return { { "any", L("v_admin.accounts.any") }, { "yes", L("v_admin.accounts.has_email") }, { "no", L("v_admin.accounts.no_email") } }
    end },
    { key = "updates", label = function() return L("v_admin.accounts.f_updates") end, values = function()
        return { { "any", L("v_admin.accounts.any") }, { "yes", L("v_admin.accounts.subscribed") }, { "no", L("v_admin.accounts.unsubscribed") } }
    end },
}

local COND_KEYS = {
    { "money", function() return L("v_admin.accounts.c_cash") end },
    { "bank", function() return L("v_admin.accounts.c_bank") end },
    { "level", function() return L("v_admin.accounts.c_level") end },
    { "xp", function() return L("v_admin.accounts.c_xp") end },
    { "playtime", function() return L("v_admin.accounts.c_playtime") end },
    { "vehicles", function() return L("v_admin.accounts.c_vehicles") end },
    { "adminLevel", function() return L("v_admin.accounts.c_admin") end },
    { "id", function() return L("v_admin.accounts.c_id") end },
}
local OPS = { ">=", "<=", "=" }

local function condLabel(key)
    for _, k in ipairs(COND_KEYS) do if k[1] == key then return k[2]() end end
    return key
end

local function valueLabel(f, v)
    for _, it in ipairs(f.values()) do if it[1] == v then return it[2] end end
    return v
end

local function setArg(key, v)
    st.args[key] = v
    st.args.page = 0
    reqList()
end

local function applyConds()
    for i, c in ipairs(st.args.conds) do
        c.value = AP.trim(AP.fieldText("acc_cond" .. i))
    end
    st.args.page = 0
    reqList()
end

-- left-to-right placement that wraps to a new row when `w` is full
local function newFlow(x, y, w)
    return { x = x, y = y, w = w, cx = x, cy = y, rowH = 0 }
end

local function place(fl, bw, bh)
    if fl.cx + bw > fl.x + fl.w and fl.cx > fl.x then
        fl.cx, fl.cy, fl.rowH = fl.x, fl.cy + fl.rowH + S(8), 0
    end
    local bx, by = fl.cx, fl.cy
    fl.cx, fl.rowH = fl.cx + bw + S(8), math.max(fl.rowH, bh)
    return bx, by
end

--- start the next group of controls on a fresh row
local function breakRow(fl, gap)
    if fl.rowH > 0 then fl.cx, fl.cy, fl.rowH = fl.x, fl.cy + fl.rowH + (gap or S(10)), 0 end
end

local function drawFilters(x, y, w)
    local fl = newFlow(x, y, w)

    -- search + dropdown filters
    local h = S(40)
    local sw = math.min(S(300), w)
    local sx, sy = place(fl, sw, h)
    AP.field("acc_search", sx, sy, sw, h, { placeholder = L("v_admin.accounts.search"), max = 64,
        onEnter = function(t) st.search = AP.trim(t); st.args.page = 0; reqList() end })
    local text = AP.trim(AP.fieldText("acc_search"))
    if text ~= st.search then
        if st.searchAt == 0 then st.searchAt = getTickCount() end
        if getTickCount() - st.searchAt > 450 then
            st.search, st.searchAt, st.args.page = text, 0, 0
            reqList()
        end
    else
        st.searchAt = 0
    end

    for _, f in ipairs(FILTERS) do
        local label = f.label() .. ": " .. valueLabel(f, st.args[f.key])
        local bw = math.min(L.width(label, F(0.95), "default-bold") + S(30), w)
        local bx, by = place(fl, bw, h)
        AP.button(bx, by, bw, h, label, function()
            local items = {}
            for _, it in ipairs(f.values()) do
                items[#items + 1] = { label = it[2], active = st.args[f.key] == it[1], fn = function() setArg(f.key, it[1]) end }
            end
            AP.openDropdown(bx, by + h + S(4), math.max(bw, S(240)), items)
        end, st.args[f.key] ~= "any" and "active" or nil)
    end
    breakRow(fl)

    -- numeric conditions
    local ch = S(36)
    local ax, ay = place(fl, S(150), ch)
    AP.button(ax, ay, S(150), ch, L("v_admin.accounts.add_filter"), function()
        local items = {}
        for _, k in ipairs(COND_KEYS) do
            items[#items + 1] = { label = k[2](), fn = function()
                st.args.conds[#st.args.conds + 1] = { key = k[1], op = ">=", value = "" }
                AP.setField("acc_cond" .. #st.args.conds, "")
                AP.setFocus("acc_cond" .. #st.args.conds)
            end }
        end
        AP.openDropdown(ax, ay + ch + S(4), S(240), items)
    end)
    for i, c in ipairs(st.args.conds) do
        local lw = L.width(condLabel(c.key), F(0.85), "default-bold") + S(16)
        local cw = lw + S(44) + S(110) + S(36)
        local cx, cy = place(fl, cw, ch)
        dxDrawRectangle(cx, cy, cw, ch, C.rowSel)
        AP.text(condLabel(c.key), cx + S(8), cy, lw, ch, C.text, 0.85, "default-bold")
        AP.button(cx + lw, cy + S(3), S(40), S(30), c.op, function()
            local n = 1
            for k, op in ipairs(OPS) do if op == c.op then n = k end end
            c.op = OPS[n % #OPS + 1]
            if c.value ~= "" then applyConds() end
        end)
        AP.field("acc_cond" .. i, cx + lw + S(44), cy + S(3), S(106), S(30), { max = 12, numeric = true, onEnter = applyConds })
        AP.button(cx + cw - S(34), cy + S(3), S(30), S(30), "x", function()
            table.remove(st.args.conds, i)
            for k = i, #st.args.conds do AP.setField("acc_cond" .. k, st.args.conds[k].value) end
            applyConds()
        end, "danger")
    end
    local bx, by = place(fl, S(100), ch)
    AP.button(bx, by, S(100), ch, L("v_admin.accounts.apply"), applyConds, "active")
    bx, by = place(fl, S(100), ch)
    AP.button(bx, by, S(100), ch, L("v_admin.accounts.clear"), function()
        st.args = { admin = "any", status = "any", registered = "any", email = "any", updates = "any",
                    conds = {}, sort = st.args.sort, dir = st.args.dir, page = 0 }
        st.search = ""
        AP.setField("acc_search", "")
        reqList()
    end)
    breakRow(fl, S(8))

    -- saved filters (accData of the admin's own account)
    local nw = math.min(S(190), w)
    bx, by = place(fl, nw, ch)
    AP.field("acc_filtername", bx, by, nw, ch, { placeholder = L("v_admin.accounts.filter_name"), max = 40,
        onEnter = function() saveFilter() end })
    bx, by = place(fl, S(100), ch)
    AP.button(bx, by, S(100), ch, L("v_admin.accounts.save_filter"), saveFilter)
    bx, by = place(fl, S(100), ch)
    AP.button(bx, by, S(100), ch, L("v_admin.accounts.saved_filters", { n = #st.filters }), function()
        local items = {}
        for _, sf in ipairs(st.filters) do
            items[#items + 1] = { label = sf.name, fn = function() applySaved(sf) end }
        end
        for _, sf in ipairs(st.filters) do
            items[#items + 1] = { label = L("v_admin.accounts.delete_filter", { name = sf.name }), fn = function()
                AP.call("accounts", "delfilter", { name = sf.name }, function(r) if type(r) == "table" then st.filters = r.list or {} end end, true)
            end }
        end
        if #items == 0 then items[1] = { label = L("v_admin.accounts.no_saved_filters"), disabled = true, fn = function() end } end
        AP.openDropdown(bx, by + ch + S(4), S(320), items)
    end, #st.filters > 0 and nil or "off")
    return fl.cy + fl.rowH + S(10)
end

--------------------------------------------------------------------------------
-- list
--------------------------------------------------------------------------------

local function statusOf(r)
    if r.banned then return L("v_admin.accounts.banned"), C.bad end
    if r.jailed then return L("v_admin.accounts.jailed"), C.warn end
    if r.muted then return L("v_admin.accounts.muted"), C.warn end
    return L("v_admin.accounts.ok"), C.dim
end

local function drawList(x, y, w, h)
    local ty = drawFilters(x, y, w)
    local d = st.data
    local info = d and L("v_admin.accounts.matches", { n = AP.fmtInt(d.total), all = AP.fmtInt(d.all) }) or L("common.loading")
    if d and d.cachedAt then info = info .. "   ·   " .. L("v_admin.accounts.cached", { ago = AP.ago(d.cachedAt, d.now) }) end
    AP.text(info, x, ty, w - S(330), S(26), C.dim, 0.8)
    AP.button(x + w - S(110), ty - S(2), S(110), S(28), L("v_admin.accounts.reload"), function() reqList(true) end)
    -- CSV of every matching account; in game it goes to the clipboard
    AP.button(x + w - S(310), ty - S(2), S(190), S(28), L("v_admin.accounts.export_csv"), function()
        local args = currentFilter()
        AP.call("accounts", "export", args, function(r)
            if type(r) ~= "table" or not r.csv then return end
            setClipboard(r.csv)
            AP.notify(L("v_admin.accounts.export_copied", { n = r.count, total = r.total }))
        end, true)
    end)
    ty = ty + S(32)

    local cols = {
        { key = "name", label = L("v_admin.accounts.col_account"), w = S(190), sort = true, bold = true,
          text = function(r) return (r.onServer and "● " or "") .. r.name end,
          color = function(r) return r.onServer and C.good or C.text end },
        { key = "display", label = L("v_admin.accounts.col_display"), sort = true, text = function(r) return r.display or "-" end },
        { key = "adminLevel", label = L("v_admin.accounts.col_admin_short"), w = S(64), sort = true, align = "center", bold = true,
          text = function(r) return r.adminLevel > 0 and tostring(r.adminLevel) or "-" end,
          color = function(r) return r.adminLevel > 0 and C.gold or C.off end },
        { key = "lastLogin", label = L("v_admin.accounts.col_last_seen"), w = S(160), sort = true,
          text = function(r) return r.onServer and onServerText(r.onServer) or AP.ago(r.lastLogin, d and d.now) end,
          color = function(r) return r.onServer and C.good or C.dim end },
        { key = "status", label = L("v_admin.accounts.col_status"), w = S(120),
          text = function(r) return (statusOf(r)) end, color = function(r) return select(2, statusOf(r)) end },
    }
    local pagerH = S(44)
    AP.table("acc_list", x, ty, w, h - (ty - y) - pagerH, cols, d and d.rows or {}, {
        rowH = S(40),
        sortKey = st.args.sort, sortDir = st.args.dir,
        onSort = function(key)
            if st.args.sort == key then
                st.args.dir = st.args.dir == "asc" and "desc" or "asc"
            else
                st.args.sort = key
                st.args.dir = (key == "name" or key == "display") and "asc" or "desc"
            end
            st.args.page = 0
            reqList()
        end,
        selected = function(r) return st.sel == r.name end,
        onClick = function(r) selectAccount(r.name) end,
        empty = st.loading and L("common.loading") or L("v_admin.accounts.no_match"),
    })

    -- pager
    local py = y + h - pagerH + S(6)
    if d then
        AP.button(x, py, S(44), S(36), "<", function() st.args.page = d.page - 1; reqList() end, d.page > 0 and nil or "off")
        AP.text(L("v_admin.accounts.page", { page = d.page + 1, pages = d.pages }), x + S(50), py, S(200), S(36), C.dim, 0.9, "default", "center")
        AP.button(x + S(256), py, S(44), S(36), ">", function() st.args.page = d.page + 1; reqList() end, d.page < d.pages - 1 and nil or "off")
    end
end

--------------------------------------------------------------------------------
-- details
--------------------------------------------------------------------------------

local TABS = {
    { id = "overview" }, { id = "stats" }, { id = "vehicles" }, { id = "mails" }, { id = "punishments" },
    { id = "achievements" }, { id = "inventory" }, { id = "social" }, { id = "notes" },
}

local function openForm(what, label, numeric, value, extra)
    st.form = { what = what, label = label, numeric = numeric, extra = extra }
    AP.setField("acc_form", value and tostring(value) or "")
    AP.setFocus("acc_form")
end

local function submitForm()
    local f = st.form
    if not f then return end
    local v = AP.trim(AP.fieldText("acc_form"))
    if v == "" and f.what ~= "email" then return AP.notify(L("v_admin.accounts.enter_value")) end
    local extra = {}
    for k, val in pairs(f.extra or {}) do extra[k] = val end
    if f.what == "ban" then extra.reason = v
    elseif f.what == "note" then extra.text = v
    elseif f.what == "vehgive" then extra.model = v
    else extra.value = v end
    edit(f.what, extra)
    st.form = nil
    AP.setFocus(nil)
end

local function drawForm(x, y, w)
    local f = st.form
    dxDrawRectangle(x, y, w, S(104), C.side)
    AP.text(f.label, x + S(14), y + S(6), w - S(28), S(30), C.head, 0.9, "default-bold")
    AP.field("acc_form", x + S(14), y + S(42), w - S(28) - S(250), S(44), { max = f.what == "note" and ADMIN.accounts.notesMax or 64,
        numeric = f.numeric, onEnter = submitForm })
    AP.button(x + w - S(14) - S(240), y + S(42), S(115), S(44), L("common.confirm"), submitForm, f.what == "ban" and "danger" or "active")
    AP.button(x + w - S(14) - S(120), y + S(42), S(120), S(44), L("common.cancel"), function() st.form = nil; AP.setFocus(nil) end)
    return S(114)
end

local function levelDropdown(d, bx, by)
    local maxGrant = AP.myLevel >= ADMIN.maxLevel and ADMIN.maxLevel or AP.myLevel - 1
    local items = {}
    for lvl = 0, ADMIN.maxLevel do
        items[#items + 1] = {
            label = lvl .. "  " .. AP.rankName(lvl) .. (lvl <= maxGrant and "" or L("v_admin.players.locked")),
            disabled = lvl > maxGrant, active = lvl == d.adminLevel,
            fn = function() if lvl ~= d.adminLevel then edit("setlevel", { value = lvl }) end end,
        }
    end
    AP.openDropdown(bx, by, S(300), items)
end

-- action buttons (wrapping rows); returns the height used
local function drawButtons(x, y, w, list)
    local bh, gap = S(40), S(8)
    local cx, cy = x, y
    for _, b in ipairs(list) do
        if not b.hide then
            local bw = L.width(b.label, F(0.95), "default-bold") + S(28)
            if cx + bw > x + w and cx > x then cx, cy = x, cy + bh + gap end
            local allowed = not b.perm or AP.can(b.perm)
            local bx, by = cx, cy
            AP.button(bx, by, bw, bh, b.label, function() b.fn(bx, by + bh + S(4)) end,
                not allowed and "off" or b.style)
            cx = cx + bw + gap
        end
    end
    return cy + bh - y
end

-- small button inside a tile (smaller text than AP.button)
local function miniButton(x, y, w, h, label, fn)
    local hot = AP.hovered(x, y, w, h)
    dxDrawRectangle(x, y, w, h, hot and C.btnHot or C.btn)
    AP.text(label, x, y, w, h, C.text, 0.75, "default-bold", "center")
    AP.area(x, y, w, h, fn)
end

--- edit buttons on the right side of a tile: list = { { label, fn } }
local function tileButtons(x, y, w, h, list)
    if not AP.can("accountEdit") then return end
    local bh, gap = S(28), S(6)
    local bx = x + w - S(8)
    for i = #list, 1, -1 do
        local b = list[i]
        local bw = L.width(b[1], F(0.75), "default-bold") + S(16)
        bx = bx - bw
        miniButton(bx, y + (h - bh) / 2, bw, bh, b[1], b[2])
        bx = bx - gap
    end
end

local function drawOverview(d, x, y, w, h)
    local cols, gap = 2, S(10)
    local tw, th = (w - gap) / 2, S(58)
    local played = d.playtimeText or (("%dh %02dm"):format(math.floor(d.playtime / 60), d.playtime % 60))
    local editLabel = L("v_admin.accounts.edit")
    local tiles = {
        { L("v_admin.players.e_mail"), d.email or "-" },
        { L("v_admin.accounts.update_mails"), d.hasEmail and (d.updates and L("v_admin.accounts.subscribed") or L("v_admin.accounts.unsubscribed")) or "-",
          d.updates and C.good or C.dim },
        { L("v_admin.accounts.cash"), "€" .. AP.fmtInt(d.money), C.good, buttons = {
            { editLabel, function() openForm("money", L("v_admin.accounts.edit_cash"), true, d.money) end } } },
        { L("v_admin.accounts.bank"), "€" .. AP.fmtInt(d.bank), C.good, buttons = {
            { editLabel, function() openForm("bank", L("v_admin.accounts.edit_bank"), true, d.bank) end } } },
        { L("v_admin.accounts.level_xp"), d.level .. "  ·  " .. AP.fmtInt(d.xp), buttons = {
            { L("v_admin.accounts.c_level"), function() openForm("level", L("v_admin.accounts.edit_level"), true, d.level) end },
            { L("v_admin.accounts.c_xp"), function() openForm("xp", L("v_admin.accounts.edit_xp"), true, d.xp) end } } },
        { L("common.played_time"), played },
        { L("v_admin.accounts.last_login"), d.onServer and onServerText(d.onServer, true) or AP.fmtDate(d.lastLogin) },
        { L("v_admin.accounts.last_serial"), d.lastSerial or "-" },
        { L("v_admin.accounts.last_ip"), d.lastIp or "-" },
        { L("v_admin.accounts.achievements"), d.achievements and (d.achievements.done .. " / " .. d.achievements.total) or "-" },
        { L("v_admin.accounts.vehicles"), d.vehicles },
    }
    for i, t in ipairs(tiles) do
        local cx = x + ((i - 1) % cols) * (tw + gap)
        local cy = y + math.floor((i - 1) / cols) * (th + gap)
        AP.kv(cx, cy, tw, th, t[1], t[2], t[3])
        if t.buttons then tileButtons(cx, cy, tw, th, t.buttons) end
    end
    local ty = y + math.ceil(#tiles / cols) * (th + gap) + S(6)
    if d.banned then
        dxDrawRectangle(x, ty, w, S(40), C.danger)
        AP.text(L("v_admin.accounts.banned_by", { admin = d.banned.admin or "?", reason = d.banned.reason or "?" }),
            x + S(12), ty, w - S(24), S(40), C.text, 0.85, "default-bold")
        ty = ty + S(48)
    end

    -- work levels
    if #d.works > 0 then
        AP.text(L("v_admin.accounts.work_levels"):upper(), x, ty, w, S(28), C.head, 0.8, "default-bold")
        ty = ty + S(30)
        for _, wk in ipairs(d.works) do
            if ty + S(34) > y + h then break end
            dxDrawRectangle(x, ty, w, S(32), C.row)
            AP.text(wk.name, x + S(12), ty, w * 0.45, S(32), C.text, 0.85, "default-bold")
            AP.text(L("v_admin.accounts.work_level", { level = wk.level, max = wk.maxLevel, xp = AP.fmtInt(wk.xp) }),
                x + w * 0.45, ty, w * 0.4, S(32), C.dim, 0.85)
            if AP.can("accountEdit") then
                AP.button(x + w - S(90), ty + S(2), S(86), S(28), L("v_admin.accounts.set_xp"), function()
                    openForm("workxp", L("v_admin.accounts.set_work_xp", { work = wk.name }), true, wk.xp, { work = wk.id })
                end)
            end
            ty = ty + S(36)
        end
    end
end

local function drawStats(x, y, w, h)
    local r = st.tabData.stats
    AP.table("acc_stats", x, y, w, h, {
        { key = "name", label = L("v_admin.accounts.col_stat") },
        { key = "category", label = L("v_admin.accounts.col_category"), w = S(160) },
        { key = "value", label = L("v_admin.accounts.col_value"), w = S(150), align = "right", text = function(s) return fmtValue(s.value, s.unit) end },
    }, r and r.list or {}, { rowH = S(34), empty = r and L("v_admin.page.no_rows") or L("common.loading") })
end

local function drawVehicles(x, y, w, h)
    local r = st.tabData.vehicles
    local sel = st.tabSel.vehicles
    local bh = S(48)
    AP.table("acc_veh", x, y, w, h - bh, {
        { key = "id", label = "#", w = S(70) },
        { key = "name", label = L("v_admin.accounts.col_model"), bold = true },
        { key = "plate", label = L("v_admin.accounts.col_plate"), w = S(120) },
        { key = "state", label = L("v_admin.accounts.col_status"), w = S(120),
          text = function(v) return v.destroyed and L("v_admin.accounts.destroyed") or (v.spawned and L("v_admin.accounts.spawned") or L("v_admin.accounts.garage")) end,
          color = function(v) return v.destroyed and C.bad or (v.spawned and C.good or C.dim) end },
    }, r and r.list or {}, { rowH = S(36), selected = function(v) return sel == v.id end,
        onClick = function(v) st.tabSel.vehicles = v.id end, empty = r and L("v_admin.page.no_rows") or L("common.loading") })
    local selected
    for _, v in ipairs(r and r.list or {}) do if v.id == sel then selected = v end end
    drawButtons(x, y + h - bh + S(8), w, {
        { label = L("v_admin.accounts.give_vehicle"), perm = "vehicles", fn = function()
            openForm("vehgive", L("v_admin.accounts.give_vehicle_model"), false)
        end },
        { label = L("v_admin.accounts.restore"), perm = "vehicles", hide = not (selected and selected.destroyed),
          fn = function() edit("vehrestore", { id = selected.id }); st.tabData.vehicles = nil; setTimer(loadTab, 500, 1, "vehicles") end },
        { label = L("v_admin.accounts.delete_vehicle"), perm = "vehicles", style = "danger", hide = not selected,
          fn = function() edit("vehdelete", { id = selected.id }); st.tabSel.vehicles = nil; setTimer(loadTab, 500, 1, "vehicles") end },
    })
end

local function drawMails(x, y, w, h)
    local r = st.tabData.mails
    local listH = st.mail and h * 0.45 or h
    AP.table("acc_mails", x, y, w, listH, {
        { key = "ts", label = L("v_admin.accounts.col_date"), w = S(150), text = function(m) return AP.fmtDate(m.ts) end },
        { key = "kind", label = L("v_admin.accounts.col_kind"), w = S(120) },
        { key = "subject", label = L("v_admin.accounts.col_subject") },
        { key = "status", label = L("v_admin.accounts.col_status"), w = S(90),
          color = function(m) return m.status == "sent" and C.good or (m.status == "failed" and C.bad or C.warn) end },
    }, r and r.list or {}, { rowH = S(34), selected = function(m) return st.mail and st.mail.id == m.id end,
        onClick = function(m)
            AP.call("accounts", "mail", { id = m.id }, function(t)
                if t then
                    st.mail = t
                    AP.setField("acc_mailview", t.subject .. "\n\n" .. t.body .. (t.error and ("\n\n[" .. t.error .. "]") or ""))
                end
            end)
        end, empty = r and L("v_admin.page.no_rows") or L("common.loading") })
    if st.mail then
        AP.field("acc_mailview", x, y + listH + S(10), w, h - listH - S(10), { multiline = true, readonly = true, max = 100000 })
    end
end

local function sanctionStatus(e, now)
    if e.kind == "kick" then return "-", C.dim end
    if e.lifted > 0 then return L("v_admin.accounts.lifted_by", { admin = e.liftedBy or "?" }), C.dim end
    if e.minutes and e.at + e.minutes * 60 <= now then return L("v_admin.accounts.expired"), C.dim end
    return L("v_admin.accounts.active"), C.bad
end

local function drawPunishments(x, y, w, h)
    local r = st.tabData.punishments
    local now = r and r.now or getRealTime().timestamp
    local half = (h - S(20)) / 2
    AP.text(L("v_admin.accounts.sanctions"):upper(), x, y, w, S(26), C.head, 0.8, "default-bold")
    AP.table("acc_bans", x, y + S(28), w, half - S(28), {
        { key = "at", label = L("v_admin.accounts.col_date"), w = S(140), text = function(e) return AP.fmtDate(e.at) end },
        { key = "kind", label = L("v_admin.accounts.col_kind"), w = S(90), bold = true,
          text = function(e) return L("v_admin.accounts.kind_" .. e.kind) end },
        { key = "reason", label = L("v_admin.players.reason") },
        { key = "minutes", label = L("v_admin.accounts.col_duration"), w = S(90),
          text = function(e)
              if e.kind == "ban" then return L("v_admin.accounts.permanent") end
              return e.minutes and fmtDuration(e.minutes * 60) or "-"
          end },
        { key = "admin", label = L("v_admin.accounts.col_admin"), w = S(110) },
        { key = "lifted", label = L("v_admin.accounts.col_status"), w = S(140),
          text = function(e) return (sanctionStatus(e, now)) end, color = function(e) return select(2, sanctionStatus(e, now)) end },
    }, r and r.sanctions or {}, { rowH = S(34), empty = r and L("v_admin.page.no_rows") or L("common.loading") })
    local ly = y + half + S(20)
    AP.text(L("v_admin.accounts.admin_actions"):upper(), x, ly, w, S(26), C.head, 0.8, "default-bold")
    AP.table("acc_alog", x, ly + S(28), w, y + h - ly - S(28), {
        { key = "ts", label = L("v_admin.accounts.col_date"), w = S(150), text = function(l) return AP.fmtDate(l.ts) end },
        { key = "admin", label = L("v_admin.accounts.col_admin"), w = S(130) },
        { key = "action", label = L("v_admin.accounts.col_action") },
    }, r and r.actions or {}, { rowH = S(34), empty = r and L("v_admin.page.no_rows") or L("common.loading") })
end

local function drawAchievements(x, y, w, h)
    local r = st.tabData.achievements
    local sel = st.tabSel.achievements
    local bh = S(48)
    AP.table("acc_ach", x, y, w, h - bh, {
        { key = "name", label = L("v_admin.accounts.col_achievement"), bold = true },
        { key = "progress", label = L("v_admin.accounts.col_progress"), w = S(210), align = "right",
          text = function(a)
              if a.unit == "s" then return fmtValue(math.min(a.progress, a.goal), "s") .. " / " .. fmtValue(a.goal, "s") end
              return fmtValue(math.min(a.progress, a.goal)) .. " / " .. fmtValue(a.goal, a.unit)
          end },
        { key = "done", label = L("v_admin.accounts.col_status"), w = S(150),
          text = function(a) return a.done and AP.fmtDate(a.at, false) or "-" end,
          color = function(a) return a.done and C.good or C.off end },
    }, r and r.list or {}, { rowH = S(34), selected = function(a) return sel == a.id end,
        onClick = function(a) st.tabSel.achievements = a.id end, empty = r and L("v_admin.page.no_rows") or L("common.loading") })
    local function reload() setTimer(loadTab, 500, 1, "achievements") end
    drawButtons(x, y + h - bh + S(8), w, {
        { label = L("v_admin.accounts.give"), perm = "achievements", hide = not sel, fn = function() edit("achgive", { id = sel }); reload() end },
        { label = L("v_admin.accounts.reset"), perm = "achievements", hide = not sel, fn = function() edit("achreset", { id = sel }); reload() end },
        { label = L("v_admin.accounts.reset_all"), perm = "achievements", style = "danger", fn = function() edit("achreset", {}); reload() end },
    })
end

local function drawInventory(x, y, w, h)
    local r = st.tabData.inventory
    if r and not r.online then
        return AP.text(L("v_admin.accounts.inventory_offline"), x, y, w, S(40), C.dim, 0.95)
    end
    AP.table("acc_inv", x, y, w, h, {
        { key = "name", label = L("v_admin.accounts.col_item"), text = function(i) return ("    "):rep(i.depth) .. i.name end },
        { key = "slot", label = L("v_admin.accounts.col_slot"), w = S(120) },
        { key = "amount", label = L("v_admin.accounts.col_amount"), w = S(100), align = "right" },
    }, r and r.list or {}, { rowH = S(34), empty = r and L("v_admin.page.no_rows") or L("common.loading") })
end

local function drawSocial(x, y, w, h)
    local r = st.tabData.social
    if not r then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 0.95) end
    local c = r.crewInfo or r.crew
    local crew = "-"
    if type(c) == "table" then
        crew = c.name .. (c.tag and (" [" .. c.tag .. "]") or "")
        if c.members then crew = crew .. "  ·  " .. L("v_admin.accounts.crew_info", { n = c.members, founder = c.founder or "?" }) end
    elseif type(c) == "string" then
        crew = c
    end
    AP.kv(x, y, w, S(58), L("v_admin.accounts.crew"), crew)
    local rows = {}
    for i, n in ipairs(r.friends) do rows[i] = { name = n } end
    AP.table("acc_friends", x, y + S(70), w, h - S(70), {
        { key = "name", label = L("v_admin.accounts.friends", { n = #rows }) },
    }, rows, { rowH = S(34), onClick = function(f) AP.setField("acc_search", f.name); selectAccount(f.name) end })
end

local function drawNotes(d, x, y, w, h)
    local notes = d.notes or {}
    local rows = {}
    for i, n in ipairs(notes) do rows[i] = { i = i, t = n.t, admin = n.admin, text = n.text } end
    local bh = S(48)
    AP.table("acc_notes", x, y, w, h - bh, {
        { key = "t", label = L("v_admin.accounts.col_date"), w = S(150), text = function(n) return AP.fmtDate(n.t) end },
        { key = "admin", label = L("v_admin.accounts.col_admin"), w = S(120) },
        { key = "text", label = L("v_admin.accounts.col_note") },
    }, rows, { rowH = S(34), selected = function(n) return st.tabSel.notes == n.i end,
        onClick = function(n) st.tabSel.notes = n.i; AP.notify(n.text) end })
    drawButtons(x, y + h - bh + S(8), w, {
        { label = L("v_admin.accounts.add_note"), perm = "notes", fn = function() openForm("note", L("v_admin.accounts.add_note"), false) end },
        { label = L("v_admin.accounts.delete_note"), perm = "notes", style = "danger", hide = not st.tabSel.notes,
          fn = function() edit("delnote", { index = st.tabSel.notes }); st.tabSel.notes = nil end },
    })
end

local function tabLabel(id, d)
    local L2 = L("v_admin.accounts.tab_" .. id)
    if id == "vehicles" and d then return L2 .. " " .. d.vehicles end
    if id == "notes" and d and #(d.notes or {}) > 0 then return L2 .. " " .. #d.notes end
    return L2
end

local function drawDetail(x, y, w, h)
    dxDrawRectangle(x, y, w, h, C.top)
    local pad = S(20)
    x, y, w, h = x + pad, y + pad, w - pad * 2, h - pad * 2
    local d = st.detail
    if not st.sel then return AP.text(L("v_admin.accounts.select_account"), x, y, w, S(40), C.dim, 1.0) end
    if d == nil then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 1.0) end
    if d == false then return AP.text(L("v_admin.page.no_such_account"), x, y, w, S(40), C.bad, 1.0) end

    -- header
    local av = S(60)
    dxDrawRectangle(x, y, av, av, C.accent)
    AP.text(d.name:sub(1, 1):upper(), x, y, av, av, C.text, 1.6, "default-bold", "center")
    AP.text(d.name, x + av + S(14), y, w - av - S(14), S(34), C.text, 1.25, "default-bold")
    if d.adminLevel > 0 then
        local nw = L.width(d.name, F(1.25), "default-bold")
        AP.text(AP.rankName(d.adminLevel), x + av + S(26) + nw, y, S(200), S(34), C.gold, 0.85, "default-bold")
    end
    local sub = (d.display or "-") .. "  ·  #" .. d.id .. "  ·  " .. L("v_admin.accounts.registered_at", { date = AP.fmtDate(d.created, false) })
    AP.text(sub, x + av + S(14), y + S(34), w - av - S(14), S(26), C.dim, 0.8)
    if d.onServer then
        AP.text(onServerText(d.onServer, true), x, y + S(34), w, S(26), C.good, 0.8, "default-bold", "right")
    end
    local cy = y + av + S(14)

    -- tabs
    local items = {}
    for _, t in ipairs(TABS) do items[#items + 1] = { id = t.id, label = tabLabel(t.id, d) } end
    cy = cy + AP.tabs(x, cy, w, items, st.tab, function(id)
        st.tab = id
        st.mail = nil
        if not st.tabData[id] then loadTab(id) end
    end)

    -- actions at the bottom (overview: account, mails: e-mail)
    local actionsH = 0
    local buttons
    if st.tab == "overview" then
        buttons = {
            { label = L("v_admin.accounts.set_admin_level"), perm = "setLevel", fn = function(bx, by) levelDropdown(d, bx, by) end },
            { label = L("v_admin.players.unmute"), perm = "mute", hide = not d.muted, fn = function() edit("unmute") end },
            { label = L("v_admin.players.unban_account"), perm = "ban", hide = not d.banned, fn = function() edit("unban") end },
            { label = L("v_admin.players.ban_account"), perm = "ban", style = "danger", hide = d.banned and true or false,
              fn = function() openForm("ban", L("v_admin.accounts.ban_reason"), false) end },
        }
    elseif st.tab == "mails" then
        buttons = {
            { label = L("v_admin.accounts.set_email"), perm = "email",
              fn = function() openForm("email", L("v_admin.accounts.set_email_hint"), false, "") end },
            { label = L("v_admin.accounts.pwreset"), perm = "passwordReset", hide = not d.hasEmail,
              fn = function() edit("pwreset") end },
            { label = L("v_admin.accounts.send_mail"), perm = "mail", hide = not d.hasEmail,
              fn = function() AP.setPage("mail", { recipients = { d.name } }) end },
        }
    end
    if buttons then
        -- measure: draw off the bottom first (rows wrap), then place
        local bw = 0
        local rows = 1
        for _, b in ipairs(buttons) do
            if not b.hide then
                local w2 = L.width(b.label, F(0.95), "default-bold") + S(36)
                if bw + w2 > w and bw > 0 then rows, bw = rows + 1, 0 end
                bw = bw + w2
            end
        end
        actionsH = rows * S(48) + S(10)
    end
    local formH = st.form and S(114) or 0
    local bodyH = y + h - cy - actionsH - formH

    if st.tab == "overview" then drawOverview(d, x, cy, w, bodyH)
    elseif st.tab == "stats" then drawStats(x, cy, w, bodyH)
    elseif st.tab == "vehicles" then drawVehicles(x, cy, w, bodyH)
    elseif st.tab == "mails" then drawMails(x, cy, w, bodyH)
    elseif st.tab == "punishments" then drawPunishments(x, cy, w, bodyH)
    elseif st.tab == "achievements" then drawAchievements(x, cy, w, bodyH)
    elseif st.tab == "inventory" then drawInventory(x, cy, w, bodyH)
    elseif st.tab == "social" then drawSocial(x, cy, w, bodyH)
    elseif st.tab == "notes" then drawNotes(d, x, cy, w, bodyH) end

    if st.form then drawForm(x, y + h - actionsH - formH, w) end
    if buttons then
        dxDrawRectangle(x, y + h - actionsH, w, S(1), C.line)
        drawButtons(x, y + h - actionsH + S(10), w, buttons)
    end
end

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

AP.addPage({
    id = "accounts", category = "players", perm = "accounts", order = 30,
    label = function() return L("v_admin.page.accounts") end,
    onShow = function(name)
        if type(name) == "string" and name ~= "" then
            AP.setField("acc_search", name)
            st.search = name
            st.args.page = 0
            st.sel = nil
            selectAccount(name)
            st.tab = "overview"
        end
        reqList()
        AP.call("accounts", "filters", {}, function(r) if type(r) == "table" then st.filters = r.list or {} end end, true)
    end,
    onClose = function() st.form = nil end,
    draw = function(x, y, w, h)
        local detailW = math.min(S(800), w * 0.5) + S(20) -- the list gives up 20 px
        local gap = S(20)
        drawList(x, y, w - detailW - gap, h)
        drawDetail(x + w - detailW, y, detailW, h)
    end,
})
