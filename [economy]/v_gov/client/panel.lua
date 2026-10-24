-- v_gov / client/panel.lua
-- The /gov panel (DESIGN.md 3): a full-screen CEF page (web/index.html, opened through web_api's
-- loader for the shared osa.css / osa.js and cache busting). This file only relays:
--
--   page   mta.triggerEvent("v_gov:pageCall", id, action, "[args]")
--          -> "v_gov:call" -> server/panel.lua -> "v_gov:reply" -> GOV._resolve(id, result, error)
--   page   mta.triggerEvent("v_gov:pageReady", "[[keys]]") -> GOV._init({ role, strings })
--
-- Texts stay in v_locals: the page asks for the keys it uses, error keys are translated here.
-- /gov again, Esc or the page's close button closes it. /vote opens web/vote.html the same way.

local gui, browser, role

addEvent("v_gov:pageCall", false)    -- from the page (source = the browser)
addEvent("v_gov:pageReady", false)
addEvent("v_gov:pageClose", false)

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

--------------------------------------------------------------------------------
-- requests
--------------------------------------------------------------------------------

local reqs, nextReq = {}, 0

addEventHandler("v_gov:pageCall", root, function(jsId, action, argsJson)
    if source ~= browser or type(action) ~= "string" then return end
    local args = type(argsJson) == "string" and fromJSON(argsJson) or nil
    nextReq = nextReq + 1
    reqs[nextReq] = { jsId = tonumber(jsId) or 0, action = action }
    triggerServerEvent("v_gov:call", resourceRoot, nextReq, action, type(args) == "table" and args or {})
end)

addEvent("v_gov:reply", true)
addEventHandler("v_gov:reply", resourceRoot, function(id, result, err)
    local req = reqs[id]
    reqs[id] = nil
    if not req then return end
    if result == false then return js("_resolve", req.jsId, false, text(tostring(err or "v_gov.err.unknown"))) end
    if req.action == "treasuryLedger" and type(result) == "table" then
        for _, r in ipairs(result.rows or {}) do r.text = txText(r) end
    end
    js("_resolve", req.jsId, result, false)
end)

addEventHandler("v_gov:pageReady", root, function(keysJson)
    if source ~= browser then return end
    local keys = type(keysJson) == "string" and fromJSON(keysJson) or {}
    local strings = {}
    for _, k in ipairs(type(keys) == "table" and keys or {}) do
        if type(k) == "string" and L.has(k) then strings[k] = L.text(k) end
    end
    js("_init", { role = role, strings = strings })
    focusBrowser(browser)
end)

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

-- Destroying a CEF browser synchronously crashes the client (CTD) when it still has input focus
-- or when it happens inside one of its own events (the page's close button / Esc arrive as
-- mta.triggerEvent from the page). So: drop focus, hide and detach now, destroy a bit later.
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
    gui, browser, reqs = nil, nil, {}
    showCursor(false)
    guiSetInputMode("allow_binds")
    setElementData(localPlayer, "browserOpen", false, false)
end

local function open(page)
    close()
    local sw, sh = guiGetScreenSize()
    gui = guiCreateBrowser(0, 0, sw, sh, true, false, false)
    if not gui then return end
    browser = guiGetBrowser(gui)
    showCursor(true)
    guiSetInputMode("no_binds")
    setElementData(localPlayer, "browserOpen", true, false)
    addEventHandler("onClientBrowserCreated", browser, function()
        if source ~= browser then return end   -- closed before CEF was ready
        loadBrowserURL(source, ("http://mta/web_api/loader.html?app=%s&page=web/%s&v=%d"):format(
            getResourceName(resource), page, getTickCount()))
        focusBrowser(source)
    end)
end

addEventHandler("v_gov:pageClose", root, function()
    if source == browser then close() end
end)

-- Esc: the page closes its dialog first, the panel only when none is open
addEventHandler("onClientKey", root, function(key, press)
    if not gui or not press or key ~= "escape" then return end
    cancelEvent()
    js("_escape")
end)

addEvent("v_gov:open", true)
addEventHandler("v_gov:open", resourceRoot, function(r)
    role = r
    if gui then close() else open("index.html") end
end)

-- /vote: the open state votes (any logged-in player)
addEvent("v_gov:openVote", true)
addEventHandler("v_gov:openVote", resourceRoot, function()
    if gui then close() else open("vote.html") end
end)

addEvent("v_gov:voteOpened", true)
addEventHandler("v_gov:voteOpened", resourceRoot, function(title)
    pcall(function() exports.ui_core:addNotification(text("v_gov.ui.vote_new"), tostring(title) .. "  -  /vote") end)
end)

addEvent("v_gov:denied", true)
addEventHandler("v_gov:denied", resourceRoot, function()
    pcall(function() exports.ui_core:addNotification("/gov", text("v_gov.err.no_right")) end)
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
