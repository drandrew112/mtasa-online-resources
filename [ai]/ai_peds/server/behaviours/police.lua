-- Behaviours for police work (police_system): "police", "detained", "cuffed", "patient".
--
-- police   args: target, armed (shoots with its weapon at the combat accuracy), accuracy, arrestDist (2),
--                arrestTime (3000 ms). Unarmed it walks / runs to the target and stands next to it; after arrestTime
--                there it fires onAIPedArrestTarget(target) once (the owner arrests). Armed it fights like an enemy
--                but only this target. Shots / attacks do not scare it. Target dead / gone: onAIPedTargetLost, idle.
-- detained args: officer. Stands, faces the officer (a stopped pedestrian).
-- cuffed   args: leader (optional). Hands cuffed: stands, or walks after the leader (escort, stays ~1 m behind).
-- patient  lies on the ground (injured, waits for the ambulance).

Behaviours = Behaviours or {}

local T = AIPEDS

local function sameSpace(p, el)
    return getElementDimension(el) == getElementDimension(p.el) and getElementInterior(el) == getElementInterior(p.el)
end

local function targetPos(t)
    local veh = (getElementType(t) == "player" or getElementType(t) == "ped") and getPedOccupiedVehicle(t)
    return getElementPosition(veh or t)
end

-- moves towards (tx, ty, tz): straight when close, else a navmesh "free" route (asked at most every REPATH_MIN)
local function approach(p, b, now, tx, ty, tz, d, speed)
    local c = p.cmd
    if d <= T.DIRECT_DIST then
        if c.m ~= "move" or not c.pts or #c.pts ~= 1 or (c.pts[1][1] - tx) ^ 2 + (c.pts[1][2] - ty) ^ 2 > 1 or c.sp ~= speed then
            Peds.setCmd(p, { m = "move", pts = { { tx, ty } }, sp = speed })
        end
        return
    end
    if now - (b.pathAt or 0) < T.REPATH_MIN then return end
    if b.ptx and (b.ptx - tx) ^ 2 + (b.pty - ty) ^ 2 < T.REPATH_MOVE ^ 2 and c.m == "move" then return end
    b.pathAt, b.ptx, b.pty = now, tx, ty
    local token = {}
    b.token = token
    local ok = Nav.requestPedRoute(p.x, p.y, p.z, tx, ty, tz, "free", function(res)
        if p.removed or p.b ~= b or b.token ~= token then return end
        local pts = res and res.points
        if not pts or #pts < 2 then pts = { { tx, ty, tz } } else pts[#pts + 1] = { tx, ty, tz } end
        Peds.setCmd(p, { m = "move", pts = Peds.pts2D(pts), sp = speed, i = math.min(2, #pts) })
    end)
    if not ok then Peds.setCmd(p, { m = "move", pts = { { tx, ty } }, sp = speed }) end
end

Behaviours.police = {
    enter = function(p, args)
        local b = p.b
        b.target = args.target
        b.armed = args.armed and true or false
        b.arrestDist = tonumber(args.arrestDist) or 2
        b.arrestTime = tonumber(args.arrestTime) or 3000
        if args.accuracy then p.combat.accuracy = math.max(0, math.min(1, tonumber(args.accuracy) or p.combat.accuracy)) end
        b.pathAt = 0
        Peds.idle(p)
    end,

    update = function(p, now)
        local b = p.b
        local t = b.target
        if not Peds.alive(t) or not sameSpace(p, t) then
            if t and not b.lost then
                b.lost = true
                triggerEvent("onAIPedTargetLost", p.el, t or false, Peds.alive(t) and "gone" or "dead")
            end
            if p.cmd.m ~= "idle" then Peds.idle(p) end
            return
        end
        local tx, ty, tz = targetPos(t)
        local d = Peds.dist2D(p, tx, ty)
        Peds.track(p)
        if b.armed and (p.weapon or 0) > 0 then
            local w = T.WEAPONS[p.weapon]
            local range = w and w.range or 30
            if p.cmd.m ~= "combat" or p.cmd.t ~= t then
                Peds.setCmd(p, { m = "combat", t = t, r = range, me = false, keep = range * 0.6,
                    acc = p.combat.accuracy, sp = "run", burst = w and w.burst, pause = w and w.pause })
                b.pathAt = 0
            end
            if d > T.DIRECT_DIST and now - (b.pathAt or 0) > T.REPATH_MIN then
                b.pathAt = now
                local token = {}
                b.token = token
                Nav.requestPedRoute(p.x, p.y, p.z, tx, ty, tz, "free", function(res)
                    if p.removed or p.b ~= b or b.token ~= token or p.cmd.m ~= "combat" then return end
                    local pts = res and res.points
                    if pts and #pts >= 2 then
                        pts[#pts + 1] = { tx, ty, tz }
                        p.cmd.pts, p.cmd.i = Peds.pts2D(pts), 2
                        Peds.updateCmd(p)
                    end
                end)
            end
            return
        end
        -- unarmed: to the target, then stand next to it
        if d <= b.arrestDist then
            if p.cmd.m ~= "idle" then Peds.idle(p, tx, ty) end
            b.nearSince = b.nearSince or now
            if not b.fired and now - b.nearSince >= b.arrestTime then
                b.fired = true
                triggerEvent("onAIPedArrestTarget", p.el, t)
            end
            return
        end
        b.nearSince = nil
        b.fired = false
        approach(p, b, now, tx, ty, tz, d, d > 6 and "sprint" or "run")
    end,

    report = function(p, kind)
        if kind == "stuck" then p.b.pathAt, p.b.ptx = 0, nil end
    end,
}

Behaviours.detained = {
    enter = function(p, args)
        p.b.officer = args.officer
        Peds.idle(p)
    end,
    update = function(p, now)
        local o = p.b.officer
        if not isElement(o) or now < (p.b.next or 0) then return end
        p.b.next = now + 1000
        local ox, oy = getElementPosition(o)
        local c = p.cmd
        if c.m ~= "idle" or not c.fx or (c.fx - ox) ^ 2 + (c.fy - oy) ^ 2 > 1 then Peds.idle(p, ox, oy) end
    end,
}

Behaviours.cuffed = {
    enter = function(p, args)
        p.b.leader = args.leader
        Peds.idle(p)
    end,
    update = function(p, now)
        local l = p.b.leader
        if not isElement(l) or getPedOccupiedVehicle(p.el) then
            if p.cmd.m ~= "idle" then Peds.idle(p) end
            return
        end
        if now < (p.b.next or 0) then return end
        p.b.next = now + 250
        local lx, ly = getElementPosition(l)
        local d = Peds.dist2D(p, lx, ly)
        if d <= 1.1 then
            if p.cmd.m ~= "idle" then Peds.idle(p, lx, ly) end
        else
            Peds.setCmd(p, { m = "move", pts = { { lx, ly } }, sp = d > 3.5 and "run" or "walk" })
        end
    end,
}

Behaviours.patient = {
    enter = function(p)
        Peds.idle(p)
        setPedAnimation(p.el, "crack", "crckidle2", -1, true, false, false, true)
        p.b.anim = true
    end,
    update = function() end,
    leave = function(p)
        if isElement(p.el) and p.b.anim then setPedAnimation(p.el) end
    end,
}
