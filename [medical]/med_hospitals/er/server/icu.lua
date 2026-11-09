-- Intensive care (plan: Intenzív osztály): the ICU procedures of the patient panel and their model.
--   I01 rounds every 5 min (short assessment, points), I02 ventilator (VC / PC, FiO2, PEEP, RR, VT),
--   I03 noradrenaline titration (target MAP), I04 sedation (none / light / deep), I05 blood gas.
-- Simple ventilator model (every 5 s): FiO2 + PEEP - lung findings -> SpO2, minute volume -> EtCO2,
-- high PEEP lowers the pressure; a ventilated patient without sedation fights the machine.

local function ms() return ER.running("medsys") and exports.medsys or nil end
local function now() return getRealTime().timestamp end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local VISIT_EVERY = 300

local LIMITS = { fio2 = { 21, 100, 5 }, peep = { 0, 20, 1 }, rr = { 6, 35, 1 }, vt = { 250, 800, 25 } }
local NORAD_STEPS = { 0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5 }   -- mcg/kg/min
local LUNG = { ptx = 12, htx = 10, lung_contusion = 6, pulm_edema = 10, sepsis = 4, pe = 8, asphyxia = 6, asthma = 6, copd = 5 }

local function inIcu(c) return tostring(c.location or ""):find("^icu") ~= nil or tostring(c.location or ""):find("^shock") ~= nil end

local function lungPenalty(c)
    local p = 0
    for _, f in ipairs(ER.findings(c)) do if not f.treated and LUNG[f.id] then p = p + LUNG[f.id] end end
    return p
end

local function model(c, snap)
    local v = c.ventilator
    if not v then return nil end
    local spo2 = clamp(86 + (v.fio2 - 21) * 0.17 + v.peep * 0.9 - lungPenalty(c), 60, 100)
    local mv = v.rr * v.vt / 1000
    local etco2 = clamp(math.floor(40 * 6.3 / math.max(1, mv) + 0.5), 15, 90)
    if v.mode == "PC" then spo2 = spo2 + 1 end
    if (c.sedation or 0) == 0 then spo2 = spo2 - 5 end   -- fights the ventilator
    return math.floor(spo2 + 0.5), etco2, mv
end

-- panel data (his.lua detail): false outside the ICU / shock room
function ER.icuView(c)
    if not inIcu(c) then return false end
    local snap = ms() and ms():getMedicalState(c.ped) or {}
    local spo2, etco2, mv = model(c, snap)
    local sys, dia = snap.systolic or 0, snap.diastolic or 0
    return {
        vent = c.ventilator or false, intubated = snap.intubated and true or false,
        spo2Target = spo2 or false, etco2 = etco2 or false, mv = mv and math.floor(mv * 10 + 0.5) / 10 or false,
        norad = c.norad or 0, sedation = c.sedation or 0, map = math.floor((sys + 2 * dia) / 3 + 0.5),
        targetMap = 65, nextVisit = math.max(0, (c.lastVisit or 0) + VISIT_EVERY - now()),
        icu = tostring(c.location or ""):find("^icu") ~= nil, noradSteps = NORAD_STEPS, limits = LIMITS,
    }
end

local function award(player, c, code, labelKey)
    if ER.award then ER.award(player, c, code, 0, labelKey) end
end

-- action "icu": what = visit | vent | norad | sedation | abg, arg = the setting
function ER.icuAction(c, player, what, arg)
    if not inIcu(c) then return ER.notify(player, L.forPlayer(player, "med_hospitals.icu.not_in_icu"), true) end
    local px, py, pz = getElementPosition(player)
    local x, y, z = getElementPosition(c.ped)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > 4 then return ER.notify(player, L.forPlayer(player, "med_hospitals.exam.too_far"), true) end
    local snap = ms() and ms():getMedicalState(c.ped) or {}
    if what == "visit" then
        if not ER.canDo(player, "er.icu") then return end
        if now() - (c.lastVisit or 0) < VISIT_EVERY and c.visits then
            return ER.notify(player, L.forPlayer(player, "med_hospitals.icu.visit_too_soon", { s = (c.lastVisit or 0) + VISIT_EVERY - now() }), true)
        end
        c.lastVisit = now()
        c.visits = (c.visits or 0) + 1
        c.icuRounds = c.icuRounds or {}
        c.icuRounds[#c.icuRounds + 1] = { at = now(), by = (getElementData(player, "displayName") or getPlayerName(player)), hr = snap.heartRate, bp = snap.bloodPressure, spo2 = snap.spo2,
            gcs = c.gcs, vent = c.ventilator and (c.ventilator.mode .. " " .. c.ventilator.fio2 .. "%") or false, norad = c.norad or 0 }
        award(player, c, "HK-I01", "med_docs.code.hk_i01")
        ER.log(c, "icu_visit", tostring(c.visits), player)
        ER.notify(player, L.forPlayer(player, "med_hospitals.icu.visit_done", { hr = snap.heartRate or "-", bp = snap.bloodPressure or "-", spo2 = snap.spo2 or "-" }))
    elseif what == "vent" then
        if not ER.canDo(player, "er.icu") then return end
        if not snap.intubated then return ER.notify(player, L.forPlayer(player, "med_hospitals.proc.proc_not_intubated"), true) end
        arg = type(arg) == "table" and arg or {}
        local v = c.ventilator or { mode = "VC", fio2 = 60, peep = 5, rr = 14, vt = 450 }
        if arg.mode == "VC" or arg.mode == "PC" then v.mode = arg.mode end
        for k, lim in pairs(LIMITS) do
            local n = tonumber(arg[k])
            if n then v[k] = clamp(math.floor(n / lim[3] + 0.5) * lim[3], lim[1], lim[2]) end
        end
        local fresh = c.ventilator == nil
        c.ventilator = v
        if fresh then award(player, c, "HK-R06", "med_docs.code.hk_r06") end
        if not c.ventAwardAt or now() - c.ventAwardAt > 120 then
            c.ventAwardAt = now()
            award(player, c, "HK-I02", "med_docs.code.hk_i02")
        end
        ER.log(c, "ventilator", ("%s FiO2 %d PEEP %d RR %d VT %d"):format(v.mode, v.fio2, v.peep, v.rr, v.vt), player)
    elseif what == "norad" then
        if not ER.canDo(player, "er.icu") then return end
        if not snap.ivAccess then return ER.notify(player, L.forPlayer(player, "med_hospitals.icu.no_iv"), true) end
        local rate = tonumber(arg) or 0
        local okRate = false
        for _, r in ipairs(NORAD_STEPS) do if math.abs(r - rate) < 0.001 then okRate = true end end
        if not okRate then return end
        if rate > 0 and (c.norad or 0) == 0 and ER.useStock and not ER.useStock(c, "noradrenaline", 1) then return end
        c.norad = rate
        award(player, c, "HK-I03", "med_docs.code.hk_i03")
        ER.log(c, "norad", tostring(rate), player)
    elseif what == "sedation" then
        if not ER.canDo(player, "er.icu") then return end
        local lvl = math.floor(tonumber(arg) or 0)
        if lvl < 0 or lvl > 2 then return end
        if lvl > 0 and not snap.ivAccess then return ER.notify(player, L.forPlayer(player, "med_hospitals.icu.no_iv"), true) end
        c.sedation = lvl
        award(player, c, "HK-I04", "med_docs.code.hk_i04")
        ER.log(c, "sedation", tostring(lvl), player)
    elseif what == "abg" then
        if not ER.canDo(player, "er.order") then return end
        local o = ER.order(c, player, "lab.abg")
        if not o then return end
        o.status, o.drawErrors, o.ends = "running", {}, now() + 30
        award(player, c, "HK-I05", "med_docs.code.hk_i05")
        setTimer(function() if ER.cases[c.ped] then ER.finishOrder(c, o, player) end end, 30000, 1)
    else
        return
    end
    ER.syncCase(c)
end

-- the model: every 5 s for the patients in the ICU / shock room
setTimer(function()
    local m = ms()
    if not m then return end
    for ped, c in pairs(ER.cases) do
        if isElement(ped) and not c.dead and inIcu(c) then
            local snap = m:getMedicalState(ped) or {}
            if snap.dead then
                c.norad, c.sedation = nil, nil
            else
                if c.ventilator and snap.intubated and not snap.clinicalDeath then
                    local spo2 = model(c, snap)
                    if spo2 and math.abs((snap.spo2 or 0) - spo2) >= 1 then
                        local cur = snap.spo2 or spo2
                        m:setMedicalState(ped, "spo2", cur + clamp(spo2 - cur, -3, 3))
                    end
                    if c.ventilator.peep > 12 then m:setMedicalState(ped, "systolic", math.max(60, (snap.systolic or 110) - (c.ventilator.peep - 12))) end
                    if (c.sedation or 0) == 0 then m:setMedicalState(ped, "heartRate", math.min(150, (snap.heartRate or 80) + 2)) end
                elseif c.ventilator and not snap.intubated then
                    c.ventilator = nil
                end
                -- noradrenaline: lasting pressure lift while it runs (medsys hypertension = mmHg on the target systolic)
                if c.norad ~= nil then
                    m:setMedicalState(ped, "hypertension", math.floor(c.norad * 200))
                    if c.norad == 0 then c.norad = nil end
                end
                -- sedation caps the pain (light 13, deep 1)
                local cap = (c.sedation or 0) > 0 and math.max(0, 25 - c.sedation * 12) or nil
                if cap and (snap.pain or 0) > cap then m:setMedicalState(ped, "pain", cap) end
            end
        end
    end
end, 5000, 0)
