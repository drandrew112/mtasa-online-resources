-- Scripted vehicles (server): traffic agents created through exports by other resources (the bus system).
--
-- A scripted vehicle is an ordinary traffic agent (same lanes, lights, right of way, car following,
-- emergency vehicle reactions) with two differences:
--   * it follows a list of targets: stops (drive there, stand, wait) and turn points (just pass the spot),
--     the route between them is a navmesh lane route (profile option); lane changes are made where it needs them
--   * it only goes away when its owner says so (destroyScriptedVehicle), SCRIPTED_END_LIFE after the last
--     target is done / removed, or when it leaves the simulation (crash, driver seat taken, explosion)
-- Without a target it drives on like any other traffic vehicle (random exits).
--
-- ag.script = { targets = { { id, kind, lane, s, x, y, z, wait, hold, tag }, ... }, exits, wish, noPath (route
--               cache of the current head target), dwell = { left } (standing at a stop), stopLane / stopS (head
--               target when it is a stop), endLeft (ms until removal), speedFactor, profile (navmesh), owner }
-- Events (triggered on root after the simulation step, args start with the vehicle):
--   onTrafficVehicleTargetReached  (veh, id, kind, tag, x, y, z)   stop: standing at it; turn point: passed
--   onTrafficVehicleTargetDeparted (veh, id, kind, tag, x, y, z)   stop: wait over, driving on
--   onTrafficVehicleTargetFailed   (veh, id, kind, tag, reason)    no route to it, target dropped
--   onTrafficVehicleRouteFinished  (veh, removeInMs)               last target done, removal timer started
--   onTrafficVehicleRemoved        (veh, reason)                   vehicle left the scripted list: "timeout",
--                                  "vehicle_destroyed", "crash" / "damage" / "enter" / "jacked" (released, now a physics
--                                  vehicle) - not sent for destroyScriptedVehicle; veh may already be gone

Scripted = { count = 0, list = {} }   -- list: [agent] = true

local S = Scripted
local T = TRAFFIC
local sqrt, abs, min, max = math.sqrt, math.abs, math.min, math.max
local nextTargetId = 1

local EVENTS = {
    "onTrafficVehicleTargetReached", "onTrafficVehicleTargetDeparted", "onTrafficVehicleTargetFailed",
    "onTrafficVehicleRouteFinished", "onTrafficVehicleRemoved",
}
for _, name in ipairs(EVENTS) do addEvent(name) end

------------------------------------------------------------------------ events

local pending = {}

-- queued: handlers may call the exports (create / destroy vehicles) while the simulation is not iterating
local function emit(name, ...)
    pending[#pending + 1] = { name, { ... }, select("#", ...) }
end

function Scripted.flush()
    if #pending == 0 then return end
    local queue = pending
    pending = {}
    for _, e in ipairs(queue) do triggerEvent(e[1], root, unpack(e[2], 1, e[3])) end
end

------------------------------------------------------------------------ lane lookup

-- nearest lane (outer lanes only: the spawn grid) to a point; heading (MTA rotation) restricts the direction
local function snap(x, y, z, heading, radius)
    radius = radius or T.SCRIPTED_SNAP_RADIUS
    local hx, hy
    if heading then
        local a = math.rad(heading)
        hx, hy = -math.sin(a), math.cos(a)
    end
    local bestLane, bestS, bestScore
    for _, cell in ipairs(Net.cellsAround(x, y, radius)) do
        for _, id in ipairs(cell.lanes) do
            local x1, y1, x2, y2 = Geo.lx1[id], Geo.ly1[id], Geo.lx2[id], Geo.ly2[id]
            local dx, dy = x2 - x1, y2 - y1
            local l2 = dx * dx + dy * dy
            local t = l2 > 0 and ((x - x1) * dx + (y - y1) * dy) / l2 or 0
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
            local d = sqrt((x - (x1 + dx * t)) ^ 2 + (y - (y1 + dy * t)) ^ 2)
            if d <= radius then
                local pz = Geo.lz1[id] + (Geo.lz2[id] - Geo.lz1[id]) * t
                local dz = z and abs(z - pz) or 0
                local dirOk = true
                if hx and l2 > 0 then dirOk = (dx * hx + dy * hy) / sqrt(l2) >= 0 end
                if dz <= T.SCRIPTED_SNAP_Z and dirOk then
                    local score = d + dz * 1.5
                    if not bestScore or score < bestScore then
                        bestLane, bestS, bestScore = id, t * Geo.length(id), score
                    end
                end
            end
        end
    end
    return bestLane, bestS
end

------------------------------------------------------------------------ route search (navmesh)

-- lane route from `start` to the goal target (navmesh lane A*, the vehicle's profile). Returns
-- { { lane, conn = id | lc = laneId }, ... } from `start` on to the goal lane, or nil. startS: position on the
-- start lane (nil = its start). needEdge: start == goal lane but the way round to it is wanted (the vehicle
-- passed it): the search starts at the lane end.
local function findPath(ag, start, goal, startS, needEdge)
    if start == goal.lane and not needEdge then return {} end
    local len = Geo.length(start)
    local u0 = needEdge and 1 or (startS and len > 0 and startS / len or 0)
    local glen = Geo.length(goal.lane)
    local gu = glen > 0 and goal.s / glen or 0
    if needEdge and gu > 0.999 then gu = 0.999 end
    local lanes, conns = Navmesh.laneRoute(start, u0, goal.lane, gu, { profile = ag.script.profile })
    if not lanes or #lanes < 2 then return nil end
    local steps = {}
    for i = 1, #lanes - 1 do
        local c = conns[i + 1]
        if c then steps[#steps + 1] = { lane = lanes[i], conn = c }
        else steps[#steps + 1] = { lane = lanes[i], lc = lanes[i + 1] } end
    end
    return steps
end

------------------------------------------------------------------------ route following (hooks used by agents / lanes)

local function refresh(ag)
    local sc = ag.script
    local t = sc.targets[1]
    if t and t.kind == "stop" then sc.stopLane, sc.stopS = t.lane, t.s else sc.stopLane, sc.stopS = nil, nil end
end

-- forget the route cache and choose the exits ahead again (after a target change)
local function reroute(ag, missedId)
    local sc = ag.script
    sc.exits, sc.wish, sc.noPath = {}, {}, {}
    sc.failId, sc.seen, sc.missedId = nil, nil, missedId
    refresh(ag)
    Agents.replan(ag)
end

-- connection to take when leaving `lane` (nil = no route / no target: the agent chooses at random)
function Scripted.exit(ag, lane)
    local sc = ag.script
    local tgt = sc.targets[1]
    if not tgt then return nil end
    local goal, needEdge = tgt, false
    if lane == tgt.lane then
        if sc.missedId == tgt.id and lane == ag.plan[1].code then
            needEdge = true                       -- passed the stop: come round again
        else
            goal = sc.targets[2]                  -- leaving the target lane: on to the next target
            if not goal then return nil end
            needEdge = goal.lane == lane
        end
    end
    local c = sc.exits[lane]
    if c then return c end
    if sc.noPath[lane] then return nil end
    local steps = findPath(ag, lane, goal, lane == ag.plan[1].code and ag.s or nil, needEdge)
    if not steps or #steps == 0 then
        sc.noPath[lane] = true
        if lane == ag.plan[1].code and goal == tgt then sc.failId = tgt.id end
        return nil
    end
    for _, st in ipairs(steps) do
        if st.conn then sc.exits[st.lane] = st.conn else sc.wish[st.lane] = st.lc end
    end
    return sc.exits[lane]
end

-- neighbouring lane the route wants the agent to move to (lanes.lua)
function Scripted.laneWish(ag, lane)
    local sc = ag.script
    return sc.targets[1] and sc.wish[lane] or nil
end

------------------------------------------------------------------------ target handling

local function startEndTimer(ag)
    local sc = ag.script
    sc.endLeft = T.SCRIPTED_END_LIFE
    emit("onTrafficVehicleRouteFinished", ag.veh, sc.endLeft)
end

-- the head target is done
local function finishHead(ag)
    local sc = ag.script
    table.remove(sc.targets, 1)
    sc.dwell = nil
    reroute(ag)
    if #sc.targets == 0 then startEndTimer(ag) end
end

local function depart(ag, tgt)
    emit("onTrafficVehicleTargetDeparted", ag.veh, tgt.id, tgt.kind, tgt.tag, tgt.x, tgt.y, tgt.z)
    finishHead(ag)
end

local function arrive(ag, tgt)
    local sc = ag.script
    emit("onTrafficVehicleTargetReached", ag.veh, tgt.id, tgt.kind, tgt.tag, tgt.x, tgt.y, tgt.z)
    if tgt.hold then
        sc.dwell = {}
    elseif tgt.wait > 0 then
        sc.dwell = { left = tgt.wait }
    else
        depart(ag, tgt)
    end
end

-- once per simulation tick, before Sim.step
function Scripted.step(now, dt)
    local ms = dt * 1000
    for ag in pairs(S.list) do
        local sc = ag.script
        if not Agents.list[ag.id] then
            S.list[ag] = nil
        else
            local tgt = sc.targets[1]
            if tgt then
                local cur = ag.plan[1].code
                if sc.dwell then
                    local d = sc.dwell
                    if d.left then
                        d.left = d.left - ms
                        if d.left <= 0 then depart(ag, tgt) end
                    end
                elseif sc.failId == tgt.id then
                    emit("onTrafficVehicleTargetFailed", ag.veh, tgt.id, tgt.kind, tgt.tag, "no_route")
                    finishHead(ag)
                elseif tgt.kind == "turn" then
                    if cur == tgt.lane then
                        sc.seen = tgt.id
                        if ag.s >= tgt.s then arrive(ag, tgt) end
                    elseif sc.seen == tgt.id then
                        arrive(ag, tgt)           -- left the lane (lane change) without touching the spot
                    end
                else
                    if ag.stopGap and ag.stopGap < T.SCRIPTED_ARRIVE_GAP and ag.v < 0.4 then
                        arrive(ag, tgt)
                    elseif cur == tgt.lane then
                        sc.seen = tgt.id
                        -- drove past the stop point (front more than 4 m beyond it): round again
                        if ag.stopGap and ag.stopGap < -4 and sc.missedId ~= tgt.id then reroute(ag, tgt.id) end
                    else
                        if sc.missedId == tgt.id then sc.missedId = nil end
                        if sc.seen == tgt.id then reroute(ag) end   -- left the lane without stopping
                    end
                end
            elseif sc.endLeft then
                sc.endLeft = sc.endLeft - ms
                if sc.endLeft <= 0 then Agents.destroy(ag, "timeout") end
            end
        end
    end
end

-- the agent left the simulation (Agents.forget)
function Scripted.forget(ag, reason)
    local sc = ag.script
    if S.list[ag] then
        S.list[ag] = nil
        S.count = S.count - 1
    end
    if not sc.silent then emit("onTrafficVehicleRemoved", ag.veh, reason or "destroyed") end
end

------------------------------------------------------------------------ exports

local function scripted(veh)
    local ag = isElement(veh) and Agents.byVeh[veh]
    if ag and ag.script and Agents.list[ag.id] then return ag end
    return nil
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- create a vehicle (with a driver) on the road nearest to x, y, z, standing; returns the vehicle and the
-- driver ped, or false and a reason. options: heading (degrees, picks the lane direction), skin (driver),
-- speedFactor (0.3 - 1.5, multiplies the wanted speed), profile (navmesh vehicle profile for the routes: "car"
-- (default), "bus", "truck", "emergency"...)
function createScriptedVehicle(model, x, y, z, options)
    options = type(options) == "table" and options or {}
    model, x, y, z = tonumber(model), tonumber(x), tonumber(y), tonumber(z)
    if not (model and x and y) then return false, "bad_arguments" end
    if not Net.ready then return false, "network_not_loaded" end
    local lane, s = snap(x, y, z, tonumber(options.heading))
    if not lane then return false, "no_road" end
    local len = Geo.length(lane)
    local ag = Agents.spawn(lane, clamp(s, 1, max(1, len - 1)), 0, { model = model, skin = tonumber(options.skin) })
    if not ag then return false, "create_failed" end
    ag.script = {
        targets = {}, exits = {}, wish = {}, noPath = {},
        speedFactor = tonumber(options.speedFactor) and clamp(tonumber(options.speedFactor), 0.3, 1.5) or nil,
        profile = type(options.profile) == "string" and options.profile or "car",
        owner = sourceResource and getResourceName(sourceResource) or nil,
    }
    S.list[ag] = true
    S.count = S.count + 1
    setElementData(ag.veh, "ai_traffic_scripted", true)
    return ag.veh, ag.ped
end

local function addTarget(veh, kind, x, y, z, options)
    local ag = scripted(veh)
    if not ag then return false, "not_scripted" end
    options = type(options) == "table" and options or {}
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y) then return false, "bad_arguments" end
    local lane, s = snap(x, y, z, tonumber(options.heading), tonumber(options.radius))
    if not lane then return false, "no_road" end
    local len = Geo.length(lane)
    if kind == "stop" then
        -- not in the stop line zone at the lane end
        local hi = max(3, len - T.SCRIPTED_STOP_END)
        s = clamp(s, min(14, hi), hi)
    else
        s = clamp(s, 0, len)
    end
    local px, py, pz = Geo.pose(lane, s, 0)
    local t = {
        id = nextTargetId, kind = kind, lane = lane, s = s, x = px, y = py, z = pz,
        wait = max(0, tonumber(options.wait) or 0), hold = options.hold == true, tag = options.tag,
    }
    nextTargetId = nextTargetId + 1
    local sc = ag.script
    sc.targets[#sc.targets + 1] = t
    sc.endLeft = nil
    if #sc.targets <= 2 then reroute(ag) end   -- the first target and the leg after it are what the exits follow
    return t.id
end

-- the front of the vehicle stops at the road point nearest to x, y, z (outer lane of that carriageway).
-- options: wait (ms to stand, default 0), hold (true = stand until continueScriptedVehicle), tag (returned in
-- the events), heading (lane direction), radius (search). Returns the target id, or false and a reason.
function addScriptedStop(veh, x, y, z, options) return addTarget(veh, "stop", x, y, z, options) end

-- the route has to pass the road point nearest to x, y, z (place it behind a turn to force the turn)
function addScriptedTurnPoint(veh, x, y, z, options) return addTarget(veh, "turn", x, y, z, options) end

local function targetsEmptied(ag)
    local sc = ag.script
    sc.dwell = nil
    reroute(ag)
    startEndTimer(ag)
end

function removeScriptedTarget(veh, id)
    local ag = scripted(veh)
    if not ag then return false end
    local sc = ag.script
    for i, t in ipairs(sc.targets) do
        if t.id == id then
            table.remove(sc.targets, i)
            if i == 1 then
                if #sc.targets == 0 then targetsEmptied(ag) else sc.dwell = nil; reroute(ag) end
            end
            return true
        end
    end
    return false
end

function clearScriptedTargets(veh)
    local ag = scripted(veh)
    if not ag then return false end
    local sc = ag.script
    if #sc.targets == 0 then return true end
    sc.targets = {}
    targetsEmptied(ag)
    return true
end

-- end the wait at a stop (wait / hold) now
function continueScriptedVehicle(veh)
    local ag = scripted(veh)
    if not ag or not ag.script.dwell then return false end
    ag.script.dwell.left = 0
    return true
end

function destroyScriptedVehicle(veh)
    local ag = scripted(veh)
    if not ag then return false end
    ag.script.silent = true
    Agents.destroy(ag, "destroyed")
    return true
end

function isScriptedVehicle(veh) return scripted(veh) ~= nil end

function getScriptedVehicles()
    local out = {}
    for ag in pairs(S.list) do out[#out + 1] = ag.veh end
    return out
end

function getScriptedTargets(veh)
    local ag = scripted(veh)
    if not ag then return false end
    local out = {}
    for _, t in ipairs(ag.script.targets) do
        out[#out + 1] = { id = t.id, kind = t.kind, x = t.x, y = t.y, z = t.z, wait = t.wait, hold = t.hold, tag = t.tag }
    end
    return out
end

-- { targets = n, current = id | nil, waiting = bool, removeIn = ms | nil, speed = m/s }
function getScriptedVehicleState(veh)
    local ag = scripted(veh)
    if not ag then return false end
    local sc = ag.script
    return { targets = #sc.targets, current = sc.targets[1] and sc.targets[1].id or nil, waiting = sc.dwell ~= nil,
             removeIn = sc.endLeft, speed = ag.v }
end
