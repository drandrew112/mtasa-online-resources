if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Help AI assistant: state + request logic (the panel draws it, client/panel.lua).
--
--   one session = one question; AI.new() starts a fresh session
--   at most one question per minute (server/ai.lua enforces the same)
--
--   AI.state: "idle" -> "waiting" -> "done" | "error"
--
-- The help pages most related to the question go to the server as context
-- (server/ai.lua helpAI:ask -> Gemini -> helpAI:response).

AI = {
    state   = "idle",
    input   = "",
    question = "",
    answer  = "",
    err     = nil,
    reqId   = nil,
    sentAt  = 0,
    lastAskAt = nil,
}

AI.MAX_INPUT = 300
AI.COOLDOWN = 60000
local TIMEOUT = 45000
local TOPICS, TOPIC_CHARS = 4, 4500

function AI.cooldownLeft()
    if not AI.lastAskAt then return 0 end
    local left = AI.COOLDOWN - (getTickCount() - AI.lastAskAt)
    return left > 0 and math.ceil(left / 1000) or 0
end

function AI.canAsk()
    return AI.state == "idle" and AI.input:match("%S") ~= nil and AI.cooldownLeft() == 0
end

-- question words, crudely stemmed (hu/en word endings): first 6 letters
local function tokens(q)
    local out, seen = {}, {}
    for w in Search.norm(q):gmatch("%S+") do
        if L.len(w) >= 3 then
            w = L.sub(w, 1, 6)
            if not seen[w] then seen[w] = true out[#out + 1] = w end
        end
    end
    return out
end

local function buildContext(question)
    local toks = tokens(question)
    if #toks == 0 then return "" end
    local scored = {}
    for _, t in pairs(Help.topics) do
        local d = Help.topicData(t)
        local title, kw = Search.norm(d.title), Search.norm(d.keywords)
        local score = 0
        for _, tok in ipairs(toks) do
            if title:find(tok, 1, true) then score = score + 8 end
            if kw:find(tok, 1, true) then score = score + 4 end
            for _, line in ipairs(d.doc.plain) do
                if Search.norm(line):find(tok, 1, true) then score = score + 1 end
            end
        end
        if score > 0 then scored[#scored + 1] = { t = t, d = d, score = score } end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.t.id < b.t.id
    end)

    local parts = {}
    for i = 1, math.min(TOPICS, #scored) do
        local s = scored[i]
        local body = table.concat(s.d.doc.plain, "\n")
        if #body > TOPIC_CHARS then body = body:sub(1, TOPIC_CHARS) end
        parts[#parts + 1] = "## " .. s.d.title .. " (" .. Help.categoryTitle(s.t.category) .. ")\n" .. body
    end
    return table.concat(parts, "\n\n")
end

function AI.ask()
    if not AI.canAsk() then return false end
    local question = AI.input:match("^%s*(.-)%s*$")
    AI.question, AI.answer, AI.err = question, "", nil
    AI.state = "waiting"
    AI.sentAt = getTickCount()
    AI.lastAskAt = AI.sentAt
    AI.reqId = tostring(AI.sentAt)
    AI.input = ""
    triggerServerEvent("helpAI:ask", resourceRoot, AI.reqId, question, buildContext(question), L.lang())
    return true
end

function AI.new()
    if AI.state == "waiting" then return end
    AI.state, AI.question, AI.answer, AI.err, AI.reqId = "idle", "", "", nil, nil
    AI.input = ""
end

-- called every frame while the panel is open
function AI.tick()
    if AI.state == "waiting" and getTickCount() - AI.sentAt > TIMEOUT then
        AI.state, AI.err, AI.reqId = "error", L("ui_help.ai.timeout"), nil
    end
end

-- Gemini likes markdown; the panel prints plain text
function AI.clean(s)
    s = s:gsub("\r", ""):gsub("%*%*", ""):gsub("`", "")
    s = s:gsub("\n[ \t]*[%*%-][ \t]+", "\n• "):gsub("^[ \t]*[%*%-][ \t]+", "• ")
    s = s:gsub("\n#+[ \t]*", "\n"):gsub("^#+[ \t]*", "")
    return (s:gsub("\n\n\n+", "\n\n"))
end

addEvent("helpAI:response", true)
addEventHandler("helpAI:response", resourceRoot, function(requestId, answer, err)
    if AI.state ~= "waiting" or requestId ~= AI.reqId then return end
    AI.reqId = nil
    if err then
        AI.state, AI.err = "error", tostring(err)
    else
        AI.state, AI.answer = "done", AI.clean(tostring(answer))
    end
end)
