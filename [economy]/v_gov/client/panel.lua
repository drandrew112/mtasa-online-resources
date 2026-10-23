-- v_gov / client/panel.lua
-- The /gov panel (DESIGN.md 3): a page list on the left, the page on the right. Values are
-- edited through the ui_core text input; every request goes to server/panel.lua
-- ("v_gov:call" -> "v_gov:reply"). /gov again or the X closes it.

local P = {
    open = false, role = nil, page = "overview", data = {}, scroll = 0,
    sel = {},           -- per page selection (work id, company id, ...)
    cycle = {},         -- per page cycle indexes (filter, role, ...)
}

local ROLE_LEVEL = { viewer = 1, official = 2, minister = 3 }
local PAGES = { "overview", "treasury", "taxes", "works", "fees", "health", "companies", "members", "log" }
local GROUPS = { "all", "tax", "fine", "health", "work", "biz", "gov", "atc", "transfer", "admin" }
local ROLES = { "viewer", "official", "minister", "none" }
local ACC_ROLES = { "manager", "viewer", "owner", "none" }

local sw, sh = guiGetScreenSize()
local U = math.min(1, sh / 1080)
local function S(v) return math.floor(v * U + 0.5) end

local COL = {
    bg = tocolor(14, 18, 26, 245), side = tocolor(20, 26, 38, 255), row = tocolor(28, 35, 50, 255),
    rowHot = tocolor(38, 48, 68, 255), btn = tocolor(44, 56, 78, 255), btnHot = tocolor(60, 76, 104, 255),
    accent = tocolor(56, 132, 214, 255), text = tocolor(232, 238, 248, 255), dim = tocolor(150, 162, 182, 255),
    good = tocolor(96, 214, 140, 255), bad = tocolor(240, 110, 110, 255), line = tocolor(48, 60, 82, 255),
    head = tocolor(255, 214, 102, 255),
}

local areas = {}
local function area(x, y, w, h, fn) areas[#areas + 1] = { x = x, y = y, w = w, h = h, fn = fn } end

local function hovered(x, y, w, h)
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    cx, cy = cx * sw, cy * sh
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function text(str, x, y, w, h, color, scale, font, align)
    dxDrawText(tostring(str), x, y, x + w, y + h, color or COL.text, (scale or 1) * U * 1.05, font or "default",
        align or "left", "center", true)
end

local function button(x, y, w, h, label, fn, style)
    local hot = fn and hovered(x, y, w, h)
    local col = style == "active" and COL.accent or style == "danger" and COL.bad or (hot and COL.btnHot or COL.btn)
    if not fn then col = COL.row end
    dxDrawRectangle(x, y, w, h, col)
    text(label, x, y, w, h, fn and COL.text or COL.dim, 0.95, "default-bold", "center")
    if fn then area(x, y, w, h, fn) end
end

local function money(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-€" or "€") .. s
end

local function pct(r) return ("%g%%"):format(math.floor((tonumber(r) or 0) * 1000 + 0.5) / 10) end

local function can(need) return P.role and ROLE_LEVEL[P.role] >= ROLE_LEVEL[need] end

local function stamp(ts)
    local t = getRealTime(ts)
    return ("%02d-%02d %02d:%02d"):format(t.month + 1, t.monthday, t.hour, t.minute)
end

local function notify(msg, bad)
    pcall(function() exports.ui_core:addNotification("/gov", msg) end)
    if bad then outputDebugString("[v_gov] " .. tostring(msg), 3) end
end

--------------------------------------------------------------------------------
-- requests
--------------------------------------------------------------------------------

local reqs, nextReq = {}, 0

local function call(action, args, cb)
    nextReq = nextReq + 1
    reqs[nextReq] = cb
    triggerServerEvent("v_gov:call", resourceRoot, nextReq, action, args or {})
end

addEvent("v_gov:reply", true)
addEventHandler("v_gov:reply", resourceRoot, function(id, result, err)
    local cb = reqs[id]
    reqs[id] = nil
    if result == false then
        local key = tostring(err or "v_gov.err.unknown")
        notify(L.has(key) and L.text(key) or key, true)
    end
    if cb then cb(result) end
end)

local loadPage

--- a change, then the page again
local function change(action, args)
    call(action, args, function(r)
        if r ~= false then notify(L.text("v_gov.ui.saved")) end
        loadPage(P.page)
    end)
end

--------------------------------------------------------------------------------
-- text input (ui_core)
--------------------------------------------------------------------------------

local inputs = {}

local function ask(title, default, maxLen, cb)
    local ok, token = pcall(function()
        return exports.ui_core:openTextInput(title, maxLen or 32, default and tostring(default) or "", "")
    end)
    if ok and token then inputs[token] = cb end
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, value)
    local cb = inputs[token]
    if not cb then return end
    inputs[token] = nil
    if value ~= false and value ~= nil then cb(tostring(value)) end
end)

local function askNumber(title, default, cb)
    ask(title, default, 16, function(v)
        local n = tonumber((v:gsub(",", ".")))
        if not n then return notify(L.text("v_gov.err.bad_number"), true) end
        cb(n)
    end)
end

--------------------------------------------------------------------------------
-- data
--------------------------------------------------------------------------------

function loadPage(page)
    local args = {}
    if page == "treasury" then
        local g = GROUPS[P.cycle.group or 1]
        args = { id = P.sel.treasury, group = g ~= "all" and g or nil }
    end
    local action = page == "treasury" and "treasuryLedger" or page
    call(action, args, function(r)
        if r == false or P.page ~= page then return end
        P.data[page] = r
        if page == "companies" and P.sel.company then
            call("company", { id = P.sel.company }, function(c) if c then P.data.company = c.account end end)
        end
        if page == "treasury" and not P.data.overview then
            call("overview", {}, function(o) if o then P.data.overview = o end end)
        end
    end)
end

local function setPage(page)
    P.page, P.scroll = page, 0
    loadPage(page)
end

--------------------------------------------------------------------------------
-- pages
--------------------------------------------------------------------------------

local function rows(x, y, w, h, list, draw)
    -- draw(item, x, y, w, rowH); scrolls with the wheel
    local rh = S(40)
    local visible = math.floor(h / (rh + S(4)))
    local maxScroll = math.max(0, #list - visible)
    P.scroll = math.max(0, math.min(P.scroll, maxScroll))
    for i = 1, visible do
        local item = list[i + P.scroll]
        if not item then break end
        local ry = y + (i - 1) * (rh + S(4))
        dxDrawRectangle(x, ry, w, rh, hovered(x, ry, w, rh) and COL.rowHot or COL.row)
        draw(item, x, ry, w, rh)
    end
    if #list == 0 then text(L.text("v_gov.ui.empty"), x, y, w, rh, COL.dim) end
end

local function txText(r)
    local base = "v_bank.tx." .. tostring(r.key)
    local dir = base .. (r.amount < 0 and ".out" or ".in")
    local key = L.has(dir) and dir or base
    local t = L.has(key) and L.text(key, r.params or {}) or tostring(r.key)
    if r.counter and r.counter.number then t = t .. "  ·  " .. r.counter.name end
    if r.params and r.params.note and r.params.note ~= "" then t = t .. "  ·  " .. r.params.note end
    return t
end

local function groupSums(stats)
    local g = {}
    for key, s in pairs(stats or {}) do
        local name = key:match("^([%w_]+)%.") or key
        g[name] = g[name] or { inSum = 0, outSum = 0 }
        g[name].inSum = g[name].inSum + s.inSum
        g[name].outSum = g[name].outSum + s.outSum
    end
    local list = {}
    for name, s in pairs(g) do list[#list + 1] = { name = name, inSum = s.inSum, outSum = s.outSum } end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local DRAW = {}

function DRAW.overview(d, x, y, w, h)
    local t = d.treasury or {}
    text(L.text("v_gov.ui.treasury_balance"), x, y, w, S(30), COL.dim)
    text(money(t.balance), x, y + S(28), w, S(50), (t.balance or 0) < 0 and COL.bad or COL.good, 2, "default-bold")
    local cw = (w - S(20)) / 2
    for i, period in ipairs({ { "day", "v_gov.ui.last_24h" }, { "week", "v_gov.ui.last_7d" } }) do
        local cx, cy = x + (i - 1) * (cw + S(20)), y + S(100)
        text(L.text(period[2]), cx, cy, cw, S(30), COL.head, 1, "default-bold")
        local list = groupSums(d[period[1]])
        local ty = cy + S(34)
        for _, g in ipairs(list) do
            text(L.text("v_bank.group." .. g.name), cx, ty, cw * 0.4, S(28), COL.text)
            text("+" .. money(g.inSum), cx + cw * 0.4, ty, cw * 0.3, S(28), COL.good, 1, "default", "right")
            text("-" .. money(g.outSum), cx + cw * 0.7, ty, cw * 0.3, S(28), COL.bad, 1, "default", "right")
            ty = ty + S(28)
        end
        if #list == 0 then text(L.text("v_gov.ui.empty"), cx, ty, cw, S(28), COL.dim) end
    end
    local ry = y + S(420)
    text(L.text("v_gov.ui.tax_runs"), x, ry, w, S(30), COL.head, 1, "default-bold")
    rows(x, ry + S(36), w, h - (ry + S(36) - y), d.runs or {}, function(r, rx, rY, rw, rh)
        text(stamp(r.period), rx + S(10), rY, rw * 0.4, rh)
        text(L.text("v_gov.ui.companies_n", { n = r.companies }), rx + rw * 0.4, rY, rw * 0.3, rh, COL.dim)
        text(money(r.total), rx + rw * 0.7, rY, rw * 0.3 - S(10), rh, COL.good, 1, "default-bold", "right")
    end)
end

function DRAW.treasury(d, x, y, w, h)
    local states = P.data.overview and P.data.overview.states or {}
    local cur
    for _, s in ipairs(states) do if s.id == d.id then cur = s end end
    button(x, y, S(320), S(40), (cur and cur.name or "Treasury") .. "  >", function()
        if #states == 0 then return end
        local idx = 1
        for i, s in ipairs(states) do if s.id == d.id then idx = i end end
        P.sel.treasury = states[idx % #states + 1].id
        loadPage("treasury")
    end)
    button(x + S(330), y, S(220), S(40), L.text("v_bank.group." .. GROUPS[P.cycle.group or 1]) .. "  >", function()
        P.cycle.group = (P.cycle.group or 1) % #GROUPS + 1
        loadPage("treasury")
    end)
    if cur then text(money(cur.balance), x + S(560), y, w - S(560), S(40), cur.balance < 0 and COL.bad or COL.good, 1.3, "default-bold", "right") end
    -- money between the treasury and a state company (minister)
    local ty = y + S(48)
    if can("minister") and cur and cur.ownerRef ~= "treasury" then
        local function move(dir)
            askNumber(L.text("v_gov.ui.amount"), "", function(n)
                ask(L.text("v_gov.ui.note"), "", 60, function(note)
                    change("treasuryTransfer", { id = cur.id, amount = n, dir = dir, note = note })
                end)
            end)
        end
        button(x, ty, S(300), S(40), L.text("v_gov.ui.from_treasury"), function() move("to") end, "active")
        button(x + S(310), ty, S(300), S(40), L.text("v_gov.ui.to_treasury"), function() move("from") end)
        ty = ty + S(48)
    end
    rows(x, ty, w, h - (ty - y) - S(48), d.rows or {}, function(r, rx, rY, rw, rh)
        text(stamp(r.ts), rx + S(10), rY, S(120), rh, COL.dim)
        text(txText(r), rx + S(130), rY, rw - S(420), rh)
        text((r.amount > 0 and "+" or "") .. money(r.amount), rx + rw - S(290), rY, S(140), rh, r.amount < 0 and COL.bad or COL.good, 1, "default-bold", "right")
        text(r.balance and money(r.balance) or "-", rx + rw - S(150), rY, S(140), rh, COL.dim, 1, "default", "right")
    end)
    if d.more then
        button(x + w - S(220), y + h - S(40), S(220), S(40), L.text("v_gov.ui.older"), function()
            local last = d.rows[#d.rows]
            local g = GROUPS[P.cycle.group or 1]
            call("treasuryLedger", { id = d.id, before = last and last.id, group = g ~= "all" and g or nil }, function(r)
                if not r then return end
                for _, row in ipairs(r.rows or {}) do table.insert(d.rows, row) end
                d.more = r.more
            end)
        end)
    end
end

function DRAW.taxes(d, x, y, w, h)
    local edit = can("minister")
    text(L.text("v_gov.ui.company_tax"), x, y, w * 0.5, S(40), COL.text, 1.1, "default-bold")
    button(x + w * 0.5, y, S(200), S(40), pct(d.company), edit and function()
        askNumber(L.text("v_gov.ui.company_tax") .. " (%)", (d.company or 0) * 100, function(n) change("setCompanyTax", { value = n }) end)
    end or nil)
    text(L.text("v_gov.ui.income_keys"), x, y + S(60), w, S(30), COL.head, 1, "default-bold")
    local keys = {}
    for k, r in pairs(d.keys or {}) do keys[#keys + 1] = { key = k, rate = r } end
    table.sort(keys, function(a, b) return a.key < b.key end)
    local ky = y + S(96)
    for _, k in ipairs(keys) do
        dxDrawRectangle(x, ky, w, S(40), COL.row)
        text(k.key, x + S(10), ky, S(200), S(40), COL.text, 1, "default-bold")
        local users = d.used and d.used[k.key]
        text(users and table.concat(users, ", ") or "-", x + S(220), ky, w - S(560), S(40), COL.dim)
        button(x + w - S(330), ky + S(4), S(150), S(32), pct(k.rate), edit and function()
            askNumber(k.key .. " (%)", k.rate * 100, function(n) change("setTaxKey", { key = k.key, value = n }) end)
        end or nil)
        if edit and k.key ~= "standard" then
            button(x + w - S(170), ky + S(4), S(160), S(32), L.text("v_gov.ui.delete"), function()
                change("deleteTaxKey", { key = k.key })
            end, "danger")
        end
        ky = ky + S(44)
    end
    if edit then
        button(x, ky + S(4), S(260), S(40), L.text("v_gov.ui.add_key"), function()
            ask(L.text("v_gov.ui.key_name"), "", 24, function(name)
                askNumber(name .. " (%)", "", function(n) change("setTaxKey", { key = name, value = n }) end)
            end)
        end, "active")
    end
    local ry = ky + S(60)
    text(L.text("v_gov.ui.tax_runs"), x, ry, w, S(30), COL.head, 1, "default-bold")
    rows(x, ry + S(36), w, h - (ry + S(36) - y), d.runs or {}, function(r, rx, rY, rw, rh)
        text(stamp(r.period), rx + S(10), rY, rw * 0.4, rh)
        text(L.text("v_gov.ui.companies_n", { n = r.companies }), rx + rw * 0.4, rY, rw * 0.3, rh, COL.dim)
        text(money(r.total), rx + rw * 0.7, rY, rw * 0.3 - S(10), rh, COL.good, 1, "default-bold", "right")
    end)
end

local function payerName(d, spec)
    for _, p in ipairs(d.payers or {}) do if p.spec == spec then return p.name end end
    if spec:match("^company:") then return L.text("v_gov.ui.private_company", { id = spec:sub(9) }) end
    return spec
end

function DRAW.works(d, x, y, w, h)
    local list = d.works or {}
    local lw = math.min(S(320), w * 0.3)
    local sel
    for _, wk in ipairs(list) do if wk.id == P.sel.work then sel = wk end end
    sel = sel or list[1]
    local ly = y
    for _, wk in ipairs(list) do
        button(x, ly, lw, S(40), wk.name, function() P.sel.work = wk.id; P.scroll = 0 end, wk == sel and "active" or nil)
        ly = ly + S(44)
    end
    if not sel then return text(L.text("v_gov.ui.empty"), x, y, w, S(40), COL.dim) end
    local edit = can("minister")
    local rx, rw = x + lw + S(20), w - lw - S(20)
    text(sel.name .. "  (" .. sel.id .. ")", rx, y, rw, S(40), COL.head, 1.2, "default-bold")
    local fy = y + S(48)
    local function field(label, value, fn, reset)
        dxDrawRectangle(rx, fy, rw, S(40), COL.row)
        text(label, rx + S(10), fy, rw * 0.45, S(40))
        button(rx + rw * 0.45, fy + S(4), rw * 0.35, S(32), value, edit and fn or nil)
        if edit and reset then button(rx + rw * 0.8 + S(8), fy + S(4), rw * 0.2 - S(12), S(32), L.text("v_gov.ui.reset"), reset) end
        fy = fy + S(44)
    end
    field(L.text("v_gov.ui.payer"), payerName(d, sel.payer), function()
        -- cycle the state payers; the last step asks for a private company
        local opts = d.payers or {}
        local idx = 0
        for i, p in ipairs(opts) do if p.spec == sel.payer then idx = i end end
        if idx >= #opts then
            ask(L.text("v_gov.ui.company_name"), "", 48, function(name)
                change("setWork", { work = sel.id, field = "payer", value = "company:" .. name })
            end)
        else
            change("setWork", { work = sel.id, field = "payer", value = opts[idx + 1].spec })
        end
    end)
    field(L.text("v_gov.ui.multiplier"), ("x%g"):format(sel.multiplier), function()
        askNumber(L.text("v_gov.ui.multiplier"), sel.multiplier, function(n) change("setWork", { work = sel.id, field = "multiplier", value = n }) end)
    end, function() change("setWork", { work = sel.id, field = "multiplier" }) end)
    field(L.text("v_gov.ui.tax_key"), sel.taxKey .. " (" .. pct(sel.taxRate) .. ")", function()
        local keys = {}
        for k in pairs(d.taxKeys or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        local idx = 0
        for i, k in ipairs(keys) do if k == sel.taxKey then idx = i end end
        change("setWork", { work = sel.id, field = "taxKey", value = keys[idx % #keys + 1] })
    end)
    text(L.text("v_gov.ui.params"), rx, fy + S(6), rw, S(30), COL.head, 1, "default-bold")
    fy = fy + S(40)
    rows(rx, fy, rw, h - (fy - y), sel.params or {}, function(prm, px, py, pw, ph)
        text((prm.kind == "xp" and "[XP] " or "") .. prm.label, px + S(10), py, pw * 0.5, ph)
        text(L.text("v_gov.ui.default_n", { n = prm.default }), px + pw * 0.5, py, pw * 0.2, ph, COL.dim)
        local v = prm.value or prm.default
        button(px + pw * 0.7, py + S(4), pw * 0.15, ph - S(8), tostring(v), edit and function()
            askNumber(prm.label, v, function(n) change("setWork", { work = sel.id, field = "param", key = prm.key, value = n }) end)
        end or nil, prm.value and "active" or nil)
        if edit and prm.value then
            button(px + pw * 0.85 + S(6), py + S(4), pw * 0.15 - S(12), ph - S(8), L.text("v_gov.ui.reset"), function()
                change("setWork", { work = sel.id, field = "param", key = prm.key })
            end)
        end
    end)
end

function DRAW.fees(d, x, y, w, h)
    local edit = can("minister")
    rows(x, y, w, h, d.fees or {}, function(f, rx, ry, rw, rh)
        text(L.text("v_gov.fee." .. f.key), rx + S(10), ry, rw * 0.5, rh)
        text(L.text("v_gov.ui.default_n", { n = money(f.default) }), rx + rw * 0.5, ry, rw * 0.2, rh, COL.dim)
        button(rx + rw * 0.7, ry + S(4), rw * 0.15, rh - S(8), money(f.value), edit and function()
            askNumber(L.text("v_gov.fee." .. f.key), f.value, function(n) change("setFee", { key = f.key, value = n }) end)
        end or nil)
        if edit then
            button(rx + rw * 0.85 + S(6), ry + S(4), rw * 0.15 - S(12), rh - S(8), L.text("v_gov.ui.reset"), function()
                change("setFee", { key = f.key })
            end)
        end
    end)
end

function DRAW.health(d, x, y, w, h)
    local edit = can("official")
    text(L.text("v_gov.ui.health_enabled"), x, y, w * 0.5, S(40))
    button(x + w * 0.5, y, S(200), S(40), d.enabled and L.text("v_gov.ui.on") or L.text("v_gov.ui.off"), edit and function()
        change("setHealth", { field = "enabled", value = not d.enabled })
    end or nil, d.enabled and "active" or nil)
    text(L.text("v_gov.ui.hp_price"), x, y + S(48), w * 0.5, S(40))
    button(x + w * 0.5, y + S(48), S(200), S(40), money(d.hpPrice), edit and function()
        askNumber(L.text("v_gov.ui.hp_price"), d.hpPrice, function(n) change("setHealth", { field = "hp_price", value = n }) end)
    end or nil)
    text(L.text("v_gov.ui.injury_prices"), x, y + S(104), w, S(30), COL.head, 1, "default-bold")
    local list = {}
    for t, prices in pairs(d.injuries or {}) do list[#list + 1] = { type = t, prices = prices } end
    table.sort(list, function(a, b) return a.type < b.type end)
    local ly = y + S(140)
    rows(x, ly, w, h - (ly - y) - S(50), list, function(it, rx, ry, rw, rh)
        text(it.type, rx + S(10), ry, rw * 0.3, rh, COL.text, 1, "default-bold")
        for sev = 1, 3 do
            local bx = rx + rw * 0.3 + (sev - 1) * rw * 0.18
            button(bx, ry + S(4), rw * 0.17, rh - S(8), sev .. ": " .. money(it.prices[sev]), edit and function()
                askNumber(it.type .. " / " .. sev, it.prices[sev], function(n)
                    change("setHealth", { field = "injury", type = it.type, severity = sev, value = n })
                end)
            end or nil)
        end
        if edit and it.type ~= "default" then
            button(rx + rw * 0.86, ry + S(4), rw * 0.14 - S(8), rh - S(8), L.text("v_gov.ui.delete"), function()
                change("setHealth", { field = "remove_injury", type = it.type })
            end, "danger")
        end
    end)
    if edit then
        button(x, y + h - S(40), S(280), S(40), L.text("v_gov.ui.add_injury"), function()
            ask(L.text("v_gov.ui.injury_type"), "", 24, function(t)
                change("setHealth", { field = "injury", type = t, severity = 1, value = 0 })
            end)
        end, "active")
    end
end

function DRAW.companies(d, x, y, w, h)
    local list = d.list or {}
    local lw = math.min(S(380), w * 0.35)
    local ly = y
    for _, c in ipairs(list) do
        if c.status ~= "closed" then
            button(x, ly, lw, S(40), c.name, function()
                P.sel.company = c.id
                P.data.company = nil
                call("company", { id = c.id }, function(r) if r then P.data.company = r.account end end)
            end, c.id == P.sel.company and "active" or nil)
            ly = ly + S(44)
        end
    end
    if can("official") then
        button(x, ly + S(10), lw, S(40), L.text("v_gov.ui.create_company"), function()
            ask(L.text("v_gov.ui.company_code"), "", 24, function(code)
                ask(L.text("v_gov.ui.company_name"), "", 64, function(name)
                    change("createCompany", { code = code, name = name, allowNegative = false })
                end)
            end)
        end, "active")
    end
    local a = P.data.company
    if not a or a.id ~= P.sel.company then return end
    local rx, rw = x + lw + S(20), w - lw - S(20)
    text(a.name, rx, y, rw, S(40), COL.head, 1.3, "default-bold")
    text(a.number .. "  ·  " .. a.ownerRef, rx, y + S(36), rw, S(30), COL.dim)
    text(money(a.balance), rx, y + S(66), rw, S(44), a.balance < 0 and COL.bad or COL.good, 1.6, "default-bold")
    local pays = d.payers and d.payers[a.ownerRef]
    text(L.text("v_gov.ui.pays_works", { works = pays and table.concat(pays, ", ") or "-" }), rx, y + S(112), rw, S(30), COL.dim)
    local by = y + S(150)
    if can("official") then
        button(rx, by, S(200), S(40), L.text("v_gov.ui.rename"), function()
            ask(L.text("v_gov.ui.company_name"), a.name, 64, function(name) change("renameCompany", { id = a.id, name = name }) end)
        end)
        if can("minister") then
            button(rx + S(210), by, S(260), S(40), a.allowNegative and L.text("v_gov.ui.overdraft_on") or L.text("v_gov.ui.overdraft_off"),
                function() change("companyOverdraft", { id = a.id, allow = not a.allowNegative }) end, a.allowNegative and "active" or nil)
        end
        if a.ownerRef ~= "treasury" then
            button(rx + S(480), by, S(240), S(40), L.text("v_gov.ui.delete_company"), function()
                change("deleteCompany", { id = a.id, move = true })
            end, "danger")
        end
        button(rx, by + S(48), S(300), S(40), L.text("v_gov.ui.add_member") .. ": " .. ACC_ROLES[P.cycle.accRole or 1], function()
            ask(L.text("v_gov.ui.account_name"), "", 64, function(acc)
                change("companyMember", { id = a.id, account = acc, role = ACC_ROLES[P.cycle.accRole or 1] })
            end)
        end, "active")
        button(rx + S(310), by + S(48), S(200), S(40), L.text("v_gov.ui.role") .. "  >", function()
            P.cycle.accRole = (P.cycle.accRole or 1) % #ACC_ROLES + 1
        end)
    end
    text(L.text("v_gov.ui.members"), rx, by + S(100), rw, S(30), COL.head, 1, "default-bold")
    rows(rx, by + S(136), rw, h - (by + S(136) - y), a.access or {}, function(m, mx, my, mw, mh)
        text(m.account, mx + S(10), my, mw * 0.5, mh, COL.text, 1, "default-bold")
        text(m.role, mx + mw * 0.5, my, mw * 0.25, mh, COL.dim)
        if can("official") then
            button(mx + mw * 0.75, my + S(4), mw * 0.25 - S(8), mh - S(8), L.text("v_gov.ui.remove"), function()
                change("companyMember", { id = a.id, account = m.account, role = "none" })
            end, "danger")
        end
    end)
end

function DRAW.members(d, x, y, w, h)
    local edit = can("minister")
    text(L.text("v_gov.ui.admins_are_ministers", { level = d.adminLevel or 5 }), x, y, w, S(30), COL.dim)
    local ty = y + S(40)
    if edit then
        button(x, ty, S(300), S(40), L.text("v_gov.ui.add_member") .. ": " .. ROLES[P.cycle.role or 1], function()
            ask(L.text("v_gov.ui.account_name"), "", 64, function(acc)
                change("setMember", { account = acc, role = ROLES[P.cycle.role or 1] })
            end)
        end, "active")
        button(x + S(310), ty, S(200), S(40), L.text("v_gov.ui.role") .. "  >", function()
            P.cycle.role = (P.cycle.role or 1) % (#ROLES - 1) + 1
        end)
        ty = ty + S(52)
    end
    rows(x, ty, w, h - (ty - y), d.list or {}, function(m, rx, ry, rw, rh)
        text(m.account, rx + S(10), ry, rw * 0.5, rh, COL.text, 1, "default-bold")
        text(L.text("v_gov.role." .. m.role), rx + rw * 0.5, ry, rw * 0.25, rh, COL.dim)
        if edit then
            button(rx + rw * 0.75, ry + S(4), rw * 0.25 - S(8), rh - S(8), L.text("v_gov.ui.remove"), function()
                change("setMember", { account = m.account, role = "none" })
            end, "danger")
        end
    end)
end

function DRAW.log(d, x, y, w, h)
    rows(x, y, w, h, d.list or {}, function(r, rx, ry, rw, rh)
        text(stamp(r.ts), rx + S(10), ry, S(120), rh, COL.dim)
        text(r.actor, rx + S(130), ry, S(160), rh, COL.text, 1, "default-bold")
        text(r.action, rx + S(300), ry, S(170), rh, COL.head)
        text(r.detail, rx + S(480), ry, rw - S(490), rh, COL.dim)
    end)
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

local function render()
    areas = {}
    local w, h = math.min(S(1500), sw - S(60)), math.min(S(900), sh - S(60))
    local x, y = (sw - w) / 2, (sh - h) / 2
    dxDrawRectangle(x, y, w, h, COL.bg)
    local nw = S(240)
    dxDrawRectangle(x, y, nw, h, COL.side)
    text("San Andreas", x + S(20), y + S(16), nw, S(30), COL.dim)
    text(L.text("v_gov.ui.title"), x + S(20), y + S(42), nw, S(36), COL.head, 1.3, "default-bold")
    text(L.text("v_gov.role." .. tostring(P.role)), x + S(20), y + S(78), nw, S(26), COL.dim)
    local py = y + S(120)
    for _, page in ipairs(PAGES) do
        button(x + S(12), py, nw - S(24), S(42), L.text("v_gov.page." .. page), function() setPage(page) end,
            page == P.page and "active" or nil)
        py = py + S(48)
    end
    button(x + w - S(52), y + S(12), S(40), S(40), "X", function() togglePanel(false) end, "danger")

    local cx, cy, cw, ch = x + nw + S(24), y + S(20), w - nw - S(48) - S(52), h - S(40)
    text(L.text("v_gov.page." .. P.page), cx, cy, cw, S(40), COL.text, 1.5, "default-bold")
    local d = P.data[P.page]
    if not d then
        text(L.text("v_gov.ui.loading"), cx, cy + S(60), cw, S(40), COL.dim)
        return
    end
    DRAW[P.page](d, cx, cy + S(60), cw + S(52), ch - S(60))
end

local function onClick(btn, state)
    if btn ~= "left" or state ~= "up" or not P.open then return end
    for i = #areas, 1, -1 do
        local a = areas[i]
        if hovered(a.x, a.y, a.w, a.h) then a.fn() return end
    end
end

local function onKey(key, press)
    if not P.open or not press then return end
    if key == "mouse_wheel_down" then P.scroll = P.scroll + 1
    elseif key == "mouse_wheel_up" then P.scroll = math.max(0, P.scroll - 1) end
end

function togglePanel(on)
    if on == P.open then return end
    P.open = on
    if on then
        addEventHandler("onClientRender", root, render)
        addEventHandler("onClientClick", root, onClick)
        addEventHandler("onClientKey", root, onKey)
        showCursor(true)
        setPage(P.page)
    else
        removeEventHandler("onClientRender", root, render)
        removeEventHandler("onClientClick", root, onClick)
        removeEventHandler("onClientKey", root, onKey)
        showCursor(false)
    end
end

addEvent("v_gov:open", true)
addEventHandler("v_gov:open", resourceRoot, function(role)
    P.role = role
    togglePanel(not P.open)
end)

addEvent("v_gov:denied", true)
addEventHandler("v_gov:denied", resourceRoot, function()
    notify(L.text("v_gov.err.no_right"), true)
end)
