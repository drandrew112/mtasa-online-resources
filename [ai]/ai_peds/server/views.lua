-- Player cameras (server): clients report camera position + look direction. Used to spawn walkers out of sight and
-- to remove the ones nobody looks at.

Views = { list = {} }   -- [player] = { x, y, z, lx, ly, lz, t }

local T = AIPEDS
local cosHalf = math.cos(math.rad(T.VIEW_HALF_ANGLE))

addEvent(EV_VIEW, true)
addEventHandler(EV_VIEW, resourceRoot, function(x, y, z, lx, ly, lz)
    if type(x) ~= "number" or type(lx) ~= "number" then return end
    Views.list[client] = { x = x, y = y, z = z, lx = lx, ly = ly, lz = lz, t = getTickCount() }
end)

addEventHandler("onPlayerQuit", root, function() Views.list[source] = nil end)

-- can this player's camera see the point? (true when there is no fresh report)
function Views.playerSees(pl, x, y, z, now)
    local v = Views.list[pl]
    if not v or now - v.t > T.VIEW_STALE then return true end
    local dx, dy, dz = x - v.x, y - v.y, z - v.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < T.VIEW_NEAR then return true end
    return (dx * v.lx + dy * v.ly + dz * v.lz) / d >= cosHalf
end

-- does any camera within maxDist look at the point?
function Views.anySees(players, x, y, z, maxDist, now)
    for _, pl in ipairs(players) do
        local v = Views.list[pl.el]
        local cx, cy = v and v.x or pl.x, v and v.y or pl.y
        if not maxDist or (cx - x) ^ 2 + (cy - y) ^ 2 < maxDist * maxDist then
            if Views.playerSees(pl.el, x, y, z, now) then return true end
        end
    end
    return false
end
