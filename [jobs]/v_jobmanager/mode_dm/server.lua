if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
JobModes = JobModes or {}

local function checkWinner(match, endMatch)
    local count, winner = JobModes[JOB_TYPE_DM].remaining(match)
    if count <= 1 then
        endMatch(match, winner and (L.msg("v_jobmanager.core.won_deathmatch", { player = jobDisplayName(winner) })) or L.msg("v_jobmanager.core.deathmatch_ended"))
        return true
    end
    return false
end

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
            if weaponManagerRunning() then
                exports.wp_manager:setPlayerTempLoadout(player, { { id = dm.weapon, ammo = dm.ammo } }, dm.weapon)
            else
                giveWeapon(player, dm.weapon, dm.ammo, true)
            end
            setPedArmor(player, dm.armour or 0)
            match.eliminated[player] = false
        end
    end,
    remaining = function(match)
        local count, last = 0, nil
        for _, player in ipairs(match.players) do
            if not match.eliminated[player] and not match.left[player] then count, last = count + 1, player end
        end
        return count, last
    end,
    -- left the match or quit
    onPlayerGone = function(match, player, endMatch)
        match.eliminated[player] = true
        checkWinner(match, endMatch)
    end,
    canBeSpectated = function(match, player)
        return not match.eliminated[player]
    end,
    spectateInfo = function(match, player)
        return L.msg("v_jobmanager.spectate.dm_info", {
            health = math.floor(getElementHealth(player)), kills = match.kills[player] or 0,
        })
    end,
}

-- An eliminated player watches the others until the match ends.
addEventHandler("onPlayerWasted", root, function(totalAmmo, killer)
    local match = jobPlayerMatch(source)
    if not match or match.job.type ~= JOB_TYPE_DM or match.eliminated[source] or match.ended then return end

    match.deaths[source] = (match.deaths[source] or 0) + 1
    if isElement(killer) and getElementType(killer) == "player" and killer ~= source and jobPlayerMatch(killer) == match then
        match.kills[killer] = (match.kills[killer] or 0) + 1
    end

    match.eliminated[source] = true
    if not checkWinner(match, jobEndMatch) then
        Spectate.start(match, source, JOBS_CONFIG.SPECTATE_DELAY)
        Spectate.refresh(match)
    end
end)
