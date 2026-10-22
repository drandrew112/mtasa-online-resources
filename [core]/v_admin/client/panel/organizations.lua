if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/organizations.lua
--  Organizations page (biz_core): search + list on the left, the chosen
--  organization on the right (overview tiles, then Ledger / Properties /
--  Associates / Actions tabs). Data and edits: server/pages/organizations.lua.
--  The account page's Organization tile opens this page with the company id.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { rows = nil, status = "active", selected = nil, detail = nil, tab = "ledger", catalog = nil, dirty = false, giveIdx = 1 }

local function money(n)
    n = tonumber(n) or 0
    return (n < 0 and "-€" or "€") .. AP.fmtInt(math.abs(n))
end

local function loadList()
    AP.call("organizations", "list", { query = AP.trim(AP.fieldText("org_search")), status = st.status }, function(r)
        st.rows = r and r.rows or {}
    end, true)
end

local function loadDetail(id)
    st.selected = id
    st.detail = nil
    AP.call("organizations", "detail", { id = id }, function(r)
        if r and st.selected == id then st.detail = r end
    end)
end

local function edit(action, args)
    args = args or {}
    args.id = st.selected
    AP.call("organizations", action, args, function(r)
        if r then
            loadDetail(st.selected)
            loadList()
        end
    end)
end

--------------------------------------------------------------------------------
-- right side
--------------------------------------------------------------------------------

local function drawLedger(d, x, y, w, h)
    AP.table("org_ledger", x, y, w, h, {
        { key = "ts", label = L("v_admin.accounts.col_date"), w = S(160), text = function(r) return AP.fmtDate(r.ts, true) end },
        { key = "category", label = L("v_admin.org.col_category"), w = S(160) },
        { key = "description", label = L("v_admin.org.col_description") },
        { key = "amount", label = L("v_admin.org.col_amount"), w = S(140), align = "right", bold = true,
          text = function(r) return (r.amount > 0 and "+" or "") .. money(r.amount) .. (r.dirty and " D" or "") end,
          color = function(r) return r.amount < 0 and C.bad or C.good end },
        { key = "balance", label = L("v_admin.org.col_balance"), w = S(140), align = "right", text = function(r) return money(r.balance) end },
    }, d.ledger or {}, { rowH = S(36) })
end

local function drawUnits(d, x, y, w, h)
    local canEdit = AP.can("organizationsEdit")
    local hq = d.company.hqUnit
    AP.table("org_units", x, y, w, h - (canEdit and S(60) or 0), {
        { key = "name", label = L("v_admin.org.col_property"), bold = true,
          text = function(u) return u.name .. (u.id == hq and L("v_admin.org.hq_suffix") or "") end },
        { key = "kind", label = L("v_admin.org.col_kind"), w = S(110) },
        { key = "pricePaid", label = L("v_admin.org.col_paid"), w = S(150), align = "right",
          text = function(u) return money(u.pricePaid + (u.upgradesPaid or 0)) end },
        { key = "stockValue", label = L("v_admin.org.col_stock"), w = S(130), align = "right",
          text = function(u) return u.stockValue and money(u.stockValue) or "-" end },
        { key = "dimension", label = "DIM", w = S(90), align = "right" },
    }, d.units or {}, {
        rowH = S(38),
        selected = function(u) return st.unitSel == u.id end,
        onClick = function(u) st.unitSel = u.id end,
    })
    if not canEdit then return end
    local by = y + h - S(48)
    local bw = math.min(S(260), (w - S(10)) / 2)
    local sel
    for _, u in ipairs(d.units or {}) do if u.id == st.unitSel then sel = u end end
    if sel and sel.id ~= hq then
        AP.confirmButton("org_rm_unit", x, by, bw, S(44), L("v_admin.org.remove_unit", { name = sel.name }), L("v_admin.page.click_again"),
            function() edit("removeunit", { unitId = sel.id }) end)
    end
    -- give a property
    local list = st.catalog or {}
    if #list > 0 then
        st.giveIdx = math.max(1, math.min(st.giveIdx, #list))
        local p = list[st.giveIdx]
        AP.button(x + w - bw * 2 - S(10), by, bw, S(44), "< " .. p.name .. " >", function()
            st.giveIdx = st.giveIdx % #list + 1
        end)
        AP.button(x + w - bw, by, bw, S(44), L("v_admin.org.give_unit"), function() edit("giveunit", { propertyId = p.id }) end, "active")
    end
end

local function drawAssociates(d, x, y, w, h)
    if not d.company.online then
        return AP.text(L("v_admin.org.associates_offline"), x, y, w, S(40), C.dim, 0.95)
    end
    AP.table("org_assoc", x, y, w, h, {
        { key = "name", label = L("v_admin.org.col_associate"), bold = true },
        { key = "account", label = L("v_admin.accounts.col_account"), w = S(220) },
        { key = "since", label = L("v_admin.org.col_since"), w = S(180), text = function(a) return AP.fmtDate(a.since, true) end },
        { key = "kick", label = "", w = S(140), align = "center",
          text = function() return AP.can("organizationsEdit") and L("v_admin.org.remove") or "" end, color = function() return C.bad end },
    }, d.company.associates or {}, {
        rowH = S(40), empty = L("v_admin.org.no_associates"),
        onClick = function(a) if AP.can("organizationsEdit") then edit("kick", { player = a.account or a.name }) end end,
    })
end

local function drawActions(d, x, y, w, h)
    if not AP.can("organizationsEdit") then
        return AP.text(L("v_admin.org.need_edit", { level = AP.permLevel("organizationsEdit") }), x, y, w, S(40), C.dim, 0.95)
    end
    local fw = math.min(S(360), w - S(220))
    local row = S(54)
    -- rename
    AP.text(L("v_admin.org.rename"), x, y, w, S(28), C.dim, 0.85)
    AP.field("org_name", x, y + S(30), fw, S(44), { max = 32 })
    AP.button(x + fw + S(10), y + S(30), S(200), S(44), L("v_admin.page.save"), function()
        edit("rename", { name = AP.trim(AP.fieldText("org_name")) })
    end, "active")
    -- balance
    local by = y + S(30) + row + S(10)
    AP.text(L("v_admin.org.adjust"), x, by, w, S(28), C.dim, 0.85)
    AP.field("org_amount", x, by + S(30), S(180), S(44), { max = 12, numeric = false })
    AP.button(x + S(190), by + S(30), S(150), S(44), st.dirty and L("v_admin.org.part_dirty") or L("v_admin.org.part_clean"),
        function() st.dirty = not st.dirty end)
    AP.field("org_reason", x + S(350), by + S(30), math.max(S(160), fw - S(350) + S(200)), S(44), { max = 120 })
    AP.button(x + fw + S(220), by + S(30), S(200), S(44), L("v_admin.org.apply"), function()
        edit("adjust", { amount = tonumber(AP.trim(AP.fieldText("org_amount"))), dirty = st.dirty, reason = AP.trim(AP.fieldText("org_reason")) })
    end, "active")
    AP.text(L("v_admin.org.adjust_hint"), x, by + S(78), w, S(24), C.off, 0.75)
    -- transfer
    local ty = by + S(30) + row + S(40)
    AP.text(L("v_admin.org.transfer"), x, ty, w, S(28), C.dim, 0.85)
    AP.field("org_account", x, ty + S(30), fw, S(44), { max = 64 })
    AP.button(x + fw + S(10), ty + S(30), S(200), S(44), L("v_admin.org.transfer_btn"), function()
        edit("transfer", { account = AP.trim(AP.fieldText("org_account")) })
    end)
    AP.text(L("v_admin.org.transfer_hint"), x, ty + S(78), w, S(24), C.off, 0.75)
    -- force sale
    local sy = ty + S(30) + row + S(40)
    AP.confirmButton("org_forcesell", x, sy, S(320), S(44),
        d.company.online and L("v_admin.org.force_sell") or L("v_admin.org.force_close"), L("v_admin.page.click_again"),
        function() edit("forcesell") end)
end

local TABS = { ledger = drawLedger, units = drawUnits, associates = drawAssociates, actions = drawActions }

local function drawDetail(x, y, w, h)
    local d = st.detail
    if not st.selected then return AP.text(L("v_admin.org.pick"), x, y, w, S(40), C.dim, 1.0) end
    if not d then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 1.0) end
    local c = d.company
    AP.text(c.name, x, y, w, S(40), C.text, 1.3, "default-bold")
    local state = c.status ~= "active" and c.status or (c.online and (c.paused and L("v_admin.org.paused") or L("v_admin.org.online")) or L("v_admin.org.offline"))
    AP.text("#" .. c.id .. "  ·  " .. state, x, y, w, S(40), c.online and C.good or C.dim, 0.9, "default", "right")
    local tiles = {
        { L("v_admin.org.founder"), c.founder or "-" },
        { L("v_admin.org.value"), money(c.value), C.good },
        { L("v_admin.org.clean"), money(c.clean), C.good },
        { L("v_admin.org.dirty"), money(c.dirty) .. (c.launder > 0 and ("  ·  " .. L("v_admin.org.queued", { amount = money(c.launder) })) or "") },
        { L("v_admin.org.created"), AP.fmtDate(c.createdAt) },
        { L("v_admin.org.online_time"), ("%dh %02dm"):format(math.floor((c.activeSeconds or 0) / 3600), math.floor((c.activeSeconds or 0) % 3600 / 60)) },
    }
    local cols, gap = 3, S(10)
    local tw, th = (w - gap * (cols - 1)) / cols, S(58)
    local ty = y + S(48)
    for i, t in ipairs(tiles) do
        AP.kv(x + ((i - 1) % cols) * (tw + gap), ty + math.floor((i - 1) / cols) * (th + gap), tw, th, t[1], t[2], t[3])
    end
    local tabY = ty + math.ceil(#tiles / cols) * (th + gap) + S(6)
    local items = {
        { id = "ledger", label = L("v_admin.org.tab_ledger") },
        { id = "units", label = L("v_admin.org.tab_units", { n = #(d.units or {}) }) },
        { id = "associates", label = L("v_admin.org.tab_associates") },
        { id = "actions", label = L("v_admin.org.tab_actions") },
    }
    local tabH = AP.tabs(x, tabY, w, items, st.tab, function(id)
        st.tab = id
        AP.setFocus(nil)
        if id == "actions" then AP.setField("org_name", c.name) end
    end)
    TABS[st.tab](d, x, tabY + tabH, w, h - (tabY + tabH - y))
end

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

AP.addPage({
    id = "organizations", category = "players", perm = "organizations", order = 35,
    label = function() return L("v_admin.page.organizations") end,
    onShow = function(id)
        loadList()
        if not st.catalog then AP.call("organizations", "catalog", {}, function(r) st.catalog = r and r.list or {} end, true) end
        if tonumber(id) then loadDetail(tonumber(id)) end
    end,
    draw = function(x, y, w, h)
        local lw = math.min(S(560), w * 0.42)
        -- search + status
        AP.field("org_search", x, y, lw - S(110), S(44), { max = 40, placeholder = L("v_admin.org.search"), onEnter = loadList })
        AP.button(x + lw - S(100), y, S(100), S(44), L("v_admin.org.find"), loadList, "active")
        local items = {
            { id = "active", label = L("v_admin.org.status_active") },
            { id = "sold", label = L("v_admin.org.status_sold") },
            { id = "all", label = L("v_admin.org.status_all") },
        }
        local th = AP.tabs(x, y + S(52), lw, items, st.status, function(id) st.status = id; loadList() end)
        local ly = y + S(52) + th
        AP.table("org_list", x, ly, lw, h - (ly - y), {
            { key = "name", label = L("v_admin.org.col_name"), bold = true },
            { key = "founder", label = L("v_admin.org.founder"), w = S(150) },
            { key = "value", label = L("v_admin.org.value"), w = S(130), align = "right", text = function(r) return money(r.value) end,
              color = function() return C.good end },
        }, st.rows or {}, {
            rowH = S(40), empty = st.rows and L("v_admin.page.no_rows") or L("common.loading"),
            selected = function(r) return r.id == st.selected end,
            onClick = function(r) loadDetail(r.id) end,
        })
        drawDetail(x + lw + S(24), y, w - lw - S(24), h)
    end,
})
