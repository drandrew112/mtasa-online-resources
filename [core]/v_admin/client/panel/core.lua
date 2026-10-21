if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/core.lua
--  Admin panel (O key) - full screen: a left menu with the pages
--  grouped by category (ADMIN.categories), a top bar, and the page.
--  The immediate-mode DX widgets every page uses:
--    AP.button / AP.area / AP.text   - drawing + click targets
--    AP.field                        - in-panel text field (TextField,
--                                      single or multi line; keyboard goes
--                                      through onClientCharacter / onClientKey)
--    AP.table                        - sortable, scrolling rows
--    AP.tabs / AP.card / AP.kv       - tab strip, titled box, label + value tile
--    AP.openDropdown                 - a list drawn on top of everything
--    AP.scrollArea                   - mouse-wheel region
--    AP.call                         - page request to the server (server/pages.lua)
--  While the panel is open every key bind is off (guiSetInputMode
--  "no_binds"); while a field is focused every key press is cancelled
--  and "textInputOpen" is set as well.
--  Pages live in the other client/panel/*.lua files and register
--  themselves with AP.addPage.
-- ============================================================

local uicore = exports.ui_core
local E = ADMIN.events

AP = {
    open     = false,
    players  = {},
    myLevel  = 0,
    page     = "dashboard",
    scale    = 1,
    pages    = {},
    fields   = {},      -- [id] = TextField (+ .onEnter, .numeric)
    focus    = nil,     -- focused field id
    dropdown = nil,     -- { x, y, w, items = { { label, fn, disabled } } }
    scroll   = {},      -- [table id] = first visible row - 1
}

local buttons, hitList = {}, {}
local scrolls, scrollList = {}, {}
local refreshTimer
local drag = nil        -- { id, x, y } mouse selection in a field

function AP.S(v) return v * AP.scale end
function AP.F(v) return v * AP.scale * (ADMIN.panel.fontScale or 1) end
local S, F = AP.S, AP.F

AP.C = {
    bg        = tocolor(14, 16, 24, 252),
    top       = tocolor(17, 20, 30, 255),
    side      = tocolor(20, 23, 34, 255),
    sideSel   = tocolor(29, 43, 68, 255),
    line      = tocolor(34, 39, 58, 255),
    row       = tocolor(26, 30, 44, 255),
    rowHot    = tocolor(34, 39, 56, 255),
    rowSel    = tocolor(29, 43, 68, 255),
    btn       = tocolor(40, 46, 66, 255),
    btnHot    = tocolor(58, 66, 94, 255),
    btnOff    = tocolor(30, 33, 44, 255),
    field     = tocolor(9, 11, 17, 255),
    accent    = tocolor(0, 130, 220, 255),
    text      = tocolor(235, 238, 245, 255),
    dim       = tocolor(150, 158, 175, 255),
    off       = tocolor(90, 96, 110, 255),
    cat       = tocolor(90, 96, 112, 255),
    head      = tocolor(0, 150, 255, 255),
    good      = tocolor(110, 220, 130, 255),
    warn      = tocolor(255, 200, 90, 255),
    bad       = tocolor(255, 95, 95, 255),
    gold      = tocolor(255, 187, 0, 255),
    danger    = tocolor(150, 45, 45, 255),
    dangerHot = tocolor(190, 65, 65, 255),
    badge     = tocolor(42, 48, 68, 255),
    badgeHot  = tocolor(150, 48, 48, 255),
    sel       = tocolor(0, 130, 220, 110),
    shadow    = tocolor(0, 0, 0, 160),
}
local C = AP.C

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

function AP.permLevel(perm)
    if not perm then return 0 end
    return ADMIN.perms[perm] or 99
end

function AP.can(perm)
    return AP.myLevel >= AP.permLevel(perm)
end

function AP.rankName(level)
    return ADMIN.rankNames[tonumber(level) or 0] or L("v_admin.config.player")
end

function AP.fmtInt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local neg = s:sub(1, 1) == "-"
    if neg then s = s:sub(2) end
    s = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return (neg and "-" or "") .. s
end

function AP.fmtDate(ts, withTime)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "-" end
    local t = getRealTime(ts)
    if withTime == false then
        return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
    end
    return ("%04d.%02d.%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

-- "2 h ago" style text of a past timestamp (server time = client time is not assumed:
-- `now` is the server timestamp the data came with, when known)
function AP.ago(ts, now)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "-" end
    local d = math.max(0, (now or getRealTime().timestamp) - ts)
    if d < 60 then return L("v_admin.page.ago_now") end
    if d < 3600 then return L("v_admin.page.ago_min", { n = math.floor(d / 60) }) end
    if d < 86400 then return L("v_admin.page.ago_hour", { n = math.floor(d / 3600) }) end
    return L("v_admin.page.ago_day", { n = math.floor(d / 86400) })
end

function AP.trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function AP.notify(text)
    uicore:addNotification(L("v_admin.panel_core.admin_panel"), text, true)
end

function AP.sendAction(action, targetId, a, b)
    triggerServerEvent(E.panelAction, resourceRoot, action, targetId, a, b)
end

function AP.cursor()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    local sw, sh = guiGetScreenSize()
    return cx * sw, cy * sh
end

local function inRect(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function AP.hovered(x, y, w, h, layer)
    local mx, my = AP.cursor()
    if not inRect(mx, my, x, y, w, h) then return false end
    local d = AP.dropRect
    if layer ~= "dropdown" and d and inRect(mx, my, d.x, d.y, d.w, d.h) then return false end
    return true
end

-- Word-wrap plain text into lines that fit `w` at font size `size`.
function AP.wrap(str, w, size, font)
    font = font or "default"
    local sc = F(size or 1)
    local lines = {}
    for para in (tostring(str) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            local try = line == "" and word or (line .. " " .. word)
            if L.width(try, sc, font) <= w or line == "" then
                line = try
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

--------------------------------------------------------------------------------
-- server requests (server/pages.lua)
--------------------------------------------------------------------------------

local requests, nextRequest = {}, 0

--- cb(result | false, message | false); the message (if any) is also shown as a notification
--- unless `quiet` is set.
function AP.call(page, action, args, cb, quiet)
    nextRequest = nextRequest + 1
    requests[nextRequest] = { cb = cb, quiet = quiet }
    triggerServerEvent(E.pageCall, resourceRoot, nextRequest, page, action, args or {})
end

addEvent(E.pageReply, true)
addEventHandler(E.pageReply, resourceRoot, function(id, result, message)
    local r = requests[id]
    requests[id] = nil
    if not r then return end
    if message and message ~= "" and not r.quiet then AP.notify(message) end
    if r.cb then r.cb(result, message) end
end)

--------------------------------------------------------------------------------
-- widgets
--------------------------------------------------------------------------------

function AP.text(str, x, y, w, h, color, size, font, ax, ay, clip, wrap, coded)
    dxDrawText(str, x, y, x + w, y + h, color or C.text, F(size or 1), font or "default",
        ax or "left", ay or "center", clip ~= false, wrap or false, false, coded or false)
end

function AP.area(x, y, w, h, fn, layer)
    buttons[#buttons + 1] = { x = x, y = y, w = w, h = h, fn = fn, layer = layer }
end

-- style: nil | "active" | "danger" | "off" | "good"
function AP.button(x, y, w, h, label, fn, style, sub, layer)
    local hot = style ~= "off" and AP.hovered(x, y, w, h, layer)
    local col
    if style == "active" then col = C.accent
    elseif style == "danger" then col = hot and C.dangerHot or C.danger
    elseif style == "off" then col = C.btnOff
    else col = hot and C.btnHot or C.btn end
    dxDrawRectangle(x, y, w, h, col, layer == "dropdown")
    local tc = style == "off" and C.off or C.text
    if sub then
        dxDrawText(label, x, y, x + w, y + h * 0.58, tc, F(0.95), "default-bold", "center", "bottom", true, false, layer == "dropdown")
        dxDrawText(sub, x, y + h * 0.56, x + w, y + h, style == "off" and C.off or C.dim, F(0.75), "default", "center", "top", true, false, layer == "dropdown")
    else
        dxDrawText(label, x, y, x + w, y + h, tc, F(0.95), "default-bold", "center", "center", true, false, layer == "dropdown")
    end
    if fn and style ~= "off" then AP.area(x, y, w, h, fn, layer) end
end

--- A button that needs a second click within 3 s (destructive actions).
local armed = {}
function AP.confirmButton(id, x, y, w, h, label, confirmLabel, fn, style)
    local on = armed[id] and getTickCount() - armed[id] < 3000
    AP.button(x, y, w, h, on and confirmLabel or label, function()
        if armed[id] and getTickCount() - armed[id] < 3000 then
            armed[id] = nil
            fn()
        else
            armed[id] = getTickCount()
        end
    end, style or "danger")
end

function AP.scrollArea(x, y, w, h, fn)
    scrolls[#scrolls + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

--- A titled box; returns the inner x, y, w.
function AP.card(x, y, w, h, title, perm)
    dxDrawRectangle(x, y, w, h, C.side)
    if title then
        AP.text(title, x + S(18), y + S(12), w - S(36), S(36), C.head, 1.1, "default-bold")
    end
    if perm then
        local need = AP.permLevel(perm)
        AP.text(L("v_admin.panel.level", { need = need, perm = (AP.can(perm) and "" or L("v_admin.players.locked")) }),
            x + S(18), y + S(12), w - S(36), S(36), AP.can(perm) and C.dim or C.bad, 0.85, "default", "right")
    end
    return x + S(18), y + (title and S(58) or S(16)), w - S(36)
end

--- A small label + value tile.
function AP.kv(x, y, w, h, label, value, color)
    dxDrawRectangle(x, y, w, h, C.row)
    AP.text(label:upper(), x + S(12), y + S(6), w - S(24), h * 0.4, C.off, 0.7, "default-bold", "left", "top")
    AP.text(tostring(value), x + S(12), y + h * 0.42, w - S(24), h * 0.5, color or C.text, 1.0, "default-bold")
    AP.area(x, y, w, h, function()
        setClipboard(tostring(value))
        AP.notify(L("v_admin.players.copied_to_clipboard", { label = label }))
    end)
end

--- Horizontal tab strip: items = { { id, label } }; returns the height used.
function AP.tabs(x, y, w, items, active, onPick)
    local h = S(44)
    local cx = x
    for _, it in ipairs(items) do
        local tw = L.width(it.label, F(0.95), "default-bold") + S(28)
        local on = it.id == active
        local hot = AP.hovered(cx, y, tw, h)
        AP.text(it.label, cx, y, tw, h, (on or hot) and C.text or C.dim, 0.95, "default-bold", "center")
        if on then dxDrawRectangle(cx, y + h - S(3), tw, S(3), C.head) end
        if not it.disabled then AP.area(cx, y, tw, h, function() onPick(it.id) end) end
        cx = cx + tw + S(4)
    end
    dxDrawRectangle(x, y + h, w, S(1), C.line)
    return h + S(10)
end

--- Scrolling rows.
--- cols: { { key, label, w = px | nil (takes the rest), align, text = fn(row), color = fn(row), sort = bool } }
--- opts: { rowH, selected = fn(row), onClick = fn(row), sortKey, sortDir ("asc"|"desc"), onSort = fn(key),
---         empty = text, footer = text }
function AP.table(id, x, y, w, h, cols, rows, opts)
    opts = opts or {}
    local rowH = opts.rowH or S(42)
    local headH = S(32)
    local fixed, flex = 0, 0
    for _, c in ipairs(cols) do
        if c.w then fixed = fixed + c.w else flex = flex + 1 end
    end
    local flexW = flex > 0 and math.max(S(60), (w - fixed) / flex) or 0

    -- header
    local cx = x
    for _, c in ipairs(cols) do
        local cw = c.w or flexW
        local label = c.label:upper()
        if opts.sortKey == c.key then label = label .. (opts.sortDir == "asc" and "  ^" or "  v") end
        AP.text(label, cx + S(10), y, cw - S(14), headH, opts.sortKey == c.key and C.head or C.off, 0.75, "default-bold", c.align or "left")
        if c.sort and opts.onSort then AP.area(cx, y, cw, headH, function() opts.onSort(c.key) end) end
        cx = cx + cw
    end

    local ly = y + headH + S(4)
    local footH = opts.footer and S(28) or 0
    local visible = math.max(1, math.floor((y + h - footH - ly) / rowH))
    local first = math.max(0, math.min(AP.scroll[id] or 0, #rows - visible))
    AP.scroll[id] = first
    AP.scrollArea(x, ly, w, visible * rowH, function(dir) AP.scroll[id] = (AP.scroll[id] or 0) + dir * 3 end)

    if #rows == 0 then
        AP.text(opts.empty or L("v_admin.page.no_rows"), x + S(10), ly, w, S(40), C.dim, 0.95)
    end
    for i = 1, visible do
        local row = rows[first + i]
        if not row then break end
        local ry = ly + (i - 1) * rowH
        local rh = rowH - S(4)
        local sel = opts.selected and opts.selected(row)
        dxDrawRectangle(x, ry, w, rh, sel and C.rowSel or (AP.hovered(x, ry, w, rh) and C.rowHot or C.row))
        if sel then dxDrawRectangle(x, ry, S(3), rh, C.head) end
        cx = x
        for _, c in ipairs(cols) do
            local cw = c.w or flexW
            local txt = c.text and c.text(row) or row[c.key]
            if txt == nil or txt == false then txt = "-" end
            AP.text(tostring(txt), cx + S(10), ry, cw - S(14), rh, c.color and c.color(row) or C.text, 0.9,
                c.bold and "default-bold" or "default", c.align or "left")
            cx = cx + cw
        end
        if opts.onClick then AP.area(x, ry, w, rh, function() opts.onClick(row) end) end
    end
    if opts.footer then
        AP.text(opts.footer, x, y + h - footH, w, footH, C.dim, 0.8, "default", "right")
    elseif #rows > visible then
        AP.text(L("v_admin.commands.of_mouse_wheel", { scroll = first + 1, visible = math.min(#rows, first + visible), list = #rows }),
            x, ly + visible * rowH, w, S(24), C.off, 0.75, "default", "right")
    end
end

--------------------------------------------------------------------------------
-- text fields
--------------------------------------------------------------------------------

function AP.setFocus(id)
    if AP.focus == id then return end
    if AP.focus and AP.fields[AP.focus] then AP.fields[AP.focus].anchor = nil end
    AP.focus = id
    setElementData(localPlayer, "textInputOpen", id and true or false, false)
end

local function getField(id, opts)
    local f = AP.fields[id]
    if not f then
        f = TextField.new({ max = opts and opts.max or 64, multiline = opts and opts.multiline })
        AP.fields[id] = f
    end
    return f
end

function AP.fieldText(id)
    local f = AP.fields[id]
    return f and f:getText() or ""
end

function AP.setField(id, text)
    getField(id):setText(text)
end

local function digitsOnly(ch) return ch:match("^%d$") ~= nil end

-- opts: { placeholder, max, numeric, multiline, onEnter, readonly }
function AP.field(id, x, y, w, h, opts)
    opts = opts or {}
    local f = getField(id, opts)
    f.max = opts.max or f.max
    f.multiline = opts.multiline == true
    f.filter = opts.numeric and digitsOnly or nil
    f.onEnter, f.readonly = opts.onEnter, opts.readonly

    local focused = AP.focus == id
    dxDrawRectangle(x, y, w, h, focused and C.accent or C.btn)
    dxDrawRectangle(x + S(2), y + S(2), w - S(4), h - S(4), C.field)

    local pad = S(10)
    local style = { scale = F(0.95), font = "default", color = C.text, caret = C.text, sel = C.sel }
    local tx, ty, tw, th = x + pad, y, w - pad * 2 - S(6), h
    if f.multiline then ty, th = y + S(8), h - S(16) end
    f:draw(tx, ty, tw, th, focused, style)
    if f:getText() == "" and not focused then
        AP.text(opts.placeholder or "", tx, ty, tw, f.multiline and S(30) or th, C.off, 0.95, "default", "left",
            f.multiline and "top" or "center")
    end
    AP.area(x, y, w, h, function(mx, my)
        AP.setFocus(id)
        f:clickAt(mx, my, getKeyState("lshift") or getKeyState("rshift"))
        drag = { id = id, x = mx, y = my }
    end)
    if f.multiline then AP.scrollArea(x, y, w, h, function(dir) f:scrollBy(dir * 3) end) end
end

addEventHandler("onClientCharacter", root, function(ch)
    if not AP.open or not AP.focus then return end
    local f = AP.fields[AP.focus]
    if not f or f.readonly then return end
    f:insert(ch)
end)

addEventHandler("onClientPaste", root, function(text)
    if not AP.open or not AP.focus then return end
    local f = AP.fields[AP.focus]
    if not f or f.readonly then return end
    f:insert(text)
end)

--------------------------------------------------------------------------------
-- dropdown
--------------------------------------------------------------------------------

-- items: { { label = "...", fn = function, disabled = bool, active = bool } }
function AP.openDropdown(x, y, w, items)
    AP.dropdown = { x = x, y = y, w = w, items = items }
end

local function drawDropdown()
    local d = AP.dropdown
    AP.dropRect = nil
    if not d then return end
    local ih = S(44)
    local h = #d.items * ih + S(8)
    local sw, sh = guiGetScreenSize()
    local y = d.y
    if y + h > sh - S(10) then y = sh - S(10) - h end
    AP.dropRect = { x = d.x, y = y, w = d.w, h = h }

    dxDrawRectangle(d.x + S(4), y + S(4), d.w, h, C.shadow, true)
    dxDrawRectangle(d.x, y, d.w, h, C.side, true)
    dxDrawRectangle(d.x, y, d.w, S(3), C.accent, true)
    for i, it in ipairs(d.items) do
        local style = it.disabled and "off" or (it.active and "active" or nil)
        AP.button(d.x + S(4), y + S(6) + (i - 1) * ih, d.w - S(8), ih - S(4), it.label, function()
            AP.dropdown = nil
            it.fn()
        end, style, nil, "dropdown")
    end
end

--------------------------------------------------------------------------------
-- pages
--------------------------------------------------------------------------------

-- def: { id, category, label = string|function, perm, order, draw(x, y, w, h),
--        onShow(arg), onClose(), onRefresh(), badge() -> number|nil, badgeHot() -> bool }
function AP.addPage(def)
    def.category = def.category or "players"
    AP.pages[#AP.pages + 1] = def
    table.sort(AP.pages, function(a, b) return (a.order or 0) < (b.order or 0) end)
end
AP.addTab = AP.addPage

local function getPage(id)
    for _, p in ipairs(AP.pages) do
        if p.id == id then return p end
    end
end
AP.getPage = getPage

local function labelOf(p)
    return type(p.label) == "function" and p.label() or p.label
end

function AP.setPage(id, arg)
    local p = getPage(id)
    if not p or not AP.can(p.perm) then return end
    AP.page = id
    AP.dropdown = nil
    AP.setFocus(nil)
    if p.onShow then p.onShow(arg) end
end
AP.setTab = AP.setPage

--------------------------------------------------------------------------------
-- window
--------------------------------------------------------------------------------

local function myName()
    return (getPlayerName(localPlayer):gsub("#%x%x%x%x%x%x", ""))
end

local function drawSidebar(sw, sh)
    local W = S(ADMIN.panel.sideWidth or 300)
    dxDrawRectangle(0, 0, W, sh, C.side)
    dxDrawRectangle(W - S(1), 0, S(1), sh, C.line)

    local pad = S(24)
    AP.text(L("v_admin.page.title"), pad, S(16), W - pad * 2, S(36), C.text, 1.35, "default-bold")
    AP.text(myName() .. "  ·  " .. AP.rankName(AP.myLevel) .. " (" .. AP.myLevel .. ")", pad, S(52), W - pad * 2, S(24),
        C.gold, 0.8, "default-bold")
    dxDrawRectangle(0, S(88), W, S(1), C.line)

    local y = S(96)
    local itemH = S(40)
    for _, cat in ipairs(ADMIN.categories) do
        local any = false
        for _, p in ipairs(AP.pages) do
            if p.category == cat.id then
                if not any then
                    any = true
                    y = y + S(10)
                    AP.text(cat.label:upper(), pad, y, W - pad * 2, S(24), C.cat, 0.72, "default-bold")
                    y = y + S(26)
                end
                local allowed = AP.can(p.perm)
                local on = AP.page == p.id
                local hot = allowed and AP.hovered(0, y, W, itemH)
                if on then
                    dxDrawRectangle(0, y, W - S(1), itemH, C.sideSel)
                    dxDrawRectangle(0, y, S(3), itemH, C.head)
                elseif hot then
                    dxDrawRectangle(0, y, W - S(1), itemH, C.rowHot)
                end
                local label = labelOf(p)
                if not allowed then label = label .. "  " .. L("v_admin.page.locked_short", { level = AP.permLevel(p.perm) }) end
                AP.text(label, pad, y, W - pad * 2, itemH, on and C.text or (allowed and C.dim or C.off), 0.98,
                    on and "default-bold" or "default")
                local n = p.badge and p.badge()
                if n and n ~= 0 and n ~= "" then
                    local bt = tostring(n)
                    local bw = L.width(bt, F(0.72), "default-bold") + S(16)
                    local hotBadge = p.badgeHot and p.badgeHot()
                    dxDrawRectangle(W - pad - bw, y + (itemH - S(22)) / 2, bw, S(22), hotBadge and C.badgeHot or C.badge)
                    AP.text(bt, W - pad - bw, y, bw, itemH, C.text, 0.72, "default-bold", "center")
                end
                if allowed then AP.area(0, y, W, itemH, function() AP.setPage(p.id) end) end
                y = y + itemH
            end
        end
    end

    local t = getRealTime()
    AP.text(("%02d:%02d"):format(t.hour, t.minute) .. "   ·   " .. L("v_admin.page.close_hint"), pad, sh - S(40), W - pad * 2, S(30),
        C.off, 0.75)
    return W
end

local function drawTopBar(x, sw)
    local h = S(64)
    dxDrawRectangle(x, 0, sw - x, h, C.top)
    dxDrawRectangle(x, h - S(1), sw - x, S(1), C.line)
    local p = getPage(AP.page)
    local title = p and labelOf(p) or ""
    AP.text(title, x + S(28), 0, S(500), h, C.text, 1.3, "default-bold")
    local tw = L.width(title, F(1.3), "default-bold")
    for _, cat in ipairs(ADMIN.categories) do
        if p and cat.id == p.category then
            AP.text(cat.label .. "  ›  " .. title, x + S(28) + tw + S(18), 0, S(500), h, C.dim, 0.8)
        end
    end

    -- counters + close
    local closeW = S(40)
    AP.button(sw - S(20) - closeW, (h - closeW) / 2, closeW, closeW, "X", AP.close, "danger")
    local guests = 0
    for _, pl in ipairs(AP.players) do if not pl.logged then guests = guests + 1 end end
    local pill = L("v_admin.page.online_pill", { n = #AP.players, guests = guests })
    local pw = L.width(pill, F(0.8), "default-bold") + S(24)
    local px = sw - S(30) - closeW - pw
    dxDrawRectangle(px, (h - S(36)) / 2, pw, S(36), C.row)
    AP.text(pill, px, 0, pw, h, C.dim, 0.8, "default-bold", "center")
    return h
end

local function drawPanel()
    if not AP.open then return end
    buttons, scrolls = {}, {}

    if drag then
        local f = AP.fields[drag.id]
        if f and getKeyState("mouse1") and isCursorShowing() then
            local mx, my = AP.cursor()
            if math.abs(mx - drag.x) + math.abs(my - drag.y) > 3 then
                drag.moved = true
            end
            if drag.moved then f:dragTo(mx, my) end
        else
            drag = nil
        end
    end

    local sw, sh = guiGetScreenSize()
    dxDrawRectangle(0, 0, sw, sh, C.bg)
    local sideW = drawSidebar(sw, sh)
    local topH = drawTopBar(sideW, sw)

    local pad = S(24)
    local cx, cy = sideW + pad, topH + pad
    local cw, ch = sw - sideW - pad * 2, sh - topH - pad * 2
    local p = getPage(AP.page)
    if p and AP.can(p.perm) then p.draw(cx, cy, cw, ch) end

    drawDropdown()
end

-- publish the finished frame's click / scroll targets
local function publish()
    if AP.open then hitList, scrollList = buttons, scrolls end
end

function AP.close()
    if not AP.open then return end
    AP.open = false
    AP.dropdown, AP.dropRect = nil, nil
    AP.setFocus(nil)
    drag = nil
    buttons, hitList, scrolls, scrollList = {}, {}, {}, {}
    if isTimer(refreshTimer) then killTimer(refreshTimer) end
    refreshTimer = nil
    removeEventHandler("onClientRender", root, drawPanel)
    removeEventHandler("onClientRender", root, publish)
    setElementData(localPlayer, "adminPanelOpen", false, false)
    guiSetInputMode("allow_binds")
    showCursor(false)
    uicore:toggleMoveControls(true)
    for _, p in ipairs(AP.pages) do
        if p.onClose then p.onClose() end
    end
end

local function openPanel(page, arg)
    local _, sh = guiGetScreenSize()
    AP.scale = math.max(0.6, sh / 1080)
    AP.open = true
    addEventHandler("onClientRender", root, drawPanel)
    addEventHandler("onClientRender", root, publish, false, "low-10")
    setElementData(localPlayer, "adminPanelOpen", true, false)
    guiSetInputMode("no_binds")     -- every bindKey of every resource is off while open
    showCursor(true)
    uicore:toggleMoveControls(false)
    refreshTimer = setTimer(function()
        if not AP.open then return end
        triggerServerEvent(E.panelRequest, resourceRoot, true)
        local p = getPage(AP.page)
        if p and p.onRefresh then p.onRefresh() end
    end, ADMIN.panel.refresh, 0)
    AP.page = "dashboard"
    AP.setPage(page or "dashboard", arg)
end

addEvent(E.panelData, true)
addEventHandler(E.panelData, resourceRoot, function(players, myLevel, isRefresh, page, arg)
    if not players then return AP.close() end
    AP.players = players
    AP.myLevel = myLevel
    if AP.open then
        if page then AP.setPage(page, arg) end
        return
    end
    if not isRefresh then openPanel(page, arg) end
end)

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function otherPanelOpen()
    for _, key in ipairs({ "paused", "socialPanelOpen", "phoneOpen", "browserOpen", "showChatInput",
                           "reportPanelOpen", "textInputOpen", "interactionMenuOpen" }) do
        if getElementData(localPlayer, key) then return true end
    end
    return isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
end

bindKey(ADMIN.panel.key, "down", function()
    if AP.open then return end
    if (tonumber(getElementData(localPlayer, "admin_level")) or 0) < ADMIN.perms.panel then return end
    if otherPanelOpen() then return end
    triggerServerEvent(E.panelRequest, resourceRoot, false)
end)

local function wheel(dir)
    local mx, my = AP.cursor()
    for i = #scrollList, 1, -1 do
        local s = scrollList[i]
        if inRect(mx, my, s.x, s.y, s.w, s.h) then
            s.fn(dir)
            return
        end
    end
end

local function ctrlDown() return getKeyState("lctrl") or getKeyState("rctrl") end
local function shiftDown() return getKeyState("lshift") or getKeyState("rshift") end

addEventHandler("onClientKey", root, function(key, press)
    if not AP.open or not press then return end

    if key == "mouse_wheel_up" then return wheel(-1) end
    if key == "mouse_wheel_down" then return wheel(1) end

    if AP.focus then
        -- Typing: swallow every key (characters still arrive via onClientCharacter).
        -- Except Ctrl+V: MTA only fires onClientPaste for a "v" stroke that onClientKey
        -- did not cancel; keep GTA's V (camera) quiet for that one press instead
        if key == "v" and ctrlDown() then
            if isControlEnabled("change_camera") then
                toggleControl("change_camera", false)
                setTimer(toggleControl, 250, 1, "change_camera", true)
            end
            return
        end
        if key:find("^mouse") then return end
        cancelEvent()
        local f = AP.fields[AP.focus]
        if not f then return AP.setFocus(nil) end
        if key == "escape" or key == "tab" then
            AP.setFocus(nil)
        elseif (key == "enter" or key == "num_enter") and not f.multiline then
            if f.onEnter then f.onEnter(f:getText()) end
        elseif key == "a" and ctrlDown() then
            f:selectAll()
        elseif (key == "c" or key == "x") and ctrlDown() then
            local sel = f:getSelected()
            if sel then
                setClipboard(sel)
                if key == "x" and not f.readonly then f:deleteSelection() end
            end
        elseif f.readonly then
            if key:find("^arrow_") or key == "home" or key == "end" then f:key(key, shiftDown()) end
        else
            f:key(key, shiftDown())
        end
        return
    end

    if key == "escape" then
        cancelEvent()
        if AP.dropdown then AP.dropdown = nil else AP.close() end
    elseif key == ADMIN.panel.key then
        -- the O bind is off while the panel is open (no_binds), so close here
        cancelEvent()
        AP.close()
    end
end)

addEventHandler("onClientClick", root, function(btn, state)
    if not AP.open or btn ~= "left" or state ~= "down" then return end
    local mx, my = AP.cursor()

    if AP.dropdown then
        for i = #hitList, 1, -1 do
            local b = hitList[i]
            if b.layer == "dropdown" and inRect(mx, my, b.x, b.y, b.w, b.h) then
                return b.fn(mx, my)
            end
        end
        AP.dropdown = nil
        return
    end

    AP.setFocus(nil)
    for i = #hitList, 1, -1 do
        local b = hitList[i]
        if inRect(mx, my, b.x, b.y, b.w, b.h) then
            return b.fn(mx, my)
        end
    end
end)

addEventHandler("onClientDoubleClick", root, function(btn, absX, absY)
    if not AP.open or btn ~= "left" or not AP.focus then return end
    local f = AP.fields[AP.focus]
    local r = f and f.drawRect
    if r and inRect(absX, absY, r.x, r.y, r.w, r.h) then
        drag = nil
        f:selectWordAt(absX, absY)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if AP.open then AP.close() end
end)
