-- Coach registry: every passenger coach of every consist gets a coach id = the dimension of its
-- interior (RWP.DIM_BASE + n). Outside door anchors (invisible objects attached to the coach,
-- one per side) carry the "Board the train" ui_interactobject menus; they are enabled only while
-- the door on that side is usable: the train stands and the doors are released on that side
-- (released doors already mean a station platform, see DESIGN.md 3.1).

-- looked up on every call: a reloaded rw_core is a new resource and a cached exports table
-- would keep calling the old one (everything froze after rw_core reloaded)
local core = setmetatable({}, { __index = function(_, fn) return function(_, ...) return exports.rw_core[fn](nil, ...) end end })

Coaches   = {}          -- [dim] = coach
local byVehicle = {}    -- [vehicle] = coach
local Trains    = {}    -- [consistId] = { coaches = { coach, ... }, standSince, locked, lockReason }
local menuOwner = {}    -- [menuId] = { coach, door } | { coach, exit = true }

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function io() return exports.ui_interactobject end

------------------------------------------------------------------ geometry

local function flat(x, y)
    local l = math.sqrt(x * x + y * y)
    if l < 1e-6 then return 0, 1 end
    return x / l, y / l
end

-- the train's forward (2D, tail -> head) and its left vector. The doors' "left" / "right"
-- (rw.doors, canOpenDoors) are relative to the train facing its head.
function trainAxes(info)
    local head, tail = info.vehicles[1], info.vehicles[#info.vehicles]
    local fx, fy
    if isElement(head) and isElement(tail) and head ~= tail then
        local hx, hy = getElementPosition(head)
        local tx, ty = getElementPosition(tail)
        fx, fy = flat(hx - tx, hy - ty)
    elseif isElement(head) then
        local m = getElementMatrix(head)
        fx, fy = flat(m[2][1], m[2][2])
    else
        return nil
    end
    return fx, fy, -fy, fx
end

-- world pose of a coach: centre + its own right / forward vectors (2D)
local function coachPose(coach)
    local v = coach.vehicle
    if not isElement(v) then return nil end
    local m = getElementMatrix(v)
    local x, y, z = getElementPosition(v)
    local rx, ry = flat(m[1][1], m[1][2])
    local fx, fy = flat(m[2][1], m[2][2])
    return x, y, z, rx, ry, fx, fy
end

-- which side of the train ("left" | "right") a coach door is on, from the current positions
local function doorTrainSide(coach, door, info)
    local x, y, _, rx, ry, fx, fy = coachPose(coach)
    if not x then return nil end
    local _, _, lx, ly = trainAxes(info)
    if not lx then return nil end
    local dx, dy = rx * door.x + fx * door.y, ry * door.x + fy * door.y
    return (dx * lx + dy * ly) > 0 and "left" or "right"
end

-- remembered for forced exits after the vehicles are gone
local function rememberPose(coach, info)
    local x, y, z = coachPose(coach)
    if not x then return end
    local fx, fy, lx, ly = trainAxes(info)
    coach.last = { x = x, y = y, z = z, lx = lx or 1, ly = ly or 0, dim = getElementDimension(coach.vehicle) }
end

------------------------------------------------------------------ door state

-- which sides of the train can be used now: { left = bool, right = bool }, reason
function usableSides(trainId, info)
    local t = Trains[trainId]
    info = info or core:getConsist(trainId)
    if not t or not info or not isElement(info.lead) then return {}, "no train" end
    if t.locked then return {}, t.lockReason or "Boarding closed" end
    if not t.standSince or getTickCount() - t.standSince < RWP.STAND_TIME * 1000 then return {}, "The train is moving" end
    local doors = getElementData(info.lead, "rw.doors") or "closed"
    if doors == "closed" then return {}, "Doors closed" end
    return { left = doors == "left" or doors == "both", right = doors == "right" or doors == "both" }, doors
end

-- may this coach door be used now -> bool, reason
function isDoorUsable(coach, door, info)
    info = info or core:getConsist(coach.train)
    local sides, reason = usableSides(coach.train, info)
    if not sides.left and not sides.right then return false, reason end
    local side = doorTrainSide(coach, door, info)
    if not side or not sides[side] then return false, "Doors closed on this side" end
    return true, side
end

------------------------------------------------------------------ menus

local function serviceTitle(coach, info)
    info = info or core:getConsist(coach.train)
    local s = info and isElement(info.lead) and getElementData(info.lead, "rw.service")
    local base = ("Sunline Rail · Coach %d"):format(coach.index)
    if type(s) == "table" and s.name then return base .. " (" .. s.name .. ")" end
    return base
end

local function boardItems(coach, usable, reason)
    local desc = usable and ("%d / %d on board"):format(coach.count, RWP.CAPACITY) or tostring(reason)
    return { { label = "Board the train", value = "board", desc = desc, disabled = not usable } }
end

local function exitItems(coach, usable, reason)
    local desc = usable and "Doors open" or tostring(reason)
    return { { label = "Leave the train", value = "leave", desc = desc, disabled = not usable } }
end

-- pushes enabled state / texts to ui_interactobject only when they changed
-- info = the consist (core:getConsist), looked up when not given
local function refreshMenus(coach, info)
    if not running("ui_interactobject") then return end
    info = info or core:getConsist(coach.train)
    local title = serviceTitle(coach, info)
    for _, a in ipairs(coach.anchors) do
        if a.menu then
            local ok, reason = isDoorUsable(coach, a.door, info)
            if ok and coach.count >= RWP.CAPACITY then ok, reason = false, "The coach is full" end
            local sig = tostring(ok) .. "|" .. tostring(reason) .. "|" .. coach.count .. "|" .. title
            if sig ~= a.sig then
                a.sig = sig
                pcall(function()
                    io():updateInteractMenu(a.menu, { title = title, items = boardItems(coach, ok, reason) })
                end)
            end
        end
    end
    local e = coach.exit
    if e and e.menu then
        local sides, reason = usableSides(coach.train, info)
        local ok = sides.left or sides.right
        local sig = tostring(ok) .. "|" .. tostring(reason)
        if sig ~= e.sig then
            e.sig = sig
            pcall(function() io():updateInteractMenu(e.menu, { items = exitItems(coach, ok, reason) }) end)
        end
    end
end

local function registerAnchorMenus(coach)
    if not running("ui_interactobject") then return end
    for _, a in ipairs(coach.anchors) do
        if isElement(a.obj) and not a.menu then
            a.sig = nil
            local m = io():addInteractMenu(a.obj, {
                title = serviceTitle(coach), range = RWP.ANCHOR_RANGE, priority = 7, lineOfSight = false,
                items = boardItems(coach, false, "Doors closed"),
            })
            if m then a.menu = m menuOwner[m] = { coach = coach, door = a.door } end
        end
    end
    refreshMenus(coach)
end

local function removeMenu(id)
    if not id then return end
    menuOwner[id] = nil
    if running("ui_interactobject") then pcall(function() io():removeInteractMenu(id) end) end
end

------------------------------------------------------------------ exit anchor (inside)

function ensureExitAnchor(coach)
    if coach.exit and isElement(coach.exit.obj) then return end
    local I = RWP.INTERIORS.coach
    local o = createObject(RWP.ANCHOR_MODEL, I.exit.x, I.exit.y, I.exit.z)
    if not o then return end
    setElementAlpha(o, 0)
    setElementCollisionsEnabled(o, false)
    setElementInterior(o, I.interior)
    setElementDimension(o, coach.dim)
    coach.exit = { obj = o }
    setTimer(function()
        if not coach.exit or coach.exit.obj ~= o or not isElement(o) or not running("ui_interactobject") then return end
        local m = io():addInteractMenu(o, {
            title = "Sunline Rail", range = RWP.ANCHOR_RANGE, priority = 7, lineOfSight = false,
            items = exitItems(coach, false, "Doors closed"),
        })
        if m then coach.exit.menu = m menuOwner[m] = { coach = coach, exit = true } end
        refreshMenus(coach)
    end, 600, 1)
end

function removeExitAnchor(coach)
    local e = coach.exit
    if not e then return end
    removeMenu(e.menu)
    if isElement(e.obj) then destroyElement(e.obj) end
    coach.exit = nil
end

------------------------------------------------------------------ registry

local function allocDim()
    for n = 1, RWP.DIM_COUNT do
        if not Coaches[RWP.DIM_BASE + n] then return RWP.DIM_BASE + n end
    end
end

local function createAnchors(coach)
    for _, door in ipairs(RWP.COACH_DOORS) do
        local o = createObject(RWP.ANCHOR_MODEL, 0, 0, -50)
        if o then
            setElementAlpha(o, 0)
            setElementCollisionsEnabled(o, false)
            setElementDimension(o, getElementDimension(coach.vehicle))
            attachElements(o, coach.vehicle, door.x, door.y, door.z)
            coach.anchors[#coach.anchors + 1] = { obj = o, door = door }
        end
    end
    -- the clients need the objects before the menus can bind to them
    setTimer(function() if Coaches[coach.dim] == coach then registerAnchorMenus(coach) end end, 600, 1)
end

local function dropCoach(coach, reason)
    Passengers_evacuate(coach, reason)
    for _, a in ipairs(coach.anchors) do
        removeMenu(a.menu)
        if isElement(a.obj) then destroyElement(a.obj) end
    end
    removeExitAnchor(coach)
    byVehicle[coach.vehicle] = nil
    Coaches[coach.dim] = nil
    if isElement(coach.vehicle) then removeElementData(coach.vehicle, "rwp.coach") end
end

-- (re)builds the coach list of a consist from its current composition
function syncTrain(trainId)
    local info = core:getConsist(trainId)
    if not info then return end
    local t = Trains[trainId] or { coaches = {} }
    Trains[trainId] = t
    local keep, list, index = {}, {}, 0
    for i, v in ipairs(info.vehicles) do
        if RWP.COACH_TYPES[info.types[i]] and isElement(v) then
            index = index + 1
            local coach = byVehicle[v]
            if not coach then
                local dim = allocDim()
                if not dim then outputDebugString("[rw_passengers] no free coach dimension", 2) break end
                coach = { dim = dim, vehicle = v, train = trainId, anchors = {}, count = 0, passengers = {} }
                Coaches[dim] = coach
                byVehicle[v] = coach
                setElementData(v, "rwp.coach", dim)
                createAnchors(coach)
            end
            coach.train, coach.index = trainId, index
            keep[coach] = true
            list[#list + 1] = coach
        end
    end
    for _, coach in ipairs(t.coaches) do
        if not keep[coach] then dropCoach(coach, "The coach was uncoupled") end
    end
    t.coaches = list
end

local function forgetTrain(trainId, reason)
    local t = Trains[trainId]
    if not t then return end
    for _, coach in ipairs(t.coaches) do dropCoach(coach, reason) end
    Trains[trainId] = nil
end

function getTrainCoaches(trainId) return Trains[trainId] and Trains[trainId].coaches or {} end
function coachOfVehicle(v) return byVehicle[v] end
function coachOfMenu(menuId) return menuOwner[menuId] end

function setTrainLocked(trainId, on, reason)
    local t = Trains[trainId]
    if not t then return false end
    t.locked, t.lockReason = on and true or nil, on and (reason or "Boarding closed") or nil
    for _, coach in ipairs(t.coaches) do refreshMenus(coach) end
    return true
end

function refreshCoach(coach) refreshMenus(coach) end

------------------------------------------------------------------ events / timer

addEventHandler("onRailConsistSpawn", root, function(id) syncTrain(id) end)
addEventHandler("onRailConsistChange", root, function(id) setTimer(syncTrain, 200, 1, id) end)
addEventHandler("onRailConsistDestroy", root, function(id, reason)
    forgetTrain(id, reason == "the network train is gone" and "The train was taken out of service" or ("The train was removed (" .. tostring(reason) .. ")"))
end)

-- standing check + menu refresh for every train with coaches
setTimer(function()
    for trainId, t in pairs(Trains) do
        local info = core:getConsist(trainId)
        if not info then
            forgetTrain(trainId, "The train was taken out of service")
        elseif #t.coaches > 0 then
            if (info.speed or 99) < RWP.STAND_SPEED * 3.6 then
                t.standSince = t.standSince or getTickCount()
            else
                t.standSince = nil
            end
            for _, coach in ipairs(t.coaches) do
                rememberPose(coach, info)
                refreshMenus(coach, info)
            end
        end
    end
end, 250, 0)

addEventHandler("onResourceStart", root, function(res)
    if res == resource then
        -- elements created right at start reach the clients late: scan a moment later
        setTimer(function()
            for _, info in ipairs(core:getConsists() or {}) do syncTrain(info.id) end
        end, 500, 1)
    elseif getResourceName(res) == "ui_interactobject" then
        setTimer(function()
            for _, coach in pairs(Coaches) do
                for _, a in ipairs(coach.anchors) do a.menu = nil end
                registerAnchorMenus(coach)
                if coach.exit then
                    local o = coach.exit.obj
                    coach.exit = nil
                    if isElement(o) then destroyElement(o) end
                    if next(coach.passengers) then ensureExitAnchor(coach) end
                end
            end
        end, 600, 1)
    end
end)

-- debug / tests (MCP): the menus of a coach -> { { menu, anchor, side, usable, reason }, ..., exit = { menu, anchor } }
function debugCoachMenus(vehicle)
    local coach = byVehicle[vehicle]
    if not coach then return false end
    local out = { dim = coach.dim, index = coach.index, count = coach.count }
    for _, a in ipairs(coach.anchors) do
        local ok, reason = isDoorUsable(coach, a.door)
        out[#out + 1] = { menu = a.menu, anchor = a.obj, side = a.door.side, usable = ok, reason = reason }
    end
    if coach.exit then out.exit = { menu = coach.exit.menu, anchor = coach.exit.obj } end
    return out
end
