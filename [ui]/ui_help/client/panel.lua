if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Help panel (F1 or /help). Fully DX drawn.
--
--   left:  search field + topic list (categories fold open / closed),
--          while searching: the results with a text snippet
--   right: the selected page (client/markup.lua), scrollable
--
-- Controls while open: typing = search, UP / DOWN + ENTER = pick from the
-- list, mouse wheel / PGUP / PGDN / HOME / END = scroll the page, BACKSPACE =
-- delete from the search, ESC = clear the search, then close, F1 = close,
-- mouse 4 or the Back button = previous page.
--
-- While it is open: cursor shown (GTA controls off), guiSetInputMode
-- "no_binds", every keyboard onClientKey is cancelled (except Ctrl+V, so
-- onClientPaste still fires), local element data "helpOpen" = true and the
-- event "ui_help:onClientHelpToggle" (open) is triggered on localPlayer.
-- Every handler is attached only while the panel is open.

local sw, sh = guiGetScreenSize()
local SC = math.min(sw / 1920, sh / 1080)
local function S(v) return v * SC end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local OPEN_KEY = "F1"
local MAX_QUERY = 48
local REPEAT_DELAY, REPEAT_RATE = 400, 35
local WHEEL_STEP = 100 -- base px per wheel tick
local FADE_MS = 140

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
    hover    = { 255, 255, 255, 12 },
    sel      = { 0, 170, 220, 34 },
    keySel   = { 255, 255, 255, 20 },
    btn      = { 36, 40, 49, 255 },
    btnHover = { 48, 53, 64, 255 },
    noteBg   = { 0, 170, 220, 22 },
    warnBg   = { 235, 165, 50, 22 },
    scroll   = { 255, 255, 255, 40 },
    scrollOn = { 255, 255, 255, 90 },
    close    = { 230, 75, 75, 255 },
}
-- colour codes used inside page text (same colours as COL text / h / accent)
local HEX = { text = "DEE2E9", h = "F5F7FA", strong = "00AADC", code = "F0C35A" }

local F -- fonts, created on first open
local G -- geometry, computed on open

local P = {
    open     = false,
    alpha    = 0,
    openTick = 0,
    lastTick = 0,
    prevMode = "allow_binds",
    query    = "",
    focus    = "search",  -- "search" | "ai": which field gets the typing
    results  = nil,       -- Search.run result while searching
    topic    = nil,       -- open topic id, nil = home
    history  = {},        -- previous topic ids (false = home)
    collapsed = {},       -- category id -> true
    rep      = nil,       -- held key auto-repeat { key, next }
    drag     = nil,       -- scrollbar drag { view, grab, start }
    hits     = {},        -- click areas of this frame
    side     = { scroll = 0, target = 0, rows = {}, h = 0, key = nil, sel = nil },
    page     = { scroll = 0, target = 0, layout = nil, key = nil },
    ai       = { scroll = 0, target = 0, items = {}, h = 0, key = nil },
}

local A = 1 -- alpha multiplier of the current draw pass
local mx, my = -1, -1

local function col(c, a)
    return tocolor(c[1], c[2], c[3], c[4] * A * (a or 1))
end

local function rect(x, y, w, h, c, a)
    dxDrawRectangle(x, y, w, h, col(c, a))
end

local function text(s, x, y, w, h, c, font, ax, ay, clip, cc)
    dxDrawText(s, x, y, x + w, y + h, col(c), font.s, font.f, ax or "left", ay or "center", clip or false, false, false, cc or false)
end

local function within(x, y, w, h)
    return mx >= x and mx < x + w and my >= y and my < y + h
end

local function hit(x, y, w, h, fn)
    P.hits[#P.hits + 1] = { x, y, w, h, fn }
end

--------------------------------------------------------------------------------
-- fonts / geometry
--------------------------------------------------------------------------------

local function mkFont(file, size, bold)
    local f = dxCreateFont(file, max(7, floor(size * SC + 0.5)), false, "cleartype")
    local font = f and { f = f, s = 1 } or { f = bold and "default-bold" or "default", s = size / 9 * SC }
    font.h = dxGetFontHeight(font.s, font.f)
    return font
end

local function buildFonts()
    if F then return end
    F = {
        title  = mkFont("files/RobotoB.ttf", 19, true),
        h1     = mkFont("files/RobotoB.ttf", 17, true),
        h2     = mkFont("files/RobotoB.ttf", 14, true),
        h3     = mkFont("files/RobotoB.ttf", 12, true),
        body   = mkFont("files/Roboto.ttf", 11),
        bodyB  = mkFont("files/RobotoB.ttf", 11, true),
        small  = mkFont("files/Roboto.ttf", 9.5),
        smallB = mkFont("files/RobotoB.ttf", 9.5, true),
        head   = mkFont("files/RobotoB.ttf", 15, true),
    }
end

local function buildGeometry()
    G = {}
    local aiW, gap = floor(S(500)), floor(S(10))
    G.w = floor(min(S(1080), sw - 40 - aiW - gap))
    G.h = floor(min(S(800), sh - 40))
    local left = floor((sw - (aiW + gap + G.w)) / 2)
    G.x = left + aiW + gap
    G.y = floor((sh - G.h) / 2)
    G.headH = floor(S(60))
    G.sideW = floor(S(340))
    G.pad = floor(S(16))
    G.search = { x = G.x + G.pad, y = G.y + G.headH + G.pad, w = G.sideW - G.pad * 2, h = floor(S(40)) }

    local listY = G.search.y + G.search.h + floor(S(10))
    G.list = { x = G.x, y = listY, w = G.sideW, h = G.y + G.h - listY - floor(S(6)),
               padX = 0, padY = floor(S(4)), bg = COL.side }

    -- AI assistant panel, left of the help panel
    local ai = { x = left, y = G.y, w = aiW, h = G.h }
    G.ai = ai
    local fieldH = floor(S(40))
    G.aiIn = { x = ai.x + G.pad, y = ai.y + ai.h - G.pad - floor(S(22)) - fieldH, h = fieldH }
    G.aiIn.w = ai.w - G.pad * 2
    local chatY = ai.y + G.headH + G.pad
    G.aiChat = { x = ai.x + G.pad, y = chatY, w = ai.w - G.pad * 2, h = G.aiIn.y - G.pad - chatY, padX = 0, padY = 0 }

    G.body = { x = G.x + G.sideW + 1, y = G.y + G.headH + 1, w = G.w - G.sideW - 1, h = G.h - G.headH - 1,
               padX = floor(S(40)), padY = floor(S(30)), bg = COL.page }
end

-- each scroll view draws into its own render target (clean clipping); when it
-- cannot be created only the rows / lines that fit completely are drawn
local function createTargets()
    for _, v in ipairs({ G.list, G.body }) do
        v.rt = dxCreateRenderTarget(v.w, v.h, false) or nil
    end
end

local function destroyTargets()
    if not G then return end
    for _, v in ipairs({ G.list, G.body }) do
        if v.rt and isElement(v.rt) then destroyElement(v.rt) end
        v.rt = nil
    end
end

--------------------------------------------------------------------------------
-- scroll views
--------------------------------------------------------------------------------

local function inView(v, top, h, scroll)
    local t = v.padY + top - scroll
    if v.rt then return t + h > 0 and t < v.h end
    return t >= 0 and t + h <= v.h
end

-- origin of content coordinate 0,0 in the current draw pass
local function beginView(v, scroll)
    if v.rt then
        dxSetRenderTarget(v.rt, true)
        A = 1
        dxDrawRectangle(0, 0, v.w, v.h, col(v.bg))
        return v.padX, v.padY - scroll
    end
    return v.x + v.padX, v.y + v.padY - scroll
end

local function endView(v)
    if v.rt then
        dxSetRenderTarget()
        A = P.alpha
        dxDrawImage(v.x, v.y, v.w, v.h, v.rt, 0, 0, 0, tocolor(255, 255, 255, 255 * A))
    end
end

-- screen rect of a content rect, clipped to the view (nil when hidden)
local function screenRect(v, x, y, w, h, scroll)
    local sx, sy = v.x + v.padX + x, v.y + v.padY + y - scroll
    local top, bottom = max(sy, v.y), min(sy + h, v.y + v.h)
    if bottom <= top then return nil end
    return sx, top, w, bottom - top
end

local function maxScroll(v, s, contentH)
    return max(0, v.padY * 2 + contentH - v.h)
end

local function scrollBy(s, v, contentH, dy)
    s.target = max(0, min(maxScroll(v, s, contentH), s.target + dy))
end

local function updateScroll(s, v, contentH, dt)
    s.target = max(0, min(maxScroll(v, s, contentH), s.target))
    local d = s.target - s.scroll
    if abs(d) < 0.5 then s.scroll = s.target else s.scroll = s.scroll + d * min(1, dt / 1000 * 16) end
end

local function drawScrollbar(v, s, contentH, name)
    local total = v.padY * 2 + contentH
    if total <= v.h then return end
    local tw = floor(S(4))
    local tx = v.x + v.w - tw - floor(S(5))
    local th = max(S(36), v.h * v.h / total)
    local ty = v.y + (v.h - th) * (s.scroll / maxScroll(v, s, contentH))
    local on = (P.drag and P.drag.name == name) or within(tx - S(6), v.y, tw + S(12), v.h)
    rect(tx, ty, tw, th, on and COL.scrollOn or COL.scroll)
    hit(tx - S(6), v.y, tw + S(12), v.h, function()
        if my >= ty and my <= ty + th then
            P.drag = { name = name, grab = my - ty, s = s, v = v, contentH = contentH, th = th }
        else
            scrollBy(s, v, contentH, (my < ty and -1 or 1) * v.h * 0.85)
        end
    end)
end

local function updateDrag()
    local d = P.drag
    if not d then return end
    if not getKeyState("mouse1") then P.drag = nil return end
    local range = d.v.h - d.th
    if range <= 0 then return end
    local f = max(0, min(1, (my - d.grab - d.v.y) / range))
    d.s.target = f * maxScroll(d.v, d.s, d.contentH)
    d.s.scroll = d.s.target
end

--------------------------------------------------------------------------------
-- navigation
--------------------------------------------------------------------------------

local function openTopic(id)
    if P.topic == id then return end
    P.history[#P.history + 1] = P.topic or false
    P.topic = id
    P.page.scroll, P.page.target, P.page.key = 0, 0, nil
end

local function goHome()
    if P.topic == nil then return end
    P.history[#P.history + 1] = P.topic
    P.topic = nil
    P.page.scroll, P.page.target, P.page.key = 0, 0, nil
end

local function goBack()
    local n = #P.history
    if n == 0 then return end
    P.topic = P.history[n] or nil
    P.history[n] = nil
    P.page.scroll, P.page.target, P.page.key = 0, 0, nil
end

local function queryChanged()
    local q = P.query:match("^%s*(.-)%s*$")
    P.results = q ~= "" and Search.run(q) or nil
    P.side.key = nil
    P.side.scroll, P.side.target = 0, 0
end

--------------------------------------------------------------------------------
-- sidebar rows
--------------------------------------------------------------------------------

local ROW_H = { cat = 38, topic = 34, result = 60, info = 30, empty = 70 }

local function buildRows()
    local key = Help.revision .. "|" .. L.lang() .. "|" .. tostring(P.results)
    if P.side.key == key then return end
    local rows, y = {}, 0
    local function add(r)
        r.y, r.h = y, floor(S(ROW_H[r.k]))
        y = y + r.h
        rows[#rows + 1] = r
    end

    if P.results then
        if #P.results == 0 then
            add({ k = "empty", text = L("ui_help.search.no_results", { query = P.query:match("^%s*(.-)%s*$") }) })
        else
            add({ k = "info", text = L("ui_help.search.results", { count = #P.results }) })
            for _, r in ipairs(P.results) do
                add({ k = "result", id = r.id, title = r.title,
                      sub = r.category .. (r.snippet ~= "" and ("  ·  " .. r.snippet) or "") })
            end
        end
    else
        local list = Help.list()
        if #list == 0 then
            add({ k = "empty", text = L("ui_help.list.empty") })
        end
        for _, cat in ipairs(list) do
            add({ k = "cat", id = cat.id, title = cat.title, count = #cat.topics })
            if not P.collapsed[cat.id] then
                for _, t in ipairs(cat.topics) do
                    add({ k = "topic", id = t.id, title = Help.topicData(t).title })
                end
            end
        end
    end

    P.side.rows, P.side.h, P.side.key = rows, y, key
    local sel = P.side.sel
    if not (sel and rows[sel] and (rows[sel].k == "topic" or rows[sel].k == "result" or rows[sel].k == "cat")) then
        P.side.sel = nil
        if P.results then
            for i, r in ipairs(rows) do
                if r.k == "result" then P.side.sel = i break end
            end
        end
    end
end

local function selectable(r)
    return r and (r.k == "cat" or r.k == "topic" or r.k == "result")
end

local function activateRow(r)
    if not r then return end
    if r.k == "cat" then
        P.collapsed[r.id] = not P.collapsed[r.id] or nil
        P.side.key = nil
    elseif r.k == "topic" or r.k == "result" then
        openTopic(r.id)
    end
end

local function moveSel(dir)
    local rows = P.side.rows
    local i = P.side.sel or (dir > 0 and 0 or #rows + 1)
    repeat i = i + dir until i < 1 or i > #rows or selectable(rows[i])
    if not selectable(rows[i]) then return end
    P.side.sel = i
    local r, v, s = rows[i], G.list, P.side
    if r.y < s.target then s.target = r.y end
    if r.y + r.h + v.padY * 2 > s.target + v.h then s.target = r.y + r.h + v.padY * 2 - v.h end
end

local function drawRows()
    local v, s = G.list, P.side
    local ox, oy = beginView(v, s.scroll)
    local inside = within(v.x, v.y, v.w, v.h)
    local padL = floor(S(18))

    for i, r in ipairs(s.rows) do
        if inView(v, r.y, r.h, s.scroll) then
            local x, y, w, h = ox, oy + r.y, v.w, r.h
            local sx, sy, swd, shh = screenRect(v, 0, r.y, v.w, r.h, s.scroll)
            local hov = inside and sx and within(sx, sy, swd, shh)
            local active = (r.k == "topic" or r.k == "result") and r.id == P.topic

            if active then
                rect(x, y, w, h, COL.sel)
                rect(x, y, floor(S(3)), h, COL.accent)
            elseif hov and selectable(r) then
                rect(x, y, w, h, COL.hover)
            end
            if s.sel == i and not active then rect(x, y, w, h, COL.keySel) end

            if r.k == "cat" then
                local open = not P.collapsed[r.id]
                local cx = x + padL + floor(S(6))
                dxDrawText("›", cx - S(8), y, cx + S(8), y + h, col(COL.muted), F.h3.s, F.h3.f,
                    "center", "center", false, false, false, false, false, open and 90 or 0, cx, y + h / 2)
                local cw = L.width(tostring(r.count), F.small.s, F.small.f)
                text(L.fit(L.upper(r.title), w - padL * 2 - S(22) - cw - S(10), F.smallB.s, F.smallB.f),
                    cx + S(14), y, w, h, COL.h, F.smallB)
                text(tostring(r.count), x, y, w - padL, h, COL.muted, F.small, "right")
            elseif r.k == "topic" then
                local tx = x + padL + S(20)
                text(L.fit(r.title, w - (tx - x) - padL, F.body.s, F.body.f), tx, y, w, h,
                    active and COL.h or COL.text, active and F.bodyB or F.body)
            elseif r.k == "result" then
                local tw = w - padL * 2
                local t1 = y + S(10)
                text(L.fit(r.title, tw, F.bodyB.s, F.bodyB.f), x + padL, t1, tw, F.bodyB.h, COL.h, F.bodyB, "left", "top")
                text(L.fit(r.sub, tw, F.small.s, F.small.f), x + padL, t1 + F.bodyB.h + S(4), tw, F.small.h,
                    COL.muted, F.small, "left", "top")
                rect(x + padL, y + h - 1, tw, 1, COL.line, 0.5)
            elseif r.k == "info" then
                text(r.text, x + padL, y, w - padL * 2, h, COL.muted, F.small)
            elseif r.k == "empty" then
                dxDrawText(r.text, x + padL, y, x + w - padL, y + h, col(COL.muted), F.body.s, F.body.f,
                    "center", "center", true, true)
            end

            if sx and selectable(r) then
                hit(sx, sy, swd, shh, function() P.side.sel = i activateRow(r) end)
            end
        end
    end
    endView(v)
    drawScrollbar(v, s, s.h, "list")
end

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

local STYLE

local function relatedBlocks(d)
    local out = {}
    for _, id in ipairs(d.related) do
        if Help.topics[id] then out[#out + 1] = { k = "link", id = id, label = "" } end
    end
    if #out > 0 then table.insert(out, 1, { k = "h3", text = L("ui_help.related") }) end
    return out
end

local function homeBlocks()
    local doc = Help.homeDoc()
    if doc then return doc.blocks, doc.title or L("ui_help.home.title") end
    local blocks = { { k = "p", text = L("ui_help.home.text") } }
    for _, cat in ipairs(Help.list()) do
        blocks[#blocks + 1] = { k = "h2", text = cat.title }
        for _, t in ipairs(cat.topics) do
            blocks[#blocks + 1] = { k = "link", id = t.id, label = "" }
        end
    end
    return blocks, L("ui_help.home.title")
end

local function buildPage()
    local v = G.body
    local key = tostring(P.topic) .. "|" .. Help.revision .. "|" .. L.lang()
    if P.page.key == key then return end
    P.page.key = key
    STYLE = STYLE or { fonts = F, hex = HEX, S = S }

    local w = v.w - v.padX * 2
    local blocks, header
    local t = P.topic and Help.topics[P.topic]
    if P.topic and not t then
        blocks = { { k = "p", text = L("ui_help.missing_topic") } }
        header = { title = tostring(P.topic) }
    elseif t then
        local d = Help.topicData(t)
        blocks = {}
        for _, b in ipairs(d.doc.blocks) do blocks[#blocks + 1] = b end
        for _, b in ipairs(relatedBlocks(d)) do blocks[#blocks + 1] = b end
        header = { crumb = Help.categoryTitle(t.category), title = d.title }
    else
        local title
        blocks, title = homeBlocks()
        header = { crumb = L("ui_help.crumb.home"), title = title }
    end
    P.page.layout = Markup.layout(blocks, w, STYLE, header)
end

local function drawPage()
    local v, s, lay = G.body, P.page, P.page.layout
    local ox, oy = beginView(v, s.scroll)
    local inside = within(v.x, v.y, v.w, v.h)
    for _, it in ipairs(lay.items) do
        if inView(v, it.y, it.h, s.scroll) then
            local x, y = ox + it.x, oy + it.y
            local k = it.k
            if k == "text" then
                for i, line in ipairs(it.lines) do
                    local ly = it.y + (i - 1) * it.lh
                    if inView(v, ly, it.lh, s.scroll) then
                        dxDrawText(line, x, oy + ly, x + it.w, oy + ly + it.lh, col(COL[it.color]),
                            it.F.s, it.F.f, "left", "center", false, false, false, true)
                    end
                end
            elseif k == "marker" then
                text(it.text, x, y, it.w, it.h, COL[it.color], it.F, "right")
            elseif k == "box" then
                local warn = it.kind == "warn"
                rect(x, y, it.w, it.h, warn and COL.warnBg or COL.noteBg)
                rect(x, y, floor(S(3)), it.h, warn and COL.warn or COL.accent)
            elseif k == "rule" then
                rect(x, y, it.w, it.h, COL[it.color] or COL.line)
            elseif k == "img" then
                dxDrawImage(x, y, it.w, it.h, it.tex, 0, 0, 0, tocolor(255, 255, 255, 255 * A))
            elseif k == "link" then
                local sx, sy, swd, shh = screenRect(v, it.x, it.y, it.w, it.h, s.scroll)
                local hov = inside and sx and within(sx, sy, swd, shh) and not it.missing
                if hov then rect(x, y, it.w, it.h, COL.hover) end
                local c = it.missing and COL.muted or COL.accent
                text("→", x + S(8), y, S(20), it.h, c, it.F)
                text(L.fit(it.label, it.w - S(44), it.F.s, it.F.f), x + S(34), y, it.w - S(44), it.h, c,
                    hov and F.bodyB or it.F)
                if sx and not it.missing then
                    local id = it.id
                    hit(sx, sy, swd, shh, function() openTopic(id) end)
                end
            end
        end
    end
    endView(v)
    drawScrollbar(v, s, lay.h, "page")
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

local close -- forward

local function button(label, x, y, h, font, fn)
    local w = L.width(label, font.s, font.f) + S(26)
    local hov = within(x, y, w, h)
    rect(x, y, w, h, hov and COL.btnHover or COL.btn)
    text(label, x, y, w, h, COL.text, font, "center")
    hit(x, y, w, h, fn)
    return w
end

local function drawHeader()
    local x, y, w, h = G.x, G.y, G.w, G.headH
    rect(x, y, w, h, COL.head)
    rect(x, y + h, w, 1, COL.line)

    local tx = x + G.pad + S(6)
    local title = L("ui_help.title")
    rect(tx, y + h / 2 - S(11), S(3), S(22), COL.accent)
    text(title, tx + S(14), y, w, h, COL.h, F.head)
    local after = tx + S(14) + L.width(title, F.head.s, F.head.f)
    hit(tx, y, after - tx, h, goHome)

    if #P.history > 0 then
        button("‹  " .. L("ui_help.back"), after + S(22), y + (h - S(32)) / 2, S(32), F.small, goBack)
    end

    local cs = floor(S(34))
    local cx, cy = x + w - G.pad - cs, y + (h - cs) / 2
    local hov = within(cx, cy, cs, cs)
    rect(cx, cy, cs, cs, hov and COL.close or COL.btn)
    local m = S(11)
    dxDrawLine(cx + m, cy + m, cx + cs - m, cy + cs - m, col(COL.h), S(2))
    dxDrawLine(cx + cs - m, cy + m, cx + m, cy + cs - m, col(COL.h), S(2))
    hit(cx, cy, cs, cs, function() close() end)

    local hint = L("ui_help.close_hint")
    text(hint, x, y, cx - S(14) - x, h, COL.muted, F.small, "right")
end

local function drawSearch()
    local b = G.search
    rect(b.x, b.y, b.w, b.h, COL.field)
    rect(b.x, b.y + b.h - floor(S(2)), b.w, floor(S(2)), (P.query ~= "" or P.focus == "search") and COL.accent or COL.line)
    hit(b.x, b.y, b.w, b.h, function() P.focus = "search" end)

    -- magnifier
    local ix, iy = b.x + S(18), b.y + b.h / 2 - S(2)
    dxDrawCircle(ix, iy, S(7), 0, 360, col(COL.muted), col(COL.muted), 24)
    dxDrawCircle(ix, iy, S(5), 0, 360, col(COL.field), col(COL.field), 24)
    dxDrawLine(ix + S(4.5), iy + S(4.5), ix + S(9), iy + S(9), col(COL.muted), S(2.5))

    local tx = b.x + S(36)
    local clearW = P.query ~= "" and S(32) or 0
    local tw = b.w - (tx - b.x) - S(10) - clearW
    if P.query == "" then
        text(L("ui_help.search.placeholder"), tx, b.y, tw, b.h, COL.muted, F.body, "left", "center", true)
    else
        local qw = L.width(P.query, F.body.s, F.body.f)
        text(P.query, tx, b.y, tw, b.h, COL.h, F.body, qw > tw and "right" or "left", "center", true)
        local caretX = tx + min(qw, tw) + S(1)
        if P.focus == "search" and floor(getTickCount() / 530) % 2 == 0 then
            rect(caretX, b.y + b.h / 2 - F.body.h / 2, max(1, floor(S(1.5))), F.body.h, COL.accent)
        end
        local cx = b.x + b.w - clearW
        local hov = within(cx, b.y, clearW, b.h)
        local m = S(11)
        local cy = b.y + b.h / 2
        local c = hov and COL.h or COL.muted
        dxDrawLine(cx + m, cy - S(5), cx + clearW - m, cy + S(5), col(c), S(1.5))
        dxDrawLine(cx + clearW - m, cy - S(5), cx + m, cy + S(5), col(c), S(1.5))
        hit(cx, b.y, clearW, b.h, function() P.query = "" queryChanged() end)
    end
end

--------------------------------------------------------------------------------
-- AI assistant panel (logic: client/ai.lua)
--------------------------------------------------------------------------------

local function wrapText(str, maxW, font)
    local out = {}
    for para in (str .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            local try = line == "" and word or (line .. " " .. word)
            if line ~= "" and L.width(try, font.s, font.f) > maxW then
                out[#out + 1] = line
                line = word
            else
                line = try
            end
        end
        out[#out + 1] = line
    end
    return out
end

local function buildAI()
    local v, a = G.aiChat, P.ai
    local key = AI.state .. "|" .. AI.question .. "|" .. AI.answer .. "|" .. tostring(AI.err) .. "|" .. L.lang()
    if a.key == key then return end
    a.key = key
    a.scroll, a.target = 0, 0

    local items, y = {}, 0
    local function line(t, font, c)
        local lh = floor(font.h + S(4))
        items[#items + 1] = { y = y, t = t, f = font, c = c, h = lh }
        y = y + lh
    end
    local function block(t, font, c)
        for _, ln in ipairs(wrapText(t, v.w - S(16), font)) do line(ln, font, c) end
    end

    if AI.state == "idle" then
        block(L("ui_help.ai.intro"), F.body, COL.muted)
    else
        line(L("ui_help.ai.you"), F.smallB, COL.accent)
        block(AI.question, F.body, COL.h)
        y = y + floor(S(14))
        line(L("ui_help.ai.bot"), F.smallB, COL.accent)
        if AI.state == "waiting" then
            line(L("ui_help.ai.waiting"), F.body, COL.muted)
        elseif AI.state == "error" then
            block(L("ui_help.ai.error", { msg = AI.err or "?" }), F.body, COL.warn)
        else
            block(AI.answer, F.body, COL.text)
        end
    end
    a.items, a.h = items, y
end

local function drawAI()
    local b, v, a = G.ai, G.aiChat, P.ai
    rect(b.x, b.y, b.w, b.h, COL.side)
    rect(b.x, b.y, b.w, G.headH, COL.head)
    rect(b.x, b.y + G.headH, b.w, 1, COL.line)
    rect(b.x + b.w - 1, b.y, 1, b.h, COL.line)

    local tx = b.x + G.pad + S(6)
    rect(tx, b.y + G.headH / 2 - S(11), S(3), S(22), COL.accent)
    text(L("ui_help.ai.title"), tx + S(14), b.y, b.w, G.headH, COL.h, F.head)

    if AI.state == "done" or AI.state == "error" then
        local label = L("ui_help.ai.new")
        local bw = L.width(label, F.small.s, F.small.f) + S(26)
        button(label, b.x + b.w - G.pad - bw, b.y + (G.headH - S(32)) / 2, S(32), F.small, AI.new)
    end

    -- conversation (only whole lines are drawn)
    for _, it in ipairs(a.items) do
        local sy = v.y + it.y - a.scroll
        if sy >= v.y and sy + it.h <= v.y + v.h then
            text(it.t, v.x, sy, v.w, it.h, it.c, it.f)
        end
    end
    drawScrollbar(v, a, a.h, "ai")

    -- input + Ask button
    local f = G.aiIn
    local idle = AI.state == "idle"
    local bw = L.width(L("ui_help.ai.send"), F.bodyB.s, F.bodyB.f) + S(30)
    local fw = f.w - bw - S(8)
    local focused = P.focus == "ai" and idle
    rect(f.x, f.y, fw, f.h, COL.field, idle and 1 or 0.5)
    rect(f.x, f.y + f.h - floor(S(2)), fw, floor(S(2)), focused and COL.accent or COL.line)
    hit(f.x, f.y, fw, f.h, function() P.focus = "ai" end)

    local pad = S(12)
    local iw = fw - pad * 2
    local qw = L.width(AI.input, F.body.s, F.body.f)
    if AI.input == "" then
        text(L("ui_help.ai.placeholder"), f.x + pad, f.y, iw, f.h, COL.muted, F.body, "left", "center", true)
    else
        text(AI.input, f.x + pad, f.y, iw, f.h, COL.h, F.body, qw > iw and "right" or "left", "center", true)
    end
    if focused and floor(getTickCount() / 530) % 2 == 0 then
        rect(f.x + pad + min(qw, iw) + S(1), f.y + f.h / 2 - F.body.h / 2, max(1, floor(S(1.5))), F.body.h, COL.accent)
    end

    local can = AI.canAsk()
    local bx = f.x + fw + S(8)
    local hov = can and within(bx, f.y, bw, f.h)
    rect(bx, f.y, bw, f.h, can and (hov and COL.accent or COL.sel) or COL.btn, can and 1 or 0.6)
    text(L("ui_help.ai.send"), bx, f.y, bw, f.h, can and COL.h or COL.muted, F.bodyB, "center")
    hit(bx, f.y, bw, f.h, function() AI.ask() end)

    local wait = AI.cooldownLeft()
    if wait > 0 then
        text(L("ui_help.ai.cooldown", { sec = wait }), f.x, f.y + f.h + S(4), f.w, S(18), COL.muted, F.small)
    end
end

local function onRender()
    local now = getTickCount()
    local dt = min(100, now - P.lastTick)
    P.lastTick = now
    P.alpha = min(1, (now - P.openTick) / FADE_MS)
    A = P.alpha

    local cx, cy = getCursorPosition()
    if cx then mx, my = cx * sw, cy * sh else mx, my = -1, -1 end

    -- held key auto-repeat
    if P.rep then
        if not getKeyState(P.rep.key) then
            P.rep = nil
        elseif now >= P.rep.next then
            P.rep.next = now + REPEAT_RATE
            P.rep.fn()
        end
    end

    AI.tick()
    buildRows()
    buildPage()
    buildAI()
    updateDrag()
    updateScroll(P.side, G.list, P.side.h, dt)
    updateScroll(P.page, G.body, P.page.layout.h, dt)
    updateScroll(P.ai, G.aiChat, P.ai.h, dt)

    P.hits = {}
    rect(0, 0, sw, sh, COL.dim)
    rect(G.ai.x - S(6), G.y - S(6), G.x + G.w - G.ai.x + S(12), G.h + S(12), COL.shadow)
    rect(G.x, G.y, G.sideW, G.h, COL.side)
    rect(G.body.x, G.body.y, G.body.w, G.body.h, COL.page)
    rect(G.x + G.sideW, G.y + G.headH, 1, G.h - G.headH, COL.line)

    drawAI()
    drawHeader()
    drawSearch()
    drawRows()
    drawPage()
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function ctrl()
    return getKeyState("lctrl") or getKeyState("rctrl")
end

local function backspace()
    if P.focus == "ai" then
        if AI.state ~= "idle" or AI.input == "" then return end
        if ctrl() then
            AI.input = AI.input:gsub("%s*%S+%s*$", "")
        else
            AI.input = L.sub(AI.input, 1, L.len(AI.input) - 1)
        end
        return
    end
    if P.query == "" then return end
    if ctrl() then
        P.query = P.query:gsub("%s*%S+%s*$", "")
    else
        P.query = L.sub(P.query, 1, L.len(P.query) - 1)
    end
    queryChanged()
end

local function overList()
    return within(G.list.x, G.list.y, G.list.w, G.list.h)
end

local function click()
    for i = #P.hits, 1, -1 do
        local h = P.hits[i]
        if within(h[1], h[2], h[3], h[4]) then
            h[5]()
            return
        end
    end
end

local PRESS = {
    F1          = function() close() end,
    escape      = function()
        if P.focus == "ai" and AI.input ~= "" and AI.state == "idle" then AI.input = ""
        elseif P.query ~= "" then P.query = "" queryChanged() else close() end
    end,
    backspace   = backspace,
    arrow_u     = function() moveSel(-1) end,
    arrow_d     = function() moveSel(1) end,
    enter       = function()
        if P.focus == "ai" then AI.ask() else activateRow(P.side.rows[P.side.sel]) end
    end,
    num_enter   = function()
        if P.focus == "ai" then AI.ask() else activateRow(P.side.rows[P.side.sel]) end
    end,
    pgup        = function() scrollBy(P.page, G.body, P.page.layout.h, -G.body.h * 0.85) end,
    pgdn        = function() scrollBy(P.page, G.body, P.page.layout.h, G.body.h * 0.85) end,
    home        = function() P.page.target = 0 end,
    ["end"]     = function() P.page.target = math.huge end,
    mouse4      = goBack,
}
local REPEATS = { backspace = true, arrow_u = true, arrow_d = true, pgup = true, pgdn = true }

local function onKey(button, press)
    -- Ctrl+V must pass, otherwise MTA never fires onClientPaste (GTA's V does
    -- nothing anyway: the cursor has the controls off)
    if button == "v" and ctrl() then return end
    cancelEvent()

    if button == "mouse_wheel_up" or button == "mouse_wheel_down" then
        local dir = button == "mouse_wheel_up" and -1 or 1
        if within(G.aiChat.x, G.aiChat.y, G.aiChat.w, G.aiChat.h) then
            scrollBy(P.ai, G.aiChat, P.ai.h, dir * S(WHEEL_STEP) * 0.6)
        elseif overList() then
            scrollBy(P.side, G.list, P.side.h, dir * S(WHEEL_STEP) * 0.6)
        else
            scrollBy(P.page, G.body, P.page.layout.h, dir * S(WHEEL_STEP))
        end
        return
    end
    if button == "mouse1" then
        if press then click() else P.drag = nil end
        return
    end
    if not press then return end
    if button == OPEN_KEY and getTickCount() - P.openTick < 200 then return end

    local fn = PRESS[button]
    if not fn then return end
    fn()
    if REPEATS[button] and P.open then
        P.rep = { key = button, next = getTickCount() + REPEAT_DELAY, fn = fn }
    end
end

local function addText(s)
    s = tostring(s or ""):gsub("[%c]", " ")
    if P.focus == "ai" then
        if AI.state ~= "idle" then return end
        local r = AI.MAX_INPUT - L.len(AI.input)
        if r > 0 and s ~= "" then AI.input = AI.input .. L.sub(s, 1, r) end
        return
    end
    local room = MAX_QUERY - L.len(P.query)
    if room <= 0 or s == "" then return end
    P.query = P.query .. L.sub(s, 1, room)
    queryChanged()
end

local function onCharacter(ch)
    if ctrl() then return end
    if ch:byte() and ch:byte() < 32 then return end
    addText(ch)
end

local function onPaste(s)
    addText(s)
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function blocked()
    if isMainMenuActive() or isConsoleActive() then return true end
    if getElementData(localPlayer, "textInputOpen") then return true end
    if getElementData(localPlayer, "chatTyping") then return true end
    if getElementData(localPlayer, "paused") then return true end
    return false
end

function HelpPanel_open(topicId)
    if P.open then
        if topicId then openTopic(topicId) end
        return true
    end
    if blocked() then return false end

    buildFonts()
    buildGeometry()
    createTargets()

    P.open = true
    P.openTick, P.lastTick = getTickCount(), getTickCount()
    P.page.key, P.side.key, P.ai.key = nil, nil, nil
    P.rep, P.drag = nil, nil
    P.focus = "search"
    if topicId then openTopic(topicId) end

    P.prevMode = guiGetInputMode()
    guiSetInputMode("no_binds")
    showCursor(true)
    addEventHandler("onClientRender", root, onRender)
    addEventHandler("onClientKey", root, onKey, true, "high+100")
    addEventHandler("onClientCharacter", root, onCharacter)
    addEventHandler("onClientPaste", root, onPaste)
    setElementData(localPlayer, "helpOpen", true, false)
    triggerEvent("ui_help:onClientHelpToggle", localPlayer, true)
    return true
end

close = function()
    if not P.open then return false end
    P.open = false
    removeEventHandler("onClientRender", root, onRender)
    removeEventHandler("onClientKey", root, onKey)
    removeEventHandler("onClientCharacter", root, onCharacter)
    removeEventHandler("onClientPaste", root, onPaste)
    guiSetInputMode(P.prevMode or "allow_binds")
    showCursor(false)
    destroyTargets()
    Markup.freeTextures()
    P.page.layout, P.page.key = nil, nil
    P.rep, P.drag = nil, nil
    setElementData(localPlayer, "helpOpen", false, false)
    triggerEvent("ui_help:onClientHelpToggle", localPlayer, false)
    return true
end
HelpPanel_close = close

function HelpPanel_isOpen()
    return P.open
end

function HelpPanel_toggle()
    if P.open then return close() end
    return HelpPanel_open()
end

addEvent("ui_help:onClientHelpToggle")

bindKey(OPEN_KEY, "down", function() HelpPanel_toggle() end)
addCommandHandler("help", function() HelpPanel_toggle() end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if P.open then close() end
end)
