-- Traffic agents (server): lifecycle, route plan, segment occupancy, spatial hash, release.
--
-- agent = { id, veh, ped, model, len, half,
--           plan = { { code, conn }, ... }  plan[1] is the current segment; a lane entry's conn is
--                                            the connection chosen to leave it (nil = not chosen yet)
--           s, v, a, v0f (driver factor), lat, latTarget,
--           x, y, z, fx, fy, fz (pose, updated every tick),
--           hold (reason the agent waits at a stop line), stopSince, committed (conn id),
--           passedGroup, passedAt, els, overtake, blockedSince, blockedBy, horn,
--           sent = { code, s, v, a, lat, next, t } (last state sent to the clients) }

Agents = {
    list = {},      -- [id] = agent
    byVeh = {},     -- [vehicle] = agent
    byPed = {},     -- [ped] = agent
    occ = {},       -- [segment code] = { [agent] = true }
    hash = {},      -- [cell] = { agent, ... } (rebuilt every tick)
    released = {},  -- [vehicle] = { ped, at, crashed }
    count = 0,
    HASH_CELL = 50,
}

local A = Agents
local floor, random = math.floor, math.random
local nextId = 1
local PLAN_AHEAD = 140

------------------------------------------------------------------------ occupancy

local function occAdd(code, ag)
    local o = A.occ[code]
    if not o then o = {}; A.occ[code] = o end
    o[ag] = true
end

local function occRemove(code, ag)
    local o = A.occ[code]
    if o then
        o[ag] = nil
        if next(o) == nil then A.occ[code] = nil end
    end
end

------------------------------------------------------------------------ route plan

local function connWeight(c)
    local to = Net.cto[c]
    local fl = Net.lflags[to] or 0
    local w = TRAFFIC.TURN_WEIGHT[Net.cturn[c]] or 1
    if bitAnd(fl, LF_PARKING) ~= 0 then w = w * TRAFFIC.WEIGHT_PARKING end
    if bitAnd(fl, LF_EMERGENCY) ~= 0 then w = w * TRAFFIC.WEIGHT_EMERGENCY end
    if bitAnd(fl, LF_UNPAVED) ~= 0 then w = w * TRAFFIC.WEIGHT_UNPAVED end
    if bitAnd(fl, LF_SINK) ~= 0 then w = w * TRAFFIC.WEIGHT_SINK end
    if bitAnd(fl, LF_TRAP) ~= 0 then w = w * TRAFFIC.WEIGHT_TRAP end
    if bitAnd(fl, LF_ROADBLOCK) ~= 0 then w = 0 end
    return w
end

-- pick the connection leaving a lane (nil at a dead end without u-turn)
function Agents.chooseExit(lane)
    local nexts = Net.lnext[lane]
    if not nexts then return nil end
    if #nexts == 1 then return nexts[1] end
    local total, ws = 0, {}
    for i, c in ipairs(nexts) do
        ws[i] = connWeight(c)
        total = total + ws[i]
    end
    if total <= 0 then return nexts[random(#nexts)] end
    local r = random() * total
    for i, c in ipairs(nexts) do
        r = r - ws[i]
        if r <= 0 then return c end
    end
    return nexts[#nexts]
end

-- keep at least PLAN_AHEAD metres of route in front of the agent
function Agents.extendPlan(ag)
    local plan = ag.plan
    local ahead = Geo.length(plan[1].code) - ag.s
    for i = 2, #plan do ahead = ahead + Geo.length(plan[i].code) end
    local guard = 0
    while ahead < PLAN_AHEAD and #plan < 16 and guard < 16 do
        guard = guard + 1
        local last = plan[#plan]
        local nextCode
        if last.code > 0 then
            if not last.conn then last.conn = Agents.chooseExit(last.code) end
            local c = last.conn
            if not c then break end
            if Geo.isCurve(c) then
                nextCode = -c
                plan[#plan + 1] = { code = nextCode, conn = c }
            else
                nextCode = Net.cto[c]
                plan[#plan + 1] = { code = nextCode }
            end
        else
            nextCode = Net.cto[last.conn]
            plan[#plan + 1] = { code = nextCode }
        end
        ahead = ahead + Geo.length(nextCode)
    end
end

-- move s forward over segment ends; returns false when the route ends (sink / dead end)
function Agents.advance(ag)
    local plan = ag.plan
    while true do
        local len = Geo.length(plan[1].code)
        if ag.s < len then return true end
        if not plan[2] then
            ag.s = len
            return false
        end
        ag.s = ag.s - len
        occRemove(plan[1].code, ag)
        table.remove(plan, 1)
        occAdd(plan[1].code, ag)
        ag.committed = nil
        local cur = plan[1]
        if cur.code < 0 then
            local g = Net.cgroup[cur.conn]
            if g and g > 0 then ag.passedGroup, ag.passedAt = g, getTickCount() end
        end
        Agents.extendPlan(ag)
    end
end

-- next segment code after the current one (for the clients' extrapolation)
function Agents.nextCode(ag)
    local n = ag.plan[2]
    return n and n.code or 0
end

function Agents.updatePose(ag)
    local x, y, z, fx, fy, fz = Geo.pose(ag.plan[1].code, ag.s, ag.lat)
    if x then
        ag.x, ag.y, ag.z, ag.fx, ag.fy, ag.fz = x, y, z, fx, fy, fz
        local h = math.sqrt(fx * fx + fy * fy)
        if h > 1e-6 then ag.hx, ag.hy = fx / h, fy / h else ag.hx, ag.hy = 0, 1 end
    end
end

------------------------------------------------------------------------ spatial hash

function Agents.rebuildHash()
    local hash, cell = {}, A.HASH_CELL
    for _, ag in pairs(A.list) do
        local key = floor(ag.x / cell) * 10000 + floor(ag.y / cell)
        local b = hash[key]
        if not b then b = {}; hash[key] = b end
        b[#b + 1] = ag
    end
    A.hash = hash
end

-- agents within r of a point (2D)
function Agents.near(x, y, r, out)
    out = out or {}
    local cell = A.HASH_CELL
    local r2 = r * r
    for cx = floor((x - r) / cell), floor((x + r) / cell) do
        for cy = floor((y - r) / cell), floor((y + r) / cell) do
            local b = A.hash[cx * 10000 + cy]
            if b then
                for i = 1, #b do
                    local ag = b[i]
                    local dx, dy = ag.x - x, ag.y - y
                    if dx * dx + dy * dy <= r2 then out[#out + 1] = ag end
                end
            end
        end
    end
    return out
end

------------------------------------------------------------------------ lifecycle

local modelTotal = 0
for _, m in ipairs(TRAFFIC_MODELS) do modelTotal = modelTotal + m[2] end

local function pickModel()
    local r = random() * modelTotal
    for _, m in ipairs(TRAFFIC_MODELS) do
        r = r - m[2]
        if r <= 0 then return m[1], m[3] end
    end
    local m = TRAFFIC_MODELS[1]
    return m[1], m[3]
end

function Agents.spawn(lane, s, v)
    local model, len = pickModel()
    local x, y, z, fx, fy, fz = Geo.pose(lane, s, 0)
    if not x then return nil end
    local rx, ry, rz = Geo.rotation(fx, fy, fz)
    local veh = createVehicle(model, x, y, z + 1.0, rx, ry, rz)
    if not veh then return nil end
    local ped = createPed(TRAFFIC_SKINS[random(#TRAFFIC_SKINS)], x, y, z + 2)
    if not ped then destroyElement(veh); return nil end
    setElementSyncer(veh, false)
    setElementSyncer(ped, false)
    warpPedIntoVehicle(ped, veh)
    setVehicleEngineState(veh, true)
    setElementData(veh, "ai_traffic", true)
    setElementData(ped, "ai_traffic", true)

    local id = nextId
    nextId = nextId + 1
    local ag = {
        id = id, veh = veh, ped = ped, model = model, len = len, half = len / 2,
        plan = { { code = lane } }, s = s, v = v or 0, a = 0,
        v0f = TRAFFIC.DRIVER_FACTOR[1] + random() * (TRAFFIC.DRIVER_FACTOR[2] - TRAFFIC.DRIVER_FACTOR[1]),
        lat = 0, latTarget = 0, latSlope = TRAFFIC.RETURN_SLOPE,
        x = x, y = y, z = z, fx = fx, fy = fy, fz = fz, hx = 0, hy = 1,
        born = getTickCount(), posRefresh = getTickCount() + random(TRAFFIC.SERVER_POS_REFRESH),
    }
    Agents.updatePose(ag)
    A.list[id], A.byVeh[veh], A.byPed[ped] = ag, ag, ag
    A.count = A.count + 1
    occAdd(lane, ag)
    Agents.extendPlan(ag)
    return ag
end

local function forget(ag)
    for _, p in ipairs(ag.plan) do occRemove(p.code, ag) end
    A.list[ag.id] = nil
    A.byVeh[ag.veh] = nil
    A.byPed[ag.ped] = nil
    A.count = A.count - 1
    Sync.forget(ag)
end

function Agents.destroy(ag)
    forget(ag)
    if isElement(ag.ped) then destroyElement(ag.ped) end
    if isElement(ag.veh) then destroyElement(ag.veh) end
end

-- the vehicle was destroyed by someone else
function Agents.vehicleDestroyed(ag)
    forget(ag)
    if isElement(ag.ped) then destroyElement(ag.ped) end
end

-- the vehicle leaves the simulation and becomes an ordinary physics vehicle
-- reason: "crash" | "damage" | "enter" | "export"
function Agents.release(ag, reason)
    if not A.list[ag.id] then return false end
    forget(ag)
    local veh, ped = ag.veh, ag.ped
    if not isElement(veh) then return false end
    local rx, ry, rz = Geo.rotation(ag.fx, ag.fy, ag.fz)
    setElementPosition(veh, ag.x, ag.y, ag.z + 0.6, false)
    setElementRotation(veh, rx, ry, rz)
    setElementSyncer(veh, true)
    if isElement(ped) then setElementSyncer(ped, true) end
    setElementData(veh, "ai_traffic", "released")
    local crashed = reason == "crash" or reason == "damage"
    A.released[veh] = { ped = ped, at = getTickCount(), crashed = crashed }
    Sync.release(ag, reason)
    if crashed then
        setVehicleEngineState(veh, false)
        -- the driver gets out after the crash (an empty vehicle syncs reliably)
        setTimer(function()
            if isElement(ped) and isElement(veh) and getPedOccupiedVehicle(ped) == veh then
                local x, y, z = getElementPosition(veh)
                local _, _, r = getElementRotation(veh)
                local a = math.rad(r)
                removePedFromVehicle(ped)
                setElementPosition(ped, x - math.cos(a) * 2.2, y - math.sin(a) * 2.2, z + 0.3)
                setElementRotation(ped, 0, 0, r + 90)
            end
        end, 2000, 1)
    end
    return true
end

function Agents.clear()
    for _, ag in pairs(A.list) do Agents.destroy(ag) end
end

function Agents.hasPlayerInside(veh)
    for _, occ in pairs(getVehicleOccupants(veh) or {}) do
        if isElement(occ) and getElementType(occ) == "player" then return true end
    end
    return false
end

-- released vehicles are removed once nobody is near and nobody sits in them
function Agents.cleanupReleased(players, now)
    for veh, r in pairs(A.released) do
        if not isElement(veh) then
            if isElement(r.ped) then destroyElement(r.ped) end
            A.released[veh] = nil
        elseif now - r.at > TRAFFIC.RELEASED_MIN_LIFE then
            if not Agents.hasPlayerInside(veh) then
                local x, y = getElementPosition(veh)
                local near = false
                for _, p in ipairs(players) do
                    if (p.x - x) ^ 2 + (p.y - y) ^ 2 < TRAFFIC.RELEASED_CLEANUP_DIST ^ 2 then near = true; break end
                end
                if not near then
                    if isElement(r.ped) and getElementType(r.ped) == "ped" then destroyElement(r.ped) end
                    destroyElement(veh)
                    A.released[veh] = nil
                end
            end
        end
    end
end
