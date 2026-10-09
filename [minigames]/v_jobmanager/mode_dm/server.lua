JobModes = JobModes or {}

JobModes[JOB_TYPE_DM] = {
    validate = function(game)
        local dm = game.deathmatch
        if type(dm) ~= "table" then return false, "missing deathmatch block" end
        if type(dm.weapon) ~= "number" or type(dm.ammo) ~= "number" then return false, "deathmatch.weapon/ammo required" end
        if not validatePoints(dm.spawnpoints, 3, game.maxPlayers) then return false, "deathmatch.spawnpoints needs at least maxPlayers {x,y,z,rot}" end
        return true
    end,
    start = function(match, endMatch)
        local dm = match.job.deathmatch
        local spawnOrder = {}
        for index = 1, #match.job.deathmatch.spawnpoints do table.insert(spawnOrder, index) end
        for index = #spawnOrder, 2, -1 do
            local swap = math.random(index)
            spawnOrder[index], spawnOrder[swap] = spawnOrder[swap], spawnOrder[index]
        end
        for index, player in ipairs(match.players) do
            local spawn = match.job.deathmatch.spawnpoints[spawnOrder[index]]
            spawnPlayer(player, spawn[1], spawn[2], spawn[3], spawn[4] or 0, getElementModel(player), 0, match.dimension)
            giveWeapon(player, dm.weapon, dm.ammo, true)
            setPedArmor(player, dm.armour or 0)
            match.eliminated[player] = false
        end
    end,
    remaining = function(match)
        local count, last = 0, nil
        for _, player in ipairs(match.players) do if not match.eliminated[player] then count, last = count + 1, player end end
        return count, last
    end,
}
