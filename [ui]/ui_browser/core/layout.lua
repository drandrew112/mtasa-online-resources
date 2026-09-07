-- ui_browser :: core/layout.lua
-- Turns the parsed markup tree into an absolute-positioned list of draw ops and
-- clickable links, flowing vertically inside a given width. Drawn into a render
-- target so scrolling / clipping stays clean.
--
--   layout = {
--     ops, links, height, pageBg,
--     col        = { text, heading, muted, link, accent, card, cardLine },  -- page theme
--     dark       = <bool>,          -- dark background?
--     hoverWash  = <tocolor>,
--     searchRect = {x,y,w,h} | nil,
--     searchPlaceholder = <string>,
--   }
--
-- Links may carry: href, action, tab, sort, search, color, cta.

local FS = { h1 = 2.0, h2 = 1.5, h3 = 1.15, p = 1.0, small = 0.85 }

local function S(v) return BR.sc(v) end

local function fontHeight(mult, font)
    return dxGetFontHeight(BR.fscale(mult), font or BR.fonts.regular)
end

local function textWidth(text, mult, font)
    return dxGetTextWidth(text, BR.fscale(mult), font or BR.fonts.regular)
end

--------------------------------------------------------------------------------
-- low level ops
--------------------------------------------------------------------------------

local function pushRect(ctx, x, y, w, h, color)
    ctx.ops[#ctx.ops + 1] = { t = "rect", x = x, y = y, w = w, h = h, color = color }
end

local function pushLine(ctx, x, y, w, h, color)
    ctx.ops[#ctx.ops + 1] = { t = "rect", x = x, y = y, w = w, h = math.max(1, h), color = color }
end

local function pushImage(ctx, x, y, w, h, path)
    ctx.ops[#ctx.ops + 1] = { t = "image", x = x, y = y, w = w, h = h, path = path }
end

local function pushTextOp(ctx, text, x, y, x2, y2, color, mult, font, ha, va)
    ctx.ops[#ctx.ops + 1] = {
        t = "text", text = text, x = x, y = y, x2 = x2, y2 = y2,
        color = color, scale = BR.fscale(mult), font = font or BR.fonts.regular,
        ha = ha or "left", va = va or "top",
    }
end

local function pushText(ctx, text, x, y, w, mult, color, font, align)
    local scale = BR.fscale(mult)
    font = font or BR.fonts.regular
    local lh = dxGetFontHeight(scale, font)
    local lines = BR.wrapText(text, w, scale, font)
    for i, ln in ipairs(lines) do
        local ly = y + (i - 1) * lh
        ctx.ops[#ctx.ops + 1] = {
            t = "text", text = ln, x = x, y = ly, x2 = x + w, y2 = ly + lh,
            color = color, scale = scale, font = font, ha = align or "left", va = "top",
        }
    end
    return y + #lines * lh
end

local function strokeRect(ctx, x, y, w, h, color)
    local t = math.max(1, S(1))
    pushRect(ctx, x, y, w, t, color)
    pushRect(ctx, x, y + h - t, w, t, color)
    pushRect(ctx, x, y, t, h, color)
    pushRect(ctx, x + w - t, y, t, h, color)
end

local function panel(ctx, x, y, w, h, fill)
    pushRect(ctx, x, y + S(3), w, h, ctx.dark and tocolor(0, 0, 0, 110) or tocolor(19, 24, 31, 16))
    pushRect(ctx, x, y, w, h, fill or ctx.col.card)
    strokeRect(ctx, x, y, w, h, ctx.col.cardLine)
end

local function registerLink(ctx, x, y, w, h, node, extra)
    local l = { x = x, y = y, w = w, h = h }
    if node then l.href = node.attrs.href; l.action = node.attrs.action end
    if extra then for k, v in pairs(extra) do l[k] = v end end
    ctx.links[#ctx.links + 1] = l
end

local function resolveAsset(ctx, src)
    if not src or src == "" then return nil end
    if src:find("[/\\]") or src:find("^sites/") or src:find("^assets/") then return src end
    if ctx.siteDir then return ctx.siteDir .. "/" .. src end
    return src
end

local function placeholderFill(ctx)
    return ctx.dark and tocolor(255, 255, 255, 12) or tocolor(238, 240, 243, 255)
end

--------------------------------------------------------------------------------
-- handlers
--------------------------------------------------------------------------------

local handlers = {}

local function flow(ctx, nodes, x, w, y)
    for _, node in ipairs(nodes) do
        local h = handlers[node.tag] or handlers["_default"]
        y = h(ctx, node, x, w, y)
    end
    return y
end

handlers._default = function(ctx, node, x, w, y)
    return flow(ctx, node.children, x, w, y)
end
handlers.page = handlers._default
handlers.col = handlers._default
handlers.div = handlers._default
handlers.section = function(ctx, node, x, w, y)
    if node.attrs.title then
        y = pushText(ctx, node.attrs.title, x, y + S(4), w, FS.h2, ctx.col.heading, BR.fonts.heading) + S(10)
    end
    return flow(ctx, node.children, x, w, y)
end

handlers["#text"] = function(ctx, node, x, w, y)
    return pushText(ctx, node.text, x, y, w, FS.p, ctx.col.text) + S(8)
end

local function textTag(mult, role, gapBefore, gapAfter, defFont)
    return function(ctx, node, x, w, y)
        y = y + S(gapBefore or 0)
        local class = BR.classStyle(node.attrs.class)
        local color = BR.parseColor(node.attrs.color, nil)
            or (class and class.fg)
            or ctx.col[role] or ctx.col.text
        local m, font = mult, defFont or BR.fonts.regular
        if class and class.size then m = class.size end
        if class and class.bold then font = BR.fonts.bold end
        y = pushText(ctx, BR.nodeText(node), x, y, w, m, color, font, node.attrs.align)
        return y + S(gapAfter or 6)
    end
end

handlers.h1    = textTag(FS.h1, "heading", 8, 12, BR.fonts.heading)
handlers.h2    = textTag(FS.h2, "heading", 8, 10, BR.fonts.heading)
handlers.h3    = textTag(FS.h3, "heading", 4, 8, BR.fonts.heading)
handlers.p     = textTag(FS.p, "text", 0, 8)
handlers.text  = handlers.p
handlers.small = textTag(FS.small, "muted", 0, 6)

handlers.price = function(ctx, node, x, w, y)
    return pushText(ctx, BR.nodeText(node), x, y, w, 1.3, BR.theme.buy, BR.fonts.bold, node.attrs.align) + S(6)
end

handlers.br = function(ctx, node, x, w, y) return y + fontHeight(FS.p) end

handlers.space = function(ctx, node, x, w, y)
    return y + S(tonumber(node.attrs.h) or 12)
end

handlers.hr = function(ctx, node, x, w, y)
    y = y + S(8)
    pushLine(ctx, x, y, w, S(1), ctx.col.cardLine)
    return y + S(12)
end

handlers.img = function(ctx, node, x, w, y)
    local iw = node.attrs.w and math.min(w, S(tonumber(node.attrs.w) or w)) or w
    local ih = S(tonumber(node.attrs.h) or 150)
    local path = resolveAsset(ctx, node.attrs.src)
    pushRect(ctx, x, y, iw, ih, placeholderFill(ctx))
    if path and fileExists(path) then
        pushImage(ctx, x, y, iw, ih, path)
    elseif node.attrs.alt then
        pushTextOp(ctx, node.attrs.alt, x, y, x + iw, y + ih, ctx.col.muted, FS.small, BR.fonts.regular, "center", "center")
    end
    strokeRect(ctx, x, y, iw, ih, ctx.col.cardLine)
    return y + ih + S(10)
end

handlers.logo = function(ctx, node, x, w, y)
    local h = S(tonumber(node.attrs.h) or 44)
    if ctx.logo and fileExists(ctx.logo) then
        pushImage(ctx, x, y, h, h, ctx.logo)
        return y + h + S(8)
    end
    return y
end

handlers.badge = function(ctx, node, x, w, y)
    local label = BR.nodeText(node)
    local bw = textWidth(label, 0.8, BR.fonts.bold) + S(18)
    local bh = fontHeight(0.8, BR.fonts.bold) + S(8)
    local col = BR.parseColor(node.attrs.color, ctx.col.accent)
    pushRect(ctx, x, y, bw, bh, col)
    pushTextOp(ctx, label, x, y, x + bw, y + bh, tocolor(255, 255, 255, 255), 0.8, BR.fonts.bold, "center", "center")
    return y + bh + S(6)
end

handlers.link = function(ctx, node, x, w, y)
    y = y + S(2)
    local label = BR.nodeText(node)
    local scale = BR.fscale(FS.p)
    local tw = math.min(w, dxGetTextWidth(label, scale, BR.fonts.regular))
    local lh = dxGetFontHeight(scale, BR.fonts.regular)
    pushText(ctx, label, x, y, w, FS.p, ctx.col.link)
    pushLine(ctx, x, y + lh, tw, S(1), ctx.col.link)
    registerLink(ctx, x, y, math.max(tw, S(40)), lh + S(4), node)
    return y + lh + S(10)
end

handlers.button = function(ctx, node, x, w, y)
    local label = BR.nodeText(node)
    local class = BR.classStyle(node.attrs.class)
    local bg = (class and class.bg) or ctx.col.accent
    local fg = (class and class.fg) or tocolor(255, 255, 255, 255)
    local border = class and class.border

    local scale = BR.fscale(FS.p)
    local h = (node.attrs.class == "btn-cta") and S(48) or S(38)
    local padX = S(20)
    local bw = (node.attrs.block == "1") and w
        or math.min(w, dxGetTextWidth(label, scale, BR.fonts.bold) + padX * 2)

    local bx = x
    if node.attrs.align == "right" then
        bx = x + w - bw
    elseif node.attrs.align == "center" then
        bx = x + (w - bw) / 2
    end

    pushRect(ctx, bx, y, bw, h, bg)
    if border then strokeRect(ctx, bx, y, bw, h, border) end
    pushTextOp(ctx, label, bx, y, bx + bw, y + h, fg,
        (node.attrs.class == "btn-cta") and 1.15 or FS.p, BR.fonts.bold, "center", "center")
    registerLink(ctx, bx, y, bw, h, node, node.attrs.class == "btn-cta" and { cta = true } or nil)
    return y + h + S(10)
end

handlers.buttons = function(ctx, node, x, w, y)
    local gap = S(tonumber(node.attrs.gap) or 10)
    local h = S(38)
    local scale = BR.fscale(FS.p)
    local bx, rowY = x, y
    for _, kid in ipairs(BR.elementChildren(node)) do
        if kid.tag == "button" then
            local label = BR.nodeText(kid)
            local bw = math.min(w, dxGetTextWidth(label, scale, BR.fonts.bold) + S(40))
            if bx > x and bx + bw > x + w then
                bx = x
                rowY = rowY + h + gap
            end
            local class = BR.classStyle(kid.attrs.class)
            pushRect(ctx, bx, rowY, bw, h, (class and class.bg) or ctx.col.accent)
            pushTextOp(ctx, label, bx, rowY, bx + bw, rowY + h,
                (class and class.fg) or tocolor(255, 255, 255, 255), FS.p, BR.fonts.bold, "center", "center")
            registerLink(ctx, bx, rowY, bw, h, kid)
            bx = bx + bw + gap
        end
    end
    return rowY + h + S(12)
end

handlers.list = function(ctx, node, x, w, y)
    for _, item in ipairs(BR.elementChildren(node)) do
        if item.tag == "item" or item.tag == "li" then
            pushRect(ctx, x + S(2), y + fontHeight(FS.p) / 2 - S(2), S(5), S(5), ctx.col.muted)
            y = pushText(ctx, BR.nodeText(item), x + S(18), y, w - S(20), FS.p, ctx.col.text) + S(7)
        end
    end
    return y + S(4)
end

handlers.card = function(ctx, node, x, w, y)
    local pad = S(16)
    local forced = ctx.forceCardH
    ctx.forceCardH = nil
    local accent = BR.parseColor(node.attrs.accent, nil)

    local shIndex = #ctx.ops + 1
    pushRect(ctx, x, y + S(3), w, 0, ctx.dark and tocolor(0, 0, 0, 110) or tocolor(19, 24, 31, 16))
    local bgIndex = #ctx.ops + 1
    pushRect(ctx, x, y, w, 0, ctx.col.card)

    local innerTop = y + pad + (accent and S(4) or 0)
    local innerEnd = flow(ctx, node.children, x + pad, w - pad * 2, innerTop)
    local h = (innerEnd - y) + pad
    if forced and forced > h then h = forced end

    ctx.ops[shIndex].h = h
    ctx.ops[bgIndex].h = h
    if accent then pushRect(ctx, x, y, w, S(4), accent) end
    strokeRect(ctx, x, y, w, h, ctx.col.cardLine)
    return y + h + S(14)
end

handlers.row = function(ctx, node, x, w, y)
    local kids = BR.elementChildren(node)
    local k = #kids
    if k == 0 then return y end
    local gap = S(tonumber(node.attrs.gap) or 12)
    local colW = (w - gap * (k - 1)) / k
    local maxY = y
    for i, kid in ipairs(kids) do
        local cy = flow(ctx, { kid }, x + (i - 1) * (colW + gap), colW, y)
        if cy > maxY then maxY = cy end
    end
    return maxY
end

--------------------------------------------------------------------------------
-- grid / catalog
--------------------------------------------------------------------------------

local function isCell(tag)
    return tag == "card" or tag == "product"
end

local function layoutGrid(ctx, cells, x, w, y, cols, gap)
    cols = math.max(1, cols)
    local cellW = (w - gap * (cols - 1)) / cols
    local i = 1
    while i <= #cells do
        local rowCells = {}
        for c = 0, cols - 1 do
            if cells[i + c] then rowCells[#rowCells + 1] = cells[i + c] end
        end

        local opN, linkN = #ctx.ops, #ctx.links
        local rowH = 0
        for _, cell in ipairs(rowCells) do
            local cy = flow(ctx, { cell }, 0, cellW, 0)
            if cy > rowH then rowH = cy end
        end
        for j = #ctx.ops, opN + 1, -1 do ctx.ops[j] = nil end
        for j = #ctx.links, linkN + 1, -1 do ctx.links[j] = nil end

        for c, cell in ipairs(rowCells) do
            ctx.forceCardH = rowH - S(14)
            flow(ctx, { cell }, x + (c - 1) * (cellW + gap), cellW, y)
        end
        ctx.forceCardH = nil

        y = y + rowH + gap
        i = i + cols
    end
    return y
end

handlers.grid = function(ctx, node, x, w, y)
    return layoutGrid(ctx, BR.elementChildren(node), x, w, y,
        tonumber(node.attrs.cols) or 3, S(tonumber(node.attrs.gap) or 16))
end

local function drawSortBar(ctx, x, w, y)
    local segs = {
        { key = "default", label = "Default" },
        { key = "asc",     label = "Price: low to high" },
        { key = "desc",    label = "Price: high to low" },
    }
    local cur = BR.state.sort
    y = pushText(ctx, "Sort", x, y, w, FS.small, ctx.col.muted) + S(2)
    local sx, h = x, S(30)
    for _, seg in ipairs(segs) do
        local active = (cur == seg.key) or (cur == nil and seg.key == "default")
        local bw = textWidth(seg.label, FS.small, BR.fonts.bold) + S(20)
        pushRect(ctx, sx, y, bw, h, active and ctx.col.accent or ctx.col.card)
        strokeRect(ctx, sx, y, bw, h, ctx.col.cardLine)
        pushTextOp(ctx, seg.label, sx, y, sx + bw, y + h,
            active and tocolor(255, 255, 255, 255) or ctx.col.text, FS.small, BR.fonts.bold, "center", "center")
        registerLink(ctx, sx, y, bw, h, nil, { sort = seg.key })
        sx = sx + bw + S(8)
    end
    return y + h + S(16)
end

local function priceOf(node)
    local digits = (node.attrs.price or ""):gsub("[^%d]", "")
    return tonumber(digits) or 0
end

handlers.catalog = function(ctx, node, x, w, y)
    local cols = tonumber(node.attrs.cols) or 3
    local gap = S(tonumber(node.attrs.gap) or 16)
    local cells = {}
    for _, c in ipairs(BR.elementChildren(node)) do
        if isCell(c.tag) then cells[#cells + 1] = c end
    end

    if node.attrs.sort == "price" then
        y = drawSortBar(ctx, x, w, y)
        local dir = BR.state.sort
        if dir == "asc" or dir == "desc" then
            local copy = {}
            for i, c in ipairs(cells) do copy[i] = c end
            table.sort(copy, function(a, b)
                if dir == "asc" then return priceOf(a) < priceOf(b) end
                return priceOf(a) > priceOf(b)
            end)
            cells = copy
        end
    end

    return layoutGrid(ctx, cells, x, w, y, cols, gap)
end

--------------------------------------------------------------------------------
-- tabs
--------------------------------------------------------------------------------

handlers.tabs = function(ctx, node, x, w, y)
    local kids = {}
    for _, c in ipairs(BR.elementChildren(node)) do
        if c.tag == "tab" then kids[#kids + 1] = c end
    end
    if #kids == 0 then return y end

    local active = BR.clamp(BR.state.tab or 1, 1, #kids)
    local accent = BR.parseColor(node.attrs.accent, ctx.col.accent)
    local h = S(38)
    local tabW = w / #kids
    for i, t in ipairs(kids) do
        local tx = x + (i - 1) * tabW
        local sel = (i == active)
        pushRect(ctx, tx, y, tabW - S(2), h, sel and accent or ctx.col.card)
        if not sel then strokeRect(ctx, tx, y, tabW - S(2), h, ctx.col.cardLine) end
        pushTextOp(ctx, t.attrs.title or ("Tab " .. i), tx, y, tx + tabW - S(2), y + h,
            sel and tocolor(255, 255, 255, 255) or ctx.col.text, FS.p, BR.fonts.bold, "center", "center")
        registerLink(ctx, tx, y, tabW - S(2), h, nil, { tab = i })
    end
    return flow(ctx, kids[active].children, x, w, y + h + S(16))
end

--------------------------------------------------------------------------------
-- products
--------------------------------------------------------------------------------

-- A product in a listing: image + name + price, whole card links to the detail
-- page. No buy button here.
handlers.product = function(ctx, node, x, w, y)
    local pad = S(14)
    local forced = ctx.forceCardH
    ctx.forceCardH = nil

    local id = node.attrs.id or ""
    local name = node.attrs.name or "Product"
    local price = node.attrs.price or ""
    local path = resolveAsset(ctx, node.attrs.img or node.attrs.src)
    local hasImg = path and fileExists(path)
    local imgH = hasImg and S(124) or 0
    local desc = BR.nodeText(node)
    local nh = fontHeight(1.1, BR.fonts.bold)
    local ph = fontHeight(1.05, BR.fonts.bold)
    local dLines = (not hasImg and desc ~= "") and
        #BR.wrapText(desc, w - pad * 2, BR.fscale(0.9), BR.fonts.regular) or 0
    local dh = dLines * fontHeight(0.9, BR.fonts.regular)
    local h = pad + (hasImg and (imgH + S(10)) or 0) + nh + S(6) + ph
        + (dh > 0 and (dh + S(6)) or 0) + pad
    if forced and forced > h then h = forced end

    panel(ctx, x, y, w, h)
    local cy = y + pad
    if hasImg then
        pushRect(ctx, x + pad, cy, w - pad * 2, imgH, placeholderFill(ctx))
        pushImage(ctx, x + pad, cy, w - pad * 2, imgH, path)
        cy = cy + imgH + S(10)
    end
    pushTextOp(ctx, name, x + pad, cy, x + w - pad, cy + nh, ctx.col.heading, 1.1, BR.fonts.bold, "left", "top")
    cy = cy + nh + S(6)
    pushTextOp(ctx, price, x + pad, cy, x + w - pad, cy + ph, BR.theme.buy, 1.05, BR.fonts.bold, "left", "top")
    cy = cy + ph + S(6)
    if dh > 0 then
        pushText(ctx, desc, x + pad, cy, w - pad * 2, 0.9, ctx.col.muted)
    end

    registerLink(ctx, x, y, w, h, nil, { href = (ctx.siteUrl or "") .. "?product=" .. id })
    return y + h + S(14)
end

-- Big product image on the detail page (fills the left column ~ half the width).
handlers.productimage = function(ctx, node, x, w, y)
    local ih = math.min(S(460), w * 0.64)
    local path = resolveAsset(ctx, node.attrs.src)
    pushRect(ctx, x, y, w, ih, placeholderFill(ctx))
    if path and fileExists(path) then
        pushImage(ctx, x, y, w, ih, path)
    else
        pushTextOp(ctx, node.attrs.alt or "no image", x, y, x + w, y + ih, ctx.col.muted, FS.small, BR.fonts.regular, "center", "center")
    end
    strokeRect(ctx, x, y, w, ih, ctx.col.cardLine)
    return y + ih + S(10)
end

handlers.swatches = function(ctx, node, x, w, y)
    y = pushText(ctx, node.attrs.label or "Colour", x, y, w, FS.small, ctx.col.muted) + S(8)
    local sz, gap = S(38), S(12)
    local bx = x
    for _, sw in ipairs(BR.elementChildren(node)) do
        if sw.tag == "swatch" then
            local c = BR.parseColor(sw.attrs.color, ctx.col.muted)
            if sw.attrs.sel == "1" then
                strokeRect(ctx, bx - S(3), y - S(3), sz + S(6), sz + S(6), ctx.col.accent)
            end
            pushRect(ctx, bx, y, sz, sz, c)
            strokeRect(ctx, bx, y, sz, sz, ctx.col.cardLine)
            registerLink(ctx, bx - S(3), y - S(3), sz + S(6), sz + S(6), nil, { color = sw.attrs.val })
            bx = bx + sz + gap
        end
    end
    return y + sz + S(16)
end

--------------------------------------------------------------------------------
-- site / home components
--------------------------------------------------------------------------------

handlers.siteheader = function(ctx, node, x, w, y)
    local h = S(84)
    local accent = BR.parseColor(node.attrs.accent, ctx.col.accent)
    panel(ctx, x, y, w, h)
    pushRect(ctx, x, y, w, S(4), accent)

    local tx = x + S(20)
    if ctx.logo and fileExists(ctx.logo) then
        local ls = h - S(28)
        pushImage(ctx, x + S(18), y + S(16), ls, ls, ctx.logo)
        tx = x + S(18) + ls + S(16)
    end
    pushTextOp(ctx, node.attrs.title or "", tx, y + S(16), x + w - S(18), y + S(46),
        ctx.col.heading, FS.h2, BR.fonts.heading, "left", "top")
    if node.attrs.tagline then
        pushTextOp(ctx, node.attrs.tagline, tx, y + S(48), x + w - S(18), y + S(72),
            ctx.col.muted, FS.small, BR.fonts.regular, "left", "top")
    end
    return y + h + S(18)
end

handlers.brand = function(ctx, node, x, w, y)
    local src = node.attrs.src or "assets/opense_logo.png"
    local aspect = tonumber(node.attrs.aspect) or 2.772
    local ih = S(tonumber(node.attrs.h) or 116)
    local iw = math.min(w, ih * aspect)
    ih = iw / aspect
    local ix = x + (w - iw) / 2
    if fileExists(src) then
        pushImage(ctx, ix, y, iw, ih, src)
    else
        pushTextOp(ctx, BR.nodeText(node), x, y, x + w, y + ih,
            tocolor(255, 255, 255, 255), 2.4, BR.fonts.heading, "center", "center")
    end
    registerLink(ctx, ix, y, iw, ih, node)
    return y + ih + S(14)
end

handlers.searchbox = function(ctx, node, x, w, y)
    local h = S(52)
    local bw = math.min(w, S(640))
    local bx = x + (w - bw) / 2
    pushRect(ctx, bx, y + S(3), bw, h, tocolor(0, 0, 0, 35))
    pushRect(ctx, bx, y, bw, h, tocolor(255, 255, 255, 255))
    ctx.searchRect = { x = bx, y = y, w = bw, h = h }
    ctx.searchPlaceholder = node.attrs.placeholder or "Search the virtual web or type an address"
    registerLink(ctx, bx, y, bw, h, nil, { search = true })
    return y + h + S(8)
end

handlers.catbtn = function(ctx, node, x, w, y)
    local h = S(50)
    local sel = node.attrs.sel == "1"
    local accent = node.attrs.cat and BR.accentOf(node.attrs.cat)
        or BR.parseColor(node.attrs.accent, ctx.col.accent)
    pushRect(ctx, x, y, w, h, sel and accent or ctx.col.card)
    strokeRect(ctx, x, y, w, h, sel and accent or ctx.col.cardLine)
    pushTextOp(ctx, BR.nodeText(node), x + S(6), y, x + w - S(6), y + h,
        sel and tocolor(255, 255, 255, 255) or ctx.col.text, FS.p, BR.fonts.bold, "center", "center")
    registerLink(ctx, x, y, w, h, node)
    return y + h
end

handlers.sitecard = function(ctx, node, x, w, y)
    local pad = S(15)
    local forced = ctx.forceCardH
    ctx.forceCardH = nil

    local title = node.attrs.title or node.attrs.href or "Website"
    local url = node.attrs.url or node.attrs.href or ""
    local desc = BR.nodeText(node)
    local logo = node.attrs.logo
    local hasLogo = logo and fileExists(logo)
    local logoS = S(34)

    local th = fontHeight(1.1, BR.fonts.bold)
    local headH = hasLogo and math.max(logoS, th) or th
    local dScale = 0.9
    local dLines = desc ~= "" and #BR.wrapText(desc, w - pad * 2, BR.fscale(dScale), BR.fonts.regular) or 0
    local dh = dLines * fontHeight(dScale, BR.fonts.regular)
    local uh = fontHeight(0.8, BR.fonts.regular)
    local h = pad + headH + S(8) + dh + S(8) + uh + pad
    if forced and forced > h then h = forced end

    panel(ctx, x, y, w, h)
    local cy = y + pad
    local textX = x + pad
    if hasLogo then
        pushImage(ctx, x + pad, cy, logoS, logoS, logo)
        textX = x + pad + logoS + S(10)
        pushTextOp(ctx, title, textX, cy, x + w - pad, cy + logoS, ctx.col.link, 1.1, BR.fonts.bold, "left", "center")
    else
        pushTextOp(ctx, title, textX, cy, x + w - pad, cy + th, ctx.col.link, 1.1, BR.fonts.bold, "left", "top")
    end
    cy = cy + headH + S(8)
    if desc ~= "" then
        cy = pushText(ctx, desc, x + pad, cy, w - pad * 2, dScale, ctx.col.text) + S(8)
    end
    pushTextOp(ctx, url, x + pad, y + h - pad - uh, x + w - pad, y + h - pad,
        ctx.col.muted, 0.8, BR.fonts.regular, "left", "top")

    registerLink(ctx, x, y, w, h, node)
    return y + h + S(14)
end

--------------------------------------------------------------------------------
-- entry point
--------------------------------------------------------------------------------

function BR.layoutPage(node, viewportW, opts)
    opts = opts or {}
    local pa = node.attrs or {}
    local margin = S(32)

    local ctx = {
        ops = {}, links = {},
        siteDir = opts.siteDir,
        siteUrl = opts.siteUrl,
        logo = opts.logo,
        dark = BR.isDark(pa.bg),
        col = {
            text     = BR.parseColor(pa.text,     BR.theme.text),
            heading  = BR.parseColor(pa.heading,  BR.parseColor(pa.text, BR.theme.heading)),
            muted    = BR.parseColor(pa.muted,    BR.theme.muted),
            link     = BR.parseColor(pa.link,     opts.accent or BR.theme.link),
            accent   = BR.parseColor(pa.accent,   opts.accent or BR.theme.primary),
            card     = BR.parseColor(pa.card,     BR.theme.card),
            cardLine = BR.parseColor(pa.cardline, BR.theme.cardLine),
        },
    }
    ctx.pageBg = BR.parseColor(pa.bg, BR.theme.pageBg)
    ctx.hoverWash = ctx.dark and tocolor(255, 255, 255, 40) or tocolor(0, 0, 0, 45)

    local contentW = math.max(S(120), viewportW - margin * 2)
    ctx.height = flow(ctx, node.children, margin, contentW, S(28)) + S(32)
    return ctx
end

--------------------------------------------------------------------------------
-- draw a layout into the current render target
--------------------------------------------------------------------------------

function BR.renderLayout(ctx, scrollY, vw, vh)
    dxDrawRectangle(0, 0, vw, vh, ctx.pageBg)
    for _, op in ipairs(ctx.ops) do
        local y = op.y - scrollY
        local h = op.h or (op.y2 and (op.y2 - op.y)) or 0
        if y + h >= 0 and y <= vh then
            if op.t == "rect" then
                dxDrawRectangle(op.x, y, op.w, op.h, op.color)
            elseif op.t == "image" then
                dxDrawImage(op.x, y, op.w, op.h, op.path)
            elseif op.t == "text" then
                dxDrawText(op.text, op.x, y, op.x2, y + (op.y2 - op.y),
                    op.color, op.scale, op.font, op.ha, op.va, false, false, false, false)
            end
        end
    end
end
