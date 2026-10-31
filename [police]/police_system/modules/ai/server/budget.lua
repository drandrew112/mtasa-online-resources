-- police_system / modules/ai/server/budget.lua
-- The AI police budget: global MAX_VEHICLES / MAX_TANKS; suspects closer than SHARE_DIST share the units (the units
-- of the other chase near this suspect count for it too); no new unit while the suspect is evading / in an interior
-- (the AI does not call units ahead). The police get priority over the civilian traffic (findHiddenRoadSpawn
-- priority option removes an unseen civilian vehicle in a full area).

local B = {}
POL.ai.budget = B
local A = POLICE.AI
local AI = POL.ai

local function own(c, tank)
    local list = {}
    for _, u in pairs(AI.units) do
        if u.chase == c and u.state ~= "retreat" and u.tank == tank then list[#list + 1] = u end
    end
    table.sort(list, function(a, b) return a.spawnedAt > b.spawnedAt end)   -- newest first
    return list
end

-- units of other chases whose suspect is within SHARE_DIST of this one
local function shared(c, tank)
    local n = 0
    if not isElement(c.suspect) then return 0 end
    local x, y = getElementPosition(c.suspect)
    for _, u in pairs(AI.units) do
        if u.chase and u.chase ~= c and u.state ~= "retreat" and u.tank == tank and isElement(u.chase.suspect) then
            local sx, sy = getElementPosition(u.chase.suspect)
            if (sx - x) ^ 2 + (sy - y) ^ 2 < A.SHARE_DIST ^ 2 then n = n + 1 end
        end
    end
    return n
end

local function fulfilKind(c, want, tank, d, now)
    local mine = own(c, tank)
    local have = #mine + shared(c, tank)
    if have < want then
        if d.phase ~= "active" or not d.inWorld then return end
        if AI.total(tank) >= (tank and A.MAX_TANKS or A.MAX_VEHICLES) then return end
        local key = tank and "t" or "c"
        AI.lastSpawn[c] = AI.lastSpawn[c] or {}
        if now - (AI.lastSpawn[c][key] or 0) < A.SPAWN_GAP then return end
        AI.lastSpawn[c][key] = now
        AI.spawn(c, tank)
    elseif #mine > 0 and have > want then
        -- the surplus (newest first) goes, never below the own share
        local extra = math.min(#mine, have - want)
        for i = 1, extra do AI.retreat(mine[i]) end
    end
end

function B.fulfil(c, d, now)
    fulfilKind(c, d.cars or 0, false, d, now)
    fulfilKind(c, d.tanks or 0, true, d, now)
    for _, u in pairs(AI.units) do
        if u.chase == c and u.state ~= "retreat" then POL.ai.tactics.update(u, d, now) end
    end
end

-- physics vehicles that could not go back into the traffic and crews left without a vehicle: removed unseen
function B.cleanup(now)
    local t = POL.running("ai_land_traffic") and exports.ai_land_traffic
    local function unseenFar(el)
        if not isElement(el) then return true end
        local x, y = getElementPosition(el)
        for _, p in ipairs(getElementsByType("player")) do
            local px, py = getElementPosition(p)
            if (px - x) ^ 2 + (py - y) ^ 2 < A.DESPAWN_DIST ^ 2 then return false end
        end
        return not (t and t:isElementSeenByPlayers(el))
    end
    for _, u in pairs(AI.units) do
        if (u.manualDespawn or u.dead) and u.state == "retreat" or (u.dead and not u.chase) then
            if unseenFar(u.veh) then AI.remove(u) end
        end
    end
    if AI.orphans then
        for ped, at in pairs(AI.orphans) do
            if not isElement(ped) then
                AI.orphans[ped] = nil
            elseif now - at > 30000 and unseenFar(ped) then
                AI.orphans[ped] = nil
                AI.peds[ped] = nil
                if POL.running("ai_peds") then pcall(function() exports.ai_peds:destroyAIPed(ped) end) end
                if isElement(ped) then destroyElement(ped) end
            end
        end
    end
end
