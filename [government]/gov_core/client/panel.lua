-- gov_core / client/panel.lua
-- The /gov panel: a full-screen CEF page (web/index.html, opened through web_api's loader for the
-- shared osa.css / osa.js and cache busting). The page loads the page scripts of the running
-- modules (http://mta/<module>/<script>). This file only relays:
--
--   page   mta.triggerEvent("gov_core:pageCall", id, action, "[args]")
--          -> "gov_core:call" -> server/registry.lua -> module -> "gov_core:reply" -> GOV._resolve(id, result, error)
--   page   mta.triggerEvent("gov_core:pageReady", "[[keys]]") -> GOV._init({ access, pages, categories, sectors, strings })
--   page   mta.triggerEvent("gov_core:pageStrings", "[[keys]]") -> GOV._strings(strings)
--
-- Texts stay in v_locals: the page asks for the keys it uses, error keys are translated here.
-- /gov again, Esc or the page's close button closes it. Other gov_* pages (gov_votes /vote) are
-- opened with the client export openGovPage(resource, page) and use the same relay.

local browser
-- access = { super, title, grants = { {perm, branch} }, branchOf } (server GOV.accessOf)
local access, pages, categories, sectors = {}, {}, {}, {}

addEvent("gov_core:pageCall", false)    -- from the page (source = the browser)
addEvent("gov_core:pageReady", false)
addEvent("gov_core:pageStrings", false)
addEvent("gov_core:pageClose", false)

local function js(fn, ...)
    if not isElement(browser) then return end
    local args = {}
    for i, v in ipairs({ ... }) do args[i] = toJSON(v, true):match("^%[%s*(.*)%s*%]$") or "null" end
    executeBrowserJavascript(browser, ("window.GOV && GOV.%s(%s)"):format(fn, table.concat(args, ",")))
end

local function text(key, params)
    return L.has(key) and L.text(key, params or {}) or key
end

--- the ledger row text of v_bank (same as the bank app)
local function txText(r)
    local base = "v_bank.tx." .. tostring(r.key)
    local dir = base .. ((tonumber(r.amount) or 0) < 0 and ".out" or ".in")
    local key = L.has(dir) and dir or base
    return L.has(key) and L.text(key, type(r.params) == "table" and r.params or {}) or tostring(r.key)
end

local function stringsOf(keysJson)
    local keys = type(keysJson) == "string" and fromJSON(keysJson) or {}
    local strings = {}
    for _, k in ipairs(type(keys) == "table" and keys or {}) do
        if type(k) == "string" and L.has(k) then strings[k] = L.text(k) end
    end
    return strings
end

--------------------------------------------------------------------------------
-- requests
--------------------------------------------------------------------------------

local reqs, nextReq = {}, 0

addEventHandler("gov_core:pageCall", root, function(jsId, action, argsJson)
    if source ~= browser or type(action) ~= "string" then return end
    local args = type(argsJson) == "string" and fromJSON(argsJson) or nil
    nextReq = nextReq + 1
    reqs[nextReq] = { jsId = tonumber(jsId) or 0, action = action }
    triggerServerEvent("gov_core:call", resourceRoot, nextReq, action, type(args) == "table" and args or {})
end)

addEvent("gov_core:reply", true)
addEventHandler("gov_core:reply", resourceRoot, function(id, result, err)
    local req = reqs[id]
    reqs[id] = nil
    if not req then return end
    if result == false then return js("_resolve", req.jsId, false, text(tostring(err or "gov_core.err.unknown"))) end
    -- a module marks v_bank ledger rows (gov_treasury treasuryLedger): their text is made here
    if type(result) == "table" and result.ledgerRows then
        for _, r in ipairs(result.rows or {}) do r.text = txText(r) end
    end
    js("_resolve", req.jsId, result, false)
end)

addEventHandler("gov_core:pageReady", root, function(keysJson)
    if source ~= browser then return end
    js("_init", { access = access, pages = pages, categories = categories, sectors = sectors, strings = stringsOf(keysJson) })
    focusBrowser(browser)
end)

addEventHandler("gov_core:pageStrings", root, function(keysJson)
    if source ~= browser then return end
    js("_strings", stringsOf(keysJson))
end)

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

-- the browser itself lives in client/cefview.lua (dx drawn, delayed destroy)
local function close()
    if not browser then return end
    CEF.close()
    browser, reqs = nil, {}
    showCursor(false)
    guiSetInputMode("allow_binds")
    setElementData(localPlayer, "browserOpen", false, false)
end

--- app = the resource that holds the page, page = its path in that resource (web/....html)
local function open(app, page)
    close()
    browser = CEF.open(("http://mta/web_api/loader.html?app=%s&page=%s&v=%d"):format(app, page, getTickCount()))
    if not browser then return end
    showCursor(true)
    guiSetInputMode("no_binds")
    setElementData(localPlayer, "browserOpen", true, false)
end

addEventHandler("gov_core:pageClose", root, function()
    if source == browser then close() end
end)

-- Esc: the page closes its dialog first, the panel only when none is open (a page that has not
-- loaded yet cannot answer, then Esc closes it here)
addEventHandler("onClientKey", root, function(key, press)
    if not browser or not press or key ~= "escape" then return end
    cancelEvent()
    if CEF.ready then js("_escape") else close() end
end)

addEvent("gov_core:open", true)
addEventHandler("gov_core:open", resourceRoot, function(a, p, c, sc)
    access = type(a) == "table" and a or {}
    sectors = type(sc) == "table" and sc or {}
    pages = type(p) == "table" and p or {}
    categories = type(c) == "table" and c or {}
    if browser then close() else open("gov_core", "web/index.html") end
end)

-- positions / rights changed while the panel is open: new rights + menu (gov_perms)
addEvent("gov_core:access", true)
addEventHandler("gov_core:access", resourceRoot, function(a, p, c)
    access = type(a) == "table" and a or {}
    pages = type(p) == "table" and p or {}
    categories = type(c) == "table" and c or {}
    if browser then js("_access", { access = access, pages = pages, categories = categories }) end
end)

--- export: opens (or, when a gov page is open, closes) a page of another gov_* resource on the
--- same relay, e.g. openGovPage("gov_votes", "web/vote.html")
function openGovPage(app, page)
    if type(app) ~= "string" or not app:match("^[%w_]+$") or type(page) ~= "string" or page:find("..", 1, true) then return false end
    if browser then close() else open(app, page) end
    return true
end

addEvent("gov_core:denied", true)
addEventHandler("gov_core:denied", resourceRoot, function()
    pcall(function() exports.ui_core:addNotification("/gov", text("gov_core.err.no_right")) end)
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
