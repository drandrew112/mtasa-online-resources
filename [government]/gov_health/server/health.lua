-- gov_health / server/health.lua
-- State healthcare. Cost = missing HP * health.hp_price + the price of every injury / condition
-- by type and severity (medsys). Who pays it is set per hospital on the Healthcare page
-- (setting health.hospitals: hospital id -> { payer, receiver }, a missing hospital = HEALTH_DEFAULT):
--   payer    "system" (money from nothing) | "player" (the patient, from the bank, may go into
--            debt; an NPC patient pays nothing) | "state:<code>" | "company:<id>"
--   receiver "system" (nobody, the money disappears) | "state:<code>" | "company:<id>"
-- Booked as one health.care (organization -> receiver) or health.patient (patient -> receiver) row.
-- Respawn after death is not healthcare (nothing calls this there).

loadstring(exports.gov_core:importLib())()

GOV.HEALTH_DEFAULT = { payer = "state:treasury", receiver = "system" }

-- setting key -> default value
GOV_DEFAULTS = {
    ["health.enabled"] = true,
    ["health.hp_price"] = 50,
    -- who pays the treatment, per med_hospitals hospital id: { payer, receiver } (a hospital
    -- without a row: the treasury pays, nobody receives)
    ["health.hospitals"] = {},
    -- injury / condition type -> price by severity 1 / 2 / 3 ("default" for types not listed)
    ["health.injuries"] = {
        gunshot = { 800, 2000, 4500 },
        fracture = { 500, 1200, 2500 },
        burn = { 400, 1500, 4000 },
        head_injury = { 700, 2000, 5000 },
        default = { 300, 800, 2000 },
    },
}

GOV_RANGE = {
    hpPrice = { 0, 100000 },
    injuryPrice = { 0, 1000000 },
}

local function patientName(patient, taskId)
    if getElementType(patient) == "player" then
        return (getPlayerName(patient):gsub("#%x%x%x%x%x%x", "")), GOV.accountOf(patient) or ""
    end
    if taskId then return ("Unidentified patient (task %s)"):format(tostring(taskId)), "" end
    return "Unidentified patient", ""
end

--- { payer, receiver } of a hospital (the default for a hospital without its own row)
function GOV.hospitalPayment(hospitalId)
    local row = (GOV.get("health.hospitals") or {})[tostring(hospitalId or "")]
    row = type(row) == "table" and row or {}
    return { payer = type(row.payer) == "string" and row.payer or GOV.HEALTH_DEFAULT.payer,
             receiver = type(row.receiver) == "string" and row.receiver or GOV.HEALTH_DEFAULT.receiver }
end

--- the payer spec of a hospital's treatment: "system" | "player" | "state:<code>" | "company:<id>"
function getHealthcarePayer(hospitalId)
    return GOV.hospitalPayment(hospitalId).payer
end

--- does the patient pay the treatment at this hospital? (false while healthcare is switched off)
function isHealthcarePaidByPatient(hospitalId)
    return GOV.get("health.enabled") ~= false and getHealthcarePayer(hospitalId) == "player"
end

--- amount, details { hp, injuries } of treating this patient now (books nothing)
function healthcareCost(patient)
    if not isElement(patient) then return 0, { hp = 0, injuries = 0 } end
    local missing = 0
    if not isPedDead(patient) then
        missing = math.max(0, math.floor(100 - getElementHealth(patient) + 0.5))
    end
    local cost = missing * (tonumber(GOV.get("health.hp_price")) or 0)
    local injuries = 0
    if isResourceRunning("medsys") then
        local state = exports.medsys:getMedicalState(patient)
        local prices = GOV.get("health.injuries") or {}
        if state then
            for _, list in ipairs({ state.injuries or {}, state.conditions or {} }) do
                for _, inj in ipairs(list) do
                    local p = prices[inj.type] or prices.default or {}
                    local sev = math.max(1, math.min(3, tonumber(inj.severity) or 1))
                    cost = cost + (tonumber(p[sev]) or 0)
                    injuries = injuries + 1
                end
            end
        end
    end
    return math.floor(cost), { hp = missing, injuries = injuries }
end

--- computes and books the treatment -> true, amount, paidByPatient | false, err
--- hospitalId (med_hospitals id) picks the payer; without it the default payer pays
function chargeHealthcare(patient, hospitalName, taskId, hospitalId)
    if not isElement(patient) then return false, "no_patient" end
    if GOV.get("health.enabled") == false then return true, 0, false end
    local cost, d = healthcareCost(patient)
    if cost <= 0 then return true, 0, false end
    local bank = GOV.bank()
    if not bank then return false, "unavailable" end
    local pay = GOV.hospitalPayment(hospitalId)
    local receiver = GOV.specAccount(pay.receiver)
    if receiver == false then
        outputDebugString(("[gov_health] healthcare receiver %s of %s is gone, the money disappears"):format(pay.receiver, tostring(hospitalId)), 2)
    end
    receiver = tonumber(receiver)
    local hospital = tostring(hospitalName or "")

    if pay.payer == "player" then
        if getElementType(patient) ~= "player" then return true, 0, false end   -- an NPC has no account
        local ok = bank:forceTakeMoney(patient, cost, "health.patient",
            { hospital = hospital, hp = d.hp, injuries = d.injuries }, receiver)
        if ok ~= true then return false, tostring(ok) end
        return true, cost, true
    end

    local payer = GOV.specAccount(pay.payer)
    if payer == false then
        outputDebugString(("[gov_health] healthcare payer %s of %s is gone, paid from system"):format(pay.payer, tostring(hospitalId)), 2)
    end
    payer = tonumber(payer)
    if not payer and not receiver then return true, cost, false end          -- nothing to book
    if payer and payer == receiver then return true, cost, false end
    local name, account = patientName(patient, taskId)
    local ok, err = bank:transfer(payer, receiver, cost, "health.care", {
        patient = name, account = account, hospital = hospital,
        hp = d.hp, injuries = d.injuries, task = taskId and tostring(taskId) or nil,
    }, "v_gov")
    if not ok then return false, err end
    return true, cost, false
end

--- a closed private company payer / receiver of a hospital goes back to the default (checked
--- after every settings re-read of gov_core)
addEventHandler("onGovSettingsSynced", root, function()
    local bank = GOV.bank()
    if not bank or not bank:isBankReady() then return end
    local function closed(spec)
        if type(spec) ~= "string" or not spec:match("^company:") then return false end
        local id = bank:getCompanyAccount(spec:match("^company:(.+)$"))
        local info = id and bank:getAccountInfo(id)
        return info and info.status == "closed"
    end
    local hospitals, changed = GOV.get("health.hospitals") or {}, false
    for _, row in pairs(hospitals) do
        if type(row) == "table" then
            if closed(row.payer) then row.payer, changed = nil, true end
            if closed(row.receiver) then row.receiver, changed = nil, true end
        end
    end
    if changed then GOV.set("health.hospitals", hospitals, "system") end
end)
