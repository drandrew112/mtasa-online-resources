if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- /anims panel (DX). Left: Favourites, All and the categories. Right: search field + the list.
-- Bottom: the 8 favourite slots of the F9 wheel.
--
--   row click = play, star = add / remove favourite, slot left click = play, right click = remove,
--   typing = search, BACKSPACE = delete, ESC = clear the search, then close, mouse wheel = scroll.
--
-- While open: cursor shown, guiSetInputMode "no_binds", keyboard keys cancelled, local element
-- data "animPanelOpen" = true. Handlers are attached only while the panel is open.

local sw, sh = guiGetScreenSize()
local SC = math.min(sw / 1920, sh / 1080)
local function S(v) return math.floor(v * SC + 0.5) end
local max, min, floor = math.max, math.min, math.floor

local COL = {
    dim    = tocolor(0, 0, 0, 140),
    head   = tocolor(12, 14, 18, 250),
    side   = tocolor(15, 17, 21, 252),
    body   = tocolor(20, 22, 28, 252),
    field  = tocolor(29, 32, 40, 255),
    line   = tocolor(52, 57, 68, 255),
    text   = tocolor(222, 226, 233, 255),
    h      = tocolor(245, 247, 250, 255),
    muted  = tocolor(128, 136, 150, 255),
    accent = tocolor(239, 159, 39, 255),
    accDim = tocolor(239, 159, 39, 40),
    hover  = tocolor(255, 255, 255, 14),
    sel    = tocolor(239, 159, 39, 30),
    btn    = tocolor(36, 40, 49, 255),
    btnOn  = tocolor(48, 53, 64, 255),
    star   = tocolor(239, 159, 39, 255),
    starOff= tocolor(90, 96, 110, 255),
    close  = tocolor(230, 75, 75, 255),
    scroll = tocolor(255, 255, 255, 50),
    play   = tocolor(120, 200, 130, 255),
}

local F
local function mkFont(file, size)
    local f = dxCreateFont(file, max(7, floor(size * SC + 0.5)), false, "cleartype")
    return f or "default"
end
local function fonts()
    if F then return end
    F = {
        title = mkFont("client/fonts/RobotoB.ttf", 18),
        bold  = mkFont("client/fonts/RobotoB.ttf", 12),
        body  = mkFont("client/fonts/Roboto.ttf", 12),
        small = mkFont("client/fonts/Roboto.ttf", 10),
    }
end

local W, H = S(1060), S(700)
local X, Y = floor((sw - W) / 2), floor((sh - H) / 2)
local HEAD, SIDE, PAD, ROW, FOOT = S(58), S(230), S(16), S(40), S(92)
local SEARCH_H = S(38)
local LIST = { x = X + SIDE + 1, y = Y + HEAD + PAD + SEARCH_H + S(10), w = W - SIDE - 1 }
LIST.h = Y + H - FOOT - LIST.y

local P = {
    open = false, cat = "all", query = "", scroll = 0, target = 0,
    rows = {}, key = nil, hits = {}, prevMode = "allow_binds",
}
local mx, my = -1, -1
local rt

local function within(x, y, w, h) return mx >= x and mx < x + w and my >= y and my < y + h end
local function hit(x, y, w, h, fn, rfn) P.hits[#P.hits + 1] = { x, y, w, h, fn, rfn } end
-- 5-pointed star (Roboto has no star glyph): filled = favourite, outline = not
local function drawStar(cx, cy, r, c, filled)
    local pts = {}
    for k = 0, 9 do
        local ang = math.rad(-90 + k * 36)
        local rr = (k % 2 == 0) and r or r * 0.45
        pts[#pts + 1] = { cx + rr * math.cos(ang), cy + rr * math.sin(ang), c }
    end
    if filled then
        local fan = { { cx, cy, c } }
        for _, p in ipairs(pts) do fan[#fan + 1] = p end
        fan[#fan + 1] = pts[1]
        dxDrawPrimitive("trianglefan", false, unpack(fan))
    else
        pts[#pts + 1] = pts[1]
        dxDrawPrimitive("linestrip", false, unpack(pts))
    end
end

local function drawCross(x, y, s, c)
    local m = s * 0.32
    dxDrawLine(x + m, y + m, x + s - m, y + s - m, c, max(1, S(2)))
    dxDrawLine(x + s - m, y + m, x + m, y + s - m, c, max(1, S(2)))
end

local function text(s, x, y, w, h, c, f, ax, clip)
    dxDrawText(s, x, y, x + w, y + h, c, 1, f, ax or "left", "center", clip or false)
end

--------------------------------------------------------------------------------
-- list content
--------------------------------------------------------------------------------

local function searchText(a)
    return (Anims.label(a) .. " " .. Anims.command(a) .. " " .. a.id .. " " .. Anims.catLabel(a.cat)
        .. " " .. a.block .. " " .. a.name):lower()
end

local function buildRows()
    local key = P.cat .. "|" .. P.query .. "|" .. L.lang() .. "|" .. table.concat(Anims.favs, ",")
    if P.key == key then return end
    P.key = key
    local rows = {}
    local q = P.query:lower():match("^%s*(.-)%s*$")
    if q ~= "" then
        for _, a in ipairs(ANIMS.order) do
            if searchText(a):find(q, 1, true) then rows[#rows + 1] = { a = a } end
        end
    elseif P.cat == "favs" then
        for _, id in ipairs(Anims.favs) do rows[#rows + 1] = { a = ANIMS.byId[id] } end
    else
        local lastCmd
        for _, a in ipairs(ANIMS.order) do
            if P.cat == "all" or a.cat == P.cat then
                if a.cmd ~= lastCmd then
                    rows[#rows + 1] = { header = a.cmd }
                    lastCmd = a.cmd
                end
                rows[#rows + 1] = { a = a }
            end
        end
    end
    P.rows = rows
end

local function contentH() return #P.rows * ROW end
local function maxScroll() return max(0, contentH() - LIST.h) end

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local function drawSide()
    dxDrawRectangle(X, Y + HEAD, SIDE, H - HEAD - FOOT, COL.side)
    local y = Y + HEAD + S(8)
    local items = { { id = "favs", label = L("v_anims.panel.favourites"), count = #Anims.favs .. "/" .. ANIMS.MAX_FAVS },
                    { id = "all", label = L("v_anims.panel.all"), count = #ANIMS.order } }
    for _, cat in ipairs(ANIM_CATEGORIES) do
        local n = 0
        for _, g in ipairs(ANIMS.cats[cat] or {}) do n = n + #g.anims end
        items[#items + 1] = { id = cat, label = Anims.catLabel(cat), count = n }
    end
    local rh = S(34)
    for _, it in ipairs(items) do
        local on = P.cat == it.id and P.query == ""
        if on then
            dxDrawRectangle(X, y, SIDE, rh, COL.sel)
            dxDrawRectangle(X, y, S(3), rh, COL.accent)
        elseif within(X, y, SIDE, rh) then
            dxDrawRectangle(X, y, SIDE, rh, COL.hover)
        end
        text(it.label, X + PAD, y, SIDE - PAD * 2 - S(50), rh, on and COL.h or COL.text, on and F.bold or F.body, "left", true)
        text(tostring(it.count), X + SIDE - PAD - S(60), y, S(60), rh, COL.muted, F.small, "right")
        local id = it.id
        hit(X, y, SIDE, rh, function()
            P.cat, P.query, P.scroll, P.target = id, "", 0, 0
        end)
        y = y + rh
        if it.id == "all" then
            dxDrawRectangle(X + PAD, y + S(4), SIDE - PAD * 2, 1, COL.line)
            y = y + S(9)
        end
    end
end

local function drawSearch()
    local x, y, w = LIST.x + PAD, Y + HEAD + PAD, LIST.w - PAD * 2
    dxDrawRectangle(x, y, w, SEARCH_H, COL.field)
    dxDrawRectangle(x, y + SEARCH_H - S(2), w, S(2), P.query ~= "" and COL.accent or COL.line)
    local caret = (getTickCount() % 1000 < 500) and "|" or ""
    if P.query == "" then
        text(L("v_anims.panel.search"), x + S(12), y, w - S(24), SEARCH_H, COL.muted, F.body)
    else
        text(P.query .. caret, x + S(12), y, w - S(24), SEARCH_H, COL.h, F.body, "left", true)
        text(L("v_anims.panel.results", { count = #P.rows }), x, y, w - S(12), SEARCH_H, COL.muted, F.small, "right")
    end
end

-- draws the rows into the list view; ox, oy = screen (or render target) origin
local function drawRows(ox, oy, toScreen)
    local cur = Anims.current()
    local first = max(1, floor(P.scroll / ROW) + 1)
    local w = LIST.w
    for i = first, #P.rows do
        local ry = (i - 1) * ROW - P.scroll
        if ry >= LIST.h then break end
        if toScreen or (ry >= 0 and ry + ROW <= LIST.h) then
            local r = P.rows[i]
            local x, y = ox, oy + ry
            local sy = LIST.y + ry -- screen y for hit testing
            local visible = sy >= LIST.y and sy + ROW <= LIST.y + LIST.h
            local vTop, vBot = max(sy, LIST.y), min(sy + ROW, LIST.y + LIST.h)
            if r.header then
                local g = ANIMS.groups[r.header]
                text(L("v_anims.group." .. r.header), x + PAD, y + S(8), w, ROW - S(8), COL.accent, F.bold)
                text("/" .. r.header .. (#g.anims > 1 and (" 1-" .. #g.anims) or ""), x + PAD, y + S(8), w - PAD * 2, ROW - S(8), COL.muted, F.small, "right")
            else
                local a = r.a
                local playing = cur and cur.id == a.id
                local hov = vBot > vTop and mx >= LIST.x and mx < LIST.x + w and my >= vTop and my < vBot
                if playing then dxDrawRectangle(x, y, w, ROW, COL.sel)
                elseif hov then dxDrawRectangle(x, y, w, ROW, COL.hover) end
                local fav = Anims.isFav(a.id)
                local starX = x + PAD
                drawStar(starX + S(14), y + ROW / 2, S(9), fav and COL.star or COL.starOff, fav)
                text(Anims.label(a), x + PAD + S(36), y, S(300), ROW, playing and COL.h or COL.text, playing and F.bold or F.body, "left", true)
                text(Anims.command(a), x + PAD + S(340), y, S(160), ROW, COL.muted, F.body, "left", true)
                if P.cat == "all" or P.cat == "favs" or P.query ~= "" then
                    text(Anims.catLabel(a.cat), x + PAD + S(500), y, S(150), ROW, COL.muted, F.small, "left", true)
                end
                local kind = a.move and "v_anims.kind.move" or (a.loop and "v_anims.kind.loop" or (a.hold and "v_anims.kind.hold" or "v_anims.kind.once"))
                text(playing and L("v_anims.panel.playing") or L(kind), x, y, w - PAD - S(10), ROW, playing and COL.play or COL.muted, F.small, "right")
                if vBot > vTop then
                    local id = a.id
                    hit(LIST.x + PAD - S(4), vTop, S(36), vBot - vTop, function() Anims.toggleFav(id) end)
                    hit(LIST.x, vTop, w, vBot - vTop, function() Anims.play(id) end)
                end
            end
        end
    end
    if #P.rows == 0 then
        local msg = P.query ~= "" and L("v_anims.panel.no_results") or
            (P.cat == "favs" and L("v_anims.panel.no_favs") or "")
        text(msg, ox, oy, w, S(80), COL.muted, F.body, "center")
    end
end

local function drawList()
    dxDrawRectangle(LIST.x, Y + HEAD, LIST.w, H - HEAD - FOOT, COL.body)
    drawSearch()
    if rt then
        dxSetRenderTarget(rt, true)
        dxDrawRectangle(0, 0, LIST.w, LIST.h, COL.body)
        drawRows(0, 0, true)
        dxSetRenderTarget()
        dxDrawImage(LIST.x, LIST.y, LIST.w, LIST.h, rt)
    else
        drawRows(LIST.x, LIST.y, false)
    end
    -- scrollbar
    local total = contentH()
    if total > LIST.h then
        local th = max(S(30), LIST.h * LIST.h / total)
        local ty = LIST.y + (LIST.h - th) * (P.scroll / maxScroll())
        dxDrawRectangle(LIST.x + LIST.w - S(7), ty, S(4), th, COL.scroll)
    end
end

local function drawFooter()
    local y = Y + H - FOOT
    dxDrawRectangle(X, y, W, FOOT, COL.head)
    dxDrawRectangle(X, y, W, 1, COL.line)
    text(L("v_anims.panel.wheel_title", { count = #Anims.favs, max = ANIMS.MAX_FAVS }), X + PAD, y + S(6), W, S(24), COL.text, F.bold)
    text(L("v_anims.panel.wheel_hint"), X, y + S(6), W - PAD, S(24), COL.muted, F.small, "right")
    local gap = S(8)
    local cw = floor((W - PAD * 2 - gap * (ANIMS.MAX_FAVS - 1)) / ANIMS.MAX_FAVS)
    local ch = S(44)
    local cy = y + S(34)
    for i = 1, ANIMS.MAX_FAVS do
        local cx = X + PAD + (i - 1) * (cw + gap)
        local id = Anims.favs[i]
        local a = id and ANIMS.byId[id]
        local hov = within(cx, cy, cw, ch)
        dxDrawRectangle(cx, cy, cw, ch, a and (hov and COL.btnOn or COL.btn) or COL.field)
        text(tostring(i), cx + S(8), cy, S(16), ch, a and COL.accent or COL.starOff, F.bold)
        if a then
            text(L.fit(Anims.label(a), cw - S(32), 1, F.body), cx + S(26), cy + S(3), cw - S(30), ch / 2, COL.text, F.body)
            text(Anims.command(a), cx + S(26), cy + ch / 2 - S(2), cw - S(30), ch / 2, COL.muted, F.small)
            hit(cx, cy, cw, ch, function() Anims.play(id) end, function() Anims.toggleFav(id) end)
        else
            text(L("v_anims.panel.empty_slot"), cx + S(26), cy, cw - S(30), ch, COL.starOff, F.small)
        end
    end
end

local function drawHead()
    dxDrawRectangle(X, Y, W, HEAD, COL.head)
    dxDrawRectangle(X, Y + HEAD - 1, W, 1, COL.line)
    text(L("v_anims.title"), X + PAD, Y, S(300), HEAD, COL.h, F.title)
    text(L("v_anims.panel.count", { count = #ANIMS.order }), X + PAD + S(170), Y, S(300), HEAD, COL.muted, F.small)
    -- close
    local cs = S(34)
    local cx, cy = X + W - PAD - cs, Y + (HEAD - cs) / 2
    local hov = within(cx, cy, cs, cs)
    dxDrawRectangle(cx, cy, cs, cs, hov and COL.close or COL.btn)
    drawCross(cx, cy, cs, COL.h)
    hit(cx, cy, cs, cs, function() Panel.close() end)
    -- stop
    local bw = S(150)
    local bx = cx - S(10) - bw
    local cur = Anims.current()
    hov = within(bx, cy, bw, cs)
    dxDrawRectangle(bx, cy, bw, cs, cur and (hov and COL.btnOn or COL.btn) or COL.field)
    text(L("v_anims.panel.stop"), bx, cy, bw, cs, cur and COL.text or COL.starOff, F.bold, "center")
    if cur then hit(bx, cy, bw, cs, function() Anims.stop() end) end
    if cur then
        text(L("v_anims.panel.now", { name = Anims.label(cur) }), X, Y, bx - S(14) - X, HEAD, COL.play, F.small, "right")
    end
end

local lastTick = 0
local function render()
    local now = getTickCount()
    local dt = min(100, now - lastTick)
    lastTick = now
    local cx, cy = getCursorPosition()
    if cx then mx, my = cx * sw, cy * sh else mx, my = -1, -1 end
    buildRows()
    P.target = max(0, min(maxScroll(), P.target))
    P.scroll = P.scroll + (P.target - P.scroll) * min(1, dt / 1000 * 16)
    if math.abs(P.target - P.scroll) < 0.5 then P.scroll = P.target end
    P.hits = {}

    dxDrawRectangle(0, 0, sw, sh, COL.dim)
    drawHead()
    drawSide()
    drawList()
    drawFooter()
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function click(right)
    -- first matching zone wins (the star zone is added before its row)
    for _, h in ipairs(P.hits) do
        if mx >= h[1] and mx < h[1] + h[3] and my >= h[2] and my < h[2] + h[4] then
            local fn = right and h[6] or (not right and h[5])
            if fn then fn() end
            return
        end
    end
end

local function onKey(button, press)
    if button == "mouse_wheel_up" or button == "mouse_wheel_down" then
        if within(LIST.x, LIST.y, LIST.w, LIST.h) then
            P.target = max(0, min(maxScroll(), P.target + (button == "mouse_wheel_down" and 1 or -1) * ROW * 3))
        end
        return
    end
    if button == "mouse1" or button == "mouse2" then
        if press then click(button == "mouse2") end
        return
    end
    if button:find("^mouse") then return end
    if press then
        if button == "escape" then
            if P.query ~= "" then P.query, P.scroll, P.target = "", 0, 0 else Panel.close() end
        elseif button == "backspace" then
            P.query = P.query:sub(1, -2) -- ASCII search; a multibyte tail is dropped byte by byte
            while #P.query > 0 and P.query:byte(-1) >= 0x80 and P.query:byte(-1) < 0xC0 do P.query = P.query:sub(1, -2) end
            if #P.query > 0 and P.query:byte(-1) >= 0xC0 then P.query = P.query:sub(1, -2) end
            P.scroll, P.target = 0, 0
        elseif button == "pgdn" then P.target = P.target + LIST.h * 0.9
        elseif button == "pgup" then P.target = P.target - LIST.h * 0.9
        end
    end
    if button == "v" and getKeyState("lctrl") then return end
    cancelEvent()
end

local function onChar(ch)
    if #P.query >= 40 or ch == "\t" then return end
    P.query = P.query .. ch
    P.scroll, P.target = 0, 0
end

Panel = {}

function Panel.isOpen() return P.open end

function Panel.open()
    if P.open or isMainMenuActive() or isConsoleActive() then return end
    if getElementData(localPlayer, "paused") == true then return end
    fonts()
    P.open = true
    P.key = nil
    rt = dxCreateRenderTarget(LIST.w, LIST.h, true) or nil
    P.prevMode = guiGetInputMode()
    guiSetInputMode("no_binds")
    showCursor(true)
    setElementData(localPlayer, "animPanelOpen", true, false)
    lastTick = getTickCount()
    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    addEventHandler("onClientCharacter", root, onChar)
end

function Panel.close()
    if not P.open then return end
    P.open = false
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientKey", root, onKey)
    removeEventHandler("onClientCharacter", root, onChar)
    if rt and isElement(rt) then destroyElement(rt) end
    rt = nil
    guiSetInputMode(P.prevMode or "allow_binds")
    showCursor(false)
    setElementData(localPlayer, "animPanelOpen", false, false)
end

function Panel.toggle()
    if P.open then Panel.close() else Panel.open() end
end

addCommandHandler("anims", function() Panel.toggle() end)
addEventHandler("onClientRestore", root, function() P.key = nil end)
addEventHandler("onClientResourceStop", resourceRoot, function() Panel.close() end)
addEventHandler("onClientPlayerWasted", localPlayer, function() Panel.close() end)

-- exports
function openAnimPanel() Panel.open() return true end
function closeAnimPanel() Panel.close() return true end
function isAnimPanelOpen() return P.open end
