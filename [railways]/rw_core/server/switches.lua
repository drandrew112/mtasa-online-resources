-- Switches: the real switches of rw_customtracks (always thrown by the system: a train's route
-- reserves them ahead of it). This keeps the old rw_core switch API for the other resources;
-- an "owner" reservation is a rw_customtracks route reservation.

addEvent("onRailSwitchChange")      -- source: root, (id, state, player|false)
addEvent("onNetSwitchChange", false)

local function net() return exports.rw_customtracks end
local held = {}                     -- [id] = owner (reservations made through this API)

addEventHandler("onNetSwitchChange", root, function(group, state)
    triggerEvent("onRailSwitchChange", root, group, state, false)
end)

-- static geometry of a switch group (cached; the network only changes on a rebuild):
-- x, y = first node; a / b = { track, tp } of a crossover's two legs on two different lines
-- (rw_signals joins the blocks of a reversed crossover), nil for other switches
local geometry = {}
local LEG_DIST = 8          -- m from a node to the line it sits on

local function geometryOf(s)
    local g = geometry[s.id]
    if g then return g end
    g = { x = 0, y = 0 }
    local legs = {}
    for k, nid in ipairs(s.nodes or {}) do
        local node = net():netGetNode(nid)
        if node then
            if k == 1 then g.x, g.y = node.x or 0, node.y or 0 end
            local track, tp = Track.nearest(node.x or 0, node.y or 0, LEG_DIST, RW.TRACKS)
            if track then
                if not legs[1] then legs[1] = { track = track, tp = tp }
                elseif legs[1].track ~= track and not legs[2] then legs[2] = { track = track, tp = tp } end
            end
        end
    end
    if legs[1] and legs[2] then g.a, g.b = legs[1], legs[2] end
    geometry[s.id] = g
    return g
end

addEventHandler("onNetNetworkRebuilt", root, function() geometry = {} end)

-- { { id, name, state, locked, reserved, damaged, spring, x, y, a, b } }
function getSwitches()
    local t = {}
    for _, s in ipairs(net():getNetSwitches() or {}) do
        local g = geometryOf(s)
        t[#t + 1] = { id = s.id, name = s.name, state = s.state, locked = s.locked, reserved = s.reserved, damaged = s.damaged,
            spring = s.spring, x = g.x, y = g.y, a = g.a, b = g.b }
    end
    return t
end

function getSwitchState(id)
    for _, s in ipairs(net():getNetSwitches() or {}) do
        if s.id == id then return s.state end
    end
    return false
end

-- owner = a reservation owner (string): reserve the switch in that state for it.
-- Without an owner (players, admin tools) the switch is thrown when it is free.
function setSwitchState(id, state, player, owner)
    if state ~= "normal" and state ~= "reverse" then return false, "bad state" end
    if player and not hasRailwayAccess(player) then return false, "Railway staff only" end
    if owner then
        local ok, err = net():reserveNetRoute(owner, { [id] = state })
        if ok then held[id] = owner end
        return ok, err
    end
    local ok, err = net():netSetSwitch(id, state)
    return ok and true or false, err
end

-- owner = reserve the switch (in its current state) for it, nil = release it
function setSwitchReserved(id, owner)
    if owner then
        local ok = net():reserveNetRoute(owner, { [id] = getSwitchState(id) or "normal" })
        if ok then held[id] = owner end
        return ok
    end
    if held[id] then net():releaseNetRoute(held[id], id) held[id] = nil end
    return true
end
