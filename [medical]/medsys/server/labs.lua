-- Laboratory values from the simulation (the hospital lab, med_hospitals er/) and the patient log.
--
-- Clinical time (MEDIC.CLINICAL_SCALE): 1 game hour = 10 real minutes, every clinical time window
-- (STEMI, stroke lysis, S2 transfer ...) comes from it: medicClinicalHours / medicRealSeconds.
--
-- getLabValues(element) -> { hb, hct, wbc, plt, na, k, crea, glu, lact, ph, be, inr, aptt, ck, trop, crp,
--                            etoh, ddimer, group = "A+", screen = { "opioid", ... } } | false
-- Conditions add their own effects through MEDIC_LAB_EFFECTS[type](values, injury, state, ctx).
-- getPatientLog(element) -> { { at, action, option, dose, medic, success } } (every intervention, oldest first)

local BLOOD_GROUPS = { "0+", "0+", "0+", "0+", "A+", "A+", "A+", "A+", "B+", "B+", "AB+", "0-", "0-", "A-", "A-", "B-", "AB-" }
local LOG_MAX = 120

-- per patient: seconds spent with a low pressure / low oxygen / in arrest (drive lactate, creatinine)
local function ctxOf(state)
    local c = state.lab
    if not c then
        c = { lowBP = 0, lowO2 = 0, arrest = 0, since = getTickCount(), seed = math.random(1000, 9999) }
        state.lab = c
    end
    return c
end

local function bloodGroupOf(state)
    if not state.bloodGroup then state.bloodGroup = BLOOD_GROUPS[math.random(#BLOOD_GROUPS)] end
    return state.bloodGroup
end

setTimer(function()
    for _, state in pairs(Patients) do
        if not state.dead then
            local c = ctxOf(state)
            if state.systolic < 90 then c.lowBP = c.lowBP + 5 end
            if state.spo2 < 88 then c.lowO2 = c.lowO2 + 5 end
            if isInClinicalDeath(state) then c.arrest = c.arrest + 5 end
        end
    end
end, 5000, 0)

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function r2(v) return math.floor(v * 100 + 0.5) / 100 end

-- Effects of the existing injury types (new conditions add their own entries, see MEDIC_LAB_EFFECTS)
MEDIC_LAB_EFFECTS = MEDIC_LAB_EFFECTS or {}
MEDIC_LAB_EFFECTS.fracture = function(v, inj) v.ck = v.ck + ({ 400, 1300, 2600 })[inj.severity] v.wbc = v.wbc + 1.5 * inj.severity end
MEDIC_LAB_EFFECTS.gunshot = function(v, inj) v.ck = v.ck + 300 * inj.severity v.wbc = v.wbc + 1.5 * inj.severity end
MEDIC_LAB_EFFECTS.burn = function(v, inj)
    v.crp = v.crp + 15 * inj.severity v.wbc = v.wbc + 2 * inj.severity
    if inj.severity >= 3 then v.k = v.k + 1.0 v.ck = v.ck + 800 v.hb = v.hb + 12 end -- haemoconcentration, cell breakdown
end
MEDIC_LAB_EFFECTS.head_injury = function(v, inj) v.wbc = v.wbc + inj.severity v.glu = v.glu + 0.8 * inj.severity end
MEDIC_LAB_EFFECTS.alcohol = function(v, inj, state) v.etoh = v.etoh + ({ 0.9, 1.9, 3.2 })[inj.severity] end
MEDIC_LAB_EFFECTS.opioid = function(v) v.screen[#v.screen + 1] = "opioid" end
MEDIC_LAB_EFFECTS.sedative = function(v) v.screen[#v.screen + 1] = "benzodiazepine" end
MEDIC_LAB_EFFECTS.stimulant = function(v) v.screen[#v.screen + 1] = "amphetamine" v.ck = v.ck + 500 end
MEDIC_LAB_EFFECTS.postictal = function(v) v.ck = v.ck + 600 v.lact = v.lact + 3 end
MEDIC_LAB_EFFECTS.suffocation = function(v, inj) v.lact = v.lact + inj.severity end
MEDIC_LAB_EFFECTS.pulmonary_edema = function(v) v.ddimer = v.ddimer + 0.3 v.trop = v.trop + 25 end

function getLabValues(element)
    local state = isElement(element) and Patients[element]
    if not state then
        -- a healthy element: normal values (deterministic group per element)
        state = getPatient(element, false)
        if not state then
            return { hb = 145, hct = 0.43, wbc = 7.2, plt = 250, na = 139, k = 4.2, crea = 80, glu = 5.2, lact = 1.1, ph = 7.4,
                     be = 0, inr = 1.0, aptt = 30, ck = 110, trop = 6, crp = 2, etoh = 0, ddimer = 0.3, group = "0+", screen = {} }
        end
    end
    local c = ctxOf(state)
    local blood = state.bloodVolume / MEDIC.BLOOD_VOLUME
    local dilution = (state.fluidExcess or 0) / 100
    local v = {
        hb = 145 * blood ^ 0.6 - dilution * 1.5, wbc = 7.2, plt = 250 * clamp(blood, 0.4, 1) ^ 0.5,
        na = 139 - dilution * 0.4, k = 4.2, crea = 80 + c.lowBP / 60 * 6, glu = medicGlucoseMmol(state.glucose),
        lact = 1.1 + c.lowBP / 60 * 0.6 + c.lowO2 / 60 * 0.4 + c.arrest / 60 * 2.5 + (state.spo2 < 85 and 1.5 or 0),
        inr = 1.0 + (blood < 0.7 and (0.7 - blood) * 2 or 0), aptt = 30 + (blood < 0.7 and (0.7 - blood) * 40 or 0),
        ck = 110, trop = 6 + c.arrest / 60 * 40, crp = 2, etoh = 0, ddimer = 0.3, screen = {},
    }
    if state.anticoagulant then v.inr, v.aptt = v.inr + 1.6, v.aptt + 25 end
    for _, inj in ipairs(state.injuries) do
        local fx = MEDIC_LAB_EFFECTS[inj.type]
        if fx then fx(v, inj, state, c) end
    end
    -- time on the floor raises CK; a long resuscitation the potassium
    v.k = v.k + c.arrest / 600
    v.ph = 7.40 - (v.dkaPh or 0) - (v.lact - 1.1) * 0.035 - (state.spo2 < 88 and 0.05 or 0) - (state.intubated and 0 or (getBreathing(state, getTickCount()) == "slow" and 0.08 or 0))
    v.be = (v.ph - 7.40) * 60
    v.hct = v.hb / 330
    -- rounding
    for _, key in ipairs({ "hb", "plt", "crea", "ck", "trop", "aptt" }) do v[key] = math.floor(v[key] + 0.5) end
    for _, key in ipairs({ "wbc", "na", "k", "glu", "lact", "crp", "etoh", "ddimer", "be", "inr" }) do v[key] = r1(v[key]) end
    v.ph, v.hct = r2(v.ph), r2(v.hct)
    v.cohb = r1(v.cohb or 1.2)
    v.che = v.che and r1(8 * v.che / 100) or 8.0   -- cholinesterase kU/l (organophosphate: % of normal)
    v.dkaPh = nil
    v.group = bloodGroupOf(state)
    return v
end

-- the blood group of the patient (transfusion): rolled once per medical state
function getBloodGroup(element)
    local state = isElement(element) and getPatient(element, true)
    return state and bloodGroupOf(state) or false
end

---------------------------------------------------------------- patient log (EMS case sheet, Ambuláns lap)

addEventHandler("onMedicalTreatment", root, function(medic, action, success, option, dose)
    local state = Patients[source]
    if not state then return end
    state.log = state.log or {}
    if #state.log >= LOG_MAX then table.remove(state.log, 1) end
    state.log[#state.log + 1] = {
        at = getRealTime().timestamp, action = action, option = option ~= nil and tostring(option) or nil,
        dose = tonumber(dose), success = success == true,
        medic = isElement(medic) and (getElementData(medic, "displayName") or getPlayerName(medic)) or nil,
    }
end)

function getPatientLog(element)
    local state = isElement(element) and Patients[element]
    local out = {}
    for i, e in ipairs(state and state.log or {}) do out[i] = e end
    return out
end

---------------------------------------------------------------- for the hospital panel (med_hospitals er/)

-- Starts a procedure from another resource's panel (the hospital exam panel): the same checks as the
-- medsys panel, without the open medsys panel. -> true | false, reason (message object / text)
function startTreatmentFor(medic, target, action, option, dose)
    if not isElement(medic) or getElementType(medic) ~= "player" then return false end
    local ok, reason = startTreatment(medic, target, action, option, dose)
    if not ok and reason then reason = L.resolveFor(medic, reason) end
    return ok, reason
end

-- every medicine with its dosing (text parts as v_locals keys): { { id, name, class, route, hospital,
-- dosing = { unit, perKg, default, options = { { dose, high, note } } } } }
function getDrugCatalog()
    local function key(v) if type(v) == "table" and v.t then return v.t end return v end
    local out = {}
    for id, d in pairs(MEDIC_DRUGS) do
        local dosing
        if d.dosing then
            local opts = {}
            for i, o in ipairs(d.dosing.options) do opts[i] = { dose = o.dose, high = o.high or false, note = key(o.note) } end
            dosing = { unit = d.dosing.unit, perKg = d.dosing.perKg or false, default = d.dosing.default, options = opts }
        end
        out[#out + 1] = { id = id, name = d.name, class = key(d.class), desc = key(d.desc), route = d.route or "iv",
                          hospital = d.hospital or false, dosing = dosing }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end
