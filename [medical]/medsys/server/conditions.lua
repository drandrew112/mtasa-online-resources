-- Time course of the hospital conditions (shared/conditions.lua), in clinical time (1 game hour = 10 min):
--   acs        territory (LAD 56 / RCA 36 / Cx 7 / LM 1 %), onset, ECG stage, necrosis % growing until
--              reperfusion (alteplase or PCI: reperfuseACS); antiplatelets slow it; complications by territory
--   stroke     last seen well; alteplase within 4.5 h: improvement chance falls with time, 6 % (20 % with
--              contraindications) symptomatic bleeding; lysis of a haemorrhagic stroke = disaster
--   appendicitis worsens and perforates (sepsis) when left alone
--   dka        glucose drifts up, insulin brings it down; poison_co clears on oxygen
--   TXA lowers the bleeding of trauma once; nitrate in an inferior STEMI drops the pressure
-- Labs and the 12-lead ECG of every new condition are here too (MEDIC_LAB_EFFECTS / MEDIC_ECG_EFFECTS).

local TICK = 5
local CLIN_MIN = 10   -- real seconds per clinical minute

local function now() return getTickCount() end
local function clinMin(fromTick) return (now() - (fromTick or now())) / 1000 / CLIN_MIN end

local function pickTerritory()
    local r = math.random(100)
    if r <= 56 then return "anterior" elseif r <= 92 then return "inferior" elseif r <= 99 then return "lateral" end
    return "lm"
end

addEventHandler("onMedicalInjury", root, function(injuryType, severity, id)
    local state = Patients[source]
    if not state then return end
    for _, inj in ipairs(state.injuries) do
        if inj.id == id then
            if injuryType == "acs" then
                inj.territory = inj.territory or pickTerritory()
                inj.onset = now() - math.random(20, 60) * CLIN_MIN * 1000   -- symptoms began 20-60 clinical minutes ago
                inj.necrosis = 0
            elseif injuryType == "stroke" then
                inj.lastWell = now() - math.random(30, 150) * CLIN_MIN * 1000
                inj.haemorrhagic = severity >= 3
            elseif injuryType == "appendicitis" or injuryType == "dka" or injuryType:find("^poison_") then
                inj.onset = now()
            end
        end
    end
end)

local function hasDrug(state, id)
    for _, d in ipairs(state.drugs) do if d.id == id then return true end end
    return false
end

-- reperfusion of a STEMI (PCI from med_hospitals, or alteplase here); -> true if there was one to reperfuse
function reperfuseACS(element, how)
    local state = Patients[element]
    if not state then return false end
    for _, inj in ipairs(state.injuries) do
        if inj.type == "acs" and not inj.reperfused then
            inj.reperfused, inj.reperfusedBy, inj.reperfusedAt = true, how, now()
            inj.treated = true
            return true
        end
    end
    return false
end

-- Definitive care of given injuries / conditions (an operation): treated, no bleeding, no pain from
-- them. ids = { injuryId, ... }; pain = the remaining pain 0-100 (default 20). -> count
function treatInjuries(element, ids, pain)
    local state = Patients[element]
    if not state or state.dead or type(ids) ~= "table" then return 0 end
    local want = {}
    for _, id in ipairs(ids) do want[tostring(id)] = true end
    local n = 0
    for _, inj in ipairs(state.injuries) do
        if want[tostring(inj.id)] and not inj.treated then
            inj.treated, inj.bleeding = true, 0
            if inj.type == "acs" then inj.reperfused, inj.reperfusedBy, inj.reperfusedAt = true, "pci", now() end
            n = n + 1
        end
    end
    if n > 0 then state.extraPain = math.min(state.extraPain or 0, tonumber(pain) or 20) end
    return n
end

setTimer(function()
    for element, state in pairs(Patients) do
        if not state.dead then
            for _, inj in ipairs(state.injuries) do
                local t = inj.type
                if t == "acs" and not inj.reperfused and inj.severity >= 2 then
                    local rate = 0.2 * (inj.severity == 3 and 1.5 or 1)
                    if hasDrug(state, "aspirin") or hasDrug(state, "clopidogrel") or hasDrug(state, "heparin") then rate = rate * 0.5 end
                    inj.necrosis = math.min(100, (inj.necrosis or 0) + rate)
                    if inj.territory == "inferior" and inj.necrosis > 15 and not inj.avb and math.random() < 0.02 then
                        inj.avb = true
                        applyInjury(element, "avb3", 2, nil, nil, "acs")
                    elseif (inj.territory == "anterior" or inj.territory == "lm") and inj.necrosis > 20 and math.random() < 0.004 then
                        setMedicalState(element, "rhythm", "VF")
                    elseif inj.territory == "lateral" and inj.necrosis > 15 and not inj.af and math.random() < 0.015 then
                        inj.af = true
                        applyInjury(element, "afib", 1, nil, nil, "acs")
                    end
                elseif t == "appendicitis" and not inj.treated then
                    local age = clinMin(inj.onset)
                    if age > 120 and inj.severity < 3 then inj.severity = 3 inj.onset = now() end
                    if inj.severity == 3 and age > 60 and not inj.perforated then
                        inj.perforated = true
                        applyInjury(element, "sepsis", 2, "abdomen", nil, "appendicitis")
                    end
                elseif t == "dka" then
                    local target = inj.treated and 180 or 520
                    state.glucose = state.glucose + (target - state.glucose) * 0.03
                elseif t == "poison_co" and not inj.treated and state.oxygenMask then
                    inj.coOxygen = (inj.coOxygen or 0) + TICK
                    if inj.coOxygen >= 300 then inj.treated = true end
                end
            end
        end
    end
end, TICK * 1000, 0)

---------------------------------------------------------------- medicine effects with a time course

addEventHandler("onMedicalTreatment", root, function(medic, action, success, option, dose)
    if action ~= "medication" or success ~= true then return end
    local element = source
    local state = Patients[element]
    if not state then return end
    if option == "txa" then
        for _, inj in ipairs(state.injuries) do
            if (inj.type == "gunshot" or inj.type == "fracture" or inj.type == "laceration") and inj.bleeding > 0 and not inj.txa then
                inj.txa = true
                inj.bleeding = inj.bleeding - 1
            end
        end
    elseif option == "nitroglycerin" then
        for _, inj in ipairs(state.injuries) do
            if inj.type == "acs" and inj.territory == "inferior" and inj.severity >= 2 then
                -- right ventricular infarction: the nitrate drops the preload, the pressure falls
                setMedicalState(element, "systolic", math.max(60, state.systolic - 35))
                inj.nitrateError = true
            end
        end
    elseif option == "alteplase" then
        for _, inj in ipairs(state.injuries) do
            if inj.type == "stroke" and not inj.lysed then
                inj.lysed = true
                local window = clinMin(inj.lastWell)    -- clinical minutes since last seen well
                local risky = state.systolic > 185 or state.anticoagulant
                inj.lysisAt, inj.lysisWindow = now(), window
                if inj.haemorrhagic then
                    -- lysis of an intracerebral bleed
                    setMedicalState(element, "consciousness", "unconscious")
                    inj.severity = 3
                    inj.lysisHarm = true
                elseif window > 270 then
                    inj.lysisLate = true
                    if math.random() < 0.25 then setMedicalState(element, "consciousness", "unconscious") inj.lysisHarm = true end
                else
                    if math.random() < (risky and 0.2 or 0.06) then
                        inj.lysisHarm = true
                        setMedicalState(element, "consciousness", "dazed")
                    elseif math.random() < 0.75 - (window / 270) * 0.4 then
                        inj.treated = true
                        inj.severity = math.max(1, inj.severity - 1)
                        inj.lysisGood = true
                    end
                end
            elseif inj.type == "acs" and inj.severity >= 2 and not inj.reperfused then
                if math.random() < 0.7 then reperfuseACS(element, "lysis") end
                if math.random() < 0.04 then inj.lysisBleed = true setMedicalState(element, "bleeding", 2) end
            end
        end
    end
end)

---------------------------------------------------------------- labs (server/labs.lua) of the new conditions

local LE = MEDIC_LAB_EFFECTS
LE.acs = function(v, inj)
    local age = clinMin(inj.onset) * 60 / CLIN_MIN       -- real seconds since onset
    local n = inj.severity == 1 and 6 or (inj.necrosis or 0)
    v.trop = v.trop + math.floor((inj.severity == 1 and 80 or n * 45) * math.min(1, age / 600))
    v.ck = v.ck + math.floor(n * 25)
end
LE.appendicitis = function(v, inj) v.crp = v.crp + 25 * inj.severity + clinMin(inj.onset) * 0.6 v.wbc = v.wbc + 3 + 2 * inj.severity end
LE.renal_colic = function(v) v.crea = v.crea + 12 v.wbc = v.wbc + 1 end
LE.sepsis = function(v, inj) v.lact = v.lact + 1.5 * inj.severity v.crp = v.crp + 120 + 40 * inj.severity v.wbc = v.wbc + (inj.severity == 3 and -4 or 9) v.plt = v.plt - 60 * inj.severity end
LE.dka = function(v, inj) v.ph = (v.ph or 7.4) v.k = v.k + 1.1 v.crea = v.crea + 30 v.dkaPh = 0.12 * inj.severity end
LE.pe = function(v, inj) v.ddimer = v.ddimer + 2 + inj.severity v.lact = v.lact + 0.5 * inj.severity v.trop = v.trop + 10 * inj.severity end
LE.hyperkalemia = function(v, inj) v.k = math.max(v.k, 5.8 + 0.8 * inj.severity) end
LE.gi_bleed = function(v, inj) v.crea = v.crea + 10 * inj.severity end
LE.poison_paracetamol = function(v) v.screen[#v.screen + 1] = "paracetamol" end
LE.poison_tca = function(v) v.screen[#v.screen + 1] = "tca" end
LE.poison_co = function(v, inj) v.cohb = (v.cohb or 1) + ({ 15, 28, 45 })[inj.severity] * (inj.treated and 0.2 or 1) end
LE.poison_betablocker = function(v) v.screen[#v.screen + 1] = "beta_blocker" v.glu = math.max(2.8, (v.glu or 5) - 1.5) end
LE.poison_digoxin = function(v, inj) v.screen[#v.screen + 1] = "digoxin" v.k = v.k + 0.6 * inj.severity end
LE.poison_methanol = function(v, inj) v.dkaPh = (v.dkaPh or 0) + 0.12 * inj.severity v.screen[#v.screen + 1] = "methanol" end
LE.poison_cyanide = function(v, inj) v.lact = v.lact + 3 * inj.severity end
LE.poison_organophosphate = function(v, inj) v.che = ({ 40, 20, 8 })[inj.severity] end
LE.anaphylaxis = function(v) v.lact = v.lact + 1 end

---------------------------------------------------------------- 12-lead ECG of the new conditions

local EE = MEDIC_ECG_EFFECTS
EE.acs = function(spec, inj)
    if inj.severity < 2 then spec.nstemi = true return end
    local age = clinMin(inj.onset)
    local stage = inj.reperfused and "reperfused" or (age < 10 and "hyperacute" or (age > 120 and "evolved" or "acute"))
    spec.stemi = { territory = inj.territory or "anterior", stage = stage }
end
EE.tamponade = function(spec) spec.alternans, spec.lowVoltage = true, true end
EE.poison_tca = function(spec, inj) spec.qrs = math.max(spec.qrs, 0.12 + 0.02 * inj.severity) end
EE.pe = function(spec) spec.rate = math.max(spec.rate, 105) end
EE.hyperkalemia = function(spec, inj) spec.k = math.max(spec.k or 4.2, 5.8 + 0.8 * inj.severity) end
