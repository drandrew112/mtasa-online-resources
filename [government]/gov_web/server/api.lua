-- gov_web :: server/api.lua
-- The http="true" export of the page (POST /gov_web/call/govWebState; in game relayed by web_api).
-- Read only and public, no login: everything comes from v_gov's public snapshot
-- (exports.v_gov:getPublicState, rebuilt every minute), which holds money data of the last
-- 30 days only and no account names. The in-game ui_browser site is registered at the bottom.

local SITE = "gov.sa"
local TITLE = "State of San Andreas"

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

function govWebState()
    if not running("v_gov") then return { ok = false, error = "offline" } end
    local s = exports.v_gov:getPublicState()
    if type(s) ~= "table" or not s.ready then return { ok = false, error = "starting" } end
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
