if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- EMS competencies (work_core registerCompetencies, EMS.COMPETENCY): the ladder T, A, B, B+, C, D, E,
-- the drug and RSI exams, the exam markers, and the medsys limits of each medic.
--   exams: exams/<lang>/<id>.json, read here and handed to work_core (it never reads our files);
--          /examreload (work_core) reads them again
--   medsys: setMedicPermissions(player, { [key] = needed competency name }) for every activity of
--           EMS.COMPETENCY.activities the medic may not do; refreshed on duty start, on every
--           competency change and after a medsys restart. No limits while the EMS tutorial runs.

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

---------------------------------------------------------------- exam files

local function readJSON(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local text = fileRead(f, fileGetSize(f))
    fileClose(f)
    local ok, data = pcall(fromJSON, text)
    if not ok or type(data) ~= "table" then
        outputDebugString("[work_ems] invalid exam file " .. path, 1)
        return nil
    end
    return data
end

-- { [lang] = { [examId] = exam } }
local function loadExams()
    local out = {}
    for _, lang in ipairs(EMS.COMPETENCY.examLanguages) do
        for _, id in ipairs(EMS.COMPETENCY.examFiles) do
            local exam = readJSON(("exams/%s/%s.json"):format(lang, id))
            if exam then
                out[lang] = out[lang] or {}
                out[lang][id] = exam
            end
        end
    end
    return out
end

---------------------------------------------------------------- registration

function registerEmsCompetencies()
    local c = EMS.COMPETENCY
    local wc = exports.work_core
    local ok = wc:registerCompetencies(EMS.WORK_ID, {
        ranks = c.ranks, certs = c.certs, activities = c.activities, exams = c.exams,
        minigames = c.minigames, nametag = c.nametag, examData = loadExams(),
    })
    if not ok then return end
    for _, m in ipairs(EMS.EXAM_MARKERS) do
        wc:createExamMarker(EMS.WORK_ID, m[1], m[2], m[3])
    end
end

addEvent("onWorkExamsReload")
addEventHandler("onWorkExamsReload", root, function(workId)
    if workId ~= EMS.WORK_ID or not isRunning("work_core") then return end
    -- registering again replaces the definitions; the old exam marker goes first
    for _, marker in ipairs(exports.work_core:getWorkMarkers(EMS.WORK_ID) or {}) do
        if getElementData(marker, "work.marker") == "exam" then exports.work_core:destroyWorkMarker(marker) end
    end
    registerEmsCompetencies()
end)

---------------------------------------------------------------- medsys limits

function clearMedicPermissions(player)
    if isElement(player) and isRunning("medsys") then exports.medsys:setMedicPermissions(player, nil) end
end

function syncMedicPermissions(player)
    if not isElement(player) or not isRunning("medsys") then return end
    if Tutorial and Tutorial.isActive(player) then
        exports.medsys:setMedicPermissions(player, nil)
        return
    end
    if not isRunning("work_core") or not isPlayerEms(player) then
        exports.medsys:setMedicPermissions(player, nil)
        return
    end
    local wc = exports.work_core
    local allowed = wc:getAllowedActivities(player, EMS.WORK_ID) or {}
    local defs = wc:getCompetencyDefs(EMS.WORK_ID) or {}
    local denied = {}
    for key, need in pairs(EMS.COMPETENCY.activities) do
        if not allowed[key] then denied[key] = defs[need] and defs[need].name or need end
    end
    exports.medsys:setMedicPermissions(player, denied)
end

addEvent("onPlayerCompetencyChange")
addEventHandler("onPlayerCompetencyChange", root, function(workId)
    if workId == EMS.WORK_ID then syncMedicPermissions(source) end
end)

addEvent("onPlayerCompetenciesLoaded")
addEventHandler("onPlayerCompetenciesLoaded", root, function() syncMedicPermissions(source) end)

addEventHandler("onResourceStop", resourceRoot, function()
    if not isRunning("medsys") then return end
    for _, player in ipairs(getElementsByType("player")) do exports.medsys:setMedicPermissions(player, nil) end
end)
