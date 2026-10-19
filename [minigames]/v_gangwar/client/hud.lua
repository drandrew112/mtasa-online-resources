-- Gang war HUD: ui_core stat rows (bottom right), banners, notifications, money popups.

local uicore = exports.ui_core

local ROWS = { "gw_killed", "gw_left", "gw_time" }

local hud = nil         -- { id, startTick | nil, finished }
local clockTimer = nil

local function fmtTime(ms)
    local s = math.floor((ms or 0) / 1000)
    return ("%02d:%02d"):format(math.floor(s / 60), s % 60)
end

local function stopClock()
    if clockTimer and isTimer(clockTimer) then killTimer(clockTimer) end
    clockTimer = nil
end

local function clear()
    stopClock()
    for _, id in ipairs(ROWS) do uicore:removeStatTracker(id) end
    hud = nil
end

local function drawTime()
    if not hud then return end
    uicore:updateStatTracker("gw_time", hud.startTick and fmtTime(getTickCount() - hud.startTick) or "--:--")
end

addEvent("gangwar:hud", true)
addEventHandler("gangwar:hud", resourceRoot, function(data, id)
    if not data then
        if hud and (not id or hud.id == id) then clear() end
        return
    end
    if not hud or hud.id ~= data.id then
        clear()
        hud = { id = data.id }
        uicore:addStatTracker("gw_time", L("v_gangwar.hud.time"), "--:--", { order = 1 })
        uicore:addStatTracker("gw_left", L("v_gangwar.hud.enemies_left"), data.left, { order = 2, color = { 255, 90, 90 } })
        uicore:addStatTracker("gw_killed", L("v_gangwar.hud.enemies_killed"), data.killed, { order = 3 })
    end
    uicore:updateStatTracker("gw_killed", data.killed)
    uicore:updateStatTracker("gw_left", data.left)
    if data.elapsed and not hud.startTick then hud.startTick = getTickCount() - data.elapsed end
    if data.finished then
        hud.finished = true
        stopClock()
        if data.elapsed then hud.startTick = getTickCount() - data.elapsed end
        drawTime()
        return
    end
    drawTime()
    if hud.startTick and not clockTimer then clockTimer = setTimer(drawTime, 1000, 0) end
end)

addEvent("gangwar:banner", true)
addEventHandler("gangwar:banner", resourceRoot, function(key)
    uicore:setBanner(L("v_gangwar.main.title"), L(key))
end)

addEvent("gangwar:notify", true)
addEventHandler("gangwar:notify", resourceRoot, function(title, text)
    uicore:addNotification(title, text)
end)

addEvent("gangwar:reward", true)
addEventHandler("gangwar:reward", resourceRoot, function(money)
    if tonumber(money) and money > 0 then uicore:showMoney("add", money, "cash") end
end)

addEvent("gangwar:summary", true)
addEventHandler("gangwar:summary", resourceRoot, function(s)
    if s.test then
        uicore:addNotification(L("v_gangwar.main.title"), L("v_gangwar.main.summary_test", {
            name = s.name, kills = s.kills, total = s.total, time = fmtTime(s.duration),
        }))
        return
    end
    uicore:addNotification(L("v_gangwar.main.title"), L("v_gangwar.main.summary", {
        name = s.name, kills = s.kills, total = s.total, time = fmtTime(s.duration),
        money = L.money(s.money + s.killMoney), xp = s.xp + s.killXp,
    }))
end)

addEventHandler("onClientResourceStop", resourceRoot, stopClock)
