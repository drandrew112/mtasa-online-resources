-- ui_browser :: exports.lua (kliens)
-- Publikus API. Ezek a fuggvenyek a meta.xml-ben exportkent szerepelnek.

-- Megnyitja a bongeszot a fooldalon.
function openBrowser()
    BR.doOpen("home")
    return true
end

-- Megnyitja a bongeszot es egy adott webcimre navigal (pl. "autohaus.vm").
-- Ha a bongeszo mar nyitva van, csak navigal.
function openBrowserSite(url)
    BR.doOpen(tostring(url or "home"))
    return true
end

-- Uj virtualis weboldal regisztralasa mas resource-bol.
--   registerBrowserSite("mycars.vm", { title=, category=, desc=, markup= | builder= })
function registerBrowserSite(url, def)
    return BR.registerSite(url, def)
end

function isBrowserOpen()
    return BR.isOpen()
end

function closeBrowser()
    BR.close()
    return true
end
