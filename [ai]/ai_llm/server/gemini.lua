-- ai_llm / server/gemini.lua
-- Gemini generateContent provider (taken over from ui_help/server/ai.lua).
-- AI.providers.gemini.send(req, done) ; done(ok, text, err, info)

AI = AI or {}
AI.providers = AI.providers or {}

local G = {}
AI.providers.gemini = G

local function setting(name)
    return get(getResourceName(resource) .. "." .. name)
end

function G.apiKey()
    local key = setting("gemini_api_key")
    if type(key) ~= "string" or key == "" or key == "PASTE_YOUR_API_KEY_HERE" then return nil end
    return key
end

function G.model(req)
    if type(req.model) == "string" and req.model:match("^[%w%.%-_]+$") then return req.model end
    local m = setting("gemini_model")
    if type(m) == "string" and m:match("^[%w%.%-_]+$") then return m end
    return AI.CONFIG.DEFAULT_MODEL
end

-- req: { system, contents = { { role, text } ... }, temperature, maxTokens, json, schema, model }
function G.send(req, done)
    local key = G.apiKey()
    if not key then return done(false, "", "not_configured", { status = 0 }) end

    local contents = AI.json.array()
    for _, turn in ipairs(req.contents) do
        contents[#contents + 1] = { role = turn.role, parts = AI.json.array({ { text = turn.text } }) }
    end

    local generationConfig = {
        temperature = req.temperature,
        maxOutputTokens = req.maxTokens,
    }
    if req.json or req.schema then generationConfig.responseMimeType = "application/json" end
    if type(req.schema) == "table" then generationConfig.responseSchema = req.schema end

    local payload = {
        systemInstruction = { parts = AI.json.array({ { text = req.system } }) },
        contents = contents,
        generationConfig = generationConfig,
    }
    local body, encErr = AI.json.encode(payload)
    if not body then return done(false, "", "encode_failed: " .. tostring(encErr), { status = 0 }) end

    local model = G.model(req)
    local url = string.format(AI.CONFIG.GEMINI_URL, model)
    local started = getTickCount()

    local queued = fetchRemote(url, {
        method = "POST",
        headers = { ["Content-Type"] = "application/json", ["x-goog-api-key"] = key },
        postData = body,
        queueName = "ai_llm",
        connectionAttempts = AI.CONFIG.CONNECTION_ATTEMPTS,
        connectTimeout = AI.CONFIG.CONNECT_TIMEOUT,
    }, function(responseData, responseInfo)
        local info = { model = model, ms = getTickCount() - started, status = 0 }
        if type(responseInfo) ~= "table" then
            return done(false, "", "bad_callback", info)
        end
        info.status = tonumber(responseInfo.statusCode) or 0

        local response = AI.json.decode(responseData)
        if not responseInfo.success then
            local detail = type(response) == "table" and type(response.error) == "table" and response.error.message
            info.apiStatus = type(response) == "table" and type(response.error) == "table" and response.error.status or nil
            outputDebugString("[ai_llm] Gemini HTTP " .. info.status .. ": " .. tostring(detail or responseData), 1)
            return done(false, "", "http_" .. info.status .. (detail and (": " .. tostring(detail)) or ""), info)
        end
        if type(response) ~= "table" then
            return done(false, "", "invalid_json", info)
        end
        if response.error then
            local e = response.error
            return done(false, "", "api_" .. tostring(e.code or "?") .. ": " .. tostring(e.message or "unknown"), info)
        end

        local cand = response.candidates and response.candidates[1]
        local parts = cand and cand.content and cand.content.parts
        local out = {}
        if type(parts) == "table" then
            for _, part in ipairs(parts) do
                if type(part.text) == "string" then out[#out + 1] = part.text end
            end
        end
        info.finishReason = cand and cand.finishReason or nil
        local usage = response.usageMetadata
        if type(usage) == "table" then
            info.promptTokens = usage.promptTokenCount
            info.outputTokens = usage.candidatesTokenCount
        end
        local text = table.concat(out, "\n")
        if text == "" then
            local blocked = type(response.promptFeedback) == "table" and response.promptFeedback.blockReason
            local reason = tostring(info.finishReason or "")
            if blocked or reason == "SAFETY" or reason == "BLOCKLIST" or reason == "PROHIBITED_CONTENT" or reason == "RECITATION" then
                return done(false, "", "blocked: " .. tostring(blocked or reason), info)
            end
            return done(false, "", "empty_answer", info)
        end
        done(true, text, false, info)
    end)

    if not queued then done(false, "", "fetch_failed", { model = model, status = 0 }) end
end
