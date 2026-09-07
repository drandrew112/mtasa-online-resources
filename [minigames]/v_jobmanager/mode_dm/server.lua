JobModes = JobModes or {}

JobModes[JOB_TYPE_DM] = {
    start = function(match, endMatch)
        local spawnOrder = {}
        for index = 1, #match.job.spawns do table.insert(spawnOrder, index) end
        for index = #spawnOrder, 2, -1 do
            local swap = math.random(index)
            spawnOrder[index], spawnOrder[swap] = spawnOrder[swap], spawnOrder[index]
        end
        for index, player in ipairs(match.players) do
            local spawn = match.job.spawns[spawnOrder[index]]
            spawnPlayer(player, spawn[1], spawn[2], spawn[3], spawn[4] or 0, getElementModel(player), 0, match.dimension)
            giveWeapon(player, match.job.weapon, match.job.ammo, true)
            setPedArmor(player, match.job.armour or 0)
            match.eliminated[player] = false
        end
    end,
    remaining = function(match)
        local count, last = 0, nil
        for _, player in ipairs(match.players) do if not match.eliminated[player] then count, last = count + 1, player end end
        return count, last
    end,
}
