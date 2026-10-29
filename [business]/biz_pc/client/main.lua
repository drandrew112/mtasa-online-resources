-- biz_pc / client/main.lua
-- Opens OrgOS full screen: a CEF browser on web_api's loader, so the page
-- talks to biz_pc's exports through the web_api bridge exactly like a
-- ui_browser site. Esc or the page's close button closes it. The browser
-- itself lives in client/cefview.lua (dx drawn, delayed destroy).

local browser, openUnit

addEvent("bizpc:open", true)
addEvent("bizpc:close", true)
addEvent("bizpc:pageClose", false)   -- mta.triggerEvent from the page (source = the browser)

local function close()
    if not browser then return end
    CEF.close()
    browser = nil
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
    browser = CEF.open(url(unitId, kind))
    if not browser then return end
    openUnit = unitId
    showCursor(true)
    guiSetInputMode("no_binds")
    setElementData(localPlayer, "browserOpen", true, false)
end)

addEventHandler("bizpc:close", resourceRoot, close)

addEventHandler("bizpc:pageClose", root, function()
    if source == browser then close() end
end)

-- Esc: the page closes its dialog first and the PC only when none is open (orgos.js keydown ->
-- bizpc:pageClose); a page that has not loaded yet cannot answer, then Esc closes it here
addEventHandler("onClientKey", root, function(key, press)
    if not browser or not press or key ~= "escape" then return end
    cancelEvent()
    if not CEF.ready then close() end
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
