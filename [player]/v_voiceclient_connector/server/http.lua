if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_voiceclient_connector / server/http.lua
-- HTTP API of the external voice client (http="true" exports, POST /v_voiceclient_connector/call/<fn>,
-- body = JSON array of the arguments). The client logs in first with v_accounts webLogin and sends
-- the token with every call; account (and work) are checked against it.
--
--   voiceRadio(token, account, work, text) -> { ok, requestId, status = "processing", work } | { ok = false, error }
--   voiceResult(token, requestId)          -> { ok, status, kind, code, text, heard, work }
--   voiceStatus(token)                     -> { ok, account, online, work, onDuty, supported, ready, codes }
--
-- Server exports (other resources / tests): submitRadioText(player, text) -> same as voiceRadio.

local flood = {}   -- [address] = { windowStart, count }

local function caller()
    return type(hostname) == "string" and hostname or "web"
end

local function flooded()
    local key, t = caller(), getTickCount()
    local f = flood[key]
    if not f or t - f[1] > 10000 then
        flood[key] = { t, 1 }
        return false
    end
    f[2] = f[2] + 1
    return f[2] > VC.CONFIG.HTTP_FLOOD_MAX
end

local function accountsRunning()
    local res = getResourceFromName("v_accounts")
    return res and getResourceState(res) == "running"
end

-- token -> account | nil, error
local function auth(token)
    if flooded() then return nil, "flood" end
    if type(token) ~= "string" or token == "" then return nil, "unauthorized" end
    if not accountsRunning() then return nil, "accounts_offline" end
    local account = exports.v_accounts:getWebSession(token)
    if not account then return nil, "unauthorized" end
    return account
end

function voiceRadio(token, account, work, text)
    local acc, err = auth(token)
    if not acc then return { ok = false, error = err } end
    if type(account) == "string" and account ~= "" and account:lower() ~= acc:lower() then
        return { ok = false, error = "account_mismatch" }
    end
    return Voice.submit(acc, work, text, caller())
end

function voiceResult(token, requestId)
    local acc, err = auth(token)
    if not acc then return { ok = false, error = err } end
    return Voice.result(acc, requestId)
end

function voiceStatus(token)
    local acc, err = auth(token)
    if not acc then return { ok = false, error = err } end
    local player = exports.v_accounts:playerOnAccount(acc)
    local out = { ok = true, account = acc, online = isElement(player), work = false, onDuty = false,
        supported = false, ready = false, codes = {} }
    if not isElement(player) then return out end
    local wres = getResourceFromName("work_core")
    if wres and getResourceState(wres) == "running" then
        local workId = exports.work_core:getPlayerWork(player)
        out.work = workId or false
        out.onDuty = workId and exports.work_core:isPlayerOnDuty(player, workId) or false
    end
    if out.work and Codes.isSupported(out.work) then
        out.supported = true
        out.ready = Codes.isReady(out.work)
        for _, c in ipairs(Codes.activeCodes(out.work)) do
            local label = c.id
            pcall(function() label = exports.v_locals:translate(player, Codes.label(out.work, c.id)) end)
            out.codes[#out.codes + 1] = { id = c.id, label = label }
        end
    end
    return out
end

-- in-game / script entry (no token: the caller resource is trusted)
function submitRadioText(player, text)
    if not isElement(player) or not accountsRunning() then return { ok = false, error = "offline" } end
    local acc = exports.v_accounts:getName(player)
    if not acc then return { ok = false, error = "not_logged_in" } end
    return Voice.submit(acc, nil, text, "script")
end

-- /voicetest <text>: types a radio message as if the voice client sent it (admin level 5)
addCommandHandler("voicetest", function(player, _, ...)
    local res = getResourceFromName("v_mysql")
    local level = res and getResourceState(res) == "running" and tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    if level < 5 then return end
    local r = submitRadioText(player, table.concat({ ... }, " "))
    outputServerLog("[voice] /voicetest " .. getPlayerName(player) .. ": " .. tostring(r.ok) .. " " .. tostring(r.error or r.requestId))
end)

setTimer(function()
    local t = getTickCount()
    for k, f in pairs(flood) do
        if t - f[1] > 60000 then flood[k] = nil end
    end
end, 60000, 0)
