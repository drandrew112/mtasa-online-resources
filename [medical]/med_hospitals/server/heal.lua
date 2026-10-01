-- Free treatment marker: a player standing in it for HOSP.HEAL_TIME (15 s) is healed completely
-- (medsys healCompletely: injuries, bleeding, vitals; plus full health). Leaving cancels it.

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
    if not needsTreatment(player) then return "You do not need any treatment." end
    return nil
end

local function cancel(player, reason)
    if not procs[player] then return end
    procs[player] = nil
    stopProgress(player)
    if reason then notify(player, "Treatment cancelled: " .. reason) end
end

local function finish(player, p)
    procs[player] = nil
    stopProgress(player)
    local h = p.point.hospital
    if isResourceRunning("medsys") then exports.medsys:healCompletely(player) end
    setElementHealth(player, 100)
    notify(player, "You were treated at " .. h.name .. ". Get well soon!")
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
                    startProgress(player, point.marker, HOSP.HEAL_TIME, "Treatment in progress")
                    notify(player, ("Treatment started - stay in the marker for %d seconds. It is free of charge.")
                        :format(HOSP.HEAL_TIME / 1000))
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
            cancel(player, "you left the treatment marker.")
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
    for player in pairs(procs) do cancel(player, "the hospitals were reloaded.") end
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
