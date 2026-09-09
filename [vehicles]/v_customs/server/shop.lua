-- v_customs :: workshop sessions (server)
--
-- A session starts when a vehicle is driven onto a workshop marker: the car is
-- snapped onto the lift, frozen, made damage-proof and pushed (with its driver)
-- into a private dimension so nobody else is in the shot. It ends when the temp
-- menu closes, the player quits, or the vehicle dies.

Customs = Customs or {}

local sessions = {}   -- [player] = { veh, marker, dim, prevDim, origPlate }
local cooldown = {}   -- [player] = tick until which marker hits are ignored
local nextDim  = 30001

addEvent("v_customs:closeSession", true)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function nearestMarker(x, y, z)
    local best, bestDist
    for _, m in ipairs(Customs.MARKERS or {}) do
        local d = getDistanceBetweenPoints3D(x, y, z, m[1], m[2], m[3])
        if not bestDist or d < bestDist then
            best, bestDist = m, d
        end
    end
    return best, bestDist
end

function Customs.sessionVehicle(player)
    local s = sessions[player]
    return s and isElement(s.veh) and s.veh or nil
end

function Customs.session(player)
    return sessions[player]
end

--------------------------------------------------------------------------------
-- Session lifecycle
--------------------------------------------------------------------------------

local function startSession(player, veh)
    if sessions[player] then return end
    if cooldown[player] and cooldown[player] > getTickCount() then return end

    local vx, vy, vz = getElementPosition(veh)
    local marker = nearestMarker(vx, vy, vz)
    if not marker then return end

    local dim = nextDim
    nextDim = nextDim + 1
    if nextDim > 60000 then nextDim = 30001 end

    sessions[player] = {
        veh       = veh,
        marker    = marker,
        dim       = dim,
        prevDim   = getElementDimension(player),
        origPlate = getVehiclePlateText(veh),
    }

    setElementPosition(veh, marker[1], marker[2], marker[3])
    setElementRotation(veh, 0, 0, marker[4] or 0)
    setElementVelocity(veh, 0, 0, 0)
    setElementFrozen(veh, true)
    setVehicleDamageProof(veh, true)
    setElementDimension(veh, dim)
    setElementDimension(player, dim)
    setElementData(player, "customs:inShop", true)

    triggerClientEvent(player, "v_customs:sessionStarted", player, veh)
end

local function endSession(player, playerGone)
    local s = sessions[player]
    if not s then return end
    sessions[player] = nil
    cooldown[player] = getTickCount() + 2000

    if isElement(s.veh) then
        setElementFrozen(s.veh, false)
        setVehicleDamageProof(s.veh, false)
        setElementDimension(s.veh, s.prevDim or 0)
    end
    if isElement(player) and not playerGone then
        setElementDimension(player, s.prevDim or 0)
        setElementData(player, "customs:inShop", false)
        triggerClientEvent(player, "v_customs:sessionEnded", player)
    end
end
Customs.endSession = endSession

--------------------------------------------------------------------------------
-- Markers
--------------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    for _, m in ipairs(Customs.MARKERS or {}) do
        local marker = createMarker(m[1], m[2], m[3] - 1, "cylinder", Customs.MARKER_SIZE, 0, 120, 200, 90)
        setElementData(marker, "customs:marker", true)

        addEventHandler("onMarkerHit", marker, function(hit, matchingDim)
            if not matchingDim then return end

            local veh
            if getElementType(hit) == "vehicle" then
                veh = hit
            elseif getElementType(hit) == "player" then
                veh = getPedOccupiedVehicle(hit)
            end
            if not veh or getElementDimension(veh) ~= 0 then return end

            local driver = getVehicleController(veh)
            if driver and getElementType(driver) == "player" then
                startSession(driver, veh)
            end
        end)
    end
end)

--------------------------------------------------------------------------------
-- Teardown triggers
--------------------------------------------------------------------------------

addEventHandler("v_customs:closeSession", root, function()
    endSession(client)
end)

addEventHandler("onPlayerQuit", root, function()
    endSession(source, true)
end)

addEventHandler("onVehicleExplode", root, function()
    for player, s in pairs(sessions) do
        if s.veh == source then endSession(player) end
    end
end)

-- Driver bails out of the car mid-session -> close it.
addEventHandler("onVehicleExit", root, function(player)
    if sessions[player] then endSession(player) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do endSession(player) end
end)
