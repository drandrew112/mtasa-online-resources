-- ui_browser :: core/browser.lua
-- The virtual browser window: URL bar on top (read-only), back button on the
-- left, close button on the right. Right click = go back; if there is nothing
-- left to go back to, it leaves the browser. Mouse wheel scrolls. The home page
-- search box is the only place you can type an address.

local uicore = exports.ui_core

BR.state = {
    open       = false,
    current    = nil,     -- current URL string
    history    = {},      -- back stack of URL strings
    site       = nil,     -- current site def (nil on the home page)
    node       = nil,     -- parsed markup tree
    layout     = nil,     -- BR.layoutPage result
    scrollY    = 0,
    tab        = 1,       -- active <tabs> index (reset per page)
    sort       = nil,     -- nil | "asc" | "desc" (reset per page)
    productColor = nil,   -- selected product colour (reset per page)
    needLayout = false,
    rtDirty    = true,
    search     = { focused = false, buffer = "" },
}

local WIN_FRACTION = 0.8

local win = { x = 0, y = 0, w = 0, h = 0, chromeH = 0 }
local ui = {}          -- clickable chrome rects: back, close, url
local rt, rtW, rtH

--------------------------------------------------------------------------------
-- geometry
--------------------------------------------------------------------------------

local function computeWindow()
    local sw, sh = guiGetScreenSize()
    local w = math.floor(sw * WIN_FRACTION)
    local h = math.floor(sh * WIN_FRACTION)
    local x = math.floor((sw - w) / 2)
    local y = math.floor((sh - h) / 2)

    if w ~= win.w or h ~= win.h then
        BR.state.needLayout = true
    end
    win.x, win.y, win.w, win.h = x, y, w, h
    win.chromeH = math.floor(BR.sc(52))

    ui.back  = { x = win.x + BR.sc(10), y = win.y + BR.sc(8), w = BR.sc(36), h = BR.sc(36) }
    ui.close = { x = win.x + win.w - BR.sc(46), y = win.y + BR.sc(8), w = BR.sc(36), h = BR.sc(36) }
    local ux = ui.back.x + ui.back.w + BR.sc(10)
    ui.url = { x = ux, y = win.y + BR.sc(10), w = ui.close.x - BR.sc(10) - ux, h = BR.sc(32) }
end

local function contentRect()
    return win.x, win.y + win.chromeH, win.w, win.h - win.chromeH
end

local function maxScroll()
    local _, _, _, vh = contentRect()
    local total = (BR.state.layout and BR.state.layout.height) or 0
    return math.max(0, total - vh)
end

--------------------------------------------------------------------------------
-- render target
--------------------------------------------------------------------------------

local function ensureRT(w, h)
    w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
    if rt and (rtW ~= w or rtH ~= h) then
        if isElement(rt) then destroyElement(rt) end
        rt = nil
    end
    if not rt then
        rt = dxCreateRenderTarget(w, h, true)
        rtW, rtH = w, h
        BR.state.rtDirty = true
    end
    return rt
end

local function ensureLayout()
    local st = BR.state
    if not st.node then return end
    if st.needLayout or not st.layout then
        st.layout = BR.layoutPage(st.node, win.w, {
            siteDir = st.site and st.site.dir,
            siteUrl = st.site and st.site.url,
            logo    = st.site and BR.siteLogo(st.site),
            accent  = st.site and BR.accentOf(st.site.category),
        })
        st.needLayout = false
        st.rtDirty = true
        st.scrollY = BR.clamp(st.scrollY, 0, maxScroll())
    end
end

--------------------------------------------------------------------------------
-- navigation
--------------------------------------------------------------------------------

local function readFile(path)
    local f = fileOpen(path, true)
    local s = fileRead(f, fileGetSize(f))
    fileClose(f)
    return s
end

-- keepState: keep tab / sort / selected colour / scroll (a same-page reload,
-- e.g. bank balance refresh or picking a product colour).
local function loadPage(url, keepState)
    local st = BR.state
    local u = BR.parseUrl(url)
    local src

    st.site = nil
    if u.path == "home" then
        src = BR.buildHome(u.query)
    elseif u.path == "search" then
        src = BR.buildSearch(u.query and u.query.q or "")
    else
        local site = BR.getSite(u.path)
        if not site then
            src = BR.buildErrorPage(u.raw, "That address was not found.")
        else
            st.site = site
            if site.builder then
                src = site.builder(u.query) or BR.buildErrorPage(u.raw, "The site did not respond.")
            elseif site.markup and fileExists(site.markup) then
                src = readFile(site.markup)
                if u.query.product then
                    local tree = BR.parseMarkup(src)
                    local prod = BR.findNode(tree, function(n)
                        return n.tag == "product" and n.attrs.id == u.query.product
                    end)
                    if prod then
                        src = BR.buildProduct(tree.attrs, site, prod, keepState and st.productColor or nil)
                    else
                        src = BR.buildErrorPage(u.raw, "That product was not found.")
                    end
                end
            else
                src = BR.buildErrorPage(u.raw, "The page content could not be loaded.")
            end
        end
    end

    st.node = BR.parseMarkup(src)
    if not keepState then
        st.tab = 1
        st.sort = nil
        st.productColor = nil
        st.scrollY = 0
    end
    st.search.focused = false
    st.search.buffer = ""
    st.needLayout = true
    st.rtDirty = true
end

function BR.navigate(url, push)
    local st = BR.state
    local raw = BR.parseUrl(url).raw
    if raw == "" then raw = "home" end
    if raw == st.current then return end -- already here
    if push ~= false and st.current then
        st.history[#st.history + 1] = st.current
    end
    st.current = raw
    loadPage(st.current)
end

-- The home search box: resolve a typed query to an address, a category or a
-- text search.
function BR.submitSearch(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    local u = BR.parseUrl(text)
    if u.path == "home" or u.path == "search" or BR.getSite(u.path) then
        BR.navigate(text)
        return
    end
    local low = text:lower()
    for _, c in ipairs(BR.categories) do
        if c.id == low or c.label:lower() == low then
            BR.navigate("home?cat=" .. c.id)
            return
        end
    end
    BR.navigate("search?q=" .. text)
end

function BR.back()
    local st = BR.state
    if st.search.focused then
        st.search.focused = false
        return
    end
    if #st.history == 0 then
        BR.close()
        return
    end
    st.current = table.remove(st.history)
    st.scrollY = 0
    loadPage(st.current)
end

-- Re-run the current page keeping tab/sort/colour/scroll (bank refresh, colour pick).
function BR.refresh()
    if not BR.state.open or not BR.state.current then return end
    loadPage(BR.state.current, true)
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function onRender() BR.render() end

function BR.doOpen(url)
    local st = BR.state
    if not st.open then
        st.open = true
        st.history = {}
        st.current = nil
        st.scrollY = 0
        showCursor(true)
        setElementData(localPlayer, "browserOpen", true, false)
        uicore:toggleMoveControls(false)
        addEventHandler("onClientRender", root, onRender)
    end
    BR.navigate(url or "home", false)
end

function BR.close()
    local st = BR.state
    if not st.open then return end
    st.open = false
    st.search.focused = false
    removeEventHandler("onClientRender", root, onRender)
    showCursor(false)
    setElementData(localPlayer, "browserOpen", false, false)
    uicore:toggleMoveControls(true)
end

function BR.isOpen() return BR.state.open end

--------------------------------------------------------------------------------
-- URL bar text (display only)
--------------------------------------------------------------------------------

local function displayUrl()
    local u = BR.parseUrl(BR.state.current or "home")
    if u.path == "home" then
        if u.query.cat then
            local c = BR.getCategory(u.query.cat)
            return "opense://home/" .. (c and c.label or u.query.cat)
        end
        return "opense://home"
    end
    if u.path == "search" then
        return "opense://results/" .. (u.query.q or "")
    end
    return u.path
end

--------------------------------------------------------------------------------
-- link activation / actions
--------------------------------------------------------------------------------

addEvent("ui_browser:action", false)

local function activateLink(link)
    local st = BR.state

    if link.search then
        st.search.focused = true
        return
    end
    if link.tab then
        st.tab = link.tab
        st.scrollY = 0
        st.needLayout = true
        st.rtDirty = true
        return
    end
    if link.sort then
        st.sort = (link.sort == "default") and nil or link.sort
        st.scrollY = 0
        st.needLayout = true
        st.rtDirty = true
        return
    end
    if link.color then
        st.productColor = link.color
        BR.refresh()
        return
    end
    if link.action then
        local verb, arg = link.action:match("^([^:]+):?(.*)$")
        verb = verb or link.action
        arg = arg or ""
        triggerEvent("ui_browser:action", localPlayer, st.current, verb, arg, st.site and st.site.category)
        triggerServerEvent("ui_browser:action", localPlayer, st.current, verb, arg, st.site and st.site.category)
        return
    end
    if link.href then
        BR.navigate(link.href)
    end
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function pageHitTest(ax, ay)
    local cx, cy, cw, ch = contentRect()
    if ax < cx or ax > cx + cw or ay < cy or ay > cy + ch then return nil end
    local px = ax - cx
    local py = ay - cy + BR.state.scrollY
    for _, l in ipairs(BR.state.layout and BR.state.layout.links or {}) do
        if px >= l.x and px <= l.x + l.w and py >= l.y and py <= l.y + l.h then
            return l
        end
    end
    return "content"
end

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not BR.state.open or state ~= "down" then return end

    if button == "right" then
        BR.back()
        return
    end
    if button ~= "left" then return end

    if BR.pointInRect(ax, ay, ui.back) then BR.back() return end
    if BR.pointInRect(ax, ay, ui.close) then BR.close() return end

    local hit = pageHitTest(ax, ay)
    if type(hit) == "table" then
        if not hit.search then BR.state.search.focused = false end
        activateLink(hit)
    else
        BR.state.search.focused = false
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not BR.state.open then return end

    if key == "mouse_wheel_up" then
        BR.state.scrollY = BR.clamp(BR.state.scrollY - BR.sc(80), 0, maxScroll())
        BR.state.rtDirty = true
        cancelEvent()
        return
    elseif key == "mouse_wheel_down" then
        BR.state.scrollY = BR.clamp(BR.state.scrollY + BR.sc(80), 0, maxScroll())
        BR.state.rtDirty = true
        cancelEvent()
        return
    end

    if not BR.state.search.focused then return end
    if key:find("^mouse") then return end
    cancelEvent()
    if not press then return end

    local s = BR.state.search
    if key == "backspace" then
        s.buffer = s.buffer:sub(1, -2)
    elseif key == "enter" then
        local target = s.buffer
        s.focused = false
        BR.submitSearch(target)
    elseif key == "escape" then
        s.focused = false
    elseif key == "v" and (getKeyState("lctrl") or getKeyState("rctrl")) then
        local clip = getClipboard and getClipboard()
        if type(clip) == "string" then s.buffer = (s.buffer .. clip):sub(1, 160) end
    end
end)

addEventHandler("onClientCharacter", root, function(char)
    local s = BR.state.search
    if not BR.state.open or not s.focused then return end
    if #s.buffer < 160 then s.buffer = s.buffer .. char end
end)

addEventHandler("onClientRestore", root, function()
    if isElement(rt) then destroyElement(rt) end
    rt, rtW, rtH = nil, nil, nil
    BR.state.rtDirty = true
end)

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local function cursorScreen()
    local cx, cy = getCursorPosition()
    if not cx then return nil end
    local sw, sh = guiGetScreenSize()
    return cx * sw, cy * sh
end

local function drawChrome()
    dxDrawRectangle(win.x, win.y, win.w, win.chromeH, BR.theme.chrome)
    dxDrawRectangle(win.x, win.y + win.chromeH - 1, win.w, 1, BR.theme.chromeLine)

    local mx, my = cursorScreen()
    local function btn(r, icon)
        local hi = mx and BR.pointInRect(mx, my, r)
        dxDrawRectangle(r.x, r.y, r.w, r.h, hi and BR.theme.chromeBtnHi or BR.theme.chromeBtn)
        dxDrawText(icon, r.x, r.y, r.x + r.w, r.y + r.h, BR.theme.chromeIcon,
            BR.fscale(1.3), BR.fonts.bold, "center", "center")
    end
    btn(ui.back, "<")
    btn(ui.close, "X")

    dxDrawRectangle(ui.url.x, ui.url.y, ui.url.w, ui.url.h, BR.theme.urlBar)
    dxDrawText(displayUrl(), ui.url.x + BR.sc(12), ui.url.y, ui.url.x + ui.url.w - BR.sc(12),
        ui.url.y + ui.url.h, BR.theme.urlText, BR.fscale(0.95), BR.fonts.regular,
        "left", "center", true, false, false, false)
end

local function drawSearchOverlay()
    local layout = BR.state.layout
    local sr = layout and layout.searchRect
    if not sr then return end
    local cx, cy, cw, ch = contentRect()
    local bx = cx + sr.x
    local by = cy + sr.y - BR.state.scrollY
    if by + sr.h < cy or by > cy + ch then return end

    local s = BR.state.search
    dxDrawRectangle(bx, by, sr.w, sr.h, tocolor(255, 255, 255, 255))
    if s.focused then
        dxDrawRectangle(bx, by, sr.w, sr.h, tocolor(37, 99, 235, 22))
        dxDrawRectangle(bx, by + sr.h - BR.sc(2), sr.w, BR.sc(2), BR.theme.primary)
    end

    local text, col
    if s.buffer ~= "" then
        text, col = s.buffer, BR.theme.text
    elseif s.focused then
        text, col = "", BR.theme.text
    else
        text, col = layout.searchPlaceholder or "Search...", BR.theme.muted
    end
    if s.focused and (getTickCount() % 1000) < 500 then text = text .. "|" end

    dxDrawText(text, bx + BR.sc(16), by, bx + sr.w - BR.sc(16), by + sr.h,
        col, BR.fscale(1.0), BR.fonts.regular, "left", "center", true, false, false, false)
end

local function drawScrollbar()
    local _, cy, _, ch = contentRect()
    local ms = maxScroll()
    if ms <= 0 then return end
    local trackX = win.x + win.w - BR.sc(6)
    dxDrawRectangle(trackX, cy, BR.sc(4), ch, BR.theme.scrollTrack)
    local total = BR.state.layout.height
    local thumbH = math.max(BR.sc(32), ch * (ch / total))
    local thumbY = cy + (ch - thumbH) * (BR.state.scrollY / ms)
    dxDrawRectangle(trackX, thumbY, BR.sc(4), thumbH, BR.theme.scrollThumb)
end

local function drawHover()
    local mx, my = cursorScreen()
    if not mx then return end
    local cx, cy, cw, ch = contentRect()
    if mx < cx or mx > cx + cw or my < cy or my > cy + ch then return end
    local px = mx - cx
    local py = my - cy + BR.state.scrollY
    local wash = (BR.state.layout and BR.state.layout.hoverWash) or BR.theme.hoverWash
    for _, l in ipairs(BR.state.layout and BR.state.layout.links or {}) do
        if px >= l.x and px <= l.x + l.w and py >= l.y and py <= l.y + l.h then
            local ry = cy + l.y - BR.state.scrollY
            local top = math.max(ry, cy)
            local bot = math.min(ry + l.h, cy + ch)
            if bot > top then
                local c = wash
                if l.cta then c = tocolor(0, 0, 0, 95) end
                if l.search then c = tocolor(0, 0, 0, 20) end
                dxDrawRectangle(cx + l.x, top, l.w, bot - top, c)
            end
            return
        end
    end
end

-- Cash / bank HUD: plain text, top-right of the screen, only while the browser
-- is open. Cash comes from getPlayerMoney (shared); bank from element data.
local function drawHUD()
    local sw, sh = guiGetScreenSize()
    local fmt = BR.formatMoney or function(n) return "$" .. tostring(n) end
    local cash = fmt(getPlayerMoney(localPlayer) or 0)
    local bank = fmt(tonumber(getElementData(localPlayer, "bank_money")) or 0)

    local scale = BR.fscale(1.5)
    local lh = dxGetFontHeight(scale, BR.fonts.bold)
    local rx = sw - BR.sc(24)
    local lx = rx - BR.sc(500)
    local y = BR.sc(20)

    local function line(text, ty, color)
        dxDrawText(text, lx + BR.sc(2), ty + BR.sc(2), rx + BR.sc(2), ty + lh + BR.sc(2),
            tocolor(0, 0, 0, 160), scale, BR.fonts.bold, "right", "top")
        dxDrawText(text, lx, ty, rx, ty + lh,
            color, scale, BR.fonts.bold, "right", "top")
    end
    line(cash, y, tocolor(90, 224, 128, 255))
    line(bank, y + lh + BR.sc(4), tocolor(30, 140, 74, 255))
end

function BR.render()
    computeWindow()
    ensureLayout()

    local sw, sh = guiGetScreenSize()
    dxDrawRectangle(0, 0, sw, sh, BR.theme.dim)
    dxDrawRectangle(win.x, win.y, win.w, win.h, BR.theme.window)

    local cx, cy, cw, ch = contentRect()
    local target = ensureRT(cw, ch)
    if target and BR.state.layout then
        if BR.state.rtDirty then
            dxSetRenderTarget(target, true)
            BR.renderLayout(BR.state.layout, BR.state.scrollY, cw, ch)
            dxSetRenderTarget()
            BR.state.rtDirty = false
        end
        dxDrawImage(cx, cy, cw, ch, target)
    end

    drawHover()
    drawSearchOverlay()
    drawScrollbar()
    drawChrome()
    drawHUD()
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

addEvent("ui_browser:open", true)
addEventHandler("ui_browser:open", resourceRoot, function(url)
    BR.doOpen(url or "home")
end)

addEvent("ui_browser:refresh", true)
addEventHandler("ui_browser:refresh", resourceRoot, function()
    BR.refresh()
end)

addEvent("ui_browser:notify", true)
addEventHandler("ui_browser:notify", resourceRoot, function(title, text)
    pcall(function()
        uicore:addNotification(tostring(title or "Open SE"), tostring(text or ""))
    end)
end)

addCommandHandler("browser", function(_, ...)
    local arg = table.concat({ ... }, " ")
    BR.doOpen(arg ~= "" and arg or "home")
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if BR.state.open then BR.close() end
    if isElement(rt) then destroyElement(rt) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    math.randomseed((getTickCount() % 100000) + (getRealTime().timestamp % 100000))
    setElementData(localPlayer, "browserOpen", false, false)
end)
