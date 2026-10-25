-- gov_web :: server/api.lua
-- The http="true" export of the page (POST /gov_web/call/govWebState; in game relayed by web_api).
-- Read only and public, no login. The snapshot is put together here every PUBLIC_REFRESH_MS from
-- the public exports of the gov_* modules (each holds money data of the last 30 days only and no
-- account names); a module that does not run leaves its part empty. The in-game ui_browser site
-- is registered at the bottom.

local SITE = "gov.sa"
local TITLE = "State of San Andreas"
local PUBLIC_REFRESH_MS = 60000
local HISTORY_DAYS = 30

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

--- the table export `fn` of a running resource returns, or nil
local function ask(res, fn)
    if not running(res) then return nil end
    local ok, v = pcall(function() return exports[res][fn](exports[res]) end)
    return ok and type(v) == "table" and v or nil
end

local PUBLIC = { ready = false }

addEvent("gov_core:ready", false)

local function coreReady()
    if not running("gov_core") then return false end
    local ok, v = pcall(function() return exports.gov_core:isGovReady() end)
    return ok and v == true
end

local function rebuild()
    if not coreReady() then PUBLIC = { ready = false }; return end
    local finance = ask("gov_treasury", "getPublicFinance") or {}
    local taxes = ask("gov_tax", "getPublicTaxes") or {}
    local works = ask("gov_works", "getPublicWorks") or {}
    local companies = finance.companies or {}
    -- the works every state company pays
    local byCode = {}
    for _, c in ipairs(companies) do
        c.works = {}
        byCode[c.code] = c
    end
    for _, w in ipairs(works) do
        if w.payerCode and byCode[w.payerCode] then table.insert(byCode[w.payerCode].works, w.name) end
        w.payerCode = nil
    end
    PUBLIC = {
        ready = true, updated = getRealTime().timestamp, days = finance.days or HISTORY_DAYS,
        treasury = finance.treasury or { name = "State Treasury", balance = 0, inSum = 0, outSum = 0, groups = {} },
        daily = finance.daily or {}, companies = companies, works = works, fees = taxes.fees or {},
        taxes = taxes.taxes or { company = 0, income = {}, vat = {}, property = 0, runs = { count = 0, total = 0 } },
        health = ask("gov_health", "getPublicHealth") or { enabled = false, hpPrice = 0, injuries = {} },
        votes = ask("gov_votes", "getPublicVotes") or {},
    }
end

-- built once gov_core is ready (the modules load their data right after gov_core:ready, so a few
-- seconds later), then every PUBLIC_REFRESH_MS
addEventHandler("onResourceStart", resourceRoot, function()
    if coreReady() then rebuild() end
    setTimer(rebuild, PUBLIC_REFRESH_MS, 0)
end)
addEventHandler("gov_core:ready", root, function() setTimer(rebuild, 5000, 1) end)

function govWebState()
    if not running("gov_core") then return { ok = false, error = "offline" } end
    if not PUBLIC.ready then return { ok = false, error = "starting" } end
    local s = {}
    for k, v in pairs(PUBLIC) do s[k] = v end
    s.ok = true
    s.now = getRealTime().timestamp
    return s
end

---------------------------------------------------------------- in-game site

local function registerSite()
    if not running("web_api") then return end
    exports.web_api:registerApp({
        title       = TITLE,
        site        = SITE,
        category    = "services",
        description = TITLE .. " - open government: treasury, budget, taxes, VAT, fees and the state votes.",
        page        = "web/index.html",
    })
end
addEventHandler("onResourceStart", resourceRoot, registerSite)
addEventHandler("onWebApiStart", root, registerSite)
