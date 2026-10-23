-- acc_menu server: collects the menu's data from the other resources' APIs and
-- starts the loading on Join game. Every source is optional (only queried while running).

addEvent("onPlayerDataReady")
addEvent("acc_menu:join", true)
addEvent("acc_menu:reopen", true)
addEvent("acc_menu:setPreference", true)
addEvent("acc_menu:refresh", true)

local NEWS_COUNT = 8
local inMenu = {}   -- [player] = true while the menu is up

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function try(resName, fn)
    if not resourceRunning(resName) then return nil end
    local ok, a, b = pcall(fn)
    if ok then return a, b end
    outputDebugString(("[acc_menu] %s query failed: %s"):format(resName, tostring(a)), 2)
    return nil
end

local function dateText(ts)
    local t = getRealTime(tonumber(ts) or 0)
    return ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

local function collect(player)
    local data = {}
    data.profile = try("acc_savesys", function() return exports.acc_savesys:getProfile(player) end) or {}
    data.collectibles = try("acc_savesys", function() return exports.acc_savesys:getCollectibles(player) end) or {}

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
    return data
end

local function open(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return end
    if getElementData(player, "loaded") == true then return end
    inMenu[player] = true
    triggerClientEvent(player, "acc_menu:open", player, collect(player))
end

addEventHandler("onPlayerDataReady", root, function()
    open(source)
end)

-- acc_menu restarted while the player was in the menu
addEventHandler("acc_menu:reopen", root, function()
    if resourceRunning("acc_loading") and exports.acc_loading:isPlayerLoading(client) then return end
    open(client)
end)

addEventHandler("acc_menu:refresh", root, function()
    if not inMenu[client] then return end
    triggerClientEvent(client, "acc_menu:data", client, collect(client))
end)

addEventHandler("acc_menu:join", root, function()
    local player = client
    if not inMenu[player] then return end
    inMenu[player] = nil
    if not resourceRunning("acc_loading") or not exports.acc_loading:beginLoading(player, "normal") then
        outputServerLog(("[acc_menu] could not start the loading of %s"):format(getPlayerName(player)))
        open(player)
    end
end)

addEventHandler("acc_menu:setPreference", root, function(id, value)
    local player = client
    if not inMenu[player] or type(id) ~= "string" then return end
    if not resourceRunning("acc_savesys") then return end
    exports.acc_savesys:setPreference(player, id, value)
    local profile = exports.acc_savesys:getProfile(player)
    if profile then triggerClientEvent(player, "acc_menu:data", player, { profile = profile }) end
end)

addEventHandler("onPlayerQuit", root, function()
    inMenu[source] = nil
end)
