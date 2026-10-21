-- Web tablet: the unit tablet (client/tablet.lua) as a web page, for crew members who are
-- signed in to a unit. Logs in with the acc_auth account (exports.acc_auth:httpLogin),
-- a separate instance from the in-game tablet. English only (web UI).
--
-- The session only proves WHO the account is; the unit is looked up on every call from the
-- online player on that account (Units.byPlayer), so signing in / out in game is followed
-- live. Called through med_web (webCall in server/http.lua), first argument = session token.

WebTablet = {
    sessions  = {},   -- [token] = { account, lastSeen }
    events    = {},   -- ring of { id, unit, title, text, alert }
    nextEvent = 1,
}

local SESSION_TIMEOUT = 10 * 60
local MAX_FAILS, FAIL_WINDOW = 5, 60
local MAX_EVENTS = 100
local fails = {}     -- [client] = { timestamps }

local DENIED = { ok = false, error = "unauthorized" }

local function accountsRunning()
    local res = getResourceFromName("acc_auth")
    return res and getResourceState(res) == "running"
end

---------------------------------------------------------------- notifications

-- Called by Units.notify: what the in-game tablet would show / sound, queued for the page.
function WebTablet.push(u, title, text, alert)
    if type(text) == "function" then text = text(nil) end
    local id = WebTablet.nextEvent
    WebTablet.nextEvent = id + 1
    WebTablet.events[#WebTablet.events + 1] = {
        id = id, unit = u.id, title = tostring(title or ""), text = tostring(text or ""), alert = alert == true,
    }
    while #WebTablet.events > MAX_EVENTS do table.remove(WebTablet.events, 1) end
end

---------------------------------------------------------------- sessions

local function tooManyFails(id)
    local t, keep = now(), {}
    for _, ts in ipairs(fails[id] or {}) do
        if t - ts < FAIL_WINDOW then keep[#keep + 1] = ts end
    end
    fails[id] = keep
    return #keep >= MAX_FAILS
end

local function newToken(account)
    return hash("sha256", table.concat({
        tostring(getTickCount()), tostring(now()), account,
        tostring(math.random(1, 2 ^ 30)), tostring(math.random(1, 2 ^ 30)),
    }, ":"))
end

local function check(token)
    local s = type(token) == "string" and WebTablet.sessions[token]
    if not s then return nil end
    if now() - s.lastSeen > SESSION_TIMEOUT then
        WebTablet.sessions[token] = nil
        return nil
    end
    s.lastSeen = now()
    return s
end

setTimer(function()
    local t = now()
    for token, s in pairs(WebTablet.sessions) do
        if t - s.lastSeen > SESSION_TIMEOUT then WebTablet.sessions[token] = nil end
    end
end, 60000, 0)

-- The unit (and its online player) of an account that is a unit member -> unit, player
local function unitOfAccount(account)
    if not accountsRunning() then return nil end
    for _, p in ipairs(getElementsByType("player")) do
        local u = Units.byPlayer[p]
        if u and exports.acc_auth:getName(p) == account then return u, p end
    end
    return nil
end

---------------------------------------------------------------- payload

local function publicMessage(m)
    return {
        id = m.id, ts = m.ts, time = m.time, channel = m.channel, target = m.target,
        label = m.label, from = m.from, fromDispatch = m.fromDispatch, fromUnit = m.fromUnit, text = m.text,
    }
end

local function state(s, lastMessageId, lastEventId)
    local u, player = unitOfAccount(s.account)
    local out = { ok = true, time = now(), account = s.account, inUnit = u and true or false }

    -- the first call (no event id yet) only learns the current end of the queue
    local sinceEvent = tonumber(lastEventId)
    out.lastEvent = WebTablet.nextEvent - 1
    out.events = {}
    if not u then return out end

    if sinceEvent and sinceEvent >= 0 then
        for _, e in ipairs(WebTablet.events) do
            if e.id > sinceEvent and e.unit == u.id then
                out.events[#out.events + 1] = { id = e.id, title = e.title, text = e.text, alert = e.alert }
            end
        end
    end

    local unit = Units.payload(u).unit
    local members = {}
    for _, m in ipairs(unit.members) do members[#members + 1] = { name = m.name, account = m.account } end
    unit.members = members

    local t = u.task and Tasks.get(u.task)
    local task = false
    if t then
        task = Tasks.public(t)
        task.title, task.description = Tasks.textFor(t, player)
        task.meta, task.responseLog, task.unitLog = nil, nil, nil
        local x, y = Units.position(u)
        task.distance = getDistanceBetweenPoints2D(x, y, t.x, t.y)
    end

    out.unit, out.task = unit, task
    out.messages = {}
    lastMessageId = tonumber(lastMessageId) or 0
    for _, m in ipairs(Chat.forUnit(u.id)) do
        if m.id > lastMessageId then out.messages[#out.messages + 1] = publicMessage(m) end
    end
    return out
end

---------------------------------------------------------------- web API (called through med_web)

local function result(ok, err)
    if ok then return { ok = true } end
    return { ok = false, error = err or "Failed" }
end

function ermTabletLogin(_, username, password)
    local id = Web.callerId()
    if tooManyFails(id) then return { ok = false, error = "Too many failed attempts. Try again in a minute." } end
    if not accountsRunning() then return { ok = false, error = "Account system is not available." } end

    local ok, account = exports.acc_auth:httpLogin(username, password)
    if not ok then
        table.insert(fails[id], now())
        outputServerLog("[erm] failed web tablet login from " .. id)
        return { ok = false, error = account }
    end

    local token = newToken(account)
    WebTablet.sessions[token] = { account = account, lastSeen = now() }
    outputServerLog("[erm] web tablet login: " .. account .. " (" .. id .. ")")
    return { ok = true, token = token, account = account }
end

function ermTabletLogout(token)
    WebTablet.sessions[token] = nil
    return { ok = true }
end

function ermTabletState(token, lastMessageId, lastEventId)
    local s = check(token)
    if not s then return DENIED end
    return state(s, lastMessageId, lastEventId)
end

-- The same actions as the in-game tablet (server/tablet.lua), on the account's unit.
local function withUnit(token, fn)
    local s = check(token)
    if not s then return DENIED end
    local u, player = unitOfAccount(s.account)
    if not u then return { ok = false, error = "You are not a member of any ambulance unit." } end
    return fn(u, player)
end

function ermTabletCaseAction(token, action)
    return withUnit(token, function(u)
        if action ~= "start" and action ~= "stop" then return result(false, "Unknown action.") end
        return result(Units.caseAction(u, action))
    end)
end

function ermTabletLeaveCase(token)
    return withUnit(token, function(u)
        if not u.task then return result(false, "No active case.") end
        return result(Tasks.leave(u.task, u.id))
    end)
end

function ermTabletCloseCase(token, reason)
    return withUnit(token, function(u)
        if not u.task then return result(false, "No active case.") end
        reason = cleanText(reason, 90)
        if #reason < 3 then return result(false, "Give a reason for closing the case.") end
        return result(Tasks.close(u.task, u.callsign .. ": " .. reason))
    end)
end

-- channel: "dispatch" (unit <-> dispatchers) or "case" (every unit on the task + dispatch)
function ermTabletSendMessage(token, text, channel)
    return withUnit(token, function(u, player)
        local from = u.callsign .. " (" .. getPlayerName(player) .. ")"
        local id, err
        if channel == "case" then
            if not u.task then return result(false, "No active case.") end
            id, err = Chat.post("task", u.task, from, false, text, u.id)
        else
            id, err = Chat.post("unit", u.id, from, false, text, u.id)
        end
        return result(id, err)
    end)
end

function ermTabletEndShift(token)
    return withUnit(token, function(u, player)
        Units.signOut(u, "Shift ended by " .. getPlayerName(player) .. " (web tablet).")
        return { ok = true }
    end)
end
