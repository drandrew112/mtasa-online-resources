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
    nextId = nextId + 1
    local spec = {
        id = ("%d-%d"):format(getTickCount(), nextId), rhythm = rhythm, rate = math.max(0, rate), pr = 0.16, qrs = 0.09,
        k = 4.2, alternans = false, lowVoltage = false, stemi = nil, seed = math.random(1, 999999), at = getRealTime().timestamp,
        swapRALA = errors and errors.swapRALA == true or false, wrongV = errors and tonumber(errors.wrongV) or 0,
        noP = NO_P[rhythm] or false,
    }
    if rhythm == "VT_WITH_PULSE" or rhythm == "PULSELESS_VT" then spec.rate = math.max(spec.rate, 170) end
    if WIDE[rhythm] then spec.qrs = 0.16 end
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
    local rr = spec.rate > 0 and 60 / spec.rate or 1
    spec.hr, spec.prMs, spec.qrsMs = spec.rate, (spec.noP or rhythm == "AVB3") and nil or math.floor(spec.pr * 1000), math.floor(spec.qrs * 1000)
    spec.qt = math.floor((0.36 + (spec.qrs - 0.09)) * math.sqrt(rr) * 1000 + 0.5)
    spec.qtc = math.floor(spec.qt / math.sqrt(rr) + 0.5)
    spec.axis = spec.swapRALA and 150 or 55
    local interp = { INTERP[rhythm] or "sinus" }
    if spec.stemi then interp[#interp + 1] = "stemi_" .. spec.stemi.territory end
    if spec.k >= 6.0 then interp[#interp + 1] = "hyperk" end
    if spec.alternans then interp[#interp + 1] = "alternans" end
    if spec.lowVoltage then interp[#interp + 1] = "low_voltage" end
    if spec.qrs >= 0.12 and not WIDE[rhythm] then interp[#interp + 1] = "wide_qrs" end
    if spec.swapRALA then interp[#interp + 1] = "swap_rala" end
    if spec.wrongV > 0 then interp[#interp + 1] = "poor_r" end
    spec.interp = interp
    return spec
end

---------------------------------------------------------------- the Lifepak "12-LEAD" button (EMS) and PRINT

addEvent("medic:ecg12Request", true)
addEventHandler("medic:ecg12Request", resourceRoot, function(target)
    local medic = client
    if not canMedicAttend(medic, target, MEDIC.INTERACT_RANGE + 2) then return end
    local ok, why = checkMedicPermission(medic, "action.ecg12")
    if not ok then return triggerClientEvent(medic, "medic:panelMessage", resourceRoot, why, true) end
    local state = Patients[target]
    if not state or not state.monitor then
        return triggerClientEvent(medic, "medic:panelMessage", resourceRoot, L.msg("medsys.ecg12.needs_monitor"), true)
    end
    local spec = getECGSpec(target)
    triggerClientEvent(medic, "medic:ecg12", resourceRoot, target, spec)
    triggerEvent("onMedicalTreatment", target, medic, "ecg12", true, spec.interp[1])
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
