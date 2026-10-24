-- biz_pc / client/main.lua
-- Opens OrgOS full screen: a CEF browser on web_api's loader, so the page
-- talks to biz_pc's exports through the web_api bridge exactly like a
-- ui_browser site. Esc or the page's close button closes it.

local gui, browser, openUnit

addEvent("bizpc:open", true)
addEvent("bizpc:close", true)
addEvent("bizpc:pageClose", false)   -- mta.triggerEvent from the page (source = the browser)

-- Destroying a CEF browser synchronously crashes the client (CTD) when it still has input focus
-- or when it happens inside one of its own events (the page's close button arrives as
-- mta.triggerEvent from the page, Esc is also delivered to the focused page). So: drop focus,
-- hide and detach now, destroy a bit later.
local function disposeBrowser(g, b)
    if isElement(b) then
        focusBrowser(nil)
        setBrowserRenderingPaused(b, true)
    end
    if isElement(g) then
        guiSetVisible(g, false)
        guiSetEnabled(g, false)
        setTimer(function() if isElement(g) then destroyElement(g) end end, 100, 1)
    end
end

local function close()
    if not gui then return end
    disposeBrowser(gui, browser)
    gui, browser = nil, nil
    showCursor(false)
    guiSetInputMode("allow_binds")
    setElementData(localPlayer, "browserOpen", false, false)
    if openUnit then triggerServerEvent("bizpc:closed", resourceRoot) end
    openUnit = nil
end

local function url(unitId, kind)
    return ("http://mta/web_api/loader.html?app=%s&page=web/index.html&v=%d&unit=%d&kind=%s"):format(
        getResourceName(resource), getTickCount(), unitId, tostring(kind or ""))
end

addEventHandler("bizpc:open", resourceRoot, function(unitId, kind)
    close()
    local sw, sh = guiGetScreenSize()
    gui = guiCreateBrowser(0, 0, sw, sh, true, false, false)
    if not gui then return end
    browser = guiGetBrowser(gui)
    openUnit = unitId
    showCursor(true)
    guiSetInputMode("no_binds")
    setElementData(localPlayer, "browserOpen", true, false)
    addEventHandler("onClientBrowserCreated", browser, function()
        if source ~= browser then return end   -- closed before CEF was ready
        loadBrowserURL(source, url(unitId, kind))
        focusBrowser(source)
    end)
end)

addEventHandler("bizpc:close", resourceRoot, close)

addEventHandler("bizpc:pageClose", root, function()
    if source == browser then close() end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not gui or not press then return end
    if key == "escape" then
        cancelEvent()
        close()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
