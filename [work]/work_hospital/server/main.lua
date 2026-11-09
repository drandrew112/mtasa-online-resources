if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Hospital work on top of work_core. Being on duty = the medsys medic role + element data
-- "hosp.staff" (the med_hospitals id of the hospital); med_hospitals er/ reads it for everything
-- (patient labels, PC, tablet, interventions). Points of interventions are collected here and paid
-- at duty end (also on quit) through work_core payWork.

local Granted = {}          -- players this resource gave the medic role to
local Points = {}           -- player -> { total, items = { [code] = { label, count, points } }, order = {code...} }

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function setMedic(player, enabled)
    if enabled then Granted[player] = true else Granted[player] = nil end
    if isElement(player) and isRunning("medsys") then exports.medsys:setPlayerMedic(player, enabled, "hospital") end
end

---------------------------------------------------------------- exams

local function readJSON(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local text = fileRead(f, fileGetSize(f))
    fileClose(f)
    local ok, data = pcall(fromJSON, text)
    if not ok or type(data) ~= "table" then
        outputDebugString("[work_hospital] invalid exam file " .. path, 1)
        return nil
    end
    return data
end

local function loadExams()
    local out = {}
    for _, lang in ipairs(HOSPW.COMPETENCY.examLanguages) do
        for _, id in ipairs(HOSPW.COMPETENCY.examFiles) do
            local exam = readJSON(("exams/%s/%s.json"):format(lang, id))
            if exam then
                out[lang] = out[lang] or {}
                out[lang][id] = exam
            end
        end
    end
    return out
end

---------------------------------------------------------------- medsys limits by rank

function syncMedicPermissions(player)
    if not isElement(player) or not isRunning("medsys") then return end
    if not isRunning("work_core") or not exports.work_core:isPlayerOnDuty(player, HOSPW.WORK_ID) then
        if not Granted[player] then return end
        exports.medsys:setMedicPermissions(player, nil)
        return
    end
    local wc = exports.work_core
    local allowed = wc:getAllowedActivities(player, HOSPW.WORK_ID) or {}
    local defs = wc:getCompetencyDefs(HOSPW.WORK_ID) or {}
    local denied = {}
    for key, need in pairs(HOSPW.COMPETENCY.activities) do
        if not key:find("^er%.") and not allowed[key] then denied[key] = defs[need] and defs[need].name or need end
    end
    exports.medsys:setMedicPermissions(player, denied)
end

---------------------------------------------------------------- registration

local function hospitalOfStation(st) return st.hospital end

local function setup()
    if not isRunning("work_core") then return end
    local wc = exports.work_core
    wc:registerWork(HOSPW.WORK_ID, {
        name = HOSPW.NAME, description = HOSPW.DESCRIPTION, color = HOSPW.COLOR, skins = HOSPW.SKINS,
        maxLevel = HOSPW.MAX_LEVEL, levelXp = HOSPW.LEVEL_XP, levelStep = HOSPW.LEVEL_STEP, rankBadges = true,
    })
    local c = HOSPW.COMPETENCY
    wc:registerCompetencies(HOSPW.WORK_ID, {
        ranks = c.ranks, certs = c.certs, activities = c.activities, exams = c.exams, minigames = c.minigames,
        nametag = c.nametag, examData = loadExams(),
    })
    for _, st in ipairs(HOSPW.STATIONS) do
        local d = st.duty
        local marker = wc:createDutyMarker(HOSPW.WORK_ID, d[1], d[2], d[3], { blip = st.blip })
        if isElement(marker) then setElementData(marker, "hosp.station", hospitalOfStation(st), false) end
    end
    for _, m in ipairs(HOSPW.EXAM_MARKERS) do wc:createExamMarker(HOSPW.WORK_ID, m[1], m[2], m[3]) end
    for _, player in ipairs(wc:getWorkPlayers(HOSPW.WORK_ID) or {}) do
        setMedic(player, true)
        if not getElementData(player, "hosp.staff") then setElementData(player, "hosp.staff", HOSPW.STATIONS[1].hospital) end
        syncMedicPermissions(player)
    end
end
addEventHandler("onResourceStart", resourceRoot, setup)
addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, setup)

addEvent("onWorkExamsReload")
addEventHandler("onWorkExamsReload", root, function(workId)
    if workId ~= HOSPW.WORK_ID or not isRunning("work_core") then return end
    for _, marker in ipairs(exports.work_core:getWorkMarkers(HOSPW.WORK_ID) or {}) do
        if getElementData(marker, "work.marker") == "exam" then exports.work_core:destroyWorkMarker(marker) end
    end
    setup()
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "medsys" then return end
    for player in pairs(Granted) do
        if isElement(player) then
            exports.medsys:setPlayerMedic(player, true, "hospital")
            syncMedicPermissions(player)
        end
    end
end)

---------------------------------------------------------------- pay

local function payPoints(player, reason)
    local p = Points[player]
    Points[player] = nil
    if not p or p.total <= 0 or not isElement(player) or not isRunning("work_core") then return end
    local items, other = {}, 0
    local value = HOSPW.POINT_VALUE
    local gh = isRunning("gov_health") and exports.gov_health or nil
    if gh then
        local _, salary = gh:getHospitalPointValues()
        value = tonumber(salary) or value
    end
    value = value * (HOSPW.PAY_FACTOR or 1)
    for i, code in ipairs(p.order) do
        local it = p.items[code]
        local amount = math.floor(it.points * value)
        if i <= HOSPW.MAX_RECEIPT_LINES then
            items[#items + 1] = { label = it.count > 1 and ("%s ×%d"):format(it.label, it.count) or it.label, amount = amount }
        else
            other = other + amount
        end
    end
    if other > 0 then items[#items + 1] = { label = L.forPlayer(player, "work_hospital.pay.other"), amount = other } end
    local bonus = tonumber(HOSPW.COMPETENCY_BONUS[topRank(player)]) or 0
    if bonus > 0 then
        local rank = topRank(player)
        items[#items + 1] = { label = L.forPlayer(player, "work_hospital.pay.competency", { rank = L.forPlayer(player, "work_hospital.comp." .. rank) }), amount = bonus }
    end
    local opts
    if gh and p.hospital then opts = { payer = gh:getHospitalSalaryPayer(p.hospital, p.total * value + bonus) } end
    exports.work_core:payWork(player, HOSPW.WORK_ID, items, reason, opts)
    exports.work_core:giveWorkXp(player, HOSPW.WORK_ID, math.floor(p.total * HOSPW.XP_PER_POINT))
end

---------------------------------------------------------------- work_core events

for _, name in ipairs({ "onPlayerWorkDutyStart", "onPlayerWorkDutyEnd" }) do addEvent(name) end

---------------------------------------------------------------- Ú11: duty time per rank, cases as the treating doctor (accData)

local dutySince = {}   -- player -> { at, rank }

local function accData(player, key) return isRunning("v_mysql") and exports.v_mysql:getAccData(player, key) or nil end
local function topRank(player)
    for i = #HOSPW.COMPETENCY.ranks, 1, -1 do
        local r = HOSPW.COMPETENCY.ranks[i]
        if r.base or exports.work_core:hasCompetency(player, HOSPW.WORK_ID, r.id) then return r.id end
    end
    return "nurse"
end
local function bookDuty(player)
    local d = dutySince[player]
    dutySince[player] = nil
    if not d or not isRunning("v_mysql") then return end
    local key = "hosp.duty." .. d.rank
    local sec = math.max(0, getRealTime().timestamp - d.at)
    exports.v_mysql:setAccData(player, key, (tonumber(accData(player, key)) or 0) + sec)
end

-- med_hospitals: a case closed with this player as the treating doctor
function addHospitalTreatedCase(player)
    if not isElement(player) or not isRunning("v_mysql") then return false end
    local n = (tonumber(accData(player, "hosp.cases")) or 0) + 1
    exports.v_mysql:setAccData(player, "hosp.cases", n)
    setElementData(player, "hosp.cases", n) -- the hospital PC status bar
    return true
end

-- work_core exams.check -> true | false, reason
function checkHospitalExam(player, examId)
    local req = HOSPW.COMPETENCY.examRequirements[examId]
    if not req then return true end
    local sec = tonumber(accData(player, "hosp.duty." .. req.rank)) or 0
    local d = dutySince[player]
    if d and d.rank == req.rank then sec = sec + (getRealTime().timestamp - d.at) end
    if sec < req.hours * 3600 then
        return false, L.forPlayer(player, "work_hospital.exam.need_hours", { hours = req.hours, rank = L.forPlayer(player, "work_hospital.comp." .. req.rank),
            have = ("%.1f"):format(sec / 3600) })
    end
    local cases = tonumber(accData(player, "hosp.cases")) or 0
    if req.cases and cases < req.cases then
        return false, L.forPlayer(player, "work_hospital.exam.need_cases", { n = req.cases, have = cases })
    end
    return true
end

addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId ~= HOSPW.WORK_ID then return end
    dutySince[source] = { at = getRealTime().timestamp, rank = topRank(source) }
    -- the station whose duty marker is nearest
    local px, py, pz = getElementPosition(source)
    local best, bestD
    for _, st in ipairs(HOSPW.STATIONS) do
        local d = getDistanceBetweenPoints3D(px, py, pz, st.duty[1], st.duty[2], st.duty[3])
        if not bestD or d < bestD then best, bestD = st, d end
    end
    setElementData(source, "hosp.staff", best and best.hospital or HOSPW.STATIONS[1].hospital)
    setElementData(source, "hosp.cases", tonumber(accData(source, "hosp.cases")) or 0)
    setMedic(source, true)
    syncMedicPermissions(source)
end)

addEventHandler("onPlayerWorkDutyEnd", root, function(workId, reason)
    if workId ~= HOSPW.WORK_ID then return end
    bookDuty(source)
    removeElementData(source, "hosp.staff")
    removeElementData(source, "hosp.points")
    removeElementData(source, "hosp.cases")
    setMedic(source, false)
    if isRunning("medsys") then exports.medsys:setMedicPermissions(source, nil) end
    payPoints(source, L.forPlayer(source, reason == "quit" and "work_hospital.pay.reason_quit" or "work_hospital.pay.reason_duty_end"))
end)

addEventHandler("onPlayerQuit", root, function()
    Granted[source] = nil
    Points[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(dutySince) do if isElement(player) then bookDuty(player) end end
    for player in pairs(Points) do
        if isElement(player) then payPoints(player, L.forPlayer(player, "work_hospital.pay.reason_duty_end")) end
    end
    for player in pairs(Granted) do
        setMedic(player, false)
        if isElement(player) then removeElementData(player, "hosp.staff") end
    end
end)

addEvent("onPlayerCompetencyChange")
addEventHandler("onPlayerCompetencyChange", root, function(workId)
    if workId ~= HOSPW.WORK_ID then return end
    syncMedicPermissions(source)
    -- a new rank on duty: the time so far goes to the old one
    if dutySince[source] then
        local rank = topRank(source)
        if rank ~= dutySince[source].rank then bookDuty(source) dutySince[source] = { at = getRealTime().timestamp, rank = rank } end
    end
end)
addEvent("onPlayerCompetenciesLoaded")
addEventHandler("onPlayerCompetenciesLoaded", root, function() syncMedicPermissions(source) end)

---------------------------------------------------------------- exports

function isHospitalStaff(player, hospitalId)
    if not isElement(player) or not isRunning("work_core") then return false end
    if not exports.work_core:isPlayerOnDuty(player, HOSPW.WORK_ID) then return false end
    return hospitalId == nil or getElementData(player, "hosp.staff") == hospitalId
end

function getHospitalStaff(hospitalId)
    if not isRunning("work_core") then return {} end
    local out = {}
    for _, p in ipairs(exports.work_core:getWorkPlayers(HOSPW.WORK_ID) or {}) do
        if hospitalId == nil or getElementData(p, "hosp.staff") == hospitalId then out[#out + 1] = p end
    end
    return out
end

-- med_hospitals: an intervention was done. code = "HK-..", label = receipt text (player's language)
function addHospitalPoints(player, code, points, label)
    points = tonumber(points) or 0
    if not isHospitalStaff(player) or points == 0 then return false end
    local p = Points[player]
    if not p then p = { total = 0, items = {}, order = {} } Points[player] = p end
    p.hospital = getElementData(player, "hosp.staff") or p.hospital   -- the salary payer (gov_health)
    local it = p.items[code]
    if not it then
        it = { label = tostring(label or code), count = 0, points = 0 }
        p.items[code] = it
        p.order[#p.order + 1] = code
    end
    it.count = it.count + 1
    it.points = it.points + points
    p.total = p.total + points
    setElementData(player, "hosp.points", p.total)
    return p.total
end

function getHospitalPoints(player)
    return Points[player] and Points[player].total or 0
end

-- rank check of an er.* activity (true | false, need id, need name)
function canStaffPerform(player, activity)
    if not isHospitalStaff(player) then return false end
    -- before the tutorial (no Ápoló rank) nothing of the ER may be done
    if hasNurseRank and not hasNurseRank(player) then
        return false, "nurse", L.forPlayer(player, "work_hospital.comp.nurse")
    end
    return exports.work_core:canPerform(player, HOSPW.WORK_ID, activity)
end

function getHospitalWorkId() return HOSPW.WORK_ID end
