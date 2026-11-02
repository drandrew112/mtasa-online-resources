if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Donate panel (F3 or /donate). Fully DX drawn, same look as the help panel.
--
--   left:  how to support the server: reward (base multiplier, the running
--          event in its own banner), the payment link (Copy button), the
--          account name to write in the comment (Copy button), warning
--   right: the player's payments (v_admin payments table): pending,
--          approved (multiplier, bank money, approved by), rejected (reason)
--
-- Data: server/donate.lua ("ui_help:donateRequest" -> "ui_help:donateData").
-- While open: cursor shown, guiSetInputMode "no_binds", every keyboard
-- onClientKey cancelled, local element data "donateOpen" = true.

local sw, sh = guiGetScreenSize()
local SC = math.min(sw / 1920, sh / 1080)
local function S(v) return v * SC end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local FADE_MS = 140
local COPIED_MS = 2200
local WHEEL_STEP = 70

local COL = {
    dim      = { 0, 0, 0, 150 },
    shadow   = { 0, 0, 0, 80 },
    head     = { 12, 14, 18, 252 },
    side     = { 15, 17, 21, 255 },
    page     = { 20, 22, 28, 255 },
    field    = { 29, 32, 40, 255 },
    line     = { 52, 57, 68, 255 },
    accent   = { 0, 170, 220, 255 },
    text     = { 222, 226, 233, 255 },
    h        = { 245, 247, 250, 255 },
    muted    = { 128, 136, 150, 255 },
    warn     = { 235, 165, 50, 255 },
    good     = { 90, 200, 120, 255 },
    bad      = { 230, 90, 90, 255 },
    btn      = { 36, 40, 49, 255 },
    btnHover = { 48, 53, 64, 255 },
    noteBg   = { 0, 170, 220, 22 },
    warnBg   = { 235, 165, 50, 22 },
    goodBg   = { 90, 200, 120, 26 },
    row      = { 26, 29, 36, 255 },
    scroll   = { 255, 255, 255, 40 },
    close    = { 230, 75, 75, 255 },
}
local STATUS_COL = { pending = "warn", approved = "good", rejected = "bad" }

local F, G
local P = {
    open = false, alpha = 0, openTick = 0, lastTick = 0, prevMode = "allow_binds",
    data = nil,          -- server reply, nil = loading
    event = nil,         -- running event (pushed by the server too), false = none
    copied = nil,        -- { what, tick }
    scroll = 0, target = 0,  -- history list
    lscroll = 0,             -- left column, only when it does not fit
    hits = {},
    layout = nil, key = nil,
}
local A = 1
local mx, my = -1, -1

local function col(c, a) return tocolor(c[1], c[2], c[3], c[4] * A * (a or 1)) end
local function rect(x, y, w, h, c, a) dxDrawRectangle(x, y, w, h, col(c, a)) end
local function text(s, x, y, w, h, c, font, ax, ay, clip)
    dxDrawText(s, x, y, x + w, y + h, col(c), font.s, font.f, ax or "left", ay or "center", clip or false)
end
local function within(x, y, w, h) return mx >= x and mx < x + w and my >= y and my < y + h end
local function hit(x, y, w, h, fn) P.hits[#P.hits + 1] = { x, y, w, h, fn } end

local function fmtDate(ts)
    if not ts or ts <= 0 then return "-" end
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

local function mkFont(file, size, bold)
    local f = dxCreateFont(file, max(7, floor(size * SC + 0.5)), false, "cleartype")
    local font = f and { f = f, s = 1 } or { f = bold and "default-bold" or "default", s = size / 9 * SC }
    font.h = dxGetFontHeight(font.s, font.f)
    return font
end

local function buildFonts()
    if F then return end
    F = {
        head   = mkFont("files/RobotoB.ttf", 15, true),
        big    = mkFont("files/RobotoB.ttf", 30, true),
        h2     = mkFont("files/RobotoB.ttf", 13, true),
        body   = mkFont("files/Roboto.ttf", 11),
        bodyB  = mkFont("files/RobotoB.ttf", 11, true),
        small  = mkFont("files/Roboto.ttf", 9.5),
        smallB = mkFont("files/RobotoB.ttf", 9.5, true),
    }
end

local function buildGeometry()
    G = {}
    G.w = floor(min(S(1240), sw - 40))
    G.h = floor(min(S(880), sh - 40))
    G.x, G.y = floor((sw - G.w) / 2), floor((sh - G.h) / 2)
    G.headH = floor(S(60))
    G.pad = floor(S(28))
    G.leftW = floor(G.w * 0.52)
    G.left = { x = G.x + G.pad, y = G.y + G.headH + G.pad, w = G.leftW - G.pad * 2 }
    G.left.h = G.y + G.h - G.pad - G.left.y
    local rx = G.x + G.leftW + 1
    G.right = { x = rx + G.pad, y = G.y + G.headH + G.pad, w = G.x + G.w - rx - G.pad * 2 }
    G.list = { x = G.right.x, y = G.right.y + floor(S(44)), w = G.right.w }
    G.list.h = G.y + G.h - G.pad - G.list.y
end

local function copy(what, value)
    if setClipboard(value) then P.copied = { what = what, tick = getTickCount() } end
end

local function copiedNow(what)
    return P.copied and P.copied.what == what and getTickCount() - P.copied.tick < COPIED_MS
end

local function button(label, x, y, h, font, fn, primary)
    local w = L.width(label, font.s, font.f) + S(30)
    local hov = within(x, y, w, h)
    if primary then
        rect(x, y, w, h, COL.accent, hov and 1 or 0.85)
        text(label, x, y, w, h, COL.h, font, "center")
    else
        rect(x, y, w, h, hov and COL.btnHover or COL.btn)
        text(label, x, y, w, h, COL.text, font, "center")
    end
    hit(x, y, w, h, fn)
    return w
end

--------------------------------------------------------------------------------
-- left side
--------------------------------------------------------------------------------

local function wrapped(str, w, font) return L.wrap(str, w, font.s, font.f) end

local function account()
    return P.data and P.data.account or nil
end

-- layout of the left column (cached per language + data); every item is
-- { k, y, h, ... }, drawn by drawLeft
local function buildLeft()
    local key = L.lang() .. "|" .. tostring(P.data) .. "|" .. tostring(P.event and P.event.to or false)
    if P.key == key then return end
    P.key = key
    local b = G.left
    local items, y = {}, 0
    local function add(it) it.y = y; items[#items + 1] = it; y = y + it.h end
    local function para(str, font, c, gap)
        local lines = wrapped(str, b.w, font)
        add({ k = "text", lines = lines, font = font, c = c, lh = floor(font.h * 1.25), h = floor(font.h * 1.25) * #lines })
        y = y + floor(S(gap or 14))
    end

    para(L("ui_help.donate.intro"), F.body, COL.text, 18)

    -- reward
    local base = P.data and P.data.base or DONATE.baseMultiplier
    local rw = b.w - floor(S(130))
    local rlines = wrapped(L("ui_help.donate.reward_text", { mult = base }), rw, F.body)
    add({ k = "reward", mult = base, lines = rlines,
          h = max(floor(S(86)), floor(S(40)) + F.h2.h + #rlines * floor(F.body.h * 1.2)) })
    y = y + floor(S(10))
    if P.event then
        local e = P.event
        local str = L("ui_help.donate.event_text", { mult = e.multiplier, time = fmtDate(e.to) })
        local lines = wrapped(str, b.w - floor(S(36)), F.body)
        add({ k = "event", e = e, lines = lines,
              h = floor(S(30)) + F.bodyB.h + (e.label ~= "" and F.body.h + floor(S(4)) or 0) + #lines * floor(F.body.h * 1.2) })
        y = y + floor(S(10))
    end
    y = y + floor(S(10))

    -- steps
    local function step(n, str)
        local lines = wrapped(str, b.w - floor(S(40)), F.bodyB)
        add({ k = "step", n = n, lines = lines, lh = floor(F.bodyB.h * 1.25), h = floor(F.bodyB.h * 1.25) * #lines + floor(S(8)) })
    end
    step(1, L("ui_help.donate.step_link"))
    add({ k = "copybox", what = "link", value = DONATE.url, h = floor(S(44)) })
    y = y + floor(S(16))
    step(2, L("ui_help.donate.step_method"))
    y = y + floor(S(8))
    step(3, L("ui_help.donate.step_comment"))
    if account() then
        add({ k = "copybox", what = "account", value = account(), h = floor(S(44)) })
    else
        para(L("ui_help.donate.no_account"), F.small, COL.muted, 0)
    end
    y = y + floor(S(16))

    local wl = wrapped(L("ui_help.donate.warning"), b.w - floor(S(36)), F.body)
    add({ k = "warn", lines = wl, h = floor(S(26)) + F.smallB.h + floor(S(6)) + #wl * floor(F.body.h * 1.2) })
    y = y + floor(S(16))
    step(4, L("ui_help.donate.step_wait", { mult = base }))

    P.layout = { items = items, h = y }
end

local function drawLeft()
    local b = G.left
    local x0, y0 = b.x, b.y - P.lscroll
    for _, it in ipairs(P.layout.items) do
        local y = y0 + it.y
        if y < b.y - 1 or y + it.h > b.y + b.h + 1 then
            -- outside the column (only whole items are drawn)
        elseif it.k == "text" then
            for i, ln in ipairs(it.lines) do text(ln, x0, y + (i - 1) * it.lh, b.w, it.lh, it.c, it.font) end
        elseif it.k == "reward" then
            rect(x0, y, b.w, it.h, COL.goodBg)
            rect(x0, y, floor(S(3)), it.h, COL.good)
            text("×" .. it.mult, x0, y, floor(S(120)), it.h, COL.good, F.big, "center")
            local tx = x0 + floor(S(120))
            text(L("ui_help.donate.reward_title"), tx, y + S(16), b.w, F.h2.h, COL.h, F.h2, "left", "top")
            local lh = floor(F.body.h * 1.2)
            for i, ln in ipairs(it.lines) do
                text(ln, tx, y + S(22) + F.h2.h + (i - 1) * lh, b.w - S(130), lh, COL.text, F.body)
            end
        elseif it.k == "event" then
            rect(x0, y, b.w, it.h, COL.warnBg)
            rect(x0, y, floor(S(3)), it.h, COL.warn)
            local tx, ty = x0 + S(18), y + S(14)
            text(L("ui_help.donate.event_title", { mult = it.e.multiplier }), tx, ty, b.w, F.bodyB.h, COL.warn, F.bodyB, "left", "top")
            ty = ty + F.bodyB.h + S(4)
            if it.e.label ~= "" then
                text(it.e.label, tx, ty, b.w - S(36), F.body.h, COL.h, F.body, "left", "top", true)
                ty = ty + F.body.h + S(4)
            end
            local lh = floor(F.body.h * 1.2)
            for i, ln in ipairs(it.lines) do text(ln, tx, ty + (i - 1) * lh, b.w - S(36), lh, COL.text, F.body) end
        elseif it.k == "step" then
            local d = floor(S(26))
            dxDrawCircle(x0 + d / 2, y + it.lh / 2, d / 2, 0, 360, col(COL.accent), col(COL.accent), 24)
            text(tostring(it.n), x0, y + it.lh / 2 - d / 2, d, d, COL.h, F.smallB, "center")
            for i, ln in ipairs(it.lines) do
                text(ln, x0 + S(40), y + (i - 1) * it.lh, b.w - S(40), it.lh, COL.h, F.bodyB)
            end
        elseif it.k == "copybox" then
            local bx = x0 + S(40)
            local done = copiedNow(it.what)
            local label = done and L("ui_help.donate.copied") or L("ui_help.donate.copy")
            local bw = max(L.width(L("ui_help.donate.copy"), F.bodyB.s, F.bodyB.f), L.width(L("ui_help.donate.copied"), F.bodyB.s, F.bodyB.f)) + S(30)
            local fw = b.w - S(40) - bw - S(8)
            rect(bx, y, fw, it.h, COL.field)
            rect(bx, y + it.h - floor(S(2)), fw, floor(S(2)), done and COL.good or COL.accent)
            text(L.fit(it.value, fw - S(24), F.bodyB.s, F.bodyB.f), bx + S(12), y, fw - S(24), it.h, COL.h, F.bodyB)
            local value, what = it.value, it.what
            hit(bx, y, fw, it.h, function() copy(what, value) end)
            local cx = bx + fw + S(8)
            local hov = within(cx, y, bw, it.h)
            rect(cx, y, bw, it.h, done and COL.good or COL.accent, (hov or done) and 1 or 0.85)
            text(label, cx, y, bw, it.h, COL.h, F.bodyB, "center")
            hit(cx, y, bw, it.h, function() copy(what, value) end)
        elseif it.k == "warn" then
            rect(x0, y, b.w, it.h, COL.warnBg)
            rect(x0, y, floor(S(3)), it.h, COL.warn)
            text(L("ui_help.block.warning"), x0 + S(18), y + S(12), b.w, F.smallB.h, COL.warn, F.smallB, "left", "top")
            local lh = floor(F.body.h * 1.2)
            local ty = y + S(12) + F.smallB.h + S(6)
            for i, ln in ipairs(it.lines) do text(ln, x0 + S(18), ty + (i - 1) * lh, b.w - S(36), lh, COL.text, F.body) end
        end
    end
    local total = P.layout.h
    if total > b.h then
        local th = max(S(36), b.h * b.h / total)
        rect(b.x + b.w + S(12), b.y + (b.h - th) * (P.lscroll / (total - b.h)), floor(S(4)), th, COL.scroll)
    end
end

--------------------------------------------------------------------------------
-- right side: history
--------------------------------------------------------------------------------

local ROW_H = 96

local function history() return P.data and P.data.history or nil end

local function listH()
    local h = history()
    return h and #h * floor(S(ROW_H + 8)) or 0
end

local function drawRight()
    local r, v = G.right, G.list
    text(L("ui_help.donate.history"), r.x, r.y, r.w, S(30), COL.h, F.h2, "left", "top")
    local refresh = L("ui_help.donate.refresh")
    local bw = L.width(refresh, F.small.s, F.small.f) + S(30)
    button(refresh, r.x + r.w - bw, r.y - S(4), S(30), F.small, function() DonatePanel_request() end)

    local msg
    if not P.data then msg = L("ui_help.donate.loading")
    elseif not P.data.account then msg = L("ui_help.donate.no_account")
    elseif P.data.error then msg = L("ui_help.donate.history_error")
    elseif #P.data.history == 0 then msg = L("ui_help.donate.history_empty") end
    if msg then
        dxDrawText(msg, v.x, v.y, v.x + v.w, v.y + S(120), col(COL.muted), F.body.s, F.body.f, "center", "center", false, true)
        return
    end

    local rowH, gap = floor(S(ROW_H)), floor(S(8))
    for i, p in ipairs(P.data.history) do
        local y = v.y + (i - 1) * (rowH + gap) - P.scroll
        if y >= v.y - 1 and y + rowH <= v.y + v.h + 1 then
            local sc = COL[STATUS_COL[p.status] or "muted"]
            rect(v.x, y, v.w, rowH, COL.row)
            rect(v.x, y, floor(S(3)), rowH, sc)
            local px, pw = v.x + S(18), v.w - S(36)
            local l1 = y + S(12)
            text(fmtDate(p.created) .. "   #" .. p.id, px, l1, pw, F.small.h, COL.muted, F.small, "left", "top")
            text(L.upper(L("ui_help.donate.status_" .. p.status)), px, l1, pw, F.small.h, sc, F.smallB, "right", "top")

            local l2 = l1 + F.small.h + S(8)
            local paid = L("ui_help.donate.points", { n = L.int(p.amount) })
            if p.status == "rejected" then
                text(paid, px, l2, pw, F.bodyB.h, COL.h, F.bodyB, "left", "top")
            else
                local m = p.multiplier > (P.data.base or DONATE.baseMultiplier)
                local s = paid .. "  ×" .. p.multiplier .. "  =  "
                text(s, px, l2, pw, F.bodyB.h, COL.h, F.bodyB, "left", "top")
                local sx = px + L.width(s, F.bodyB.s, F.bodyB.f)
                text(L.money(p.bankMoney), sx, l2, pw, F.bodyB.h, p.status == "approved" and COL.good or COL.text, F.bodyB, "left", "top")
                if m then
                    local ex = sx + L.width(L.money(p.bankMoney), F.bodyB.s, F.bodyB.f) + S(10)
                    text(L("ui_help.donate.event_tag"), ex, l2, pw, F.bodyB.h, COL.warn, F.smallB, "left", "center")
                end
            end

            local l3 = l2 + F.bodyB.h + S(8)
            local note
            if p.status == "approved" then
                note = L("ui_help.donate.approved_by", { admin = p.reviewedBy ~= "" and p.reviewedBy or "-", time = fmtDate(p.reviewedAt) })
            elseif p.status == "pending" then
                note = L("ui_help.donate.pending_note")
            else
                note = L("ui_help.donate.rejected_note", { reason = p.reason ~= "" and p.reason or "-" })
            end
            text(L.fit(note, pw, F.small.s, F.small.f), px, l3, pw, F.small.h, p.status == "rejected" and COL.bad or COL.muted, F.small, "left", "top")
        end
    end

    -- scrollbar
    local total = listH()
    if total > v.h then
        local tw = floor(S(4))
        local th = max(S(36), v.h * v.h / total)
        local ty = v.y + (v.h - th) * (P.scroll / (total - v.h))
        rect(v.x + v.w + S(10), ty, tw, th, COL.scroll)
    end
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

local close -- forward

local function drawHeader()
    local x, y, w, h = G.x, G.y, G.w, G.headH
    rect(x, y, w, h, COL.head)
    rect(x, y + h, w, 1, COL.line)
    local tx = x + G.pad
    rect(tx, y + h / 2 - S(11), S(3), S(22), COL.accent)
    text(L("ui_help.donate.title"), tx + S(14), y, w, h, COL.h, F.head)

    local cs = floor(S(34))
    local cx, cy = x + w - S(16) - cs, y + (h - cs) / 2
    local hov = within(cx, cy, cs, cs)
    rect(cx, cy, cs, cs, hov and COL.close or COL.btn)
    local m = S(11)
    dxDrawLine(cx + m, cy + m, cx + cs - m, cy + cs - m, col(COL.h), S(2))
    dxDrawLine(cx + cs - m, cy + m, cx + m, cy + cs - m, col(COL.h), S(2))
    hit(cx, cy, cs, cs, function() close() end)
    text(L("ui_help.donate.close_hint", { key = DONATE.key }), x, y, cx - S(14) - x, h, COL.muted, F.small, "right")
end

local function onRender()
    local now = getTickCount()
    local dt = min(100, now - P.lastTick)
    P.lastTick = now
    P.alpha = min(1, (now - P.openTick) / FADE_MS)
    A = P.alpha

    local cx, cy = getCursorPosition()
    if cx then mx, my = cx * sw, cy * sh else mx, my = -1, -1 end

    buildLeft()
    local maxS = max(0, listH() - G.list.h)
    P.target = max(0, min(maxS, P.target))
    local d = P.target - P.scroll
    if abs(d) < 0.5 then P.scroll = P.target else P.scroll = P.scroll + d * min(1, dt / 1000 * 16) end

    P.hits = {}
    rect(0, 0, sw, sh, COL.dim)
    rect(G.x - S(6), G.y - S(6), G.w + S(12), G.h + S(12), COL.shadow)
    rect(G.x, G.y, G.leftW, G.h, COL.page)
    rect(G.x + G.leftW, G.y, G.w - G.leftW, G.h, COL.side)
    rect(G.x + G.leftW, G.y + G.headH, 1, G.h - G.headH, COL.line)
    drawHeader()
    drawLeft()
    drawRight()
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function onKey(button, press)
    cancelEvent()
    if button == "mouse_wheel_up" or button == "mouse_wheel_down" then
        local dir = button == "mouse_wheel_up" and -1 or 1
        if within(G.list.x, G.list.y, G.list.w, G.list.h) then
            P.target = P.target + dir * S(WHEEL_STEP)
        elseif P.layout and within(G.x, G.y + G.headH, G.leftW, G.h - G.headH) then
            P.lscroll = max(0, min(max(0, P.layout.h - G.left.h), P.lscroll + dir * S(WHEEL_STEP)))
        end
        return
    end
    if not press then return end
    if button == "mouse1" then
        for i = #P.hits, 1, -1 do
            local h = P.hits[i]
            if within(h[1], h[2], h[3], h[4]) then return h[5]() end
        end
        return
    end
    if button == "escape" then return close() end
    if button == DONATE.key and getTickCount() - P.openTick > 200 then return close() end
    if button == "c" and (getKeyState("lctrl") or getKeyState("rctrl")) then copy("link", DONATE.url) end
end

--------------------------------------------------------------------------------
-- data
--------------------------------------------------------------------------------

local lastRequest = 0
function DonatePanel_request()
    if getTickCount() - lastRequest < 2000 then return end
    lastRequest = getTickCount()
    triggerServerEvent("ui_help:donateRequest", resourceRoot)
end

addEvent("ui_help:donateData", true)
addEventHandler("ui_help:donateData", resourceRoot, function(data)
    if type(data) ~= "table" then return end
    if type(data.history) ~= "table" then data.history = {} end
    P.data = data
    P.event = data.event or false
end)

addEvent("ui_help:donateEvent", true)
addEventHandler("ui_help:donateEvent", resourceRoot, function(e)
    P.event = type(e) == "table" and e or false
    if P.open then lastRequest = 0 DonatePanel_request() end -- pending rows show the new multiplier
end)

addEvent("ui_help:donateNotify", true)
addEventHandler("ui_help:donateNotify", resourceRoot, function(msg)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(L("ui_help.donate.title"), tostring(msg))
    end
end)

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function blocked()
    if isMainMenuActive() or isConsoleActive() then return true end
    if getElementData(localPlayer, "textInputOpen") then return true end
    if getElementData(localPlayer, "chatTyping") then return true end
    if getElementData(localPlayer, "paused") then return true end
    if getElementData(localPlayer, "helpOpen") then return true end
    return false
end

function DonatePanel_open()
    if P.open then return true end
    if blocked() then return false end
    buildFonts()
    buildGeometry()
    P.open = true
    P.openTick, P.lastTick = getTickCount(), getTickCount()
    P.scroll, P.target, P.lscroll, P.key, P.copied = 0, 0, 0, nil, nil
    DonatePanel_request()

    P.prevMode = guiGetInputMode()
    guiSetInputMode("no_binds")
    showCursor(true)
    addEventHandler("onClientRender", root, onRender)
    addEventHandler("onClientKey", root, onKey, true, "high+100")
    setElementData(localPlayer, "donateOpen", true, false)
    return true
end

close = function()
    if not P.open then return false end
    P.open = false
    removeEventHandler("onClientRender", root, onRender)
    removeEventHandler("onClientKey", root, onKey)
    guiSetInputMode(P.prevMode or "allow_binds")
    showCursor(false)
    P.layout, P.key = nil, nil
    setElementData(localPlayer, "donateOpen", false, false)
    return true
end
DonatePanel_close = close

function DonatePanel_isOpen() return P.open end

function DonatePanel_toggle()
    if P.open then return close() end
    return DonatePanel_open()
end

bindKey(DONATE.key, "down", function() DonatePanel_toggle() end)
addCommandHandler("donate", function() DonatePanel_toggle() end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if P.open then close() end
end)
