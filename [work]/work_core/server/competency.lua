if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
-- Competencies: exam based qualifications of a work, independent of the work level.
-- A work registers them with registerCompetencies(workId, def) (README.md "Competencies"):
--   ranks  an ordered ladder; a player's competency = the highest rank held
--          base = true: everyone has it (no row stored), auto = { ids }: given when all are held,
--          appoint = { adminLevel, requires }: given by an admin (/appoint), exam = the exam that grants it
--   certs  extra qualifications next to the ladder (also exams), may be required by a rank
--   activities  [key] = rank id | cert id: what a competency allows (canPerform)
-- Storage (v_mysql): work_competencies (held competencies), work_exam_attempts (server/exams.lua).
-- Element data COMP_DATA.PLAYER = { [workId] = { r = rank id, o = order, c = { cert ids } } } (synced, logged in players).

addEvent("onPlayerCompetencyChange")   -- source: player; workId, compId, granted (bool), how
addEvent("onPlayerCompetenciesLoaded") -- source: player

Competencies = {}                      -- workId -> normalised definition
local held = {}                        -- player -> { [workId] = { [compId] = how } }   (base ranks not stored)
local loading = {}                     -- player -> true while the DB answer is pending

COMP_DB = { ready = false }

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS work_competencies (
        account VARCHAR(64) NOT NULL,
        work_id VARCHAR(32) NOT NULL,
        comp_id VARCHAR(32) NOT NULL,
        source VARCHAR(16) NOT NULL,
        granted_by VARCHAR(64) NULL,
        granted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (account, work_id, comp_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS work_exam_attempts (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        account VARCHAR(64) NOT NULL,
        work_id VARCHAR(32) NOT NULL,
        exam_id VARCHAR(32) NOT NULL,
        correct SMALLINT NOT NULL,
        total SMALLINT NOT NULL,
        percent TINYINT UNSIGNED NOT NULL,
        passed TINYINT(1) NOT NULL,
        answers TEXT NULL,
        started_at DATETIME NOT NULL,
        finished_at DATETIME NOT NULL,
        PRIMARY KEY (id),
        KEY idx_acc_exam (account, work_id, exam_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    -- payWork calls held back while the player is not loaded yet (server/payment.lua)
    [[CREATE TABLE IF NOT EXISTS work_pending_pay (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        account VARCHAR(64) NOT NULL,
        work_id VARCHAR(32) NOT NULL,
        items TEXT NOT NULL,
        reason TEXT NULL,
        opts TEXT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_account (account)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

function compExec(sql, ...)
    local res = getResourceFromName("v_mysql")
    if not res or getResourceState(res) ~= "running" then return false end
    return exports.v_mysql:mysqlExec(sql, ...)
end

function accountOf(player)
    if not isElement(player) or getElementType(player) ~= "player" then return nil end
    if getElementData(player, "isLogged") ~= true then return nil end
    local name = getElementData(player, "accName")
    return type(name) == "string" and name ~= "" and name or nil
end

function playerByAccount(name)
    name = tostring(name or ""):lower()
    for _, p in ipairs(getElementsByType("player")) do
        if tostring(getElementData(p, "accName") or ""):lower() == name then return p end
    end
    return nil
end

---------------------------------------------------------------- definition

local function idList(v)
    local out = {}
    if type(v) == "string" then out[1] = v
    elseif type(v) == "table" then
        for _, x in ipairs(v) do if type(x) == "string" then out[#out + 1] = x end end
    end
    return out
end

-- a name from the work's config: L.text message objects stay messages (resolved per player when sent)
local function label(v, fallback)
    if L.isMsg(v) then return v end
    return tostring(v or fallback)
end

local function normalise(workId, def)
    local c = { work = workId, ranks = {}, rankById = {}, certs = {}, certById = {}, exams = {},
                activities = {}, minigames = {}, nametag = def.nametag == true }
    for i, r in ipairs(type(def.ranks) == "table" and def.ranks or {}) do
        if type(r) == "table" and type(r.id) == "string" then
            local rank = {
                id = r.id, order = #c.ranks + 1, name = label(r.name, r.id), short = label(r.short, r.id),
                badge = type(r.badge) == "string" and r.badge or nil,   -- client image path (":res/img.png")
                nametagCerts = idList(r.nametagCerts),                   -- held cert -> nametag badge "<order>_<cert>"
                base = r.base == true, exam = type(r.exam) == "string" and r.exam or nil,
                requires = idList(r.requires), auto = r.auto and idList(r.auto) or nil,
                appoint = type(r.appoint) == "table" and {
                    adminLevel = tonumber(r.appoint.adminLevel) or WORK.ADMIN_LEVEL,
                    requires = idList(r.appoint.requires),
                } or nil,
            }
            c.ranks[#c.ranks + 1] = rank
            c.rankById[rank.id] = rank
        end
    end
    for _, x in ipairs(type(def.certs) == "table" and def.certs or {}) do
        if type(x) == "table" and type(x.id) == "string" then
            local cert = { id = x.id, name = label(x.name, x.id), short = label(x.short, x.id),
                           exam = type(x.exam) == "string" and x.exam or nil, requires = idList(x.requires),
                           exactRank = type(x.exactRank) == "string" and x.exactRank or nil }
            c.certs[#c.certs + 1] = cert
            c.certById[cert.id] = cert
        end
    end
    -- exam id -> the competency it grants
    for _, r in ipairs(c.ranks) do if r.exam then c.exams[r.exam] = { comp = r.id, kind = "rank" } end end
    for _, x in ipairs(c.certs) do if x.exam then c.exams[x.exam] = { comp = x.id, kind = "cert" } end end
    if type(def.activities) == "table" then
        for k, v in pairs(def.activities) do
            if type(k) == "string" and type(v) == "string" then c.activities[k] = v end
        end
    end
    local e = type(def.exams) == "table" and def.exams or {}
    c.passPercent = tonumber(e.passPercent) or WORK.EXAM_PASS_PERCENT
    c.retryCooldown = tonumber(e.retryCooldown) or WORK.EXAM_RETRY_COOLDOWN
    c.helpTopic = type(e.help) == "string" and e.help or nil
    c.minigames = type(def.minigames) == "table" and def.minigames or {}
    return c
end

---------------------------------------------------------------- queries (pure)

local function heldOf(player, workId)
    local h = held[player]
    return h and h[workId] or {}
end

-- highest rank (table) the player holds in the work, or nil when the work has no ranks
local function topRank(player, c)
    local mine, best = heldOf(player, c.work), nil
    for _, r in ipairs(c.ranks) do
        if r.base or mine[r.id] then best = r end
    end
    return best
end

-- does the player have the competency (rank: at least this one; cert: held)
local function has(player, c, id)
    if c.certById[id] then return heldOf(player, c.work)[id] ~= nil end
    local want = c.rankById[id]
    if not want then return false end
    local top = topRank(player, c)
    return top ~= nil and top.order >= want.order
end

local function hasAll(player, c, list)
    for _, id in ipairs(list or {}) do
        if not has(player, c, id) then return false, id end
    end
    return true
end

function compDisplayName(c, id)
    local x = c.rankById[id] or c.certById[id]
    return x and x.name or tostring(id)
end

---------------------------------------------------------------- sync

local function syncPlayer(player)
    if not isElement(player) then return end
    local t = {}
    for workId, c in pairs(Competencies) do
        local top = topRank(player, c)
        local certs = {}
        for _, x in ipairs(c.certs) do
            if heldOf(player, workId)[x.id] then certs[#certs + 1] = x.id end
        end
        t[workId] = { r = top and top.id or false, o = top and top.order or 0, c = certs }
    end
    setElementData(player, WORK_DATA.PLAYER_COMP, t)
    if setRankData then setRankData(player) end
end

function syncAllCompetencies()
    for _, p in ipairs(getElementsByType("player")) do
        if held[p] then syncPlayer(p) end
    end
end

-- public part of the definitions (client sync with the works, see registry publicWorks)
function publicCompetencies(workId)
    local c = Competencies[workId]
    if not c then return nil end
    local ranks, certs = {}, {}
    for i, r in ipairs(c.ranks) do ranks[i] = { id = r.id, name = r.name, short = r.short, order = r.order, badge = r.badge } end
    for i, x in ipairs(c.certs) do certs[i] = { id = x.id, name = x.name, short = x.short } end
    return { ranks = ranks, certs = certs }
end

---------------------------------------------------------------- grant / revoke

local runAuto

local function store(player, workId, id, how, by)
    local account = accountOf(player)
    if not account then return false end
    held[player] = held[player] or {}
    held[player][workId] = held[player][workId] or {}
    if held[player][workId][id] then return false end
    held[player][workId][id] = how
    compExec("INSERT IGNORE INTO work_competencies (account, work_id, comp_id, source, granted_by) VALUES (?, ?, ?, ?, ?)",
        account, workId, id, how, by)
    triggerEvent("onPlayerCompetencyChange", player, workId, id, true, how)
    return true
end

-- grantCompetency(player, workId, id [, how [, by]]) -> true | false, err
--   how: "exam" | "auto" | "appoint" | "admin" (default "admin")
function grantCompetency(player, workId, id, how, by)
    local c = Competencies[workId]
    if not c then return false, "unknown work" end
    if not (c.rankById[id] or c.certById[id]) then return false, "unknown competency" end
    if c.rankById[id] and c.rankById[id].base then return false, "base rank" end
    if not held[player] then return false, "player not loaded" end
    if not store(player, workId, id, how or "admin", by) then return false, "already held" end
    runAuto(player, c)
    syncPlayer(player)
    return true
end

-- revokeCompetency(player, workId, id) -> true | false, err
-- A rank takes every higher rank with it; an auto rank also takes the certs of its rule.
function revokeCompetency(player, workId, id)
    local c = Competencies[workId]
    if not c or not held[player] then return false, "unknown work / player not loaded" end
    local account = accountOf(player)
    local mine = heldOf(player, workId)
    local drop = {}
    local rank = c.rankById[id]
    if rank then
        for _, r in ipairs(c.ranks) do
            if r.order >= rank.order and mine[r.id] then drop[#drop + 1] = r.id end
        end
        if rank.auto then
            for _, x in ipairs(rank.auto) do if c.certById[x] and mine[x] then drop[#drop + 1] = x end end
        end
    elseif mine[id] then
        drop[1] = id
    end
    if #drop == 0 then return false, "not held" end
    for _, x in ipairs(drop) do
        mine[x] = nil
        if account then
            compExec("DELETE FROM work_competencies WHERE account = ? AND work_id = ? AND comp_id = ?", account, workId, x)
        end
        triggerEvent("onPlayerCompetencyChange", player, workId, x, false, "revoke")
    end
    syncPlayer(player)
    return true
end

runAuto = function(player, c)
    local changed = true
    while changed do
        changed = false
        for _, r in ipairs(c.ranks) do
            if r.auto and not heldOf(player, c.work)[r.id] and hasAll(player, c, r.auto) then
                if store(player, c.work, r.id, "auto") then changed = true end
            end
        end
    end
end

---------------------------------------------------------------- load

local function load(player)
    local account = accountOf(player)
    if not account or loading[player] then return end
    loading[player] = true
    MYSQL.query(function(rows)
        loading[player] = nil
        if not isElement(player) or accountOf(player) ~= account then return end
        held[player] = {}
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
            local w = tostring(row.work_id)
            held[player][w] = held[player][w] or {}
            held[player][w][tostring(row.comp_id)] = tostring(row.source)
        end
        for _, c in pairs(Competencies) do runAuto(player, c) end
        syncPlayer(player)
        triggerEvent("onPlayerCompetenciesLoaded", player)
    end, "SELECT work_id, comp_id, source FROM work_competencies WHERE account = ?", account)
end

local function loadAll()
    for _, p in ipairs(getElementsByType("player")) do load(p) end
end

local function runSchema(i)
    if i > #SCHEMA then
        COMP_DB.ready = true
        loadAll()
        if loadAllExamResults then loadAllExamResults() end
        if flushAllPendingPay then flushAllPendingPay() end
        return
    end
    MYSQL.query(function(ok, err)
        if ok == false then
            outputDebugString("[work_core] competency schema " .. i .. " failed: " .. tostring(err), 1)
            setTimer(runSchema, 10000, 1, i)
            return
        end
        runSchema(i + 1)
    end, SCHEMA[i])
end

addEventHandler("onResourceStart", resourceRoot, function() runSchema(1) end)
addEventHandler("onPlayerLoaded", root, function()
    if COMP_DB.ready then load(source) end
end)
addEventHandler("onPlayerQuit", root, function()
    held[source], loading[source] = nil, nil
end)

function isCompetencyLoaded(player)
    return held[player] ~= nil
end

---------------------------------------------------------------- exports

-- registerCompetencies(workId, def) -> true | false (see the top of this file and README.md)
function registerCompetencies(workId, def)
    if type(workId) ~= "string" or type(def) ~= "table" then return false end
    if not Works[workId] then
        outputDebugString(("[work_core] registerCompetencies(%s): register the work first"):format(workId), 2)
        return false
    end
    local c = normalise(workId, def)
    c.owner = getCallerResourceName() or (Competencies[workId] and Competencies[workId].owner)
    Competencies[workId] = c
    if setExamDefinitions then setExamDefinitions(workId, def.examData, def.exams) end
    for p in pairs(held) do if isElement(p) then runAuto(p, c) end end
    syncAllCompetencies()
    syncWorks()
    outputDebugString(("[work_core] competencies of %s: %d ranks, %d certs"):format(workId, #c.ranks, #c.certs))
    return true
end

function unregisterCompetencies(workId)
    if not Competencies[workId] then return false end
    if endExamsOfWork then endExamsOfWork(workId) end
    Competencies[workId] = nil
    syncAllCompetencies()
    return true
end

-- -> rank id, order | false
function getPlayerCompetency(player, workId)
    local c = Competencies[workId]
    if not c then return false end
    local top = topRank(player, c)
    if not top then return false end
    return top.id, top.order
end

function hasCompetency(player, workId, id)
    local c = Competencies[workId]
    return c ~= nil and has(player, c, id)
end

-- -> { rank, order, name, certs = { [id] = true } } | false
function getPlayerCompetencies(player, workId)
    local c = Competencies[workId]
    if not c then return false end
    local top = topRank(player, c)
    local certs = {}
    for _, x in ipairs(c.certs) do if heldOf(player, workId)[x.id] then certs[x.id] = true end end
    return { rank = top and top.id or false, order = top and top.order or 0, name = top and top.name or false, certs = certs }
end

-- canPerform(player, workId, activity) -> true | false, needed competency id, its name
-- An activity the work did not list is allowed.
function canPerform(player, workId, activity)
    local c = Competencies[workId]
    if not c then return true end
    local need = c.activities[activity]
    if not need or has(player, c, need) then return true end
    return false, need, compDisplayName(c, need)
end

-- -> { [activity] = true } of every listed activity the player may do
function getAllowedActivities(player, workId)
    local c = Competencies[workId]
    local out = {}
    if not c then return out end
    for key, need in pairs(c.activities) do
        if has(player, c, need) then out[key] = true end
    end
    return out
end

-- -> { [id] = { name, short, kind = "rank" | "cert", order } }
function getCompetencyDefs(workId)
    local c = Competencies[workId]
    if not c then return false end
    local out = {}
    for _, r in ipairs(c.ranks) do out[r.id] = { name = r.name, short = r.short, kind = "rank", order = r.order } end
    for _, x in ipairs(c.certs) do out[x.id] = { name = x.name, short = x.short, kind = "cert" } end
    return out
end

-- shared with server/exams.lua
CompInternal = { has = has, hasAll = hasAll, topRank = topRank, heldOf = heldOf, sync = syncPlayer }

---------------------------------------------------------------- resource lifecycle

addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    for workId, c in pairs(Competencies) do
        if c.owner == name then unregisterCompetencies(workId) end
    end
end)

---------------------------------------------------------------- admin commands

local function adminLevel(player)
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and tonumber(level) or 0
end

local function reply(player, key, params)
    outputChatBox(L.forPlayer(player, key, params), player, 200, 200, 200)
end

local function findPlayer(text)
    if not text then return nil end
    local exact = getPlayerFromName(text)
    if exact then return exact end
    text = text:lower()
    for _, p in ipairs(getElementsByType("player")) do
        local n = (getPlayerName(p) .. " " .. tostring(getElementData(p, "accName") or "")
            .. " " .. tostring(getElementData(p, "displayName") or "")):lower():gsub("#%x%x%x%x%x%x", "")
        if n:find(text, 1, true) then return p end
    end
    return nil
end

-- the work of a command: the given id, or the only work with competencies
local function commandWork(arg, filter)
    if arg and Competencies[arg] then return Competencies[arg] end
    local found
    for _, c in pairs(Competencies) do
        if not filter or filter(c) then
            if found then return nil end
            found = c
        end
    end
    return found
end

local function appointRank(c)
    for _, r in ipairs(c.ranks) do if r.appoint then return r end end
    return nil
end

-- /appoint <player> [work]: gives the appointed rank (EMS: chief physician)
addCommandHandler("appoint", function(player, _, target, workArg)
    local c = commandWork(workArg, appointRank)
    local rank = c and appointRank(c)
    if not rank then return reply(player, "work_core.comp.no_appoint_rank") end
    if adminLevel(player) < rank.appoint.adminLevel then return end
    local p = findPlayer(target)
    if not p then return reply(player, "work_core.comp.player_not_found") end
    if not held[p] then return reply(player, "work_core.comp.player_not_loaded") end
    local ok, missing = hasAll(p, c, rank.appoint.requires)
    if not ok then
        return reply(player, "work_core.comp.cannot_appoint_needs", { player = getPlayerName(p), need = compDisplayName(c, missing) })
    end
    local done, err = grantCompetency(p, c.work, rank.id, "appoint", accountOf(player))
    if not done then return reply(player, "work_core.comp.failed", { err = err }) end
    reply(player, "work_core.comp.appointed", { player = getPlayerName(p), rank = rank.name })
    notifyPlayer(p, Works[c.work] and Works[c.work].name or c.work, L.forPlayer(p, "work_core.comp.you_were_appointed", { rank = rank.name }))
end)

addCommandHandler("unappoint", function(player, _, target, workArg)
    local c = commandWork(workArg, appointRank)
    local rank = c and appointRank(c)
    if not rank then return reply(player, "work_core.comp.no_appoint_rank") end
    if adminLevel(player) < rank.appoint.adminLevel then return end
    local p = findPlayer(target)
    if not p then return reply(player, "work_core.comp.player_not_found") end
    local ok, err = revokeCompetency(p, c.work, rank.id)
    if not ok then return reply(player, "work_core.comp.failed", { err = err }) end
    reply(player, "work_core.comp.unappointed", { player = getPlayerName(p), rank = rank.name })
end)

-- /competency <player> [work]: rank, certs and exam results
addCommandHandler("competency", function(player, _, target, workArg)
    if adminLevel(player) < 1 then return end
    local p = findPlayer(target) or player
    local c = commandWork(workArg)
    if not c then return reply(player, "work_core.comp.give_work_id") end
    local info = getPlayerCompetencies(p, c.work)
    local certs = {}
    for _, x in ipairs(c.certs) do if info.certs[x.id] then certs[#certs + 1] = L.resolveFor(player, x.name) end end
    reply(player, "work_core.comp.info", { player = getPlayerName(p), work = c.work, rank = info.name or "-",
        certs = #certs > 0 and table.concat(certs, ", ") or "-" })
    for examId, r in pairs(getExamResults and getExamResults(p, c.work) or {}) do
        reply(player, "work_core.comp.info_exam", { exam = examId, best = r.best, passed = r.passed and "+" or "-" })
    end
end)

-- /setcompetency <player> <work> <id> [remove]
addCommandHandler("setcompetency", function(player, _, target, workId, id, remove)
    if adminLevel(player) < WORK.ADMIN_LEVEL then return end
    local p = findPlayer(target)
    if not p or not workId or not id then return reply(player, "work_core.comp.setcompetency_usage") end
    local ok, err
    if remove == "remove" then ok, err = revokeCompetency(p, workId, id)
    else ok, err = grantCompetency(p, workId, id, "admin", accountOf(player)) end
    if not ok then return reply(player, "work_core.comp.failed", { err = err }) end
    reply(player, "work_core.comp.done")
end)

-- Hungarian aliases of the admin commands
for alias, cmd in pairs({ kinevez = "appoint", kinevezesvissza = "unappoint", kompetencia = "competency",
                          setkompetencia = "setcompetency" }) do
    addCommandHandler(alias, function(player, _, ...)
        executeCommandHandler(cmd, player, table.concat({ ... }, " "))
    end)
end
