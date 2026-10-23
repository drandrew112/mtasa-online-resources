-- biz_pc / client/main.lua
-- Opens OrgOS centred at 80% of the screen: a CEF browser on web_api's loader, so the page
-- talks to biz_pc's exports through the web_api bridge exactly like a
-- ui_browser site. Esc or the page's close button closes it.

local gui, browser, openUnit

addEvent("bizpc:open", true)
addEvent("bizpc:close", true)
addEvent("bizpc:pageClose", false)   -- mta.triggerEvent from the page (source = the browser)

local function close()
    if not gui then return end
    if isElement(gui) then destroyElement(gui) end
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
    local w, h = math.floor(sw * 0.8), math.floor(sh * 0.8)
    gui = guiCreateBrowser(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, true, false, false)
    if not gui then return end
    browser = guiGetBrowser(gui)
    openUnit = unitId
    showCursor(true)
    guiSetInputMode("no_binds")
    setElementData(localPlayer, "browserOpen", true, false)
    addEventHandler("onClientBrowserCreated", browser, function()
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
