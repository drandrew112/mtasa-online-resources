if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Ambulance bays are for on-duty ambulances only.
--
-- A vehicle in a bay that is not an on-duty ERM unit's vehicle (an off-duty ambulance or anything
-- else) turns the bay marker red and its driver is warned. While it stays, the driver is fined
-- the bay fine (v_gov fee "bay_fine", fallback HOSP.BAY_FINE) every HOSP.BAY_FINE_INTERVAL through
-- v_bank forceTakeMoney (from the bank account, which may go negative). Getting out does not help:
-- the fines go to whoever drove it in (or drives it now). The money reaches the State Treasury in
-- one sum per offender when the vehicle has left the bay (fine.hospital_bay_income).
-- Bay occupancy (bay.vehicle) is tracked by server/handover.lua.

addEvent("onHospitalBayFine", false)  -- (player, vehicle, hospitalId, amount)

local violators = {}  -- [vehicle] = { offender, nextFine, hospital, fined = { [name] = { total, count } } }

--- the fine per interval: /gov (v_gov fee), else the config
local function bayFine()
    if isResourceRunning("v_gov") then
        local v = tonumber(exports.v_gov:getFee("bay_fine"))
        if v and v > 0 then return math.floor(v) end
    end
    return HOSP.BAY_FINE
end

--- the violation is over: what was taken goes to the treasury, one row per offender
local function settle(v)
    if not v.fined or not isResourceRunning("v_bank") then return end
    for name, f in pairs(v.fined) do
        if f.total > 0 then
            exports.v_bank:credit(nil, f.total, "fine.hospital_bay_income",
                { player = name, hospital = v.hospital.name, count = f.count }, "med_hospitals")
        end
    end
    v.fined = nil
end

local function ermRunning() return isResourceRunning("med_erm") end

local function isAuthorized(vehicle)
    return exports.med_erm:getVehicleUnit(vehicle) ~= false
end

local function warn(player, h)
    notify(player, L.msg("med_hospitals.restricted.only_ambulances_on_duty_may_stop", { name = h.name, bay_fine = bayFine(), bay_fine_interval = HOSP.BAY_FINE_INTERVAL / 1000 }))
end

local function fine(v, vehicle)
    local player = v.offender
    if not isResourceRunning("v_bank") then return end
    local amount = bayFine()
    local ok = exports.v_bank:forceTakeMoney(player, amount, "fine.hospital_bay", { hospital = v.hospital.name })
    if ok ~= true then return end
    local name = getPlayerName(player):gsub("#%x%x%x%x%x%x", "")
    v.fined = v.fined or {}
    local f = v.fined[name] or { total = 0, count = 0 }
    f.total, f.count = f.total + amount, f.count + 1
    v.fined[name] = f
    notify(player, L.msg("med_hospitals.restricted.you_were_fined_for_blocking_ambulance", { bay_fine = amount, name = v.hospital.name }))
    triggerEvent("onHospitalBayFine", resourceRoot, player, vehicle, v.hospital.id, amount)
end

local function updateRestricted()
    local enforce = ermRunning()
    local now = getTickCount()
    local seen = {}

    for bay in eachPoint("bay") do
        local vehicle = bay.vehicle
        local bad = enforce and isElement(vehicle) and not isAuthorized(vehicle)
        setBayRestricted(bay, bad)
        if bad then seen[vehicle] = seen[vehicle] or bay.hospital end
    end

    for vehicle, v in pairs(violators) do
        if not seen[vehicle] then
            settle(v)
            violators[vehicle] = nil
        end
    end

    -- one entry per vehicle: a vehicle across two bays is fined once
    for vehicle, h in pairs(seen) do
        local v = violators[vehicle]
        if not v then
            v = { hospital = h, nextFine = now + HOSP.BAY_FINE_INTERVAL }
            violators[vehicle] = v
        end
        if v.offender and not isElement(v.offender) then v.offender = nil end

        local driver = getVehicleController(vehicle)
        if driver and driver ~= v.offender then
            -- new driver (or the first one): warned, a full interval to leave
            v.offender, v.nextFine = driver, now + HOSP.BAY_FINE_INTERVAL
            warn(driver, h)
        end

        if now >= v.nextFine then
            v.nextFine = now + HOSP.BAY_FINE_INTERVAL
            if v.offender then fine(v, vehicle) end
        end
    end
end

UnloadHandlers[#UnloadHandlers + 1] = function()
    for _, v in pairs(violators) do settle(v) end
    violators = {}  -- vehicles still in a bay are warned again by the new bays
end

addEventHandler("onResourceStop", resourceRoot, function()
    for _, v in pairs(violators) do settle(v) end
end)

addEventHandler("onPlayerQuit", root, function()
    for _, v in pairs(violators) do
        if v.offender == source then v.offender = nil end
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(updateRestricted, HOSP.TICK, 0)
end)
