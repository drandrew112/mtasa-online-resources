if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
-- Exams of the competencies (server/competency.lua). The questions come from the work resource
-- (registerCompetencies def.examData = { [lang] = { [examId] = exam } }, read from its own JSON files),
-- so work_core needs no access to other resources' files. The server keeps the answers: the client
-- only gets the question, the image path and the shuffled answers, and sends back the index it picked.
--
-- exam = { id, title, description, questionCount, passPercent, help,
--          questions = { { id, q, answers = { 4 strings }, correct = 1..4, image = "path" }, ... } }
-- image paths are relative to the work resource (":<resource>/<path>" on the client).
--
-- Exam marker: createExamMarker(workId, x, y, z [, opts]) (kind "exam" in server/markers.lua).

addEvent("onPlayerExamFinish")     -- source: player; workId, examId, percent, passed

local Exams = {}                   -- workId -> { data = { [lang] = { [examId] = exam } }, order = { examId... } }
local results = {}                 -- player -> { [workId] = { [examId] = { best, passed, lastFail } } }
local sessions = {}                -- player -> running exam

local function now() return getRealTime().timestamp end

local function sqlTime(ts)
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d %02d:%02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute, t.second)
end

---------------------------------------------------------------- definitions

local function validQuestion(q)
    if type(q) ~= "table" or type(q.q) ~= "string" or type(q.answers) ~= "table" or #q.answers ~= 4 then return false end
    for i = 1, 4 do if type(q.answers[i]) ~= "string" then return false end end
    local c = tonumber(q.correct)
    return c ~= nil and c >= 1 and c <= 4
end

-- called by registerCompetencies
function setExamDefinitions(workId, data, opts)
    local entry = { data = {}, order = {} }
    local seenOrder = {}
    for lang, list in pairs(type(data) == "table" and data or {}) do
        entry.data[lang] = {}
        for examId, exam in pairs(type(list) == "table" and list or {}) do
            if type(exam) == "table" then
                local qs, bad = {}, 0
                for i, q in ipairs(type(exam.questions) == "table" and exam.questions or {}) do
                    if validQuestion(q) then
                        qs[#qs + 1] = { id = tostring(q.id or (examId .. "_" .. i)), q = q.q, answers = q.answers,
                                        correct = math.floor(tonumber(q.correct)), image = type(q.image) == "string" and q.image or nil }
                    else
                        bad = bad + 1
                    end
                end
                if bad > 0 then
                    outputDebugString(("[work_core] exam %s/%s/%s: %d invalid question(s) skipped"):format(workId, lang, examId, bad), 2)
                end
                entry.data[lang][examId] = {
                    id = examId, title = tostring(exam.title or examId), description = tostring(exam.description or ""),
                    count = math.max(1, math.min(#qs, math.floor(tonumber(exam.questionCount) or #qs))),
                    pass = tonumber(exam.passPercent), help = type(exam.help) == "string" and exam.help or nil,
                    questions = qs,
                }
            end
        end
    end
    local order = type(opts) == "table" and opts.order
    if type(order) == "table" then
        for _, id in ipairs(order) do
            if not seenOrder[id] then seenOrder[id] = true; entry.order[#entry.order + 1] = id end
        end
    end
    Exams[workId] = entry
end

local function examFor(player, workId, examId)
    local e = Exams[workId]
    if not e then return nil end
    local ok, lang = pcall(function() return exports.v_locals:getPlayerLanguage(player) end)
    lang = ok and lang or "en"
    for _, l in ipairs({ lang, "en", "hu" }) do
        if e.data[l] and e.data[l][examId] then return e.data[l][examId] end
    end
    for _, list in pairs(e.data) do if list[examId] then return list[examId] end end
    return nil
end

---------------------------------------------------------------- results

local function setResult(player, workId, examId, percent, passed, failTs)
    results[player] = results[player] or {}
    results[player][workId] = results[player][workId] or {}
    local r = results[player][workId][examId] or { best = 0, passed = false }
    r.best = math.max(r.best, percent)
    r.passed = r.passed or passed
    if failTs then r.lastFail = math.max(r.lastFail or 0, failTs) end
    results[player][workId][examId] = r
end

local function loadResults(player)
    local account = accountOf(player)
    if not account then return end
    MYSQL.query(function(rows)
        if not isElement(player) or accountOf(player) ~= account then return end
        results[player] = {}
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
            setResult(player, tostring(row.work_id), tostring(row.exam_id), math.floor(tonumber(row.best) or 0),
                (tonumber(row.passed) or 0) > 0, tonumber(row.last_fail))
        end
    end, [[SELECT work_id, exam_id, MAX(percent) AS best, MAX(passed) AS passed,
               UNIX_TIMESTAMP(MAX(CASE WHEN passed = 0 THEN finished_at END)) AS last_fail
           FROM work_exam_attempts WHERE account = ? GROUP BY work_id, exam_id]], account)
end

function loadAllExamResults()
    for _, p in ipairs(getElementsByType("player")) do loadResults(p) end
end

addEventHandler("onPlayerLoaded", root, function()
    if COMP_DB.ready then loadResults(source) end
end)

-- -> { [examId] = { best, passed, lastFail } }
function getExamResults(player, workId)
    local r = results[player] and results[player][workId] or {}
    local out = {}
    for id, v in pairs(r) do out[id] = { best = v.best, passed = v.passed, lastFail = v.lastFail } end
    return out
end

---------------------------------------------------------------- availability

-- -> "open" | "done" | "failed" (retry allowed) | "cooldown", seconds | "locked", reason message | "held"
local function examState(player, c, examId)
    local target = c.exams[examId]
    if not target then return "locked", L.forPlayer(player, "work_core.exam.not_available") end
    local res = results[player] and results[player][c.work] and results[player][c.work][examId]
    if res and res.passed then return "done" end
    local I = CompInternal
    if I.has(player, c, target.comp) then return "held" end
    local def = target.kind == "rank" and c.rankById[target.comp] or c.certById[target.comp]
    local ok, missing = I.hasAll(player, c, def.requires)
    if not ok then return "locked", L.forPlayer(player, "work_core.exam.needs", { need = compDisplayName(c, missing) }) end
    if def.exactRank then
        local top = I.topRank(player, c)
        if not top or top.id ~= def.exactRank then
            return "locked", L.forPlayer(player, "work_core.exam.only_for", { rank = compDisplayName(c, def.exactRank) })
        end
    end
    if res and res.lastFail and c.retryCooldown > 0 then
        local left = res.lastFail + c.retryCooldown - now()
        if left > 0 then return "cooldown", left end
    end
    return res and "failed" or "open"
end

-- the card list of the exam centre for one player
local function overview(player, workId)
    local c, e = Competencies[workId], Exams[workId]
    if not c or not e then return nil end
    local cards = {}
    local ids = {}
    for _, id in ipairs(e.order) do ids[#ids + 1] = id end
    if #ids == 0 then
        for _, r in ipairs(c.ranks) do if r.exam then ids[#ids + 1] = r.exam end end
        for _, x in ipairs(c.certs) do if x.exam then ids[#ids + 1] = x.exam end end
    end
    for _, examId in ipairs(ids) do
        local exam = examFor(player, workId, examId)
        local target = c.exams[examId]
        if exam and target then
            local state, extra = examState(player, c, examId)
            local res = results[player] and results[player][workId] and results[player][workId][examId]
            cards[#cards + 1] = {
                id = examId, title = exam.title, description = exam.description, count = exam.count,
                pass = exam.pass or c.passPercent, row = target.kind, comp = target.comp,
                state = state, reason = state == "locked" and extra or nil, wait = state == "cooldown" and extra or nil,
                best = res and res.best or nil,
            }
        end
    end
    local info = getPlayerCompetencies(player, workId)
    local work = Works[workId]
    return {
        work = workId, workName = work and work.name or workId, cards = cards,
        rank = info and info.rank or false, certs = info and info.certs or {},
        help = c.helpTopic, minigames = c.minigames,
    }
end

local function sendOverview(player, workId)
    local o = overview(player, workId)
    if o then triggerClientEvent(player, "work:examOverview", resourceRoot, o) end
end

---------------------------------------------------------------- sessions

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function sendQuestion(player)
    local s = sessions[player]
    local item = s.list[s.i]
    local answers = {}
    for k, idx in ipairs(item.order) do answers[k] = item.q.answers[idx] end
    triggerClientEvent(player, "work:examQuestion", resourceRoot, {
        title = s.title, index = s.i, total = #s.list, text = item.q.q, answers = answers,
        image = item.q.image and (":" .. s.resource .. "/" .. item.q.image) or nil,
    })
end

local function finish(player, aborted)
    local s = sessions[player]
    if not s then return end
    sessions[player] = nil
    local c = Competencies[s.work]
    local total = #s.list
    local percent = total > 0 and math.floor(s.correct / total * 100 + 1e-6) or 0
    local passed = not aborted and percent >= s.pass
    local account = accountOf(player)
    if account then
        compExec([[INSERT INTO work_exam_attempts (account, work_id, exam_id, correct, total, percent, passed, answers, started_at, finished_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            account, s.work, s.exam, s.correct, total, percent, passed and 1 or 0, toJSON(s.answers, true),
            sqlTime(s.started), sqlTime(now()))
    end
    if not isElement(player) then return end
    setResult(player, s.work, s.exam, percent, passed, not passed and now() or nil)
    local granted
    if passed and c and c.exams[s.exam] then
        local target = c.exams[s.exam].comp
        local before = getPlayerCompetency(player, s.work)
        grantCompetency(player, s.work, target, "exam")
        local after = getPlayerCompetency(player, s.work)
        granted = compDisplayName(c, target)
        if after ~= before and after ~= target then granted = granted .. " + " .. compDisplayName(c, after) end
    end
    triggerEvent("onPlayerExamFinish", player, s.work, s.exam, percent, passed)
    triggerClientEvent(player, "work:examResult", resourceRoot, {
        title = s.title, correct = s.correct, total = total, percent = percent, pass = s.pass,
        passed = passed, aborted = aborted == true, granted = granted,
    })
    sendOverview(player, s.work)
end

function endExamsOfWork(workId)
    for p, s in pairs(sessions) do
        if s.work == workId then finish(p, true) end
    end
end

local function startExam(player, workId, examId)
    local c = Competencies[workId]
    if not c or sessions[player] then return end
    if not isCompetencyLoaded(player) then
        return notifyPlayer(player, L.msg("work_core.exam.title"), L.msg("work_core.exam.loading"))
    end
    local state, extra = examState(player, c, examId)
    if state == "cooldown" then
        return notifyPlayer(player, L.msg("work_core.exam.title"), L.msg("work_core.exam.retry_in", { time = math.ceil(extra) }))
    elseif state ~= "open" and state ~= "failed" then
        return notifyPlayer(player, L.msg("work_core.exam.title"), state == "locked" and extra or L.msg("work_core.exam.not_available"))
    end
    local exam = examFor(player, workId, examId)
    if not exam or #exam.questions == 0 then return end
    local pool = shuffle({ unpack(exam.questions) })
    local list = {}
    for i = 1, exam.count do
        list[i] = { q = pool[i], order = shuffle({ 1, 2, 3, 4 }) }
    end
    sessions[player] = {
        work = workId, exam = examId, title = exam.title, resource = c.owner or "work_core",
        pass = exam.pass or c.passPercent, list = list, i = 1, correct = 0, answers = {}, started = now(),
    }
    sendQuestion(player)
end

---------------------------------------------------------------- client requests

local lastReq = {}
local function throttle(player)
    local t = getTickCount()
    if lastReq[player] and t - lastReq[player] < 250 then return false end
    lastReq[player] = t
    return true
end

-- the exam marker the player stands at (lag tolerant, on duty in its work) -> marker data | nil
local function examMarker(player, marker)
    local m = Markers[marker]
    if not m or m.kind ~= "exam" or not isPlayerAtMarker(player, marker) then return nil end
    if not isPlayerOnDuty(player, m.work) then return nil end
    return m
end

addEvent("work:examOpen", true)
addEventHandler("work:examOpen", resourceRoot, function(marker)
    if not throttle(client) then return end
    local m = examMarker(client, marker)
    if not m then return end
    if not accountOf(client) then return end
    sendOverview(client, m.work)
end)

addEvent("work:examStart", true)
addEventHandler("work:examStart", resourceRoot, function(marker, examId)
    if not throttle(client) or type(examId) ~= "string" then return end
    local m = examMarker(client, marker)
    if not m then return end
    startExam(client, m.work, examId)
end)

addEvent("work:examAnswer", true)
addEventHandler("work:examAnswer", resourceRoot, function(index, pick)
    local player, s = client, sessions[client]
    pick = tonumber(pick)
    if not s or s.waiting or tonumber(index) ~= s.i or not pick or pick < 1 or pick > 4 then return end
    pick = math.floor(pick)
    local item = s.list[s.i]
    local original = item.order[pick]
    local ok = original == item.q.correct
    if ok then s.correct = s.correct + 1 end
    s.answers[#s.answers + 1] = { q = item.q.id, a = original, ok = ok }
    -- the client shows the picked answer red / green and the correct one green for WORK.EXAM_FEEDBACK_TIME
    local correctPick
    for k, idx in ipairs(item.order) do if idx == item.q.correct then correctPick = k end end
    triggerClientEvent(player, "work:examFeedback", resourceRoot, s.i, pick, correctPick)
    s.waiting = true
    s.i = s.i + 1
    setTimer(function()
        if sessions[player] ~= s then return end   -- aborted / quit meanwhile
        s.waiting = nil
        if s.i > #s.list then finish(player, false) else sendQuestion(player) end
    end, WORK.EXAM_FEEDBACK_TIME, 1)
end)

-- closing the panel / leaving the marker during an exam counts as a failed attempt
addEvent("work:examAbort", true)
addEventHandler("work:examAbort", resourceRoot, function()
    if sessions[client] then finish(client, true) end
end)

addEventHandler("onPlayerQuit", root, function()
    if sessions[source] then finish(source, true) end
    results[source], lastReq[source] = nil, nil
end)

addEventHandler("onPlayerWasted", root, function()
    if sessions[source] then finish(source, true) end
end)

-- an admin reloaded the exam files of a work (the work resource answers by registering again)
addEvent("onWorkExamsReload")
addCommandHandler("examreload", function(player, _, workId)
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    if not ok or (tonumber(level) or 0) < WORK.ADMIN_LEVEL then return end
    for id in pairs(Competencies) do
        if not workId or workId == id then triggerEvent("onWorkExamsReload", root, id) end
    end
    outputChatBox(L.forPlayer(player, "work_core.exam.reloaded"), player, 200, 200, 200)
end)

-- createExamMarker(workId, x, y, z [, opts]) -> marker | false (opts as createDutyMarker)
-- Only players on duty in the work (work_core duty) see and use it.
function createExamMarker(workId, x, y, z, opts)
    if not Competencies[workId] then
        outputDebugString(("[work_core] createExamMarker(%s): register the competencies first"):format(tostring(workId)), 2)
        return false
    end
    local marker = createKindMarker("exam", workId, x, y, z, opts)
    if not marker then return false end
    setElementVisibleToWork(marker, workId)
    local m = Markers[marker]
    if m and m.blip then setElementVisibleToWork(m.blip, workId) end
    return marker
end
