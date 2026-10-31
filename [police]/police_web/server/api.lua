-- police_web :: server/api.lua
-- The public police site (web_api): one http="true" export, the cached data of police_system (getPublicStats; the
-- names in it are English, the site is English). The in-game ui_browser site is registered at the bottom.

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

function policeWebStats()
    if not running("police_system") then return { ok = false, error = "offline" } end
    local ok, d = pcall(function() return exports.police_system:getPublicStats() end)
    if not ok or not d then return { ok = false, error = "loading" } end
    return { ok = true, data = d }
end

local function registerSite()
    if not running("web_api") then return end
    exports.web_api:registerApp({
        title = "San Andreas Police", site = "sapd.sa", category = "services",
        description = "San Andreas Police Department - join the police, statistics, warrants, penal code.",
        page = "web/index.html",
    })
end
addEventHandler("onResourceStart", resourceRoot, registerSite)
addEventHandler("onWebApiStart", root, registerSite)
