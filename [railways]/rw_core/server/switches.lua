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

-- { { id, name, state, locked, reserved, x, y } }
function getSwitches()
    local t = {}
    for _, s in ipairs(net():getNetSwitches() or {}) do
        local x, y = 0, 0
        local node = s.nodes and s.nodes[1] and net():netGetNode(s.nodes[1])
        if node then x, y = node.x or 0, node.y or 0 end
        t[#t + 1] = { id = s.id, name = s.name, state = s.state, locked = s.locked, reserved = s.reserved, damaged = s.damaged,
            spring = s.spring, x = x, y = y }
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
