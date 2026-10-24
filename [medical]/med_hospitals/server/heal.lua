if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Treatment marker: a player standing in it for HOSP.HEAL_TIME (15 s) is healed completely
-- (medsys healCompletely: injuries, bleeding, vitals; plus full health). Leaving cancels it.
-- Billed through gov_health chargeHealthcare: the payer is set per hospital on the /gov Healthcare page
-- (free for the player, unless the patient pays there: marker data hosp.paid, server/hospitals.lua).

addEvent("onHospitalPlayerHealed", false)  -- (player, hospitalId)

local procs = {}  -- [player] = { point, ends }
local done = {}   -- [player] = point   (healed / refused: no restart until they step out)

local function needsTreatment(player)
    if getElementHealth(player) < 100 then return true end
    if isResourceRunning("medsys") then
        local state = exports.medsys:getMedicalState(player)
        if state and state.isPatient then return true end
    end
    return false
end

-- Reason the player cannot be treated now, or nil
local function refusal(player)
    if isPedDead(player) or getPedOccupiedVehicle(player) then return "" end
    if getElementData(player, "stretcher.on") then return "" end          -- lying on a stretcher
    if getElementData(player, "stretcher.pushing") then return "" end     -- pushing one
    if not needsTreatment(player) then return L.msg("med_hospitals.heal.you_do_not_need_any_treatment") end
    return nil
end

local function cancel(player, reason)
    if not procs[player] then return end
    procs[player] = nil
    stopProgress(player)
    if reason then notify(player, L.msg("med_hospitals.heal.treatment_cancelled", { reason = reason })) end
end

local function finish(player, p)
    procs[player] = nil
    stopProgress(player)
    local h = p.point.hospital
    -- billed before the patient is healed (the cost is what is healed)
    if isResourceRunning("gov_health") then
        local ok, amount, paid = exports.gov_health:chargeHealthcare(player, h.name, nil, h.id)
        if ok and paid and amount > 0 then notify(player, L.msg("med_hospitals.heal.you_paid_for_treatment", { amount = amount })) end
    end
    if isResourceRunning("medsys") then exports.medsys:healCompletely(player) end
    setElementHealth(player, 100)
    notify(player, L.msg("med_hospitals.heal.you_were_treated_at_get_well", { name = h.name }))
    triggerEvent("onHospitalPlayerHealed", resourceRoot, player, h.id)
end

local function update()
    local seen = {}
    local now = getTickCount()

    for point in eachPoint("heal") do
        for _, player in ipairs(elementsInPoint(point, "player")) do
            seen[player] = point
            if not procs[player] and done[player] ~= point then
                local reason = refusal(player)
                if not reason then
                    procs[player] = { point = point, ends = now + HOSP.HEAL_TIME }
                    startProgress(player, point.marker, HOSP.HEAL_TIME, L.msg("med_hospitals.heal.treatment_in_progress"))
                    notify(player, L.msg(isPaidHospital(point.hospital) and "med_hospitals.heal.treatment_started_paid"
                        or "med_hospitals.heal.treatment_started_stay_in_marker_for", { heal_time = HOSP.HEAL_TIME / 1000 }))
                elseif reason ~= "" then
                    done[player] = point
                    notify(player, reason)
                end
            end
        end
    end

    for player, point in pairs(done) do
        if seen[player] ~= point then done[player] = nil end
    end

    for player, p in pairs(procs) do
        if not isElement(player) then
            procs[player] = nil
        elseif seen[player] ~= p.point then
            cancel(player, L.msg("med_hospitals.heal.you_left_treatment_marker"))
        elseif isPedDead(player) or getPedOccupiedVehicle(player) or getElementData(player, "stretcher.on") then
            cancel(player)
        elseif now >= p.ends then
            done[player] = p.point
            finish(player, p)
        end
    end
end

function isHealing(player) return procs[player] ~= nil end

UnloadHandlers[#UnloadHandlers + 1] = function()
    for player in pairs(procs) do cancel(player, L.msg("med_hospitals.handover.hospitals_were_reloaded")) end
    procs, done = {}, {}
end

addEventHandler("onPlayerQuit", root, function()
    procs[source], done[source] = nil, nil
end)

addEventHandler("onPlayerWasted", root, function()
    cancel(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(update, HOSP.TICK, 0)
end)
