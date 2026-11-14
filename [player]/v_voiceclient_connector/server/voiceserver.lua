-- v_voiceclient_connector / server/voiceserver.lua
-- Sync with the FreeV VoiceServer, every VC.VOICESERVER.SYNC_MS, with OUTGOING HTTPS only (fetchRemote):
--   PUT /api/v1/integration/players   the logged-in players: frequency, unit, on duty, mute (full list)
--   GET /api/v1/integration/state     running transmissions + connected external clients
-- The difference of two state answers gives the events and the v_radar / client updates.
-- (fetchRemote sends everything as POST + X-HTTP-Method-Override, the VoiceServer accepts that.)
--
-- Server events (source = the player, or resourceRoot when the speaker has no player in game):
--   onVoiceRadioTransmitStart (info)            info = { frequency, username, displayName, callsign | false, clientType, transmissionId }
--   onVoiceRadioTransmitStop  (info, reason)    reason = "ended"
--   onVoiceClientConnect      (clientType)      source = player
--   onVoiceClientDisconnect   (clientType, reason)  reason = "gone" (logout, or 20 s without a poll: crashed client)
--   onVoiceServerOffline      ()                after VC.VOICESERVER.OFFLINE_AFTER failed syncs
--   onVoiceServerOnline       ()
-- Server exports: getRadioSpeakers(freq), isPlayerRadioTalking(player), isPlayerVoiceClientConnected(player)

VoiceServer = {
    dirty = true,
    online = nil,        -- nil = unknown yet
    failures = 0,
    busy = false,
    tx = {},             -- [transmissionId] = info (last state)
    conn = {},           -- [sessionId] = { username, clientType }
    lastSpeaker = {},    -- [freq] = { info, endedAt }
    warnedHtml = false,
}

for _, name in ipairs({ "onVoiceRadioTransmitStart", "onVoiceRadioTransmitStop", "onVoiceClientConnect",
    "onVoiceClientDisconnect", "onVoiceServerOffline", "onVoiceServerOnline" }) do
    addEvent(name, false)
end

local CFG = VC.VOICESERVER

local function log(level, fmt, ...)
    outputDebugString("[voiceserver] " .. string.format(fmt, ...), level)
end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function playerOf(username)
    if type(username) ~= "string" or not running("v_accounts") then return nil end
    local ok, p = pcall(function() return exports.v_accounts:playerOnAccount(username) end)
    return ok and isElement(p) and p or nil
end

-- VoiceServer API call; cb(data | nil, errorText)
local function call(method, path, body, cb)
    if CFG.URL == "" or CFG.KEY == "" then return cb(nil, "not configured (VC.VOICESERVER URL / KEY)") end
    local ok = fetchRemote(CFG.URL .. "/api/v1/" .. path, {
        method = "POST",
        queueName = "freev_voiceserver",
        connectionAttempts = 1,
        connectTimeout = CFG.TIMEOUT_MS,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["X-FreeV-Integration"] = CFG.KEY,
            ["X-HTTP-Method-Override"] = method,
        },
        postData = body and toJSON(body, true):sub(2, -2) or "{}",   -- toJSON wraps the value in [ ]
    }, function(data, info)
        if not info or not info.success then
            return cb(nil, "HTTP " .. tostring(info and info.statusCode or "?"))
        end
        if type(data) == "string" and data:find("aes.js", 1, true) then
            -- the host answered with its JavaScript anti-bot page (InfinityFree type hosting):
            -- fetchRemote cannot pass it, the VoiceServer needs a host without that filter
            if not VoiceServer.warnedHtml then
                VoiceServer.warnedHtml = true
                outputServerLog("[v_voiceclient_connector] the VoiceServer host answers with an anti-bot JavaScript page: "
                    .. "the MTA integration cannot work on this host (see VoiceServer docs/MTA-INTEGRATION.md 1.)")
            end
            return cb(nil, "host anti-bot page")
        end
        local res = type(data) == "string" and fromJSON("[" .. data .. "]")
        if type(res) ~= "table" then return cb(nil, "invalid answer") end
        if not res.ok then return cb(nil, tostring(res.error and res.error.code or "error")) end
        cb(res.data or {})
    end)
    if not ok then cb(nil, "fetchRemote refused") end
end

------------------------------------------------------------------------ helpers

local function speakerName(info, player)
    -- in-game players: their in-game display name (as the old v_voice radio showed); others: the VoiceServer name
    if isElement(player) and info.displayName == info.username then
        local ok, d = pcall(function() return exports.v_accounts:getDisplayName(player) end)
        if ok and type(d) == "string" and d ~= "" then return (d:gsub("#%x%x%x%x%x%x", "")) end
    end
    return info.displayName
end

local function toInfo(t)
    return {
        frequency = tonumber(t.frequency),
        username = t.username,
        displayName = t.displayName,
        callsign = t.callsign or false,
        clientType = t.clientType,
        transmissionId = tonumber(t.id),
        state = t.state,
    }
end

-- what the clients on a frequency see as the speaker (v_radar getRadioSpeaker shape)
local function clientSpeaker(info, live)
    local player = playerOf(info.username)
    return {
        player = player or false,
        name = speakerName(info, player),
        unit = info.callsign or false,
        live = live,
        frequency = info.frequency,
        username = info.username,
    }
end

local function sendSpeaker(freq, speaker)
    local list = getRadioFrequencyPlayers(freq)
    if #list > 0 then triggerClientEvent(list, "v_voiceclient_connector:radioSpeaker", resourceRoot, speaker) end
end

function VoiceServer.externalOf(player)
    local acc = Radio.account(player)
    if not acc then return false end
    local lower = acc:lower()
    for _, c in pairs(VoiceServer.conn) do
        if c.username:lower() == lower and c.clientType ~= "mta_cef" then return c.clientType end
    end
    return false
end

------------------------------------------------------------------------ sync

local function playersPayload()
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        local acc = Radio.account(p)
        if acc then
            local muted = tonumber(getElementData(p, "mute_until"))
            list[#list + 1] = {
                username = acc,
                frequency = Radio.freqOf[p] or false,
                callsign = Radio.unitOf[p] or false,
                onDuty = Radio.workOf[p] ~= nil,
                mutedUntil = muted or false,
            }
        end
    end
    return list
end

local function applyState(data)
    local now = getTickCount()
    -- transmissions
    local seen = {}
    for _, t in ipairs(type(data.transmissions) == "table" and data.transmissions or {}) do
        local info = toInfo(t)
        if info.transmissionId and info.frequency then
            seen[info.transmissionId] = true
            local old = VoiceServer.tx[info.transmissionId]
            VoiceServer.tx[info.transmissionId] = info
            local player = playerOf(info.username)
            if not old then
                triggerEvent("onVoiceRadioTransmitStart", player or resourceRoot, info)
                if player then triggerClientEvent(player, "v_voiceclient_connector:radioSelf", resourceRoot, info.state) end
                sendSpeaker(info.frequency, clientSpeaker(info, info.state == "live"))
            elseif old.state ~= info.state then
                if player then triggerClientEvent(player, "v_voiceclient_connector:radioSelf", resourceRoot, info.state) end
                sendSpeaker(info.frequency, clientSpeaker(info, info.state == "live"))
            end
        end
    end
    for id, info in pairs(VoiceServer.tx) do
        if not seen[id] then
            VoiceServer.tx[id] = nil
            local player = playerOf(info.username)
            triggerEvent("onVoiceRadioTransmitStop", player or resourceRoot, info, "ended")
            if player then triggerClientEvent(player, "v_voiceclient_connector:radioSelf", resourceRoot, "off") end
            VoiceServer.lastSpeaker[info.frequency] = { info = info, endedAt = now }
            sendSpeaker(info.frequency, clientSpeaker(info, false))
        end
    end

    -- external client connections
    local conns = {}
    for _, c in ipairs(type(data.connections) == "table" and data.connections or {}) do
        if type(c.sessionId) == "string" then
            conns[c.sessionId] = { username = tostring(c.username), clientType = tostring(c.clientType) }
        end
    end
    local changed = {}
    for id, c in pairs(conns) do
        if not VoiceServer.conn[id] then
            local p = playerOf(c.username)
            if p then
                triggerEvent("onVoiceClientConnect", p, c.clientType)
                changed[p] = true
            end
        end
    end
    for id, c in pairs(VoiceServer.conn) do
        if not conns[id] then
            local p = playerOf(c.username)
            if p then
                triggerEvent("onVoiceClientDisconnect", p, c.clientType, "gone")
                changed[p] = true
            end
        end
    end
    VoiceServer.conn = conns
    for p in pairs(changed) do Radio.sendState(p) end
end

local function setOnline(on)
    if VoiceServer.online == on then return end
    VoiceServer.online = on
    if on then
        outputServerLog("[v_voiceclient_connector] FreeV VoiceServer reachable")
        triggerEvent("onVoiceServerOnline", resourceRoot)
    else
        outputServerLog("[v_voiceclient_connector] FreeV VoiceServer NOT reachable – radio speakers are not shown")
        -- nothing is known any more: end every transmission locally
        applyState({ transmissions = {}, connections = {} })
        triggerEvent("onVoiceServerOffline", resourceRoot)
    end
end

local function failed(err)
    VoiceServer.failures = VoiceServer.failures + 1
    if VoiceServer.failures == 1 or VC.CONFIG.DEBUG then log(2, "sync failed: %s", tostring(err)) end
    if VoiceServer.failures >= CFG.OFFLINE_AFTER then setOnline(false) end
    VoiceServer.busy = false
end

local function sync()
    -- a lost callback must not stop the sync for good
    if VoiceServer.busy and getTickCount() - (VoiceServer.busySince or 0) < CFG.TIMEOUT_MS * 3 then return end
    VoiceServer.busy = true
    VoiceServer.busySince = getTickCount()
    call("PUT", "integration/players", { players = playersPayload(), full = true }, function(_, err)
        if err then return failed(err) end
        call("GET", "integration/state", nil, function(data, err2)
            if err2 then return failed(err2) end
            VoiceServer.failures = 0
            VoiceServer.busy = false
            setOnline(true)
            applyState(data)
        end)
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    if CFG.URL == "" or CFG.KEY == "" then
        outputServerLog("[v_voiceclient_connector] VC.VOICESERVER URL / KEY not set: real time radio sync is off")
        return
    end
    sync()
    setTimer(sync, CFG.SYNC_MS, 0)
end)

------------------------------------------------------------------------ exports

-- getRadioSpeakers(freq) -> { { player | false, name, unit | false, live, clientType }, ... }
function getRadioSpeakers(freq)
    freq = Radio.validFreq(freq)
    local list = {}
    if not freq then return list end
    for _, info in pairs(VoiceServer.tx) do
        if info.frequency == freq then
            local s = clientSpeaker(info, info.state == "live")
            s.clientType = info.clientType
            list[#list + 1] = s
        end
    end
    return list
end

-- true while the player's external client (WPF / web) transmits live
function isPlayerRadioTalking(player)
    local acc = Radio.account(player)
    if not acc then return false end
    for _, info in pairs(VoiceServer.tx) do
        if info.username:lower() == acc:lower() and info.state == "live" then return true end
    end
    return false
end

-- false | { clientType = "wpf" | "web" | "mta_cef", clients = { type, ... } }
function isPlayerVoiceClientConnected(player)
    local acc = Radio.account(player)
    if not acc then return false end
    local types = {}
    for _, c in pairs(VoiceServer.conn) do
        if c.username:lower() == acc:lower() then types[#types + 1] = c.clientType end
    end
    if #types == 0 then return false end
    return { clientType = types[1], clients = types }
end
