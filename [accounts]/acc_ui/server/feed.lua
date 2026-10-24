-- acc_ui server: which panel a joining client gets, and the cards' data
-- (v_news latest articles, v_weekly info). Both resources are optional: no
-- include, they are only queried while running.

local NEWS_COUNT = 200          -- candidates, newest first; cut to NEWS_DAYS below
local NEWS_DAYS  = 7            -- the card shows the articles of the last 7 days

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function isLogged(player)
    return getElementData(player, "isLogged") == true
end

local function sendWeekly(player)
    if not resourceRunning("v_weekly") then return end
    local ok, info = pcall(function() return exports.v_weekly:getWeeklyInfo(0) end)
    if ok and type(info) == "table" then
        triggerClientEvent(player, "acc_ui:weekly", player, info)
    end
end

local function newsList()
    if not resourceRunning("v_news") then return nil end
    local ok, list = pcall(function() return exports.v_news:getLatestNews(NEWS_COUNT) end)
    if not ok or type(list) ~= "table" then return nil end
    local out = {}
    local since = getRealTime().timestamp - NEWS_DAYS * 86400
    for _, a in ipairs(list) do
        local date = tonumber(a.date) or 0
        if date < since then break end
        local t = getRealTime(date)
        -- title / body = the default language; texts = every language, the client picks its own
        out[#out + 1] = { dateText = ("%04d.%02d.%02d"):format(t.year + 1900, t.month + 1, t.monthday),
                   title = tostring(a.title or ""), body = tostring(a.body or ""),
                   texts = type(a.texts) == "table" and a.texts or {} }
    end
    return out
end

local function sendNews(player, list)
    list = list or newsList()
    if list then triggerClientEvent(player, "acc_ui:news", player, list) end
end

-- the players still in front of the login panels
local function waitingPlayers()
    local out = {}
    for _, p in ipairs(getElementsByType("player")) do
        if not isLogged(p) and getElementData(p, "banned") ~= true then out[#out + 1] = p end
    end
    return out
end

addEvent("acc_ui:requestPanel", true)
addEventHandler("acc_ui:requestPanel", root, function()
    local player = client
    if not isElement(player) then return end

    if getElementData(player, "banned") == true then
        triggerClientEvent(player, "acc_ui:setPanel", player, "banned")
    elseif isLogged(player) then
        triggerClientEvent(player, "acc_ui:setPanel", player, nil)
    else
        triggerClientEvent(player, "acc_ui:setPanel", player, "login")
        sendWeekly(player)
        sendNews(player)
    end
end)

addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if name == "v_weekly" then
        for _, p in ipairs(waitingPlayers()) do sendWeekly(p) end
    elseif name == "v_news" then
        setTimer(function()
            local list = newsList()
            for _, p in ipairs(waitingPlayers()) do sendNews(p, list) end
        end, 3000, 1)
    end
end)

-- an article was added / edited / deleted or a scheduled one went public
addEvent("onNewsChanged")
addEventHandler("onNewsChanged", root, function()
    local list = newsList()
    for _, p in ipairs(waitingPlayers()) do sendNews(p, list) end
end)
