-- Behaviour "scared": sprints away from the threat, anywhere (not bound to sidewalks). Calms down once the threat is
-- FLEE_SAFE away and nothing scared it for FLEE_CALM, then goes back to `calmTo` (default civilian: its task again).
-- Cornered (no flee point) with the threat close: cowers.
--
-- args: threat (element), x, y, z (threat position without an element), calmTo

Behaviours = Behaviours or {}

local T = AIPEDS
local random, sqrt, cos, sin, atan2, pi = math.random, math.sqrt, math.cos, math.sin, math.atan2, math.pi
local ANGLES = { 0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5 }

local function threatPos(b)
    if b.threat and isElement(b.threat) then
        b.tx, b.ty, b.tz = getElementPosition(b.threat)
    end
    return b.tx, b.ty, b.tz
end

local function cower(p, b, on)
    if b.cowering == on then return end
    b.cowering = on
    if on then
        Peds.idle(p)
        setPedAnimation(p.el, "ped", "cower", -1, true, false, false, false)
    else
        setPedAnimation(p.el)
    end
end

-- a walkable point FLEE_DIST away from the threat (or nil)
local function fleePoint(p, b)
    local tx, ty = threatPos(b)
    local base
    if tx and (tx - p.x) ^ 2 + (ty - p.y) ^ 2 > 0.25 then
        base = atan2(p.y - ty, p.x - tx)
    else
        base = random() * 2 * pi
    end
    for _, da in ipairs(ANGLES) do
        for _, f in ipairs({ 1, 0.5 }) do
            local a = base + da + (random() - 0.5) * 0.3
            local x, y = p.x + cos(a) * T.FLEE_DIST * f, p.y + sin(a) * T.FLEE_DIST * f
            if not Nav.available() then return x, y, p.z end
            local z = Nav.ground(x, y, p.z, 8)
            if z then return x, y, z end
        end
    end
    return nil
end

local function flee(p, b)
    b.lastFlee = getTickCount()
    local x, y, z = fleePoint(p, b)
    if not x then
        local tx, ty = threatPos(b)
        if tx and Peds.dist2D(p, tx, ty) < T.COWER_DIST then cower(p, b, true) else Peds.idle(p) end
        b.retryAt = getTickCount() + 2000
        return
    end
    cower(p, b, false)
    b.fx, b.fy, b.fz = x, y, z
    b.fleeing = true
    p.route = nil
    Peds.setCmd(p, { m = "move", pts = { { x, y } }, sp = "sprint" })
    if T.FLEE_ROUTE then
        local token = {}
        b.token = token
        Nav.requestPedRoute(p.x, p.y, p.z, x, y, z, "free", function(res)
            if p.removed or p.b ~= b or b.token ~= token or not res or not res.points or #res.points < 2 then return end
            local pts = res.points
            pts[#pts + 1] = { x, y, z }
            Peds.setCmd(p, { m = "move", pts = Peds.pts2D(pts), i = 2, sp = "sprint" })
        end)
    end
end

Behaviours.scared = {
    enter = function(p, args)
        local b = p.b
        b.threat = isElement(args.threat) and args.threat or nil
        b.tx, b.ty, b.tz = args.x, args.y, args.z
        if not b.tx and b.threat then threatPos(b) end
        b.calmTo = args.calmTo or "civilian"
        b.lastScare = getTickCount()
        flee(p, b)
    end,

    update = function(p, now)
        local b = p.b
        local tx, ty = threatPos(b)
        local d = tx and Peds.dist2D(p, tx, ty) or math.huge
        if b.retryAt then
            if now < b.retryAt then return end
            b.retryAt = nil
            flee(p, b)
            return
        end
        Peds.track(p)
        if d > T.FLEE_SAFE and now - b.lastScare > T.FLEE_CALM then
            Peds.setBehaviour(p, b.calmTo, {})
            return
        end
        if b.fleeing and Peds.atEnd(p) then
            b.fleeing = false
            if d < T.FLEE_SAFE then flee(p, b) else Peds.idle(p) end
        end
    end,

    leave = function(p)
        if p.b.cowering then setPedAnimation(p.el) end
    end,

    report = function(p, kind)
        if kind == "stuck" then flee(p, p.b) end
    end,

    threat = function(p, kind, src, x, y, z)
        local b = p.b
        b.lastScare = getTickCount()
        local changed = src and src ~= b.threat
        if src and isElement(src) then b.threat = src end
        if x and not src then b.tx, b.ty, b.tz = x, y, z end
        local tx, ty = threatPos(b)
        -- a new threat, or the old one came close: run again (away from it), at most every 1.5 s
        if b.lastFlee and getTickCount() - b.lastFlee < 1500 then return end
        if changed or (tx and Peds.dist2D(p, tx, ty) < 15) or not b.fleeing then flee(p, b) end
    end,
}
