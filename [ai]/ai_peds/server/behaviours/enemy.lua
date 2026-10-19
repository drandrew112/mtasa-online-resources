-- Behaviour "enemy": attacks its target with its weapon (fists / melee weapon when it has no gun). Not bound to
-- sidewalks: routes to the target are navmesh "free" ped routes (open terrain), close up it goes straight at it.
-- Without a target it does its task (patrol, guard, idle...) and scans for hostiles (server/groups.lua) within its
-- aggro radius. A ped with a home (scripted guards) does not chase farther than its leash from it.
--
-- args: target (element), calmTo (behaviour once no target is left and it has no task of its own; drivers: "civilian")
--
-- Cover (later): set Behaviours.enemy.positionProvider = function(p, target, tx, ty, tz) -> x, y, z | nil. When it
-- returns a point the ped goes there and fights from it (cmd.hold: it does not walk on towards the target).

Behaviours = Behaviours or {}

local T = AIPEDS
local Enemy

local function weaponInfo(p)
    local w = p.weapon or 0
    if T.MELEE_WEAPONS[w] or not T.WEAPONS[w] then return T.MELEE_RANGE, true end
    return T.WEAPONS[w].range, false
end

local function sameSpace(p, el)
    return getElementDimension(el) == getElementDimension(p.el) and getElementInterior(el) == getElementInterior(p.el)
end

local function combatCmd(p, b)
    local range, melee = weaponInfo(p)
    local w = T.WEAPONS[p.weapon or 0]
    Peds.setCmd(p, {
        m = "combat", t = b.target, r = range, me = melee, keep = melee and 1.0 or range * 0.6,
        acc = p.combat.accuracy, sp = "run", burst = w and w.burst, pause = w and w.pause,
    })
    b.pathAt, b.ptx, b.pty = 0, nil, nil
end

local function engage(p, b, target)
    local old = b.target
    b.target = target
    b.mode = "engage"
    p.route = nil
    p.taskActive = false
    combatCmd(p, b)
    if old ~= target then triggerEvent("onAIPedTargetAcquired", p.el, target) end
end

local function calm(p, b)
    b.mode = "calm"
    b.target = nil
    b.nextScan = 0
    -- a civilian / driver that fought: back to its old behaviour; a born enemy (scripted) back to its task
    if b.calmTo then
        Peds.setBehaviour(p, b.calmTo, {})
        return
    end
    Tasks.run(p)
end

local function lose(p, b, reason)
    local target = b.target
    b.target = nil
    if target and (reason == "dead" or reason == "export") then p.grudges[target] = nil end
    triggerEvent("onAIPedTargetLost", p.el, target or false, reason)
    local nxt = Groups.findHostile(p, p.combat.aggro)
    if nxt then engage(p, b, nxt) else calm(p, b) end
end

-- route / straight line towards the target (or to the cover point)
local function repath(p, b, now, tx, ty, tz, d)
    local c = p.cmd
    local px, py, pz, hold = tx, ty, tz, false
    if Enemy.positionProvider then
        local cx, cy, cz = Enemy.positionProvider(p, b.target, tx, ty, tz)
        if cx then px, py, pz, hold = cx, cy, cz, true end
    end
    if c.hold ~= hold then c.hold = hold; Peds.updateCmd(p) end
    local dd = Peds.dist2D(p, px, py)
    if dd <= T.DIRECT_DIST and not hold then
        if c.pts then c.pts = nil; Peds.updateCmd(p) end
        return
    end
    if now - b.pathAt < T.REPATH_MIN then return end
    if b.ptx and (b.ptx - px) ^ 2 + (b.pty - py) ^ 2 < T.REPATH_MOVE ^ 2 and c.pts then return end
    b.pathAt, b.ptx, b.pty = now, px, py
    if dd <= T.DIRECT_DIST then
        c.pts, c.i = { { px, py } }, 1
        Peds.updateCmd(p)
        return
    end
    local token = {}
    b.token = token
    local ok = Nav.requestPedRoute(p.x, p.y, p.z, px, py, pz, "free", function(res)
        if p.removed or p.b ~= b or b.token ~= token or b.mode ~= "engage" then return end
        local pts = res and res.points
        if not pts or #pts < 2 then
            pts = { { px, py, pz } }
        else
            pts[#pts + 1] = { px, py, pz }
        end
        p.cmd.pts, p.cmd.i = Peds.pts2D(pts), math.min(2, #pts)
        Peds.updateCmd(p)
    end)
    if not ok then
        c.pts, c.i = { { px, py } }, 1
        Peds.updateCmd(p)
    end
end

Enemy = {
    positionProvider = nil,

    enter = function(p, args)
        local b = p.b
        b.calmTo = args.calmTo
        b.nextScan = 0
        if args.target and Peds.alive(args.target) then
            engage(p, b, args.target)
        else
            b.mode = "calm"
            Tasks.run(p)
        end
    end,

    update = function(p, now)
        local b = p.b
        if b.mode == "engage" then
            local t = b.target
            if not Peds.alive(t) then return lose(p, b, "dead") end
            if not sameSpace(p, t) then return lose(p, b, "gone") end
            local tx, ty, tz = getElementPosition(t)
            local d = Peds.dist2D(p, tx, ty)
            if d > T.LOSE_DIST then return lose(p, b, "far") end
            local home = p.combat.home
            if home and (tx - home[1]) ^ 2 + (ty - home[2]) ^ 2 > p.combat.leash ^ 2 then return lose(p, b, "leash") end
            if not Groups.isHostile(p, t) then return lose(p, b, "peace") end
            -- a hostile much closer than the target takes over
            if now >= b.nextScan then
                b.nextScan = now + T.SCAN_INTERVAL * 2
                if d > 15 then
                    local n = Groups.findHostile(p, math.min(8, p.combat.aggro))
                    if n and n ~= t then engage(p, b, n); return end
                end
            end
            Peds.track(p)
            repath(p, b, now, tx, ty, tz, d)
            return
        end
        Tasks.update(p, now)
        if now >= b.nextScan then
            b.nextScan = now + T.SCAN_INTERVAL
            local h = Groups.findHostile(p, p.combat.aggro)
            if h then engage(p, b, h) end
        end
    end,

    report = function(p, kind)
        local b = p.b
        if kind ~= "stuck" then return end
        if b.mode == "engage" then b.pathAt, b.ptx = 0, nil else Tasks.stuck(p) end
    end,

    threat = function(p, kind, src, x, y, z)
        local b = p.b
        if not src or not Peds.alive(src) then return end
        if kind == "attacked" then
            if not p.combat.retaliate then return end
            Groups.grudge(p, src)
            if b.mode ~= "engage" then engage(p, b, src); return end
            -- switch to the attacker when it is closer than the current target
            local tx, ty = getElementPosition(b.target)
            local sx, sy = getElementPosition(src)
            if (sx - p.x) ^ 2 + (sy - p.y) ^ 2 < (tx - p.x) ^ 2 + (ty - p.y) ^ 2 then engage(p, b, src) end
        elseif kind == "shot" and b.mode ~= "engage" and Groups.isHostile(p, src) then
            engage(p, b, src)
        end
    end,

    -- current target or nil
    target = function(p) return p.behaviour == "enemy" and p.b.target or nil end,
    engage = function(p, target) if p.behaviour == "enemy" then engage(p, p.b, target) end end,
    disengage = function(p) if p.behaviour == "enemy" and p.b.target then lose(p, p.b, "export") end end,
}

Behaviours.enemy = Enemy
