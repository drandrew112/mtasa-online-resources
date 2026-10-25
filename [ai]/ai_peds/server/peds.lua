-- AI ped registry (server): lifecycle, syncer tracking, motor commands.
--
-- The server is the brain (behaviours, tasks, routes); the ped's syncer client is the motor: it walks the given
-- points, aims and fires with control states (client/motor.lua). MTA picks the syncer (nearest player within
-- ped_syncer_distance); without one the ped stands still on the server until a player comes near.
--
-- p = { el, id, kind ("traffic" | "driver" | "scripted"), behaviour, b (behaviour state), task, group, weapon,
--       combat = { aggro, leash, accuracy, retaliate, home }, role (navmesh route role), speed,
--       cmd (current motor command), syncer, mv / fighting / fight (syncer's move and fight state, DATA_MOVE / DATA_FIGHT), x, y, z, born, seenAt, dead, deadAt, grudges = { [el] = until } }
--
-- cmd = { m = mode ("idle" | "move" | "wait" | "combat" | "exit"), v = version, pts = { {x, y}, ... }, i = next point,
--         sp = "walk" | "run" | "sprint", t = target, r = attack range, me = melee, acc = accuracy,
--         keep = wanted distance to the target, fx / fy = point to face }

Peds = {
    list = {},      -- [ped element] = p
    count = 0,
    byKind = { traffic = 0, driver = 0, scripted = 0 },
    ready = {},     -- [player] = true: client scripts loaded
}

local P = Peds
local nextId = 1
local sqrt, random = math.sqrt, math.random

------------------------------------------------------------------------ lifecycle

local function register(el, kind, opts)
    opts = opts or {}
    local x, y, z = getElementPosition(el)
    local now = getTickCount()
    local p = {
        el = el, id = nextId, kind = kind, group = opts.group or (kind == "scripted" and "scripted" or "civilian"),
        weapon = 0, role = opts.role or "civilian", speed = opts.speed or "walk",
        combat = {
            aggro = opts.aggroRadius or AIPEDS.AGGRO_RADIUS, leash = opts.leash or AIPEDS.LEASH,
            accuracy = opts.accuracy or AIPEDS.ACCURACY, retaliate = opts.retaliate ~= false, home = opts.home,
        },
        x = x, y = y, z = z, born = now, seenAt = now, grudges = {},
        cmd = { m = "idle", v = 0 }, cmdVer = 0,
    }
    nextId = nextId + 1
    P.list[el] = p
    P.count = P.count + 1
    P.byKind[kind] = P.byKind[kind] + 1
    setElementData(el, "ai_peds", kind)
    p.syncer = getElementSyncer(el) or nil
    return p
end

-- new ped of this resource. opts: rot, dimension, interior, + register opts (group, role, speed, aggroRadius, leash,
-- accuracy, retaliate, home)
function Peds.create(skin, x, y, z, kind, opts)
    opts = opts or {}
    local el = createPed(skin, x, y, z, opts.rot or 0)
    if not el then return nil end
    if opts.dimension then setElementDimension(el, opts.dimension) end
    if opts.interior then setElementInterior(el, opts.interior) end
    local p = register(el, kind, opts)
    p.own = true
    return p
end

-- a ped of another resource (ai_land_traffic driver) taken over
function Peds.adopt(el, kind, opts)
    if P.list[el] then return P.list[el] end
    return register(el, kind, opts)
end

-- reason: "culled" | "destroyed" | "cleared" | "body" | "export" | ...
function Peds.remove(p, reason, keepElement)
    if not P.list[p.el] then return end
    if p.behaviour and Behaviours[p.behaviour] and Behaviours[p.behaviour].leave then
        Behaviours[p.behaviour].leave(p)
    end
    P.list[p.el] = nil
    P.count = P.count - 1
    P.byKind[p.kind] = P.byKind[p.kind] - 1
    p.removed = true
    if isElement(p.el) then
        triggerEvent("onAIPedRemoved", p.el, reason or "removed")
        if p.syncer and isElement(p.syncer) and P.ready[p.syncer] then triggerClientEvent(p.syncer, EV_DROP, resourceRoot, p.el) end
        if keepElement then
            removeElementData(p.el, "ai_peds")
            removeElementData(p.el, DATA_MOVE)
            removeElementData(p.el, DATA_FIGHT)
        else
            destroyElement(p.el)
        end
    end
end

function Peds.get(el) return P.list[el] end

------------------------------------------------------------------------ behaviours

-- switch the behaviour ("civilian" | "scared" | "enemy" | "exiting" | "dead"); args go to its enter()
function Peds.setBehaviour(p, name, args)
    local nb = Behaviours[name]
    if not nb or p.removed then return false end
    local old = p.behaviour
    if old and Behaviours[old].leave then Behaviours[old].leave(p) end
    p.behaviour = name
    p.b = {}
    p.taskActive = false   -- Tasks.run turns it on (late route answers of an old task are ignored)
    nb.enter(p, args or {})
    if old ~= name and isElement(p.el) then triggerEvent("onAIPedBehaviourChanged", p.el, name, old or false) end
    return true
end

------------------------------------------------------------------------ the other clients (DATA_MOVE, DATA_FIGHT)

-- the syncer's move state
local MOVES = { walk = true, run = true, sprint = true }

local function setMove(p, mv)
    mv = MOVES[mv] and mv or false
    if p.mv == mv then return end
    p.mv = mv
    if isElement(p.el) then setElementData(p.el, DATA_MOVE, mv) end
end

-- while the syncer fights (aims + fires / hits in melee range): the combat command's target and firing pattern
local function refreshFight(p)
    local c = p.cmd
    local d = false
    if p.fighting and c.m == "combat" and isElement(c.t) then
        d = { t = c.t, me = c.me, r = c.r, acc = c.acc, burst = c.burst, pause = c.pause }
    end
    local o = p.fight
    if not d and not o then return end
    if d and o and d.t == o.t and d.me == o.me and d.r == o.r and d.acc == o.acc then return end
    p.fight = d
    if isElement(p.el) then setElementData(p.el, DATA_FIGHT, d) end
end

local function setFighting(p, on)
    p.fighting = on and true or false
    refreshFight(p)
end

------------------------------------------------------------------------ commands

local function send(p)
    local s = p.syncer
    if s and isElement(s) and P.ready[s] then
        triggerClientEvent(s, EV_CMD, resourceRoot, p.el, p.cmd)
    end
end

-- new motor command (replaces the old one; the syncer gets it now, a new syncer on takeover)
function Peds.setCmd(p, cmd)
    p.cmdVer = p.cmdVer + 1
    cmd.v = p.cmdVer
    cmd.i = cmd.i or 1
    p.cmd = cmd
    refreshFight(p)
    send(p)
end

-- small change of the running command (e.g. resume after a wait): same table, new version
function Peds.updateCmd(p)
    p.cmdVer = p.cmdVer + 1
    p.cmd.v = p.cmdVer
    refreshFight(p)
    send(p)
end

function Peds.idle(p, fx, fy)
    if p.cmd.m == "idle" and not fx then return end
    Peds.setCmd(p, { m = "idle", fx = fx, fy = fy })
end

-- points { {x, y, z}, ... } -> compact 2D list for the client
function Peds.pts2D(points)
    local out = {}
    for i, pt in ipairs(points) do out[i] = { pt[1], pt[2] } end
    return out
end

-- server side progress along the command points (the client reports too)
function Peds.track(p)
    local c = p.cmd
    local pts = c.pts
    if not pts or (c.m ~= "move" and c.m ~= "combat") then return end
    local r = c.sp == "walk" and 1.4 or 2.0
    while c.i <= #pts do
        local pt = pts[c.i]
        local dx, dy = pt[1] - p.x, pt[2] - p.y
        if dx * dx + dy * dy > r * r then break end
        c.i = c.i + 1
    end
end

-- command points done?
function Peds.atEnd(p)
    local c = p.cmd
    return not c.pts or c.i > #c.pts
end

------------------------------------------------------------------------ syncers

local function setSyncer(p, s)
    s = s or nil
    if p.syncer == s then return end
    local old = p.syncer
    p.syncer = s
    setMove(p, false)   -- the new syncer reports its own
    setFighting(p, false)
    -- only clients whose scripts are loaded (EV_READY): a joining player has no handler yet
    if old and isElement(old) and P.ready[old] then triggerClientEvent(old, EV_DROP, resourceRoot, p.el) end
    send(p)
end

addEventHandler("onElementStartSync", root, function(newSyncer)
    local p = P.list[source]
    if p then setSyncer(p, newSyncer) end
end)

addEventHandler("onElementStopSync", root, function(oldSyncer)
    local p = P.list[source]
    if p and p.syncer == oldSyncer then setSyncer(p, nil) end
end)

-- catches missed sync events
function Peds.checkSyncers()
    for el, p in pairs(P.list) do
        if isElement(el) then setSyncer(p, getElementSyncer(el) or nil) end
    end
end

addEvent(EV_READY, true)
addEventHandler(EV_READY, resourceRoot, function()
    P.ready[client] = true
    for el, p in pairs(P.list) do
        if p.syncer == client then send(p) end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    P.ready[source] = nil
    for _, p in pairs(P.list) do
        if p.syncer == source then p.syncer = nil; setMove(p, false); setFighting(p, false) end
        p.grudges[source] = nil
    end
end)

------------------------------------------------------------------------ syncer reports

addEvent(EV_REPORT, true)
addEventHandler(EV_REPORT, resourceRoot, function(el, kind, data)
    local p = P.list[el]
    if not p or p.syncer ~= client then return end
    if kind == "wp" then
        local i = tonumber(data)
        if i and p.cmd.pts and data and i > p.cmd.i and i <= #p.cmd.pts + 1 then p.cmd.i = i end
        return
    elseif kind == "mv" then
        setMove(p, data)
        return
    elseif kind == "fight" then
        setFighting(p, data == true)
        return
    end
    local b = Behaviours[p.behaviour]
    if b and b.report then b.report(p, kind, data) end
end)

------------------------------------------------------------------------ helpers

function Peds.dist2D(p, x, y)
    return sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
end

function Peds.alive(el)
    return isElement(el) and not isPedDead(el) and (getElementType(el) == "ped" or getElementType(el) == "player")
end

-- weapon given by the server (GTA weapons on peds; players use wp_manager)
function Peds.giveWeapon(p, weapon, ammo)
    weapon = tonumber(weapon) or 0
    takeAllWeapons(p.el)
    p.weapon = weapon
    if weapon > 0 then
        giveWeapon(p.el, weapon, ammo or 9999, true)
        setPedWeaponSlot(p.el, getSlotFromWeapon(weapon))
    end
    return true
end

function Peds.randomSkin()
    local list = AIPEDS.WALK_SKINS or AIPEDS_SKINS
    return list[random(#list)]
end

-- peds (of this resource) within r of a point
function Peds.near(x, y, r, filter)
    local out, r2 = {}, r * r
    for _, p in pairs(P.list) do
        if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= r2 and (not filter or filter(p)) then out[#out + 1] = p end
    end
    return out
end
