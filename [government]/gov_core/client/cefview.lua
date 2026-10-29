-- client/cefview.lua (same file in gov_core and biz_pc)
-- One full-screen CEF page: a plain createBrowser drawn with dxDrawImage, mouse / wheel injected
-- here, keyboard through focusBrowser (the ui_browser web site pattern). No guiCreateBrowser:
-- tearing down the CEGUI browser window was what still crashed the client (CTD) on closing.
--
--   CEF.open(url) -> browser     CEF.close()     CEF.browser     CEF.ready (page drawn)
--
-- The browser is never destroyed synchronously: closing usually happens inside one of its own
-- events (the page's close button / Esc arrive as mta.triggerEvent from the page), so it loses
-- focus and input now and is destroyed a moment later.

CEF = { browser = nil, ready = false }

local sw, sh = guiGetScreenSize()
local BG = tocolor(15, 18, 22, 255)
local WHITE = tocolor(255, 255, 255, 255)
local hooked = false

local function draw()
    dxDrawRectangle(0, 0, sw, sh, BG, true)
    if CEF.ready and isElement(CEF.browser) then dxDrawImage(0, 0, sw, sh, CEF.browser, 0, 0, 0, WHITE, true) end
end

local function cursorMove(_, _, ax, ay)
    if isElement(CEF.browser) then injectBrowserMouseMove(CEF.browser, ax, ay) end
end

local function click(button, state, ax, ay)
    local b = CEF.browser
    if not isElement(b) then return end
    injectBrowserMouseMove(b, ax, ay)
    if state == "down" then
        if not isBrowserFocused(b) then focusBrowser(b) end
        injectBrowserMouseDown(b, button)
    else
        injectBrowserMouseUp(b, button)
    end
end

local function wheel(key, press)
    if key ~= "mouse_wheel_up" and key ~= "mouse_wheel_down" then return end
    cancelEvent()
    local b = CEF.browser
    if not press or not isElement(b) then return end
    -- CEF ignores the wheel on an unfocused browser and scrolls under ITS last known pointer
    if not isBrowserFocused(b) then focusBrowser(b) end
    local mx, my = getCursorPosition()
    if mx then injectBrowserMouseMove(b, mx * sw, my * sh) end
    injectBrowserMouseWheel(b, key == "mouse_wheel_up" and 120 or -120, 0)
end

local function hook(on)
    if on == hooked then return end
    hooked = on
    local fn = on and addEventHandler or removeEventHandler
    fn("onClientRender", root, draw)
    fn("onClientCursorMove", root, cursorMove)
    fn("onClientClick", root, click)
    fn("onClientKey", root, wheel)
end

function CEF.close()
    local b = CEF.browser
    CEF.browser, CEF.ready = nil, false
    hook(false)
    if not isElement(b) then return end
    focusBrowser(nil)
    setBrowserRenderingPaused(b, true)
    setTimer(function() if isElement(b) then destroyElement(b) end end, 250, 1)
end

function CEF.open(url)
    CEF.close()
    local b = createBrowser(sw, sh, true, false)
    if not b then return nil end
    CEF.browser = b
    addEventHandler("onClientBrowserCreated", b, function()
        if source ~= CEF.browser then return end   -- closed before CEF was ready
        loadBrowserURL(source, url)
        focusBrowser(source)
    end)
    addEventHandler("onClientBrowserDocumentReady", b, function()
        if source == CEF.browser then CEF.ready = true end
    end)
    hook(true)
    return b
end
