-- 12-lead ECG (plan: EKG-12 modul). The server only makes a small specification of the patient's ECG;
-- every client draws the same curves from it (ecg12/client/render.lua: a 3D heart dipole projected onto
-- the 12 lead axes). Used by the hospital (12-lead ECG order), the documents (spec, not a picture) and the
-- EMS Lifepak "12-LEAD" button (B+ competency, Ú8) with PRINT.
--
-- spec = { id, rhythm, rate, pr, qrs, k, alternans, lowVoltage, stemi = { territory, stage } | nil,
--          swapRALA, wrongV, seed, at, hr, prMs, qrsMs, qt, qtc, axis, interp = { keys } }
-- Conditions add to it through MEDIC_ECG_EFFECTS[type](spec, injury, state).

MEDIC_ECG_EFFECTS = MEDIC_ECG_EFFECTS or {}

local NO_P = { SVT = true, AFIB = true, VT_WITH_PULSE = true, PULSELESS_VT = true, VF = true, ASYSTOLE = true }
local WIDE = { VT_WITH_PULSE = true, PULSELESS_VT = true }
local INTERP = { SINUS = "sinus", SINUS_BRADY = "sinus_brady", SINUS_TACHY = "sinus_tachy", SVT = "svt", AFIB = "afib",
    VT_WITH_PULSE = "vt", PULSELESS_VT = "vt", VF = "vf", ASYSTOLE = "asystole", PEA = "sinus", AVB3 = "avb3", ADENOSINE_PAUSE = "asystole" }
local nextId = 0

-- errors = { swapRALA, wrongV } (mg_ecg electrode placement)
function getECGSpec(element, errors)
    local state = isElement(element) and Patients[element]
    local rhythm = state and state.rhythm or "SINUS"
    if state and state.pauseUntil then rhythm = "ADENOSINE_PAUSE" end
    local rate = state and math.floor(state.heartRate + 0.5) or 75
    -- no pulse: the electrical rate of a PEA / pulseless VT (state.ecgRate), nothing for VF / asystole
    local def = MEDIC_RHYTHMS[rhythm]
    if state and def and not def.pulse then rate = (rhythm == "PEA" or rhythm == "PULSELESS_VT") and (state.ecgRate or 0) or 0 end
    nextId = nextId + 1
    local spec = {
        id = ("%d-%d"):format(getTickCount(), nextId), rhythm = rhythm, rate = math.max(0, rate), pr = 0.16, qrs = 0.09,
        k = 4.2, alternans = false, lowVoltage = false, stemi = nil, seed = math.random(1, 999999), at = getRealTime().timestamp,
        swapRALA = errors and errors.swapRALA == true or false, wrongV = errors and tonumber(errors.wrongV) or 0,
        noP = NO_P[rhythm] or false,
    }
    if rhythm == "VT_WITH_PULSE" or rhythm == "PULSELESS_VT" then spec.rate = math.max(spec.rate, 170) end
    if WIDE[rhythm] then spec.qrs = 0.16 end
    if rhythm == "PEA" then spec.qrs, spec.lowVoltage = 0.14, true end   -- slow, broad, low complexes
    if state then
        local ok, labs = pcall(getLabValues, element)
        if ok and type(labs) == "table" then spec.k = labs.k or 4.2 end
        for _, inj in ipairs(state.injuries) do
            local fx = MEDIC_ECG_EFFECTS[inj.type]
            if fx then fx(spec, inj, state) end
        end
    end
    if spec.k >= 6.0 then spec.qrs = math.max(spec.qrs, spec.k >= 7.5 and 0.18 or 0.12) end
    -- automatic measurements and the machine interpretation ("Unconfirmed")
    local beating = spec.rate > 0 and rhythm ~= "VF" and rhythm ~= "ASYSTOLE" and rhythm ~= "ADENOSINE_PAUSE"
    local rr = beating and 60 / spec.rate or 1
    spec.hr = beating and spec.rate or nil
    spec.prMs = (beating and not spec.noP and rhythm ~= "AVB3") and math.floor(spec.pr * 1000) or nil
    spec.qrsMs = beating and math.floor(spec.qrs * 1000) or nil
    spec.qt = beating and math.floor((0.36 + (spec.qrs - 0.09)) * math.sqrt(rr) * 1000 + 0.5) or nil
    spec.qtc = spec.qt and math.floor(spec.qt / math.sqrt(rr) + 0.5) or nil
    spec.axis = beating and (spec.swapRALA and 150 or 55) or nil
    local base = INTERP[rhythm] or "sinus"
    if rhythm == "PEA" then   -- the machine sees only the electrical activity (no pulse check)
        base = spec.rate < 60 and "sinus_brady" or (spec.rate > 100 and "sinus_tachy" or "sinus")
    end
    local interp = {}
    -- Lifepak 15 style headline of an ST elevation infarction
    if spec.stemi and spec.stemi.stage ~= "reperfused" and beating then interp[#interp + 1] = "acute_mi" end
    interp[#interp + 1] = base
    if spec.stemi and beating then interp[#interp + 1] = "stemi_" .. spec.stemi.territory end
    if spec.nstemi and not spec.stemi and beating then interp[#interp + 1] = "nstemi" end
    if spec.k >= 6.0 then interp[#interp + 1] = "hyperk" end
    if spec.alternans then interp[#interp + 1] = "alternans" end
    if spec.lowVoltage then interp[#interp + 1] = "low_voltage" end
    if spec.qrs >= 0.12 and not WIDE[rhythm] then interp[#interp + 1] = "wide_qrs" end
    if spec.swapRALA then interp[#interp + 1] = "swap_rala" end
    if spec.wrongV > 0 then interp[#interp + 1] = "poor_r" end
    spec.interp = interp
    return spec
end

---------------------------------------------------------------- the Lifepak "12-LEAD" button (EMS + hospital) and PRINT

addEvent("onMedicalECG12", false)   -- source = patient; (medic, spec): med_hospitals accepts it for an ordered 12-lead ECG

-- the recorded 12-lead: the viewer for the medic, the last one kept on the patient, the hospital told
local function deliverECG12(medic, target, spec)
    if not isElement(target) or type(spec) ~= "table" then return end
    setElementData(target, "ecg.last12", { spec = spec, at = getRealTime().timestamp }, false)
    if isElement(medic) then triggerClientEvent(medic, "medic:ecg12", resourceRoot, target, spec) end
    triggerEvent("onMedicalECG12", target, medic, spec)
end

local function minigameRunning()
    local res = getResourceFromName("mg_ecg")
    return res and getResourceState(res) == "running"
end

addEvent("medic:ecg12Request", true)
addEventHandler("medic:ecg12Request", resourceRoot, function(target)
    local medic = client
    if not canMedicAttend(medic, target, MEDIC.INTERACT_RANGE + 2) then return end
    local ok, why = checkMedicPermission(medic, "action.ecg12")
    if not ok then return sendPanelMessage(medic, why, true) end
    local state = Patients[target]
    if not state or not state.monitor then
        return sendPanelMessage(medic, L.msg("medsys.ecg12.needs_monitor"), true)
    end
    -- the electrodes are placed in the mg_ecg minigame (PROCEDURES.ecg12, server/treatment.lua)
    if minigameRunning() then
        local started, reason = startTreatment(medic, target, "ecg12")
        if not started then sendPanelMessage(medic, reason, true) end
        return
    end
    -- without the minigame: recorded at once, no placement errors
    local spec = getECGSpec(target)
    deliverECG12(medic, target, spec)
    triggerEvent("onMedicalTreatment", target, medic, "ecg12", true, spec.interp[1] or "sinus")
end)

-- the minigame is done (finishTreatment fires onMedicalTreatment after PROCEDURES.ecg12.apply)
addEventHandler("onMedicalTreatment", root, function(medic, action, success, option)
    if action ~= "ecg12" or option ~= nil then return end   -- option set: the direct path above
    local state = Patients[source]
    local spec = state and state.ecg12Pending
    if not spec then return end
    state.ecg12Pending = nil
    if success then deliverECG12(medic, source, spec) end
end)

addEvent("medic:ecg12Print", true)
addEventHandler("medic:ecg12Print", resourceRoot, function(target, spec)
    local medic = client
    if type(spec) ~= "table" or not canMedicAttend(medic, target, MEDIC.INTERACT_RANGE + 2) then return end
    -- the printed strip: the EMS case sheet (med_docs) takes the last one; a document of its own too
    setElementData(target, "ecg.lastPrint", spec, false)
    local res = getResourceFromName("med_docs")
    if res and getResourceState(res) == "running" then
        exports.med_docs:createDocument("ecg", { author = medic, patient = getElementData(target, MEDIC.DATA_NAME) or "" },
            { spec = spec, at = spec.at, rhythm = spec.rhythm, patient = { name = getElementData(target, MEDIC.DATA_NAME) or false } })
    end
    triggerClientEvent(medic, "medic:panelMessage", resourceRoot, L.msg("medsys.ecg12.printed"), false)
end)
