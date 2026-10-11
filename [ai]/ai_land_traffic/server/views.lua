-- Player cameras (server). Clients report their camera position and look direction every VIEW_SEND;
-- the spawner keeps new vehicles out of close view and the cleanup removes vehicles no camera sees.
-- A player without a fresh report counts as seeing everything (nothing near them is culled).
--
-- view = { x, y, z, fx, fy, fz (unit look direction), t }

Views = { list = {} }

local T = TRAFFIC
local V = Views.list
local cos, rad, sqrt = math.cos, math.rad, math.sqrt
local COS_HALF = cos(rad(T.VIEW_HALF_ANGLE))
local VIEW_DIST2 = (T.DESPAWN_RADIUS + 50) ^ 2

addEvent(EV_VIEW, true)
addEventHandler(EV_VIEW, resourceRoot, function(x, y, z, fx, fy, fz)
    if type(x) ~= "number" or type(fx) ~= "number" or type(fy) ~= "number" or type(fz) ~= "number" then return end
    local l = sqrt(fx * fx + fy * fy + fz * fz)
    if l < 1e-3 then return end
    local v = V[client]
    if not v then v = {}; V[client] = v end
    v.x, v.y, v.z, v.fx, v.fy, v.fz, v.t = x, y, tonumber(z) or 0, fx / l, fy / l, fz / l, getTickCount()
end)

addEventHandler("onPlayerQuit", root, function() V[source] = nil end)

-- fresh view of a player or nil
function Views.of(player, now)
    local v = V[player]
    if v and now - v.t <= T.VIEW_STALE then return v end
    return nil
end

-- can this view see the point (x, y, z)? returns the distance too
local function sees(v, x, y, z)
    local dx, dy, dz = x - v.x, y - v.y, z - v.z
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 > VIEW_DIST2 then return false end
    local d = sqrt(d2)
    if d <= T.VIEW_NEAR then return true, d end
    return dx * v.fx + dy * v.fy + dz * v.fz >= COS_HALF * d, d
end

-- players: active players { { el, x, y, z } }. true when any of them sees the point (or has no view)
function Views.anySees(players, x, y, z, now)
    for _, p in ipairs(players) do
        local v = Views.of(p.el, now)
        if not v or sees(v, x, y, z) then return true end
    end
    return false
end

-- distance from the nearest camera that sees the point (nil = nobody looks at it)
function Views.nearestSeeing(players, x, y, z, now)
    local best
    for _, p in ipairs(players) do
        local v = Views.of(p.el, now)
        if v then
            local ok, d = sees(v, x, y, z)
            if ok and (not best or d < best) then best = d end
        end
    end
    return best
end
