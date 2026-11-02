if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/payments.lua
--  Payments page (SynHosting): status tabs + search + list on the left, the
--  chosen payment on the right. A pending payment is approved to an account
--  (points * multiplier bank money, shown before the click) or rejected
--  with a reason. Data and edits: server/pages/payments.lua.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local st = { rows = nil, status = "pending", page = 0, more = false, counts = {}, selected = nil,
             min = ADMIN.payments.minMultiplier, max = ADMIN.payments.maxMultiplier }

local function money(n) return "€" .. AP.fmtInt(n) end

local function methodName(id)
    local key = "v_admin.payments.method_" .. tostring(id)
    return L.has(key) and L(key) or ("#" .. tostring(id))
end

local STATUS_COLOR = { pending = "warn", approved = "good", rejected = "bad" }
local function statusColor(s) return C[STATUS_COLOR[s] or "dim"] or C.dim end

local function selectedRow()
    for _, r in ipairs(st.rows or {}) do
        if r.id == st.selected then return r end
    end
end

local function pick(r)
    st.selected = r and r.id or nil
    if r and r.status == "pending" then
        AP.setField("pay_account", r.suggested)
        AP.setField("pay_mult", tostring(r.eventMultiplier or st.min))
        AP.setField("pay_reason", "")
    end
end

local function loadList()
    local status = st.status ~= "all" and st.status or nil
    AP.call("payments", "list", { status = status, text = AP.trim(AP.fieldText("pay_search")), page = st.page }, function(r)
        if not r then st.rows = st.rows or {}; return end
        st.rows, st.more, st.counts = r.rows or {}, r.more == true, r.counts or {}
        st.min, st.max = r.minMultiplier or st.min, r.maxMultiplier or st.max
        if st.selected and not selectedRow() then st.selected = nil end
    end, true)
end

local function edit(action, args)
    AP.call("payments", action, args, function(r)
        if r then loadList() end
    end)
end

--------------------------------------------------------------------------------
-- right side
--------------------------------------------------------------------------------

local function drawReview(r, x, y, w)
    if not AP.can("payments") then return end
    local mult = math.floor(tonumber(AP.trim(AP.fieldText("pay_mult"))) or 0)
    local account = AP.trim(AP.fieldText("pay_account"))
    -- approve
    AP.text(L("v_admin.payments.approve_title"), x, y, w, S(28), C.dim, 0.85)
    local fw = math.max(S(160), w - S(370))
    AP.field("pay_account", x, y + S(30), fw, S(44), { max = 64, placeholder = L("v_admin.accounts.col_account") })
    AP.field("pay_mult", x + fw + S(10), y + S(30), S(140), S(44), { max = 4, numeric = true })
    AP.text("x", x + fw + S(10), y + S(30), S(130), S(44), C.off, 0.9, "default", "right")
    local okMult = mult >= st.min and mult <= st.max
    local okAll = okMult and account ~= ""
    AP.confirmButton("pay_approve", x + fw + S(160), y + S(30), S(210), S(44), L("v_admin.payments.approve"),
        L("v_admin.page.click_again"), function()
            if okAll then edit("approve", { id = r.id, account = account, multiplier = mult }) end
        end, okAll and "active" or "off")
    local preview
    if not okMult then
        preview = L("v_admin.payments.bad_multiplier", { min = st.min, max = st.max })
    elseif account == "" then
        preview = L("v_admin.payments.need_account")
    else
        preview = L("v_admin.payments.preview", { points = AP.fmtInt(r.amount), mult = mult, money = money(r.amount * mult), account = account })
    end
    AP.text(preview, x, y + S(80), w, S(30), okAll and C.good or C.bad, 0.9, okAll and "default-bold" or "default")
    if r.suggested ~= "" then
        AP.text(L("v_admin.payments.suggested", { account = r.suggested }), x, y + S(108), w, S(24), C.off, 0.75)
    else
        AP.text(L("v_admin.payments.no_suggestion"), x, y + S(108), w, S(24), C.off, 0.75)
    end
    -- reject
    local ry = y + S(150)
    AP.text(L("v_admin.payments.reject_title"), x, ry, w, S(28), C.dim, 0.85)
    local rw = math.max(S(160), w - S(220))
    AP.field("pay_reason", x, ry + S(30), rw, S(44), { max = 200, placeholder = L("v_admin.payments.reason") })
    local reason = AP.trim(AP.fieldText("pay_reason"))
    AP.confirmButton("pay_reject", x + rw + S(10), ry + S(30), S(210), S(44), L("v_admin.payments.reject"),
        L("v_admin.page.click_again"), function()
            if reason ~= "" then edit("reject", { id = r.id, reason = reason }) end
        end, reason ~= "" and "danger" or "off")
end

local function drawDetail(x, y, w, h)
    local r = selectedRow()
    if not r then return AP.text(L("v_admin.payments.pick"), x, y, w, S(40), C.dim, 1.0) end
    AP.text(L("v_admin.payments.title", { id = r.id }), x, y, w, S(40), C.text, 1.3, "default-bold")
    AP.text(L("v_admin.payments.status_" .. r.status), x, y, w, S(40), statusColor(r.status), 1.0, "default-bold", "right")
    local tiles = {
        { L("v_admin.accounts.col_date"), AP.fmtDate(r.created, true) },
        { L("v_admin.payments.method"), methodName(r.method) },
        { L("v_admin.payments.points"), AP.fmtInt(r.amount), C.good },
        { L("v_admin.payments.sms_id"), r.smsId ~= "" and r.smsId or "-" },
        { L("v_admin.payments.sender"), r.sender ~= "" and r.sender or "-" },
    }
    if r.status == "approved" then
        tiles[#tiles + 1] = { L("v_admin.accounts.col_account"), r.account }
        tiles[#tiles + 1] = { L("v_admin.payments.multiplier"), "x" .. r.multiplier }
        tiles[#tiles + 1] = { L("v_admin.payments.bank_money"), money(r.bankMoney), C.good }
    end
    if r.status ~= "pending" then
        tiles[#tiles + 1] = { L("v_admin.payments.reviewed_by"), r.reviewedBy }
        tiles[#tiles + 1] = { L("v_admin.payments.reviewed_at"), AP.fmtDate(r.reviewedAt, true) }
    end
    local cols, gap = 3, S(10)
    local tw, th = (w - gap * (cols - 1)) / cols, S(58)
    local ty = y + S(48)
    for i, t in ipairs(tiles) do
        AP.kv(x + ((i - 1) % cols) * (tw + gap), ty + math.floor((i - 1) / cols) * (th + gap), tw, th, t[1], t[2], t[3])
    end
    local cy = ty + math.ceil(#tiles / cols) * (th + gap) + S(6)
    AP.text(L("v_admin.payments.comment"), x, cy, w, S(28), C.dim, 0.85)
    local lines = AP.wrap(r.comment ~= "" and r.comment or L("v_admin.payments.no_comment"), w - S(24), 0.95)
    local lh = S(26)
    local shown = math.min(#lines, 4)
    dxDrawRectangle(x, cy + S(30), w, shown * lh + S(16), C.row)
    for i = 1, shown do
        AP.text(lines[i], x + S(12), cy + S(38) + (i - 1) * lh, w - S(24), lh, C.text, 0.95)
    end
    local ny = cy + S(30) + shown * lh + S(30)
    if r.status == "rejected" then
        AP.text(L("v_admin.payments.reject_reason"), x, ny, w, S(28), C.dim, 0.85)
        AP.text(r.rejectReason, x, ny + S(30), w, S(30), C.bad, 1.0)
    elseif r.status == "pending" then
        drawReview(r, x, ny, w)
    end
end

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

AP.addPage({
    id = "payments", category = "players", perm = "payments", order = 37,
    label = function() return L("v_admin.page.payments") end,
    onShow = function()
        st.page = 0
        loadList()
    end,
    draw = function(x, y, w, h)
        local lw = math.min(S(860), w * 0.55)
        AP.field("pay_search", x, y, lw - S(110), S(44), { max = 40, placeholder = L("v_admin.payments.search"),
            onEnter = function() st.page = 0; loadList() end })
        AP.button(x + lw - S(100), y, S(100), S(44), L("v_admin.org.find"), function() st.page = 0; loadList() end, "active")
        local c = st.counts
        local items = {
            { id = "pending", label = L("v_admin.payments.tab_pending", { n = c.pending or 0 }) },
            { id = "approved", label = L("v_admin.payments.status_approved") },
            { id = "rejected", label = L("v_admin.payments.status_rejected") },
            { id = "all", label = L("v_admin.org.status_all") },
        }
        local th = AP.tabs(x, y + S(52), lw, items, st.status, function(id)
            st.status, st.page, st.selected = id, 0, nil
            loadList()
        end)
        local ly = y + S(52) + th
        local pagerH = S(52)
        AP.table("pay_list", x, ly, lw, h - (ly - y) - pagerH, {
            { key = "id", label = "#", w = S(70) },
            { key = "created", label = L("v_admin.accounts.col_date"), w = S(150), text = function(r) return AP.fmtDate(r.created, true) end },
            { key = "method", label = L("v_admin.payments.method"), w = S(120), text = function(r) return methodName(r.method) end },
            { key = "comment", label = L("v_admin.payments.comment"), text = function(r) return r.comment ~= "" and (r.comment:gsub("%s+", " ")) or "-" end,
              color = function(r) return r.comment ~= "" and C.text or C.off end },
            { key = "amount", label = L("v_admin.payments.points"), w = S(100), align = "right", bold = true,
              text = function(r) return AP.fmtInt(r.amount) end },
            { key = "status", label = L("v_admin.payments.status"), w = S(130), bold = true,
              text = function(r) return L("v_admin.payments.status_" .. r.status) end, color = function(r) return statusColor(r.status) end },
        }, st.rows or {}, {
            rowH = S(40), empty = st.rows and L("v_admin.page.no_rows") or L("common.loading"),
            selected = function(r) return r.id == st.selected end,
            onClick = pick,
        })
        local py = y + h - S(44)
        if st.page > 0 then
            AP.button(x, py, S(60), S(44), "<", function() st.page = st.page - 1; loadList() end)
        end
        AP.text(tostring(st.page + 1), x + S(70), py, S(60), S(44), C.dim, 0.95, "default", "center")
        if st.more then
            AP.button(x + S(140), py, S(60), S(44), ">", function() st.page = st.page + 1; loadList() end)
        end
        drawDetail(x + lw + S(24), y, w - lw - S(24), h)
    end,
})
