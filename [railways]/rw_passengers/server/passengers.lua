-- Passengers: boarding through a coach's door anchor, the coach interior (interior 1, dimension =
-- coach id), leaving through the exit anchor inside, and forced exits when the coach goes away.
-- Players move freely inside; nothing here restricts what they do in the cabin.

-- looked up on every call: a reloaded rw_core is a new resource and a cached exports table
-- would keep calling the old one (everything froze after rw_core reloaded)
local core = setmetatable({}, { __index = function(_, fn) return function(_, ...) return exports.rw_core[fn](nil, ...) end end })
local I = RWP.INTERIORS.coach

Passengers = {}          -- [player] = { coach = dim, train = id }
local pending = {}       -- [player] = true while a fade is running
local guard = {}         -- [player] = true while this resource changes interior / dimension

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function tell(player, text)
    if isElement(player) then triggerClientEvent(player, "rwp:notify", resourceRoot, text) end
end

addEvent("onPlayerBoardTrain")      -- source: player, (trainId, carIndex, dim) - cancellable
addEvent("onPlayerBoardedTrain")    -- source: player, (trainId, carIndex, dim)
addEvent("onPlayerLeftTrain")       -- source: player, (trainId, carIndex, reason)

------------------------------------------------------------------ placing

local function setPlace(player, int, dim, x, y, z, rz)
    guard[player] = true
    setElementInterior(player, int)
    setElementDimension(player, dim)
    setElementPosition(player, x, y, z)
    if rz then setElementRotation(player, 0, 0, rz, "default", true) end
    guard[player] = nil
end

-- world point beside a coach. side = "left" | "right" of the train or nil (pick one: the side
-- without a neighbouring track). -> x, y, z, rz, dim | nil
local function outsidePoint(coach, side)
    local cx, cy, cz, lx, ly, dim
    local info = core:getConsist(coach.train)
    if isElement(coach.vehicle) and info then
        cx, cy, cz = getElementPosition(coach.vehicle)
        local _, _, ax, ay = trainAxes(info)
        lx, ly = ax, ay
        dim = getElementDimension(coach.vehicle)
    end
    if not lx and coach.last then
        cx, cy, cz, lx, ly, dim = coach.last.x, coach.last.y, coach.last.z, coach.last.lx, coach.last.ly, coach.last.dim
    end
    if not lx then return nil end
    local sign
    if side == "left" then sign = 1 elseif side == "right" then sign = -1 end
    if not sign then
        sign = 1
        for _, s in ipairs({ 1, -1 }) do
            local px, py = cx + lx * s * RWP.EXIT_LATERAL, cy + ly * s * RWP.EXIT_LATERAL
            if not core:projectToTrack(px, py, nil, 2.0) then sign = s break end
        end
    end
    local x, y = cx + lx * sign * RWP.EXIT_LATERAL, cy + ly * sign * RWP.EXIT_LATERAL
    local z = cz - RWP.COACH_RAIL_HEIGHT + 1.2
    local rz = math.deg(math.atan2(ly * sign, lx * sign)) - 90         -- facing away from the coach
    return x, y, z, rz, dim or 0
end

------------------------------------------------------------------ state

-- quitting = the player is leaving the server: save.position stays for v_accounts' quit save
local function clearState(player, quitting)
    local p = Passengers[player]
    if not p then return nil end
    Passengers[player] = nil
    local coach = Coaches[p.coach]
    if coach then
        coach.passengers[player] = nil
        coach.count = math.max(0, coach.count - 1)
        if not next(coach.passengers) then removeExitAnchor(coach) end
        refreshCoach(coach)
    end
    if isElement(player) and not quitting then
        removeElementData(player, "rwp.ride")
        removeElementData(player, "save.position")
    end
    return p, coach
end

-- puts a passenger outside beside the coach (forced = no door check, used when the coach goes)
local function putOutside(player, coach, side, reason, fade)
    local x, y, z, rz, dim = outsidePoint(coach, side)
    local p = Passengers[player]
    local carIndex = coach.index
    local function go()
        if not isElement(player) then return end
        if not x then
            local b = p and p.back
            if b then x, y, z, rz, dim = b[1], b[2], b[3], nil, b[5] else return end
        end
        setPlace(player, 0, dim, x, y, z, rz)
        triggerClientEvent(player, "rwp:placed", resourceRoot, x, y, z, rz)
        if fade then fadeCamera(player, true, RWP.FADE_MS / 1000) end
    end
    clearState(player)
    if fade then
        pending[player] = true
        fadeCamera(player, false, RWP.FADE_MS / 1000)
        setTimer(function() pending[player] = nil go() end, RWP.FADE_MS + 50, 1)
    else
        go()
    end
    if reason then tell(player, reason) end
    triggerEvent("onPlayerLeftTrain", player, coach.train, carIndex, reason or "left")
end

-- called by the registry when a coach goes away (uncoupled, train removed)
function Passengers_evacuate(coach, reason)
    for player in pairs(coach.passengers) do
        if isElement(player) then putOutside(player, coach, nil, reason, true) end
    end
end

------------------------------------------------------------------ boarding / leaving

local function board(player, coach, door)
    if pending[player] or Passengers[player] then return end
    if isPedInVehicle(player) or isPedDead(player) then return end
    local ok, reason = isDoorUsable(coach, door)
    if not ok then tell(player, reason) return end
    if coach.count >= RWP.CAPACITY then tell(player, "The coach is full.") return end

    -- the ticket system / conductor can refuse here (cancelEvent)
    if not triggerEvent("onPlayerBoardTrain", player, coach.train, coach.index, coach.dim) then
        tell(player, "You cannot board this train.")
        return
    end

    -- the seat is taken at once (capacity), the move happens after the fade
    local x, y, z = getElementPosition(player)
    Passengers[player] = { coach = coach.dim, train = coach.train,
        back = { x, y, z, getElementInterior(player), getElementDimension(player) } }
    coach.passengers[player] = true
    coach.count = coach.count + 1
    pending[player] = true
    fadeCamera(player, false, RWP.FADE_MS / 1000)
    setTimer(function()
        pending[player] = nil
        if not isElement(player) or not Passengers[player] or Passengers[player].coach ~= coach.dim then return end
        if Coaches[coach.dim] ~= coach then clearState(player) fadeCamera(player, true, 0.3) return end
        -- quitting inside must not log the player in inside an empty cabin
        local b = Passengers[player].back
        setElementData(player, "save.position", { b[1], b[2], b[3], b[4], b[5] }, false)
        ensureExitAnchor(coach)
        setPlace(player, I.interior, coach.dim, I.spawn.x, I.spawn.y, I.spawn.z, I.spawn.rz)
        setElementData(player, "rwp.ride", { coach.dim, coach.train, coach.index })
        fadeCamera(player, true, RWP.FADE_MS / 1000)
        refreshCoach(coach)
        triggerEvent("onPlayerBoardedTrain", player, coach.train, coach.index, coach.dim)
    end, RWP.FADE_MS + 50, 1)
end

local function leave(player, coach)
    if pending[player] then return end
    local p = Passengers[player]
    if not p or p.coach ~= coach.dim then return end
    local info = core:getConsist(coach.train)
    local sides, reason = usableSides(coach.train, info)
    if not sides.left and not sides.right then tell(player, reason) return end
    local side
    if sides.left and sides.right then
        -- both released: the platform side
        local ok, ps = false, nil
        if running("rw_timetable") then ok, ps = exports.rw_timetable:canOpenDoors(coach.train) end
        side = (ok and (ps == "left" or ps == "right")) and ps or "right"
    else
        side = sides.left and "left" or "right"
    end
    putOutside(player, coach, side, nil, true)
end

addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local owner = coachOfMenu(menuId)
    if not owner then return end
    local player = source
    if owner.exit and value == "leave" then
        leave(player, owner.coach)
    elseif owner.door and value == "board" then
        board(player, owner.coach, owner.door)
    end
end)

------------------------------------------------------------------ cleanup

addEventHandler("onPlayerQuit", root, function()
    clearState(source, true)
    pending[source], guard[source] = nil, nil
end)

addEventHandler("onPlayerWasted", root, function()
    if Passengers[source] then clearState(source) end
end)

-- something else moved the player out of the cabin (admin teleport, another resource)
local function movedAway(player)
    if guard[player] or pending[player] then return end
    local p = Passengers[player]
    if not p then return end
    if getElementInterior(player) ~= I.interior or getElementDimension(player) ~= p.coach then clearState(player) end
end
addEventHandler("onElementDimensionChange", root, function() if getElementType(source) == "player" then movedAway(source) end end)
addEventHandler("onElementInteriorChange", root, function() if getElementType(source) == "player" then movedAway(source) end end)

-- everyone inside goes out before the state is lost
addEventHandler("onResourceStop", resourceRoot, function()
    for player, p in pairs(Passengers) do
        local coach = Coaches[p.coach]
        if isElement(player) and coach then
            local x, y, z, rz, dim = outsidePoint(coach, nil)
            if not x and p.back then x, y, z, dim = p.back[1], p.back[2], p.back[3], p.back[5] end
            if x then
                setPlace(player, 0, dim, x, y, z, rz)
                triggerClientEvent(player, "rwp:placed", resourceRoot, x, y, z, rz)
            end
            fadeCamera(player, true, 0)
            removeElementData(player, "rwp.ride")
            removeElementData(player, "save.position")
        end
    end
end)

------------------------------------------------------------------ exports

function getCoachByDimension(dim)
    local c = Coaches[tonumber(dim)]
    if not c then return false end
    return c.train, c.index, c.vehicle
end

function getCoachDimension(vehicle)
    local c = coachOfVehicle(vehicle)
    return c and c.dim or false
end

function getPassengers(trainId, carIndex)
    local out = {}
    for player, p in pairs(Passengers) do
        if p.train == trainId then
            local c = Coaches[p.coach]
            if not carIndex or (c and c.index == carIndex) then out[#out + 1] = player end
        end
    end
    return out
end

function getPlayerRide(player)
    local p = Passengers[player]
    if not p then return false end
    local c = Coaches[p.coach]
    return { train = p.train, car = c and c.index or false, coach = p.coach }
end

function removePassenger(player, reason)
    local p = Passengers[player]
    if not p then return false end
    local c = Coaches[p.coach]
    if not c then clearState(player) return true end
    putOutside(player, c, nil, reason, true)
    return true
end

function setBoardingLocked(trainId, on, reason) return setTrainLocked(trainId, on, reason) end

------------------------------------------------------------------ ride state for the passengers

-- every RWP.STATE_MS the passengers of each coach get what their client needs for the windows,
-- the information display, the announcements and the sounds:
--   v      = speed along the coach's own front (m/s, + = the coach moves towards its front)
--   x, y, z = coach centre, doors = "closed" | "left" | "right" | "both" seen from the coach's
--   own front, service = rw_timetable's service view of the train (false without a service)
local function coachState(coach, info)
    if not isElement(coach.vehicle) then return nil end
    local x, y, z = getElementPosition(coach.vehicle)
    local m = getElementMatrix(coach.vehicle)
    local fx, fy = trainAxes(info)
    local k = 1
    if fx then k = (m[2][1] * fx + m[2][2] * fy) >= 0 and 1 or -1 end
    local vHead = (info.speedSigned or 0) * (info.dir or 1)
    local doors = isElement(info.lead) and getElementData(info.lead, "rw.doors") or "closed"
    if k < 0 then
        if doors == "left" then doors = "right" elseif doors == "right" then doors = "left" end
    end
    local service = isElement(info.lead) and getElementData(info.lead, "rw.service") or false
    return { v = vHead * k, x = x, y = y, z = z, doors = doors, service = service, train = info.label, index = coach.index }
end

setTimer(function()
    local byCoach = {}
    for player, p in pairs(Passengers) do
        if isElement(player) and not pending[player] then
            byCoach[p.coach] = byCoach[p.coach] or {}
            table.insert(byCoach[p.coach], player)
        end
    end
    for dim, players in pairs(byCoach) do
        local coach = Coaches[dim]
        local info = coach and core:getConsist(coach.train)
        local st = info and coachState(coach, info)
        if st then triggerClientEvent(players, "rwp:state", resourceRoot, st) end
    end
end, RWP.STATE_MS, 0)
