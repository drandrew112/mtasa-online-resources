if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- Donate panel, server side (client: client/donate.lua, settings: donate_config.lua).
--
-- History: the player's rows of the v_admin payments table (DONATE.table, only
-- read here): approved / rejected ones credited to the account, pending ones
-- whose comment names the account (v_admin `suggested`).
--
-- Events: a temporary multiplier above DONATE.baseMultiplier. They are kept in
-- DONATE.eventsFile (not in MySQL), so they live on this server instance only.
-- A payment gets the multiplier of the event that was running when it was
-- PAID (v_admin offers it as the default on approval).
--
--   /donateevent <multiplier> <hours> [label]   start an event (admin >= DONATE.adminLevel)
--   /donateevent stop                           end the running events
--   /donateevent                                show the running event
--
-- Exports:
--   getDonateMultiplier([timestamp]) -> number   multiplier at that time (default: now)
--   getDonateEvent() -> { multiplier, from, to, label, by } | false   the running event

local events = {}
local lastAsk = {}

local function now() return getRealTime().timestamp end

local function accountOf(player)
    local res = getResourceFromName("v_accounts")
    if not (res and getResourceState(res) == "running") then return nil end
    local name = exports.v_accounts:getName(player)
    return type(name) == "string" and name ~= "" and name or nil
end

local function adminLevel(player)
    local res = getResourceFromName("v_mysql")
    if not (res and getResourceState(res) == "running") then return 0 end
    return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
end

local function fmtDate(ts)
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

local function notify(player, key, params)
    triggerClientEvent(player, "ui_help:donateNotify", resourceRoot, L.msg(key, params))
end

--------------------------------------------------------------------------------
-- events (file)
--------------------------------------------------------------------------------

local function saveEvents()
    if fileExists(DONATE.eventsFile) then fileDelete(DONATE.eventsFile) end
    local f = fileCreate(DONATE.eventsFile)
    if not f then return outputDebugString("[ui_help] donate: cannot write " .. DONATE.eventsFile, 2) end
    fileWrite(f, toJSON(events, false, "tabs"))
    fileClose(f)
end

local function loadEvents()
    events = {}
    if not fileExists(DONATE.eventsFile) then return end
    local f = fileOpen(DONATE.eventsFile, true)
    if not f then return end
    local data = fromJSON(fileRead(f, fileGetSize(f)) or "")
    fileClose(f)
    local keepFrom = now() - DONATE.keepEventsDays * 86400
    for _, e in ipairs(type(data) == "table" and data or {}) do
        local m, from, to = tonumber(e.multiplier), tonumber(e.from), tonumber(e.to)
        if m and from and to and to > keepFrom then
            events[#events + 1] = { multiplier = m, from = from, to = to, label = tostring(e.label or ""), by = tostring(e.by or "") }
        end
    end
end

--- the event running at ts (the highest multiplier when several), or nil
local function eventAt(ts)
    local best
    for _, e in ipairs(events) do
        if ts >= e.from and ts < e.to and (not best or e.multiplier > best.multiplier) then best = e end
    end
    return best
end

function getDonateMultiplier(ts)
    local e = eventAt(math.floor(tonumber(ts) or now()))
    return e and e.multiplier or DONATE.baseMultiplier
end

function getDonateEvent()
    local e = eventAt(now())
    return e and { multiplier = e.multiplier, from = e.from, to = e.to, label = e.label, by = e.by } or false
end

local function broadcastEvent()
    triggerClientEvent(root, "ui_help:donateEvent", resourceRoot, getDonateEvent())
end

-- an event that ends while the server runs: open panels drop the banner
local endTimer
local function scheduleEnd()
    if endTimer and isTimer(endTimer) then killTimer(endTimer) end
    endTimer = nil
    local e = eventAt(now())
    if not e then return end
    local left = math.max(1, e.to - now())
    if left > 86400 then left = 86400 end -- setTimer limit is far, but a day is enough: it reschedules
    endTimer = setTimer(function() broadcastEvent() scheduleEnd() end, left * 1000, 1)
end

addCommandHandler("donateevent", function(player, _, a, b, ...)
    if adminLevel(player) < DONATE.adminLevel then return notify(player, "ui_help.donate.cmd.no_right") end
    local who = accountOf(player) or getPlayerName(player)

    if not a then
        local e = getDonateEvent()
        if not e then return notify(player, "ui_help.donate.cmd.none") end
        return notify(player, "ui_help.donate.cmd.running", { mult = e.multiplier, time = fmtDate(e.to), label = e.label })
    end

    if a == "stop" then
        local t, n = now(), 0
        for _, e in ipairs(events) do
            if t >= e.from and t < e.to then e.to = t n = n + 1 end
        end
        if n == 0 then return notify(player, "ui_help.donate.cmd.none") end
        saveEvents()
        scheduleEnd()
        broadcastEvent()
        outputServerLog(("[ui_help] donate event stopped by %s"):format(who))
        return notify(player, "ui_help.donate.cmd.stopped")
    end

    local mult, hours = math.floor(tonumber(a) or 0), tonumber(b)
    if mult <= DONATE.baseMultiplier or mult > DONATE.maxMultiplier or not hours
        or hours <= 0 or hours > DONATE.maxEventHours then
        return notify(player, "ui_help.donate.cmd.usage",
            { min = DONATE.baseMultiplier + 1, max = DONATE.maxMultiplier, hours = DONATE.maxEventHours })
    end
    local label = table.concat({ ... }, " "):sub(1, 64)
    local t = now()
    events[#events + 1] = { multiplier = mult, from = t, to = t + math.floor(hours * 3600), label = label, by = who }
    saveEvents()
    scheduleEnd()
    broadcastEvent()
    outputServerLog(("[ui_help] donate event x%d for %s h started by %s %s"):format(mult, tostring(hours), who, label))
    notify(player, "ui_help.donate.cmd.started", { mult = mult, hours = hours })
end)

--------------------------------------------------------------------------------
-- panel data
--------------------------------------------------------------------------------

local function rowOut(r)
    local created = tonumber(r.created_ts) or tonumber(r.copied_at) or 0
    local amount = tonumber(r.amount) or 0
    local status = tostring(r.status)
    local mult, money
    if status == "approved" then
        mult, money = tonumber(r.multiplier) or DONATE.baseMultiplier, tonumber(r.bank_money) or 0
    elseif status == "pending" then
        -- what the approval will most likely book: the multiplier at payment time
        mult = getDonateMultiplier(created)
        money = amount * mult
    else
        mult, money = 0, 0
    end
    return {
        id = tonumber(r.id), amount = amount, status = status, created = created,
        multiplier = mult, bankMoney = money,
        reviewedBy = tostring(r.reviewed_by or ""), reviewedAt = tonumber(r.reviewed_at) or 0,
        reason = tostring(r.reject_reason or ""),
    }
end

addEvent("ui_help:donateRequest", true)
addEventHandler("ui_help:donateRequest", resourceRoot, function()
    local player = client
    if not player then return end
    local t = getTickCount()
    if lastAsk[player] and t - lastAsk[player] < 2000 then return end
    lastAsk[player] = t

    local data = { base = DONATE.baseMultiplier, event = getDonateEvent(), account = accountOf(player) or false, history = false }
    if not data.account then return triggerClientEvent(player, "ui_help:donateData", resourceRoot, data) end

    local name = data.account:lower()
    MYSQL.query(function(rows)
        if not isElement(player) then return end
        if rows then
            data.history = {}
            for i, r in ipairs(rows) do data.history[i] = rowOut(r) end
        else
            data.error = true
        end
        triggerClientEvent(player, "ui_help:donateData", resourceRoot, data)
    end, "SELECT id, amount, status, multiplier, bank_money, reviewed_by, reviewed_at, reject_reason, copied_at, "
        .. "UNIX_TIMESTAMP(created) AS created_ts FROM `" .. DONATE.table .. "` "
        .. "WHERE LOWER(account) = ? OR (account IS NULL AND LOWER(suggested) = ?) ORDER BY id DESC LIMIT ?",
        name, name, DONATE.historyLimit)
end)

addEventHandler("onPlayerQuit", root, function() lastAsk[source] = nil end)

loadEvents()
scheduleEnd()
