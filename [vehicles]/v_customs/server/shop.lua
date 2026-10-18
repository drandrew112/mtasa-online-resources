-- v_customs :: workshop sessions (server)
--
-- A session starts when a vehicle is driven far enough into a workshop
-- (server/workshop.lua): the car is frozen, made damage-proof and pushed (with
-- its driver) into a private dimension; the client plays the drive-in, then
-- opens the menu. Leaving: the client plays the turn + drive-out, then asks to
-- close; only then do car and driver go back to the normal dimension. Quit,
-- explosion or leaving the car ends it at once (car put outside the door).

Customs = Customs or {}

local sessions = {}   -- [player] = { veh, ws, dim, prevDim, origPlate, exiting }
local cooldown = {}   -- [player] = tick until which the workshop ignores them
local nextDim  = 30001

-- Max distance between the reported drive-out end point and the configured one.
local EXIT_TOLERANCE = 8
-- Speed the car leaves the door with (MTA units, 0.1 = 5 m/s).
local EXIT_SPEED = 0.1

addEvent("v_customs:exitBegin", true)
addEvent("v_customs:closeSession", true)

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

function Customs.startSession(player, veh, wsIdx)
    if sessions[player] then return end
    if cooldown[player] and cooldown[player] > getTickCount() then return end
    local ws = Customs.WORKSHOPS[wsIdx]
    if not ws then return end

    local dim = nextDim
    nextDim = nextDim + 1
    if nextDim > 60000 then nextDim = 30001 end

    sessions[player] = {
        veh       = veh,
        ws        = wsIdx,
        dim       = dim,
        prevDim   = getElementDimension(player),
        origPlate = getVehiclePlateText(veh),
    }

    setElementVelocity(veh, 0, 0, 0)
    setElementFrozen(veh, true)
    setVehicleDamageProof(veh, true)
    setElementDimension(veh, dim)
    setElementDimension(player, dim)
    setElementData(player, "customs:inShop", true)

    local model = getElementModel(veh)
    local name = getResourceFromName("veh_manager") and exports.veh_manager:getModelName(model)
    triggerClientEvent(player, "v_customs:sessionStarted", player, veh, wsIdx, dim,
        name or getVehicleNameFromModel(model))
end

-- pos = { x, y, z, rz } where the client's drive-out ended (nil = forced end)
local function endSession(player, playerGone, pos)
    local s = sessions[player]
    if not s then return end
    sessions[player] = nil
    cooldown[player] = getTickCount() + 3000

    local ws = Customs.WORKSHOPS[s.ws]
    if s.exiting then Customs.holdDoor(s.ws, false) end

    if isElement(s.veh) then
        -- always come out in front of the door, never stuck behind it
        local e = ws.exit
        local x, y, z, rz = e[1], e[2], e[3] + 1.0, e[4]
        if pos and tonumber(pos[1]) and tonumber(pos[2]) and tonumber(pos[3])
           and getDistanceBetweenPoints2D(pos[1], pos[2], e[1], e[2]) <= EXIT_TOLERANCE then
            x, y, z, rz = pos[1], pos[2], pos[3], tonumber(pos[4]) or e[4]
        end

        setElementDimension(s.veh, s.prevDim or 0)
        setElementPosition(s.veh, x, y, z)
        setElementRotation(s.veh, 0, 0, rz)
        setElementFrozen(s.veh, false)
        setVehicleDamageProof(s.veh, false)
        if pos then
            local r = math.rad(rz)
            setElementVelocity(s.veh, -math.sin(r) * EXIT_SPEED, math.cos(r) * EXIT_SPEED, 0)
        end

        -- personal vehicle -> persist the tuning to v_ownveh straight away
        local ownId = tonumber(getElementData(s.veh, "ownveh:id"))
        local ownRes = getResourceFromName("v_ownveh")
        if ownId and ownRes and getResourceState(ownRes) == "running" then
            pcall(function() exports.v_ownveh:saveVehicle(ownId) end)
        end
    end
    if isElement(player) and not playerGone then
        -- on foot (got out mid-session): the real door is shut, put them outside
        if getPedOccupiedVehicle(player) ~= s.veh then
            local e = ws.exit
            local r = math.rad(e[4] + 90)
            setElementPosition(player, e[1] - math.sin(r) * 3, e[2] + math.cos(r) * 3, e[3] + 1.0)
        end
        setElementDimension(player, s.prevDim or 0)
        setElementData(player, "customs:inShop", false)
        triggerClientEvent(player, "v_customs:sessionEnded", player)
    end
end
Customs.endSession = endSession

--------------------------------------------------------------------------------
-- Client-driven exit
--------------------------------------------------------------------------------

-- Menu closed, drive-out animation starting: open the real door so it is
-- already up when the car reappears in the normal dimension.
addEventHandler("v_customs:exitBegin", root, function()
    local s = sessions[client]
    if not s or s.exiting then return end
    s.exiting = true
    Customs.holdDoor(s.ws, true)
end)

addEventHandler("v_customs:closeSession", root, function(x, y, z, rz)
    endSession(client, false, x and { x, y, z, rz } or nil)
end)

--------------------------------------------------------------------------------
-- Teardown triggers
--------------------------------------------------------------------------------

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
