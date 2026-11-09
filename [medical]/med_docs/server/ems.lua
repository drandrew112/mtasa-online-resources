-- Mentési lap (EMS case sheet, plan: Mentési lap):
--   * made at the hospital handover, or at the end of the ERM task when there was no handover (Ú12)
--   * ERM: case id, priority, times, place, unit, call text, reason (rescue / patient transport)
--   * medsys: ABCDE at handover, NACA, the crew's treatments with times, vital signs table (a sample at
--     every treatment), drugs, the 12-lead print; free text: "Mi történt?" + the handover text
--   * the unit leader edits the text parts for 15 min (new version), later only the EMS chief (E)

local EDIT_WINDOW = 900
local VITALS_MAX = 8
local GCS = { stable = 15, confused = 14, dazed = 12, unconscious = 6, clinical_death = 3, dead = 3 }

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

---------------------------------------------------------------- vital signs samples (every EMS treatment)

local samples = setmetatable({}, { __mode = "k" })   -- [ped] = { { at, hr, bp, spo2, breathing, gcs } }
local lastPatient = {}                               -- [medic name] = { ped, at }

addEventHandler("onMedicalTreatment", root, function(medic, action, success)
    if success ~= true or not isElement(medic) or not running("medsys") then return end
    if not (running("work_core") and exports.work_core:isPlayerOnDuty(medic, "ems") == true) then return end
    lastPatient[getPlayerName(medic)] = { ped = source, at = getRealTime().timestamp }
    local list = samples[source]
    if not list then list = {} samples[source] = list end
    local now = getRealTime().timestamp
    if #list > 0 and now - list[#list].at < 120 then return end   -- one row per 2 min
    local snap = exports.medsys:getMedicalState(source) or {}
    list[#list + 1] = { at = now, hr = snap.heartRate, bp = snap.bloodPressure, spo2 = snap.spo2,
                        breathing = snap.breathing, gcs = GCS[snap.consciousness or "stable"] or 15 }
    if #list > VITALS_MAX then table.remove(list, 1) end
end)
addEventHandler("onElementDestroy", root, function() samples[source] = nil end)

---------------------------------------------------------------- the sheet body

-- NACA 0-7 from the state at handover and the ERM priority
local function nacaOf(snap, priority)
    if snap.dead then return 7 end
    if snap.clinicalDeath or snap.rosc then return 6 end
    if snap.consciousness == "unconscious" or (snap.systolic or 120) < 90 or (snap.spo2 or 99) < 88 or snap.intubated then return 5 end
    local worst = 0
    for _, list in ipairs({ snap.injuries or {}, snap.conditions or {} }) do
        for _, i in ipairs(list) do worst = math.max(worst, tonumber(i.severity) or 0) end
    end
    if worst >= 3 or priority == 1 then return 4 end
    if worst == 2 or priority == 2 then return 3 end
    if worst == 1 then return 2 end
    return 1
end

-- ABCDE at the handover (codes: the viewer writes them in the reader's language)
local function abcdeOf(snap)
    return {
        a = snap.intubated and "tube" or ((snap.breathing == "none" or snap.breathing == "silent" or snap.breathing == "agonal" or snap.breathing == "snoring") and "threatened" or "open"),
        b = { breathing = snap.breathing or "normal", spo2 = snap.spo2, oxygen = snap.oxygenMask and true or false },
        c = { hr = snap.heartRate, bp = snap.bloodPressure, skin = snap.skinSign or "normal", bleeding = snap.bleeding or 0, rhythm = snap.rhythm },
        d = { consciousness = snap.consciousness or "stable", gcs = GCS[snap.consciousness or "stable"] or 15, glucose = snap.glucose },
        e = (function()
            local out = {}
            for _, i in ipairs(snap.injuries or {}) do out[#out + 1] = { type = i.type, severity = i.severity, part = i.part, side = i.side, treated = i.treated } end
            return out
        end)(),
    }
end

local function sheetBody(patient, medic, task, unit, handover)
    local snap = running("medsys") and isElement(patient) and exports.medsys:getMedicalState(patient) or {}
    local identity = isElement(patient) and getElementData(patient, "pol.identity") or {}
    local injuries = {}
    for _, i in ipairs(snap.injuries or {}) do
        injuries[#injuries + 1] = { type = i.type, severity = i.severity, treated = i.treated, part = i.part, side = i.side,
            label = L.resolveFor(medic, i.label), partLabel = i.partLabel and L.resolveFor(medic, i.partLabel) or nil }
    end
    for _, i in ipairs(snap.conditions or {}) do
        injuries[#injuries + 1] = { type = i.type, severity = i.severity, treated = i.treated, label = L.resolveFor(medic, i.label), condition = true }
    end
    local drugs = {}
    for _, d in ipairs(snap.drugs or {}) do drugs[#drugs + 1] = { id = d.id, dose = d.dose, name = L.resolveFor(medic, d.name) } end
    local meta = task and task.meta or {}
    local trauma = false
    for _, i in ipairs(snap.injuries or {}) do if not i.condition then trauma = true end end
    return {
        task = task and { id = task.id, title = task.title, description = task.description, priority = task.priority, zone = task.zone,
                          created = task.createdAt, closed = task.closedAt } or false,
        reason = meta.kind == "transfer" and "transfer" or "rescue",
        transfer = meta.kind == "transfer" and { class = meta.transferClass, from = meta.from, to = meta.to, note = meta.note } or nil,
        unit = unit and { callsign = unit.callsign, type = unit.type, members = unit.members } or false,
        leader = isElement(medic) and (getElementData(medic, "displayName") or getPlayerName(medic)) or tostring(medic or ""),
        patient = { name = identity.name or false, birth = identity.birth or false, gender = identity.gender or false, cid = identity.cid or false,
                    idChecked = identity.checked == true },
        handover = handover or false,
        illness = trauma and "trauma" or "medical",
        naca = nacaOf(snap, task and task.priority),
        abcde = abcdeOf(snap),
        vitals = { hr = snap.heartRate, bp = snap.bloodPressure, spo2 = snap.spo2, consciousness = snap.consciousness,
                   breathing = snap.breathing, glucose = snap.glucose, rhythm = snap.rhythm, pain = snap.pain },
        vitalsTable = isElement(patient) and samples[patient] or {},
        state = snap.dead and "dead" or ((snap.clinicalDeath and "arrest") or "unchanged"),
        injuries = injuries, drugs = drugs,
        timeline = isElement(patient) and getPatientCareLog(patient, true) or {},
        ecg = isElement(patient) and getElementData(patient, "ecg.lastPrint") or false,
        epicrisis = "",
    }
end

local made = {}   -- [taskId] = true once a sheet exists (handover or task end)

addEvent("onHospitalPatientHandover")
addEventHandler("onHospitalPatientHandover", root, function(hospitalId, unitId, patient, medic, taskId, text)
    if not isElement(patient) then return end
    local unit = running("med_erm") and exports.med_erm:getUnitData(unitId) or nil
    local task = taskId and running("med_erm") and exports.med_erm:getTask(taskId) or nil
    local hospital = running("med_hospitals") and exports.med_hospitals:getHospital(hospitalId) or nil
    local identity = getElementData(patient, "pol.identity") or {}
    local body = sheetBody(patient, medic, task, unit, { at = getRealTime().timestamp, hospital = hospital and hospital.name or hospitalId,
        department = "er", text = text or "", receiver = false })
    if taskId then made[taskId] = true end
    createDocument("ems", { author = medic, hospital = hospitalId, patient = identity.name or "", unit = unit and unit.callsign or "",
                            taskId = taskId, caseRef = "ems:" .. tostring(taskId or "") }, body)
end)

-- no handover (the patient stayed, died at the scene, refused): a sheet at the end of the task
addEvent("onErmTaskClosed")
addEventHandler("onErmTaskClosed", root, function(taskId, reason)
    if made[taskId] or not running("med_erm") then made[taskId] = nil return end
    local task = exports.med_erm:getTask(taskId)
    if type(task) ~= "table" then return end
    local since = (task.createdAt or 0)
    for _, u in ipairs(task.units or {}) do
        local unit = exports.med_erm:getUnitData(type(u) == "table" and (u.id or u.unitId) or u)
        for _, m in ipairs(unit and unit.members or {}) do
            -- lastPatient is keyed by the nick (identity), m.name is the display name
            local name = type(m) == "table" and (isElement(m.player) and getPlayerName(m.player) or m.name) or tostring(m)
            local lp = lastPatient[name]
            if lp and isElement(lp.ped) and lp.at >= since then
                local medic = getPlayerFromName(name) or name
                local identity = getElementData(lp.ped, "pol.identity") or {}
                local body = sheetBody(lp.ped, medic, task, unit, false)
                body.noHandover = tostring(reason or "")
                createDocument("ems", { author = medic, hospital = "", patient = identity.name or "", unit = unit.callsign or "",
                                        taskId = taskId, caseRef = "ems:" .. tostring(taskId) }, body)
                return
            end
        end
    end
end)

---------------------------------------------------------------- Ú12: editing the text parts (new version)

local function accountOf(player)
    local acc = getPlayerAccount(player)
    return acc and not isGuestAccount(acc) and getAccountName(acc) or ""
end

-- may the player edit this EMS sheet now? (author within 15 min, or the EMS chief)
function canEditEmsSheet(player, row)
    if not row or row.type ~= "ems" then return false end
    local chief = running("work_core") and exports.work_core:hasCompetency(player, "ems", DOCS.EMS_CHIEF_COMPETENCY) == true
    if chief then return true end
    local mine = row.author_account ~= "" and row.author_account == accountOf(player)
    return mine and getRealTime().timestamp - (tonumber(row.created_at) or 0) <= EDIT_WINDOW
end

addEvent("docs:editEms", true)
addEventHandler("docs:editEms", resourceRoot, function(id, fields)
    local player = client
    if type(fields) ~= "table" then return end
    MYSQL.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if not r or not isElement(player) then return end
        if not canEditEmsSheet(player, r) then
            return triggerClientEvent(player, "docs:notice", resourceRoot, "edit_denied")
        end
        local body = fromJSON(r.body or "{}") or {}
        if type(fields.epicrisis) == "string" then body.epicrisis = fields.epicrisis:gsub("[%c]", " "):sub(1, 1200) end
        if type(fields.what) == "string" then
            body.handover = type(body.handover) == "table" and body.handover or {}
            body.handover.text = fields.what:gsub("[%c]", " "):sub(1, 600)
        end
        body.editedBy = (getElementData(player, "displayName") or getPlayerName(player))
        createDocument("ems", { author = r.author, hospital = r.hospital, patient = r.patient, unit = r.unit, taskId = tonumber(r.task_id),
                                caseRef = r.case_ref, lang = r.lang, authorAccount = r.author_account, replaceId = tonumber(r.id) }, body)
        triggerClientEvent(player, "docs:notice", resourceRoot, "edit_saved")
    end, "SELECT * FROM med_docs WHERE id = ? AND type = 'ems' LIMIT 1", tonumber(id) or 0)
end)
