-- Active language of this client.
--
-- Before login the language comes from the private client file (@language.txt,
-- default "en"), so the login screen is already in the remembered language.
-- The server then answers with the account language ("v_locals:applyLanguage").
-- Every change fires the client event
--   v_locals:onClientLanguageChange(newLang, oldLang)   (source = root)
-- which every client lib listens to.

local current = LOC.DEFAULT_LANG

local function readRemembered()
    if not fileExists(LOC.CLIENT_FILE) then return nil end
    local f = fileOpen(LOC.CLIENT_FILE, true)
    if not f then return nil end
    local code = (fileRead(f, math.min(fileGetSize(f), 16)) or ""):gsub("%s", "")
    fileClose(f)
    return code
end

local function remember(code)
    local f = fileExists(LOC.CLIENT_FILE) and fileOpen(LOC.CLIENT_FILE) or fileCreate(LOC.CLIENT_FILE)
    if not f then return end
    fileSetPos(f, 0)
    fileWrite(f, code .. string.rep(" ", 8))   -- padding overwrites a longer old code
    fileClose(f)
end

function locGetLanguage()
    return current
end

-- switches the language locally; returns true when it changed
function locApplyLanguage(code)
    if not Catalog.isEnabled(code) or code == current then return false end
    local old = current
    current = code
    remember(code)
    triggerEvent("v_locals:onClientLanguageChange", root, code, old)
    return true
end

-- player choice: applied at once, the server stores it on the account
function locSetLanguage(code)
    if not Catalog.isEnabled(code) then return false end
    locApplyLanguage(code)
    triggerServerEvent("v_locals:requestLanguage", resourceRoot, code)
    return true
end

addEvent("v_locals:onClientLanguageChange")

addEvent("v_locals:applyLanguage", true)
addEventHandler("v_locals:applyLanguage", resourceRoot, function(code)
    locApplyLanguage(code)
end)

do
    local remembered = readRemembered()
    if Catalog.isEnabled(remembered) then current = remembered end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("v_locals:clientHello", resourceRoot, current)
end)

LOCALS_INTERNAL.getLanguage = locGetLanguage
