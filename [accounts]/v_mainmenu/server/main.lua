-- v_mainmenu server: collects the menu's data from the other resources' APIs and
-- starts the loading on Join game. Every source is optional (only queried while running).

addEvent("onPlayerDataReady")
addEvent("v_mainmenu:join", true)
addEvent("v_mainmenu:reopen", true)
addEvent("v_mainmenu:setPreference", true)
addEvent("v_mainmenu:refresh", true)

local NEWS_COUNT = 8
local MODELS_NOTICE_KEY = "v_mainmenu.modelsNotice"   -- accData: 1 = the first-entry models warning was closed

addEvent("v_mainmenu:modelsNoticeSeen", true)
addEventHandler("v_mainmenu:modelsNoticeSeen", root, function()
    if getElementData(client, "isLogged") ~= true then return end
    exports.v_mysql:setAccData(client, MODELS_NOTICE_KEY, 1)
end)
local inMenu = {}   -- [player] = true while the menu is up

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function try(resName, fn)
    if not resourceRunning(resName) then return nil end
    local ok, a, b = pcall(fn)
    if ok then return a, b end
    outputDebugString(("[v_mainmenu] %s query failed: %s"):format(resName, tostring(a)), 2)
    return nil
end

local function dateText(ts)
    local t = getRealTime(tonumber(ts) or 0)
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

local function collect(player)
    local data = {}
    data.profile = try("v_accounts", function() return exports.v_accounts:getProfile(player) end) or {}
    data.collectibles = try("v_accounts", function() return exports.v_accounts:getCollectibles(player) end) or {}

    local defs, values = try("v_stats", function()
        return exports.v_stats:getStatDefinitions(), exports.v_stats:getStats(player)
    end)
    data.stats = { defs = defs or {}, values = values or {} }

    local vehicles = try("v_ownveh", function() return exports.v_ownveh:getOwnedVehicles(player) end) or {}
    for _, v in ipairs(vehicles) do
        v.name = try("veh_manager", function() return exports.veh_manager:getModelName(v.model) end)
            or getVehicleNameFromModel(v.model) or tostring(v.model)
    end
    data.vehicles = vehicles

    -- in the player's language; every language rides along in a.texts for a language change in the menu
    local news = try("v_news", function() return exports.v_news:getLatestNews(NEWS_COUNT, player) end) or {}
    for _, a in ipairs(news) do a.dateText = dateText(a.date) end
    data.news = news

    data.weekly = try("v_weekly", function() return exports.v_weekly:getWeeklyInfo(0) end) or false

    -- first entry: the custom models warning (pages/models.lua), until the player closes it
    local seen = try("v_mysql", function() return exports.v_mysql:getAccData(player, MODELS_NOTICE_KEY) end)
    data.modelsNotice = resourceRunning("v_modloader") and not (seen == 1 or seen == "1" or seen == true)
    return data
end

local function open(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return end
    if getElementData(player, "loaded") == true then return end
    inMenu[player] = true
    triggerClientEvent(player, "v_mainmenu:open", player, collect(player))
end

addEventHandler("onPlayerDataReady", root, function()
    open(source)
end)

-- v_mainmenu restarted while the player was in the menu
addEventHandler("v_mainmenu:reopen", root, function()
    if resourceRunning("v_loading") and exports.v_loading:isPlayerLoading(client) then return end
    open(client)
end)

addEventHandler("v_mainmenu:refresh", root, function()
    if not inMenu[client] then return end
    triggerClientEvent(client, "v_mainmenu:data", client, collect(client))
end)

addEventHandler("v_mainmenu:join", root, function()
    local player = client
    if not inMenu[player] then return end
    inMenu[player] = nil
    if not resourceRunning("v_loading") or not exports.v_loading:beginLoading(player, "normal") then
        outputServerLog(("[v_mainmenu] could not start the loading of %s"):format(getPlayerName(player)))
        open(player)
    end
end)

addEventHandler("v_mainmenu:setPreference", root, function(id, value)
    local player = client
    if not inMenu[player] or type(id) ~= "string" then return end
    if not resourceRunning("v_accounts") then return end
    exports.v_accounts:setPreference(player, id, value)
    local profile = exports.v_accounts:getProfile(player)
    if profile then triggerClientEvent(player, "v_mainmenu:data", player, { profile = profile }) end
end)

addEventHandler("onPlayerQuit", root, function()
    inMenu[source] = nil
end)
