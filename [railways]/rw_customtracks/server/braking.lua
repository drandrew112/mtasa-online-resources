-- Braking (server): the gradient profile of the way ahead, for the ATP braking curve and the
-- router's horizon. The ATP used to take the gradient under the train only: on a long downhill
-- run it braked far too early (approach to Market), and where the gradient eased off near the
-- stop it ran past the end of the authority (Market -> Unity, ~14 km/h).
--
-- A profile is the cumulative "effective rise" (the gradient the physics feels: GRADE_FACTOR,
-- capped at GRADE_CAP) at every PROFILE_STEP metres from the rear of the train along its route.
-- With it the ATP plans a constant brake by energy: v^2 / 2 = (brake + R0) * d + g * rise(d),
-- so it stops at the end whatever the gradient between does.

Braking = {}

local STEP = 10
local G = 9.81

local function effRise(dz, dx)
    local SIM = NET.SIM
    local gr = dz / dx * SIM.GRADE_FACTOR
    if gr > SIM.GRADE_CAP then gr = SIM.GRADE_CAP elseif gr < -SIM.GRADE_CAP then gr = -SIM.GRADE_CAP end
    return gr * dx
end

-- t = network train, steps = route steps from the leading end (seg, s), sgn = leading end sign
-- (+1 head, -1 rear), uLead = u of the leading end. Covers the train itself (from its far end)
-- and maxLen metres of the route ahead.
-- -> { u0 = u of the train's far end, sign = sgn, back = distance from it to the leading end, rise = { ... } }
function Braking.profile(t, steps, s, uLead, sgn, maxLen)
    local zs = {}
    -- behind the leading end: the train's own path
    local back = t.length
    local n = math.floor(back / STEP)
    for k = n, 1, -1 do
        local _, _, z = t.path:point(uLead - sgn * k * STEP)
        zs[#zs + 1] = z
    end
    local backLen = n * STEP
    -- ahead: the route
    local seg, pos, dir = steps[1][1], s, steps[1][2]
    local i, d = 1, 0
    while true do
        local _, _, z = Net.pointAt(seg, pos)
        zs[#zs + 1] = z
        if d >= maxLen then break end
        local g = Net.segment(seg)
        local left = dir > 0 and g.len - pos or pos
        local adv = STEP
        while adv > left do
            adv = adv - left
            i = i + 1
            if not steps[i] then adv = nil break end
            seg, dir = steps[i][1], steps[i][2]
            g = Net.segment(seg)
            pos = dir > 0 and 0 or g.len
            left = g.len
        end
        if not adv then break end
        pos = pos + dir * adv
        d = d + STEP
    end
    local rise = { 0 }
    for k = 2, #zs do rise[k] = rise[k - 1] + effRise(zs[k] - zs[k - 1], STEP) end
    return { u0 = uLead - sgn * backLen, sign = sgn, back = backLen, rise = rise }
end

-- effective rise at x metres from the profile start (past its end: level)
local function riseAt(p, x)
    local r = p.rise
    local f = x / STEP + 1
    if f <= 1 then return 0 end
    if f >= #r then return r[#r] end
    local i = math.floor(f)
    return r[i] + (r[i + 1] - r[i]) * (f - i)
end

-- effective rise the train's centre goes through while its leading end (now at uLead) runs d metres
function Braking.rise(p, t, uLead, d)
    local x = (uLead - p.u0) * p.sign - t.length / 2
    return riseAt(p, x + d) - riseAt(p, x)
end

-- stopping distance from v (m/s) braking at `decel` (brake + running resistance), with the
-- gradient of the profile (no profile: level)
function Braking.distance(p, t, uLead, v, decel, maxD)
    local e = v * v / 2
    if not p then return e / decel end
    maxD = maxD or 5000
    local d = 0
    while d < maxD do
        d = d + STEP
        if decel * d + G * Braking.rise(p, t, uLead, d) >= e then return d end
    end
    return maxD
end
