-- ui_browser :: core/webview.lua
-- "Web" sites: a real (CEF) page shown in the content area instead of vhtml
-- markup. Registered with   registerBrowserSite(url, { web = "http://mta/<res>/page.html", ... })
-- The page must be a client file of its resource (local CEF page). The browser
-- is created when the site is opened and destroyed when leaving it, so every
-- visit starts fresh. Mouse and keyboard input inside the content area go to
-- the page (right click too - the chrome's back button still works).
--
-- The owning resource talks to its page itself: mta.triggerEvent() in the page
-- triggers events on the browser element, answers go back with
-- executeBrowserJavascript(browser, ...). "ui_browser:webCreated" (url, browser)
-- is triggered on localPlayer once the page starts loading.

BR.web = {
    url     = nil,    -- CEF url of the current web site (nil = no web view)
    browser = nil,
    ready   = false,
    w = 0, h = 0,
    rect    = nil,    -- last drawn content rect {x, y, w, h}
    focused = false,
}

addEvent("ui_browser:webCreated", false)

local function destroyView()
    local v = BR.web
    if isElement(v.browser) then destroyElement(v.browser) end
    v.browser, v.ready, v.focused = nil, false, false
    focusBrowser(nil)
end

function BR.webOpen(url)
    if BR.web.url == url and isElement(BR.web.browser) then return end
    destroyView()
    BR.web.url = url
end

function BR.webClose()
    destroyView()
    BR.web.url = nil
end

function BR.webActive()
    return BR.web.url ~= nil
end

local function createView(w, h)
    local v = BR.web
    v.w, v.h = w, h
    v.browser = createBrowser(w, h, true, false)
    if not v.browser then return end
    local url = v.url
    addEventHandler("onClientBrowserCreated", v.browser, function()
        loadBrowserURL(source, url)
        triggerEvent("ui_browser:webCreated", localPlayer, url, source)
    end)
    addEventHandler("onClientBrowserDocumentReady", v.browser, function()
        v.ready = true
    end)
end

function BR.webDraw(x, y, w, h)
    local v = BR.web
    w, h = math.floor(w), math.floor(h)
    v.rect = { x = x, y = y, w = w, h = h }

    if not isElement(v.browser) then
        createView(w, h)
    elseif v.w ~= w or v.h ~= h then
        resizeBrowser(v.browser, w, h)
        v.w, v.h = w, h
    end

    dxDrawRectangle(x, y, w, h, tocolor(15, 18, 22, 255))
    if isElement(v.browser) and v.ready then
        dxDrawImage(x, y, w, h, v.browser, 0, 0, 0, tocolor(255, 255, 255, 255))
    else
        dxDrawText("Loading...", x, y, x + w, y + h, tocolor(160, 170, 180, 255),
            BR.fscale(1.1), BR.fonts.regular, "center", "center")
    end
end

-- Returns true when the point is inside the web content area.
function BR.webContains(ax, ay)
    local r = BR.web.rect
    return BR.webActive() and r and ax >= r.x and ax <= r.x + r.w and ay >= r.y and ay <= r.y + r.h
end

-- Mouse button (from onClientClick). Returns true when consumed.
function BR.webMouseButton(button, state, ax, ay)
    local v = BR.web
    if not isElement(v.browser) then return false end
    if not BR.webContains(ax, ay) then
        if state == "down" and v.focused then
            focusBrowser(nil)
            v.focused = false
        end
        -- release outside still ends a drag inside the page
        if state == "up" then injectBrowserMouseUp(v.browser, button) end
        return false
    end
    injectBrowserMouseMove(v.browser, ax - v.rect.x, ay - v.rect.y)
    if state == "down" then
        if not v.focused then
            focusBrowser(v.browser)
            v.focused = true
        end
        injectBrowserMouseDown(v.browser, button)
    else
        injectBrowserMouseUp(v.browser, button)
    end
    return true
end

function BR.webWheel(delta)
    local v = BR.web
    if not isElement(v.browser) then return false end
    local mx, my = getCursorPosition()
    if not mx then return false end
    local sw, sh = guiGetScreenSize()
    if not BR.webContains(mx * sw, my * sh) then return false end
    injectBrowserMouseWheel(v.browser, delta * 40, 0)
    return true
end

addEventHandler("onClientCursorMove", root, function(_, _, ax, ay)
    local v = BR.web
    if not BR.state.open or not isElement(v.browser) or not v.rect then return end
    injectBrowserMouseMove(v.browser, ax - v.rect.x, ay - v.rect.y)
end)
