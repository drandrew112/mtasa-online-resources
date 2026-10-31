-- Perception (server): what the peds notice. Clients report gunshots (their own, and of the AI peds they sync) and
-- damage they caused (client/reports.lua); deaths and explosions come from server events. Each ped in range gets
-- Behaviours[behaviour].threat(p, kind, source, x, y, z) with kind "shot" | "attacked" | "death" | "explosion".

Perception = {}

local T = AIPEDS
local lastShot = {}   -- [shooter] = tick

local function threat(p, kind, src, x, y, z)
    if p.dead or p.removed then return end
    local b = Behaviours[p.behaviour]
    if b and b.threat then b.threat(p, kind, src, x, y, z) end
end

-- every ped within r of (x, y) in the given dimension
local function around(x, y, r, dim, fn, except)
    for _, p in pairs(Peds.list) do
        if p ~= except and not p.dead and (p.x - x) ^ 2 + (p.y - y) ^ 2 <= r * r
            and (not dim or getElementDimension(p.el) == dim) then
            fn(p)
        end
    end
end

-- the element behind an attack: a vehicle counts as its driver
local function culprit(el)
    if not isElement(el) then return nil end
    if getElementType(el) == "vehicle" then
        local d = getVehicleOccupant(el, 0)
        return d or nil
    end
    return el
end

-- a hostile act against p by src: p reacts, civilians around panic, enemies of its group are called in
function Perception.attacked(p, src)
    src = culprit(src)
    if not src or src == p.el then return end
    local dim = getElementDimension(p.el)
    threat(p, "attacked", src, getElementPosition(src))
    around(p.x, p.y, T.ATTACK_SCARE_RADIUS, dim, function(o)
        if o.behaviour == "civilian" or o.behaviour == "scared" then threat(o, "shot", src, getElementPosition(src)) end
    end, p)
    if p.group ~= "civilian" then
        around(p.x, p.y, T.GROUP_ALERT_RADIUS, dim, function(o)
            if o.group == p.group and o.behaviour == "enemy" and o.combat.retaliate then
                Groups.grudge(o, src)
                threat(o, "attacked", src, getElementPosition(src))
            end
        end, p)
    end
end

-- a gunshot: civilians near the shooter or the impact are scared, hostile enemies near it engage
function Perception.shot(shooter, hx, hy, hz)
    local sx, sy, sz = getElementPosition(shooter)
    local dim = getElementDimension(shooter)
    local r = math.max(T.SHOT_SCARE_RADIUS, T.SHOT_ALERT_RADIUS)
    local seen = {}
    local function react(p)
        if seen[p] or p.el == shooter then return end
        seen[p] = true
        local d2 = math.min((p.x - sx) ^ 2 + (p.y - sy) ^ 2, hx and (p.x - hx) ^ 2 + (p.y - hy) ^ 2 or math.huge)
        if p.behaviour == "enemy" then
            if d2 <= T.SHOT_ALERT_RADIUS ^ 2 then threat(p, "shot", shooter, sx, sy, sz) end
        elseif d2 <= T.SHOT_SCARE_RADIUS ^ 2 then
            -- friendly fire of an AI ped on its own side does not scare its group mates
            local sp = Peds.list[shooter]
            if not (sp and sp.group == p.group and p.group ~= "civilian") then threat(p, "shot", shooter, sx, sy, sz) end
        end
    end
    around(sx, sy, r, dim, react)
    if hx then around(hx, hy, T.SHOT_SCARE_RADIUS, dim, react) end
end

------------------------------------------------------------------------ client reports

addEvent(EV_THREAT, true)
addEventHandler(EV_THREAT, resourceRoot, function(kind, a, b, c, d)
    if kind == "shot" then
        -- a = shooter (the client's player, or an AI ped it syncs), b, c, d = impact point
        local shooter = a
        if shooter ~= client then
            local sp = isElement(shooter) and Peds.list[shooter]
            if not sp or sp.syncer ~= client then return end
        end
        local now = getTickCount()
        if lastShot[shooter] and now - lastShot[shooter] < T.SHOT_REPORT_GAP * 0.8 then return end
        lastShot[shooter] = now
        local hx, hy, hz = tonumber(b), tonumber(c), tonumber(d)
        Perception.shot(shooter, hx, hy, hz)
    elseif kind == "damage" then
        -- a = victim (AI ped), b = attacker (the client's player, its vehicle, or an AI ped it syncs)
        local p = isElement(a) and Peds.list[a]
        if not p or p.dead then return end
        local att = culprit(b)
        if not att then return end
        if att ~= client then
            local ap = Peds.list[att]
            if not ap or ap.syncer ~= client then return end
        end
        local x, y = getElementPosition(att)
        if (x - p.x) ^ 2 + (y - p.y) ^ 2 > 150 * 150 then return end
        -- c = weapon, d = health loss (reported by the attacker's client)
        triggerEvent("onAIPedDamaged", p.el, att, tonumber(c) or 0, tonumber(d) or 0)
        Perception.attacked(p, att)
    end
end)

addEventHandler("onPlayerQuit", root, function() lastShot[source] = nil end)

------------------------------------------------------------------------ server events

addEventHandler("onPedWasted", root, function(_, killer, weapon)
    local p = Peds.list[source]
    if not p then return end
    killer = culprit(killer)
    triggerEvent("onAIPedWasted", source, killer or false, weapon or 0)
    Peds.setBehaviour(p, "dead", {})
    local dim = getElementDimension(source)
    around(p.x, p.y, T.ATTACK_SCARE_RADIUS, dim, function(o)
        if o.behaviour == "enemy" then
            if killer and o.group == p.group and p.group ~= "civilian" and o.combat.retaliate then
                Groups.grudge(o, killer)
                threat(o, "attacked", killer, getElementPosition(killer))
            end
        else
            threat(o, "death", killer, p.x, p.y, p.z)
        end
    end, p)
end)

addEventHandler("onVehicleExplode", root, function()
    local x, y, z = getElementPosition(source)
    local dim = getElementDimension(source)
    around(x, y, 30, dim, function(o)
        if o.behaviour ~= "enemy" then threat(o, "explosion", nil, x, y, z) end
    end)
end)
