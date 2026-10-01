-- Ambulance bays are for on-duty ambulances only.
--
-- A vehicle in a bay that is not an on-duty ERM unit's vehicle (an off-duty ambulance or anything
-- else) turns the bay marker red and its driver is warned. While it stays, the driver is fined
-- HOSP.BAY_FINE every HOSP.BAY_FINE_INTERVAL through v_bank forceTakeMoney (from the bank
-- account, which may go negative). Getting out does not help: the fines go to whoever drove it
-- in (or drives it now).
-- Bay occupancy (bay.vehicle) is tracked by server/handover.lua.

addEvent("onHospitalBayFine", false)  -- (player, vehicle, hospitalId, amount)

local violators = {}  -- [vehicle] = { offender, nextFine, hospital }

local function ermRunning() return isResourceRunning("med_erm") end

local function isAuthorized(vehicle)
    return exports.med_erm:getVehicleUnit(vehicle) ~= false
end

local function warn(player, h)
    notify(player, ("#da3633Only ambulances on duty may stop in the bays of %s.#ffffff Leave now, or you are fined #da3633$%d#ffffff every %d seconds.")
        :format(h.name, HOSP.BAY_FINE, HOSP.BAY_FINE_INTERVAL / 1000))
end

local function fine(v, vehicle)
    local player = v.offender
    if not isResourceRunning("v_bank") then return end
    local ok = exports.v_bank:forceTakeMoney(player, HOSP.BAY_FINE)
    if ok ~= true then return end
    notify(player, ("You were fined #da3633$%d#ffffff for blocking an ambulance bay of %s.")
        :format(HOSP.BAY_FINE, v.hospital.name))
    triggerEvent("onHospitalBayFine", resourceRoot, player, vehicle, v.hospital.id, HOSP.BAY_FINE)
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

    for vehicle in pairs(violators) do
        if not seen[vehicle] then violators[vehicle] = nil end
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
    violators = {}  -- vehicles still in a bay are warned again by the new bays
end

addEventHandler("onPlayerQuit", root, function()
    for _, v in pairs(violators) do
        if v.offender == source then v.offender = nil end
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(updateRestricted, HOSP.TICK, 0)
end)
