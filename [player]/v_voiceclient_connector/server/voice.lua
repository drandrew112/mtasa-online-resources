if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_voiceclient_connector / server/voice.lua
-- The radio message pipeline:
--   text (speech-to-text of the external voice client)
--   -> player + supported work check
--   -> ai_llm (code list as context, schema enum = the allowed codes only)
--   -> onAiLlmResponse -> RADIO code: exports.<resource>:radioCommand(player, id, args)
--                         Q_ code: question subtitle, RAD_ERROR code: error subtitle
-- Every outcome gives the player a ui_core subtitle (client/subtitle.lua).

Voice = {
    results = {},    -- [requestId] = { account, status = "processing" | "done", kind, code, text, at }
    busy = {},       -- [player] = requestId being processed
    last = {},       -- [player] = tick of the last accepted message
    byAi = {},       -- [ai request id] = voice request id
}

local nextId = 0

local function dbg(fmt, ...)
    if VC.CONFIG.DEBUG then outputDebugString("[voice] " .. string.format(fmt, ...), 3) end
end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function stripColors(s)
    return (tostring(s or ""):gsub("#%x%x%x%x%x%x", ""))
end

-- foreign v_locals keys (labels of med_erm / police_system) in the player's language
local function translate(player, key, params)
    if type(key) ~= "string" then return tostring(key or "") end
    local ok, text = pcall(function() return exports.v_locals:translate(player, key, params) end)
    if ok and type(text) == "string" and text ~= "" then return text end
    return key
end

---------------------------------------------------------------- subtitles

function Voice.subtitle(player, text, duration)
    if not isElement(player) then return end
    triggerClientEvent(player, "voice:subtitle", resourceRoot, text, duration or VC.CONFIG.SUB_RESULT)
end

local function tag(player)
    return VC.CONFIG.COLOR_TAG .. L.forPlayer(player, "v_voiceclient_connector.tag") .. " "
end

local function say(player, color, text, duration)
    Voice.subtitle(player, tag(player) .. color .. stripColors(text), duration)
end

---------------------------------------------------------------- results

local function setResult(id, fields)
    local r = Voice.results[id]
    if not r then return end
    for k, v in pairs(fields) do r[k] = v end
    r.at = getTickCount()
end

local function finish(player, id, kind, code, text, aiError)
    setResult(id, { status = "done", kind = kind, code = code or false, text = stripColors(text), aiError = aiError or false })
    if isElement(player) and Voice.busy[player] == id then Voice.busy[player] = nil end
    dbg("#%d %s %s %s", id, kind, tostring(code), tostring(text))
end

---------------------------------------------------------------- AI errors

-- error kinds of ai_llm (AI.errorKind): overloaded, timeout, network, not_configured, auth, blocked,
-- invalid_answer, cooldown, error -> subtitle v_voiceclient_connector.ai.<kind>
local AI_KINDS = { overloaded = true, timeout = true, network = true, not_configured = true, auth = true,
    blocked = true, invalid_answer = true, cooldown = true, error = true }

function Voice.aiErrorText(player, kind)
    if not AI_KINDS[kind] then kind = "error" end
    return L.forPlayer(player, "v_voiceclient_connector.ai." .. kind), kind
end

-- the AI could not classify the message: tell the player why (overloaded, timeout, ...)
local function aiFailure(player, id, kind, err)
    outputDebugString("[voice] AI failed (" .. tostring(kind) .. "): " .. tostring(err), 2)
    if not isElement(player) then return finish(nil, id, "ai_error", "RAD_ERROR_UNKNOWN", tostring(err), kind) end
    local text
    text, kind = Voice.aiErrorText(player, kind)
    say(player, VC.CONFIG.COLOR_FAIL, text)
    finish(player, id, "ai_error", "RAD_ERROR_UNKNOWN", text, kind)
end

---------------------------------------------------------------- player / work

-- -> player, workId | player|nil, nil, errorCode
function Voice.resolve(account, work)
    if type(account) ~= "string" or account == "" then return nil, nil, "no_account" end
    if not running("v_accounts") then return nil, nil, "accounts_offline" end
    local player = exports.v_accounts:playerOnAccount(account)
    if not isElement(player) then return nil, nil, "offline" end
    if not running("work_core") then return player, nil, "work_unavailable" end
    local workId = exports.work_core:getPlayerWork(player)
    if not workId or not exports.work_core:isPlayerOnDuty(player, workId) then return player, nil, "not_on_duty" end
    if not Codes.isSupported(workId) then return player, nil, "work_not_supported" end
    if type(work) == "string" and work ~= "" and work:lower() ~= workId then return player, nil, "work_mismatch" end
    if not Codes.isReady(workId) then return player, nil, "work_unavailable" end
    return player, workId
end

-- player state for the AI (short, helps the Q_ decisions)
local function stateText(player, workId)
    local lines = { "Work: " .. workId }
    if workId == "ems" and running("med_erm") then
        local ok, u = pcall(function() return exports.med_erm:getUnitData(player) end)
        if ok and type(u) == "table" then
            lines[#lines + 1] = "Unit: " .. tostring(u.callsign or "?") .. " (" .. tostring(u.type or "?") .. "), status " .. tostring(u.status or "?")
                .. ((tonumber(u.task) or 0) > 0 and ", has an active case" or ", no active case")
        end
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------- execution

local function execute(player, id, workId, code, note)
    local w = Codes.WORKS[workId]
    local label = translate(player, Codes.label(workId, code.id))
    if code.args and code.args.note == "required" and (type(note) ~= "string" or #note < 3) then
        -- the target would refuse it without a note: ask for it
        local _, q = Codes.find(workId, workId == "ems" and "Q_EMS_AGENCY_NOTE" or (workId == "police" and "Q_POLICE_GENERAL") or "")
        local text = q and L.forPlayer(player, q.text) or L.forPlayer(player, "v_voiceclient_connector.error.unknown")
        say(player, VC.CONFIG.COLOR_QUESTION, text, VC.CONFIG.SUB_QUESTION)
        return finish(player, id, "question", q and q.id or "RAD_ERROR_UNKNOWN", text)
    end
    if not running(w.resource) then
        local text = L.forPlayer(player, "v_voiceclient_connector.fail.unavailable", { label = label })
        say(player, VC.CONFIG.COLOR_FAIL, text)
        return finish(player, id, "failed", code.id, text)
    end
    local args = {}
    if type(note) == "string" and note ~= "" then args.note = note:sub(1, 200) end
    local ok, res, err = pcall(function() return exports[w.resource]:radioCommand(player, code.id, args) end)
    if ok and res then
        local text = L.forPlayer(player, "v_voiceclient_connector.ok.sent", { label = label })
        say(player, VC.CONFIG.COLOR_OK, text)
        return finish(player, id, "success", code.id, text)
    end
    local reason = ok and type(err) == "string" and err ~= "" and err or nil
    local text = reason
        and L.forPlayer(player, "v_voiceclient_connector.fail.reason", { label = label, reason = stripColors(reason) })
        or L.forPlayer(player, "v_voiceclient_connector.fail.plain", { label = label })
    if not ok then outputDebugString("[voice] " .. w.resource .. ":radioCommand " .. code.id .. ": " .. tostring(res), 1) end
    say(player, VC.CONFIG.COLOR_FAIL, text)
    finish(player, id, "failed", code.id, text)
end

-- the AI's answer (decoded JSON) -> action
local function handleAnswer(req, answer)
    local player, workId, id = req.player, req.workId, req.id
    if not isElement(player) then return finish(nil, id, "error", "RAD_ERROR_UNKNOWN", "player left") end
    local codeId = type(answer) == "table" and type(answer.code) == "string" and answer.code:upper() or nil
    local kind, entry = Codes.find(workId, codeId)
    if not kind then
        kind, entry = Codes.find(workId, "RAD_ERROR_UNKNOWN")
        dbg("#%d invalid code from the AI: %s", id, tostring(codeId))
    end
    if kind == "error" then
        local text = L.forPlayer(player, entry.text)
        say(player, VC.CONFIG.COLOR_FAIL, text)
        return finish(player, id, "error", entry.id, text)
    elseif kind == "question" then
        local text = L.forPlayer(player, entry.text)
        say(player, VC.CONFIG.COLOR_QUESTION, text, VC.CONFIG.SUB_QUESTION)
        return finish(player, id, "question", entry.id, text)
    end
    local note = type(answer.note) == "string" and answer.note:gsub("^%s+", ""):gsub("%s+$", "") or ""
    execute(player, id, workId, entry, note)
end

addEvent("onAiLlmResponse")
addEventHandler("onAiLlmResponse", resourceRoot, function(aiId, ok, text, err, info)
    local id = Voice.byAi[aiId]
    if not id then return end
    Voice.byAi[aiId] = nil
    local req = Voice.results[id] and Voice.results[id].req
    if not req then return end
    Voice.results[id].req = nil
    if not ok then
        local kind = type(info) == "table" and info.errorKind
        if not kind then
            local okK, k = pcall(function() return exports.ai_llm:getErrorKind(err, info) end)
            kind = okK and k or "error"
        end
        return aiFailure(req.player, id, kind, err)
    end
    handleAnswer(req, info and info.json)
end)

---------------------------------------------------------------- entry

-- Voice.submit(account, work, text, source) -> result table (HTTP answer)
function Voice.submit(account, work, text, source)
    local player, workId, err = Voice.resolve(account, work)
    if not player then return { ok = false, error = err } end
    if not workId then
        say(player, VC.CONFIG.COLOR_FAIL, L.forPlayer(player, "v_voiceclient_connector.access." .. err))
        return { ok = false, error = err }
    end

    text = type(text) == "string" and text:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" then
        say(player, VC.CONFIG.COLOR_FAIL, L.forPlayer(player, "v_voiceclient_connector.error.no_speech"))
        return { ok = false, error = "no_speech" }
    end
    if #text > VC.CONFIG.MAX_TEXT then text = text:sub(1, VC.CONFIG.MAX_TEXT) end

    local now = getTickCount()
    if Voice.busy[player] then
        say(player, VC.CONFIG.COLOR_FAIL, L.forPlayer(player, "v_voiceclient_connector.error.busy"))
        return { ok = false, error = "busy", requestId = Voice.busy[player] }
    end
    if Voice.last[player] and now - Voice.last[player] < VC.CONFIG.PLAYER_COOLDOWN then
        say(player, VC.CONFIG.COLOR_FAIL, L.forPlayer(player, "v_voiceclient_connector.error.busy"))
        return { ok = false, error = "cooldown" }
    end
    if not running("ai_llm") then
        say(player, VC.CONFIG.COLOR_FAIL, L.forPlayer(player, "v_voiceclient_connector.error.ai_offline"))
        return { ok = false, error = "ai_offline" }
    end
    if not exports.ai_llm:isConfigured() then
        say(player, VC.CONFIG.COLOR_FAIL, (Voice.aiErrorText(player, "not_configured")))
        return { ok = false, error = "ai_error", aiError = "not_configured" }
    end

    nextId = nextId + 1
    local id = nextId
    local req = { id = id, player = player, workId = workId, text = text }
    Voice.results[id] = { account = exports.v_accounts:getName(player) or account, status = "processing",
        work = workId, heard = text, at = now, req = req }

    local enum = Codes.allIds(workId)
    local aiId, aiErr, aiKind = exports.ai_llm:request({
        system = VC.SYSTEM,
        context = Codes.describe(workId) .. "\n\nSPEAKER STATE:\n" .. stateText(player, workId),
        prompt = "Radio message transcript: \"" .. text .. "\"",
        schema = {
            type = "OBJECT",
            properties = {
                code = { type = "STRING", enum = enum },
                note = { type = "STRING" },
            },
            required = { "code" },
        },
        temperature = VC.CONFIG.AI_TEMPERATURE,
        maxTokens = VC.CONFIG.AI_MAX_TOKENS,
        tag = { voice = id },
    })
    if not aiId then
        -- refused at once (queue full = overloaded, not configured, ...)
        Voice.results[id] = nil
        local text, kind = Voice.aiErrorText(player, aiKind or "error")
        outputDebugString("[voice] AI request refused (" .. kind .. "): " .. tostring(aiErr), 2)
        say(player, VC.CONFIG.COLOR_FAIL, text)
        return { ok = false, error = "ai_error", aiError = kind }
    end

    Voice.byAi[aiId] = id
    Voice.busy[player] = id
    Voice.last[player] = now
    -- what the radio heard, while the AI works
    Voice.subtitle(player, tag(player) .. VC.CONFIG.COLOR_TEXT .. "\"" .. stripColors(text) .. "\"", VC.CONFIG.SUB_HEARD)
    dbg("#%d %s (%s): %s", id, tostring(account), workId, text)
    return { ok = true, requestId = id, status = "processing", work = workId }
end

-- public result of a request (only for the same account)
function Voice.result(account, id)
    local r = Voice.results[tonumber(id) or -1]
    if not r or tostring(r.account):lower() ~= tostring(account):lower() then return { ok = false, error = "not_found" } end
    return { ok = true, requestId = tonumber(id), status = r.status, kind = r.kind or false, code = r.code or false,
        text = r.text or false, heard = r.heard, work = r.work, aiError = r.aiError or false }
end

---------------------------------------------------------------- cleanup

addEventHandler("onPlayerQuit", root, function()
    Voice.busy[source] = nil
    Voice.last[source] = nil
end)

setTimer(function()
    local now = getTickCount()
    for id, r in pairs(Voice.results) do
        if now - r.at > VC.CONFIG.RESULT_KEEP then
            -- a request the AI never answered: free the player
            if r.req and isElement(r.req.player) and Voice.busy[r.req.player] == id then Voice.busy[r.req.player] = nil end
            Voice.results[id] = nil
        end
    end
    for aiId, id in pairs(Voice.byAi) do
        if not Voice.results[id] then Voice.byAi[aiId] = nil end
    end
end, 30000, 0)

-- the AI answers within its queue timeout; a stuck request should not block the player forever
setTimer(function()
    local now = getTickCount()
    for player, id in pairs(Voice.busy) do
        local r = Voice.results[id]
        if not r or (r.status == "processing" and now - r.at > 45000) then
            Voice.busy[player] = nil
            if r and r.req then
                Voice.results[id].req = nil
                aiFailure(player, id, "timeout", "no answer in 45 s")
            end
        end
    end
end, 5000, 0)
