if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
-- med_docs server: the med_docs table, document numbers, visibility and the per-patient care log of
-- the EMS crews (for the EMS case sheet).
--
-- row: id, doc_no, type, lang, hospital, case_ref, patient, citizen_id, author, author_account,
--      unit, task_id, created_at, body (JSON)

local ready = false

local function sql()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql or nil
end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function setup()
    local m = sql()
    if not m then return end
    m:mysqlExec([[CREATE TABLE IF NOT EXISTS med_docs (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        doc_no VARCHAR(24) NOT NULL DEFAULT '',
        type VARCHAR(12) NOT NULL,
        lang CHAR(2) NOT NULL DEFAULT 'hu',
        hospital VARCHAR(32) NOT NULL DEFAULT '',
        case_ref VARCHAR(48) NOT NULL DEFAULT '',
        patient VARCHAR(96) NOT NULL DEFAULT '',
        citizen_id INT UNSIGNED NULL,
        author VARCHAR(64) NOT NULL DEFAULT '',
        author_account VARCHAR(64) NOT NULL DEFAULT '',
        unit VARCHAR(32) NOT NULL DEFAULT '',
        task_id INT UNSIGNED NULL,
        created_at INT UNSIGNED NOT NULL,
        body MEDIUMTEXT,
        KEY idx_md_type (type), KEY idx_md_author (author_account), KEY idx_md_created (created_at), KEY idx_md_case (case_ref)
    ) DEFAULT CHARSET=utf8mb4]])
    -- versions (a reopened case writes a new Ambuláns lap; the EMS sheet can be edited for 15 min)
    MYSQL.query(function(rows)
        if type(rows) == "table" and #rows == 0 then
            m:mysqlExec("ALTER TABLE med_docs ADD COLUMN version SMALLINT UNSIGNED NOT NULL DEFAULT 1, ADD COLUMN parent_id INT UNSIGNED NULL")
        end
        ready = true
    end, "SHOW COLUMNS FROM med_docs LIKE 'version'")
end
addEventHandler("onResourceStart", resourceRoot, function() setTimer(setup, 500, 1) end)

local function accountOf(player)
    if not isElement(player) or getElementType(player) ~= "player" then return "" end
    local acc = getPlayerAccount(player)
    return acc and not isGuestAccount(acc) and getAccountName(acc) or ""
end

local function langOf(player)
    if isElement(player) and getElementType(player) == "player" and running("v_locals") then
        local ok, lang = pcall(function() return exports.v_locals:getPlayerLanguage(player) end)
        if ok and (lang == "hu" or lang == "en") then return lang end
    end
    return "hu"
end

---------------------------------------------------------------- creating

-- createDocument(type, meta, body) -> true (async; the number is made from the row id)
-- meta = { author = player | name, hospital, caseRef, patient, citizenId, unit, taskId, lang, authorAccount }
function createDocument(dtype, meta, body)
    local def = DOCS.TYPES[dtype]
    if not def or type(body) ~= "table" or not ready then return false end
    meta = meta or {}
    local author = meta.author
    local authorName = isElement(author) and (getElementData(author, "displayName") or getPlayerName(author)) or tostring(author or "")
    local lang = meta.lang or langOf(author)
    local now = getRealTime().timestamp
    body.lang = lang
    local function insert(version, parentId)
    MYSQL.insert(function(id)
        if type(id) ~= "number" then return end
        local no = ("%s-%d-%06d"):format(def.prefix, getRealTime().year + 1900, id)
        sql():mysqlExec("UPDATE med_docs SET doc_no = ? WHERE id = ?", no, id)
        triggerEvent("onMedicalDocumentCreated", resourceRoot, id, no, dtype, meta.caseRef or "", version)
    end, [[INSERT INTO med_docs (type, lang, hospital, case_ref, patient, citizen_id, author, author_account, unit, task_id, created_at, body, version, parent_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        dtype, lang, meta.hospital or "", meta.caseRef or "", meta.patient or "", tonumber(meta.citizenId),
        authorName:sub(1, 64), meta.authorAccount or accountOf(author), meta.unit or "", tonumber(meta.taskId), now, toJSON(body, true), version, parentId)
    end
    -- the Ambuláns lap / Mentési lap of the same case: a new version of the previous one
    if (meta.caseRef or "") ~= "" and DOCS.VERSIONED[dtype] then
        MYSQL.query(function(rows)
            local last = type(rows) == "table" and rows[1]
            if last then insert((tonumber(last.version) or 1) + 1, tonumber(last.id)) else insert(1, nil) end
        end, "SELECT id, version FROM med_docs WHERE case_ref = ? AND type = ? ORDER BY id DESC LIMIT 1", meta.caseRef, dtype)
    else
        insert(1, nil)
    end
    return true
end
addEvent("onMedicalDocumentCreated")

---------------------------------------------------------------- visibility

local function isHospitalStaff(player)
    return running("work_hospital") and exports.work_hospital:isHospitalStaff(player) == true
end

local function isEms(player)
    return running("work_core") and exports.work_core:isPlayerOnDuty(player, "ems") == true
end

local function isEmsChief(player)
    return running("work_core") and exports.work_core:hasCompetency(player, "ems", DOCS.EMS_CHIEF_COMPETENCY) == true
end

-- -> SQL where clause + args for what the player may read, or nil
local function scopeOf(player)
    if isHospitalStaff(player) then return "1=1", {} end
    if isEms(player) then
        if isEmsChief(player) then return "type = 'ems'", {} end
        return "type = 'ems' AND author_account = ?", { accountOf(player) }
    end
    return nil
end

addEvent("docs:list", true)
addEventHandler("docs:list", resourceRoot, function(filter)
    local player = client
    local where, args = scopeOf(player)
    if not where or not ready then return triggerClientEvent(player, "docs:list", resourceRoot, {}) end
    filter = type(filter) == "table" and filter or {}
    if filter.type and DOCS.TYPES[filter.type] then where = where .. " AND type = ?" args[#args + 1] = filter.type end
    if filter.caseRef then where = where .. " AND case_ref = ?" args[#args + 1] = tostring(filter.caseRef) end
    if filter.mine then where = where .. " AND author_account = ?" args[#args + 1] = accountOf(player) end
    if type(filter.search) == "string" and filter.search ~= "" then
        where = where .. " AND (patient LIKE ? OR doc_no LIKE ?)"
        local q = "%" .. filter.search:gsub("[%%_]", "") .. "%"
        args[#args + 1] = q args[#args + 1] = q
    end
    MYSQL.query(function(rows)
        if not isElement(player) then return end
        local out = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            out[#out + 1] = { id = tonumber(r.id), no = r.doc_no, type = r.type, patient = r.patient, author = r.author,
                              created = tonumber(r.created_at), lang = r.lang, unit = r.unit }
        end
        triggerClientEvent(player, "docs:list", resourceRoot, out)
    end, "SELECT id, doc_no, type, patient, author, created_at, lang, unit FROM med_docs WHERE " .. where ..
        " ORDER BY id DESC LIMIT " .. DOCS.LIST_LIMIT, unpack(args))
end)

addEvent("docs:get", true)
addEventHandler("docs:get", resourceRoot, function(id)
    local player = client
    local where, args = scopeOf(player)
    if not where or not ready then return end
    args[#args + 1] = tonumber(id) or 0
    MYSQL.query(function(rows)
        if not isElement(player) then return end
        local r = type(rows) == "table" and rows[1]
        if not r then return triggerClientEvent(player, "docs:doc", resourceRoot, false) end
        local body = fromJSON(r.body or "{}") or {}
        triggerClientEvent(player, "docs:doc", resourceRoot, {
            id = tonumber(r.id), no = r.doc_no, type = r.type, lang = r.lang, hospital = r.hospital, patient = r.patient,
            author = r.author, unit = r.unit, created = tonumber(r.created_at), body = body, version = tonumber(r.version) or 1,
            editable = canEditEmsSheet and canEditEmsSheet(player, r) or false,
        })
    end, "SELECT * FROM med_docs WHERE " .. where .. " AND id = ? LIMIT 1", unpack(args))
end)

-- may the player open the document viewer at all?
function canReadDocuments(player) return scopeOf(player) ~= nil end

---------------------------------------------------------------- care log of every patient (EMS case sheet timeline)

local careLog = setmetatable({}, { __mode = "k" })   -- [ped] = { { at, kind, action, option, medic } }

addEvent("onMedicalTreatment")
addEventHandler("onMedicalTreatment", root, function(medic, action, success, option)
    if success ~= true or not isElement(medic) then return end
    local log = careLog[source]
    if not log then log = {} careLog[source] = log end
    if #log >= 80 then return end
    log[#log + 1] = { at = getRealTime().timestamp, action = action, option = option ~= nil and tostring(option) or nil,
                      medic = getPlayerName(medic), ems = isEms(medic) }
end)

addEventHandler("onElementDestroy", root, function() careLog[source] = nil end)

-- getPatientCareLog(ped [, emsOnly]) -> copy of the log
function getPatientCareLog(ped, emsOnly)
    local out = {}
    for _, e in ipairs(careLog[ped] or {}) do
        if not emsOnly or e.ems then out[#out + 1] = e end
    end
    return out
end

-- the EMS case sheet (Mentési lap) is made in server/ems.lua
