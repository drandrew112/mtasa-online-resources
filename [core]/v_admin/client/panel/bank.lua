if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/bank.lua
--  Bank page (v_bank): search + account list on the left (kind tabs, the
--  overdraft list), the chosen account on the right (tiles, then Statement /
--  Access / Actions tabs). Data and edits: server/pages/bank.lua.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local GROUPS = { "all", "cash", "transfer", "work", "tax", "fine", "shop", "biz", "health", "atc", "pt", "gov", "admin" }
local ROLES = { "owner", "manager", "viewer", "none" }

local st = { rows = nil, kind = "all", selected = nil, account = nil, ledger = nil, more = false, group = 1, tab = "ledger", role = 2 }

local function money(n)
    n = tonumber(n) or 0
    return (n < 0 and "-€" or "€") .. AP.fmtInt(math.abs(n))
end

local function txText(r)
    local base = "v_bank.tx." .. tostring(r.key)
    local dir = base .. (r.amount < 0 and ".out" or ".in")
    local key = L.has(dir) and dir or base
    if not L.has(key) then return tostring(r.key) end
    local text = L(key, r.params or {})
    if r.params and r.params.note and r.params.note ~= "" then text = text .. "  ·  " .. r.params.note end
    if r.counter and r.counter.number then text = text .. "  ·  " .. r.counter.name .. " (" .. r.counter.number .. ")" end
    return text
end

local function loadList()
    local args = { text = AP.trim(AP.fieldText("bank_search")) }
    if st.kind == "negative" then args.negative = true elseif st.kind ~= "all" then args.kind = st.kind end
    AP.call("bank", "search", args, function(r)
        st.rows = r and r.accounts or {}
    end, true)
end

local function loadLedger(before)
    local id = st.selected
    local group = GROUPS[st.group]
    AP.call("bank", "ledger", { id = id, before = before, group = group ~= "all" and group or nil }, function(r)
        if not r or st.selected ~= id then return end
        if before and st.ledger then
            for _, row in ipairs(r.rows or {}) do st.ledger[#st.ledger + 1] = row end
        else
            st.ledger = r.rows or {}
        end
        st.more = r.more == true
    end, true)
end

local function loadDetail(id)
    st.selected, st.account, st.ledger, st.more = id, nil, nil, false
    AP.call("bank", "account", { id = id }, function(r)
        if r and st.selected == id then st.account = r.account end
    end, true)
    loadLedger()
end

local function edit(action, args)
    args = args or {}
    args.id = st.selected
    AP.call("bank", action, args, function(r)
        if r then
            loadDetail(st.selected)
            loadList()
        end
    end)
end

--------------------------------------------------------------------------------
-- right side
--------------------------------------------------------------------------------

local function drawLedger(a, x, y, w, h)
    AP.button(x, y, S(220), S(40), L("v_bank.group." .. GROUPS[st.group]) .. "  >", function()
        st.group = st.group % #GROUPS + 1
        loadLedger()
    end)
    if st.more then
        AP.button(x + w - S(220), y, S(220), S(40), L("v_admin.bank.older"), function()
            local last = st.ledger and st.ledger[#st.ledger]
            if last then loadLedger(last.id) end
        end)
    end
    local ty = y + S(50)
    AP.table("bank_ledger", x, ty, w, h - (ty - y), {
        { key = "ts", label = L("v_admin.accounts.col_date"), w = S(160), text = function(r) return AP.fmtDate(r.ts, true) end },
        { key = "key", label = L("v_admin.org.col_description"), text = txText },
        { key = "amount", label = L("v_admin.org.col_amount"), w = S(150), align = "right", bold = true,
          text = function(r) return (r.amount > 0 and "+" or "") .. money(r.amount) end,
          color = function(r) return r.amount < 0 and C.bad or C.good end },
        { key = "balance", label = L("v_admin.org.col_balance"), w = S(150), align = "right",
          text = function(r) return r.balance and money(r.balance) or "-" end },
    }, st.ledger or {}, { rowH = S(36), empty = st.ledger and L("v_admin.page.no_rows") or L("common.loading") })
end

local function drawAccess(a, x, y, w, h)
    local canEdit = AP.can("bankEdit")
    AP.table("bank_access", x, y, w, h - (canEdit and S(60) or 0), {
        { key = "account", label = L("v_admin.accounts.col_account"), bold = true },
        { key = "role", label = L("v_admin.bank.role"), w = S(160) },
        { key = "by", label = L("v_admin.bank.granted_by"), w = S(180) },
        { key = "at", label = L("v_admin.accounts.col_date"), w = S(160), text = function(r) return AP.fmtDate(r.at) end },
    }, a.access or {}, {
        rowH = S(38), empty = L("v_admin.bank.no_access"),
        onClick = function(r) AP.setField("bank_access_acc", r.account) end,
    })
    if not canEdit then return end
    local by = y + h - S(48)
    local fw = math.max(S(160), w - S(420))
    AP.field("bank_access_acc", x, by, fw, S(44), { max = 64, placeholder = L("v_admin.accounts.col_account") })
    AP.button(x + fw + S(10), by, S(190), S(44), L("v_admin.bank.role_" .. ROLES[st.role]) .. "  >", function()
        st.role = st.role % #ROLES + 1
    end)
    AP.button(x + fw + S(210), by, S(190), S(44), L("v_admin.page.save"), function()
        edit("access", { account = AP.trim(AP.fieldText("bank_access_acc")), role = ROLES[st.role] })
    end, "active")
end

local function drawActions(a, x, y, w, h)
    if not AP.can("bankEdit") then
        return AP.text(L("v_admin.org.need_edit", { level = AP.permLevel("bankEdit") }), x, y, w, S(40), C.dim, 0.95)
    end
    local row = S(54)
    -- add / take money
    AP.text(L("v_admin.bank.adjust"), x, y, w, S(28), C.dim, 0.85)
    AP.field("bank_amount", x, y + S(30), S(180), S(44), { max = 12 })
    local nw = math.max(S(160), w - S(400))
    AP.field("bank_note", x + S(190), y + S(30), nw, S(44), { max = 60, placeholder = L("v_admin.bank.note") })
    AP.button(x + S(200) + nw, y + S(30), S(200), S(44), L("v_admin.org.apply"), function()
        edit("adjust", { amount = tonumber(AP.trim(AP.fieldText("bank_amount"))), note = AP.trim(AP.fieldText("bank_note")) })
    end, "active")
    AP.text(L("v_admin.bank.adjust_hint"), x, y + S(78), w, S(24), C.off, 0.75)
    -- transfer
    local ty = y + S(30) + row + S(40)
    AP.text(L("v_admin.bank.transfer"), x, ty, w, S(28), C.dim, 0.85)
    AP.field("bank_tf_to", x, ty + S(30), S(200), S(44), { max = 20, placeholder = "LB-1-000001" })
    AP.field("bank_tf_amount", x + S(210), ty + S(30), S(160), S(44), { max = 12 })
    local tw = math.max(S(140), w - S(590))
    AP.field("bank_tf_note", x + S(380), ty + S(30), tw, S(44), { max = 60, placeholder = L("v_admin.bank.note") })
    AP.button(x + S(390) + tw, ty + S(30), S(200), S(44), L("v_admin.bank.transfer_btn"), function()
        edit("transfer", { to = AP.trim(AP.fieldText("bank_tf_to")), amount = tonumber(AP.trim(AP.fieldText("bank_tf_amount"))),
            note = AP.trim(AP.fieldText("bank_tf_note")) })
    end, "active")
    -- status + overdraft
    local sy = ty + S(30) + row + S(30)
    if a.status ~= "closed" then
        AP.confirmButton("bank_freeze", x, sy, S(300), S(44),
            a.status == "frozen" and L("v_admin.bank.unfreeze") or L("v_admin.bank.freeze"), L("v_admin.page.click_again"),
            function() edit("status", { status = a.status == "frozen" and "active" or "frozen" }) end)
    end
    AP.confirmButton("bank_overdraft", x + S(310), sy, S(300), S(44),
        a.allowNegative and L("v_admin.bank.overdraft_off") or L("v_admin.bank.overdraft_on"), L("v_admin.page.click_again"),
        function() edit("overdraft", { allow = not a.allowNegative }) end, "active")
end

local TABS = { ledger = drawLedger, access = drawAccess, actions = drawActions }

local function drawDetail(x, y, w, h)
    local a = st.account
    if not st.selected then return AP.text(L("v_admin.bank.pick"), x, y, w, S(40), C.dim, 1.0) end
    if not a then return AP.text(L("common.loading"), x, y, w, S(40), C.dim, 1.0) end
    AP.text(a.name ~= "" and a.name or a.ownerRef, x, y, w, S(40), C.text, 1.3, "default-bold")
    AP.text(a.number, x, y, w, S(40), C.dim, 0.9, "default", "right")
    local tiles = {
        { L("v_admin.bank.kind"), L("v_bank.kind." .. a.kind) },
        { L("v_admin.bank.owner"), a.ownerRef },
        { L("v_admin.org.col_balance"), money(a.balance), a.balance < 0 and C.bad or C.good },
        { L("v_admin.bank.status"), L("v_admin.bank.status_" .. a.status), a.status == "active" and C.good or C.bad },
        { L("v_admin.bank.overdraft"), a.allowNegative and L("v_admin.bank.yes") or L("v_admin.bank.no") },
        { L("v_admin.bank.loaded"), a.online and L("v_admin.bank.yes") or L("v_admin.bank.no") },
    }
    local cols, gap = 3, S(10)
    local tw, th = (w - gap * (cols - 1)) / cols, S(58)
    local ty = y + S(48)
    for i, t in ipairs(tiles) do
        AP.kv(x + ((i - 1) % cols) * (tw + gap), ty + math.floor((i - 1) / cols) * (th + gap), tw, th, t[1], t[2], t[3])
    end
    local tabY = ty + math.ceil(#tiles / cols) * (th + gap) + S(6)
    local items = {
        { id = "ledger", label = L("v_admin.bank.tab_ledger") },
        { id = "access", label = L("v_admin.bank.tab_access", { n = #(a.access or {}) }) },
        { id = "actions", label = L("v_admin.org.tab_actions") },
    }
    local tabH = AP.tabs(x, tabY, w, items, st.tab, function(id)
        st.tab = id
        AP.setFocus(nil)
    end)
    TABS[st.tab](a, x, tabY + tabH, w, h - (tabY + tabH - y))
end

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

AP.addPage({
    id = "bank", category = "players", perm = "bank", order = 36,
    label = function() return L("v_admin.page.bank") end,
    onShow = function(id)
        loadList()
        if tonumber(id) then loadDetail(tonumber(id)) end
    end,
    draw = function(x, y, w, h)
        local lw = math.min(S(600), w * 0.42)
        AP.field("bank_search", x, y, lw - S(110), S(44), { max = 40, placeholder = L("v_admin.bank.search"), onEnter = loadList })
        AP.button(x + lw - S(100), y, S(100), S(44), L("v_admin.org.find"), loadList, "active")
        local items = {
            { id = "all", label = L("v_admin.org.status_all") },
            { id = "personal", label = L("v_admin.bank.kind_personal") },
            { id = "company", label = L("v_admin.bank.kind_company") },
            { id = "state", label = L("v_admin.bank.kind_state") },
            { id = "negative", label = L("v_admin.bank.overdraft_list") },
        }
        local th = AP.tabs(x, y + S(52), lw, items, st.kind, function(id) st.kind = id; loadList() end)
        local ly = y + S(52) + th
        AP.table("bank_list", x, ly, lw, h - (ly - y), {
            { key = "number", label = L("v_admin.bank.number"), w = S(150) },
            { key = "name", label = L("v_admin.org.col_name"), bold = true, text = function(r) return r.name ~= "" and r.name or r.ownerRef end },
            { key = "balance", label = L("v_admin.org.col_balance"), w = S(140), align = "right", text = function(r) return money(r.balance) end,
              color = function(r) return r.balance < 0 and C.bad or C.good end },
        }, st.rows or {}, {
            rowH = S(40), empty = st.rows and L("v_admin.page.no_rows") or L("common.loading"),
            selected = function(r) return r.id == st.selected end,
            onClick = function(r) loadDetail(r.id) end,
        })
        drawDetail(x + lw + S(24), y, w - lw - S(24), h)
    end,
})
