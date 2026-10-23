-- v_gov / server/health.lua
-- State healthcare (DESIGN.md 7): treatment at a hospital is free for the patient, the treasury
-- pays it. Cost = missing HP * health.hp_price + the price of every injury / condition by type and
-- severity (medsys). Booked as one health.care row on the treasury. Respawn after death is not
-- healthcare (nothing calls this there).

local function patientName(patient, taskId)
    if getElementType(patient) == "player" then
        return (getPlayerName(patient):gsub("#%x%x%x%x%x%x", "")), GOV.accountOf(patient) or ""
    end
    if taskId then return ("Unidentified patient (task %s)"):format(tostring(taskId)), "" end
    return "Unidentified patient", ""
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

--- computes and books the treatment -> true, amount | false, err
function chargeHealthcare(patient, hospitalName, taskId)
    if not isElement(patient) then return false, "no_patient" end
    if GOV.get("health.enabled") == false then return true, 0 end
    local cost, d = healthcareCost(patient)
    if cost <= 0 then return true, 0 end
    local bank = GOV.bank()
    if not bank then return false, "unavailable" end
    local treasury = bank:getStateAccount("treasury")
    if not treasury then return false, "unavailable" end
    local name, account = patientName(patient, taskId)
    local ok, err = bank:debit(treasury, cost, "health.care", {
        patient = name, account = account, hospital = tostring(hospitalName or ""),
        hp = d.hp, injuries = d.injuries, task = taskId and tostring(taskId) or nil,
    }, "v_gov")
    if not ok then return false, err end
    return true, cost
end
