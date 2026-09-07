

-- Jármű lehívás
function giveArenaVehicle(player)
    local spawn = table.random(spawnpoints)

    local veh = createVehicle(table.random(vehicles), spawn.x, spawn.y, spawn.z+1.5, 0,0,spawn.rot, "ARENA-"..tostring(random(10, 99)))
    setElementInterior(veh, 15)
    setElementDimension(veh, arena_dim)
    setElementPosition(veh, spawn.x, spawn.y, spawn.z)
    setVehicleHandling(veh, "collisionDamageMultiplier", 1.6)

    warpPedIntoVehicle(player, veh, 0)
end

-- Kiesés
addEventHandler("onVehicleDamage", getRootElement(),
    function (loss)
        local player = getVehicleOccupant(source, 0)
        if not player then return end
        local int,dim = getElementInterior(player), getElementDimension(player)
        if (int==15 and dim==arena_dim) then
            local veh_hp = getElementHealth(source)
            if (veh_hp < 421) then
                exitArena(player, 1)
            end
        end
    end
)

