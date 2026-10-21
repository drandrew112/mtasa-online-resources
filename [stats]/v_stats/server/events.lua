-- Kill / death counters.

-- killer may be a vehicle: credit its driver
local function playerOf(element)
    if isElement(element) and getElementType(element) == "vehicle" then
        element = getVehicleController(element)
    end
    if isElement(element) and getElementType(element) == "player" then return element end
    return nil
end

local function bump(player, id)
    if not player then return end
    local entry = STORE.get(player)
    if entry then API_ADD(entry, id, 1) end
end

addEventHandler("onPedWasted", root, function(_, killer)
    bump(playerOf(killer), "kills_peds")
end)

addEventHandler("onPlayerWasted", root, function(_, killer)
    local victim = source
    bump(victim, "deaths")

    local k = playerOf(killer)
    if k and k ~= victim then
        bump(k, "kills_players")
        bump(victim, "deaths_by_players")
    end
end)
