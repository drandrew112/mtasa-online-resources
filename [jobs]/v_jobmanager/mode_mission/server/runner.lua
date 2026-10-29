if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Missions: the players work together through a list of stages. A stage is done when all (or
-- any) of its objectives are done (mode_mission/server/objectives.lua); the last stage done =
-- mission passed. The crew shares Team lives: every death takes one and the player comes back
-- at the stage's respawn point; a death with 0 lives left ends the mission (failed, minimal
-- reward). Players of one mission cannot hurt each other (an MTA team without friendly fire,
-- plus the client guard in mode_mission/client/hud.lua).
--
-- match.mission = { stageIndex, stageId, objectives, fails, lives, stagesDone, result, reason,
--                   ents, respawning, isCrew, interacted, signals, team, deadline, stageDeadline }

JobModes = JobModes or {}
Mission = {}

local CFG = JOBS_CONFIG.MISSION
local LIMITS = { stages = 60, objectives = 8, fails = 6, zones = 100, peds = 120, vehicles = 40, items = 30, points = 30 }
MISSION_LIMITS = LIMITS

local function now() return getTickCount() end

--------------------------------------------------------------------------------
-- validation
--------------------------------------------------------------------------------

local function isNum(v) return type(v) == "number" and v == v end
local function isId(v) return type(v) == "string" and v ~= "" and #v <= 40 end

local function idList(list, max, name, need)
    if list == nil then return {}, nil end
    if type(list) ~= "table" or #list > max then return nil, name .. " must be a list of at most " .. max end
    local ids = {}
    for i, e in ipairs(list) do
        if type(e) ~= "table" or not isId(e.id) then return nil, name .. "[" .. i .. "] needs an id" end
        if ids[e.id] then return nil, name .. ": duplicate id '" .. e.id .. "'" end
        for _, key in ipairs(need) do
            if not isNum(e[key]) then return nil, name .. "[" .. i .. "]." .. key .. " must be a number" end
        end
        ids[e.id] = e
    end
    return ids
end

local REFS = {
    enterZone = { zone = "zones", vehicle = "vehicles?" },
    stayInZone = { zone = "zones" },
    enterVehicle = { vehicle = "vehicles" },
    deliverVehicle = { vehicle = "vehicles", zone = "zones" },
    collectItem = { item = "items" },
    deliverItem = { item = "items", zone = "zones" },
    destroyVehicle = { vehicle = "vehicles" },
    interact = { point = "points" },
    -- fails
    vehicleDestroyed = { vehicle = "vehicles" },
    pedDied = { ped = "peds" },
    leaveZone = { zone = "zones" },
}

local function checkRefs(def, sets, where)
    for key, set in pairs(REFS[def.type] or {}) do
        local optional = set:sub(-1) == "?"
        set = optional and set:sub(1, -2) or set
        local v = def[key]
        if v == nil and optional then
            -- fine
        elseif not isId(v) or not sets[set][v] then
            return false, where .. ": " .. key .. " '" .. tostring(v) .. "' does not exist"
        end
    end
    if def.type == "killPeds" and not def.all then
        if type(def.peds) ~= "table" or #def.peds == 0 then return false, where .. ": killPeds needs peds or all" end
        for _, id in ipairs(def.peds) do
            if not sets.peds[id] and not sets.vehicles[id] then return false, where .. ": ped '" .. tostring(id) .. "' does not exist" end
        end
    end
    if def.type == "scriptEvent" and not isId(def.name) then return false, where .. ": scriptEvent needs a name" end
    return true
end

local function validate(game)
    local m = game.mission
    if type(m) ~= "table" then return false, "missing mission block" end
    if not validatePoints(m.spawnpoints, 3, game.maxPlayers) then return false, "mission.spawnpoints needs at least maxPlayers {x,y,z,rot}" end
    if m.teamLives ~= nil and (not isNum(m.teamLives) or m.teamLives < 0 or m.teamLives > 20) then return false, "mission.teamLives must be 0..20" end
    if m.timeLimit ~= nil and (not isNum(m.timeLimit) or m.timeLimit < 10) then return false, "mission.timeLimit must be at least 10 s" end
    if m.reward ~= nil and (type(m.reward) ~= "table" or not isNum(m.reward.money) or not isNum(m.reward.xp)) then return false, "mission.reward needs money and xp" end
    if m.loadout ~= nil then
        if type(m.loadout) ~= "table" or #m.loadout > 6 then return false, "mission.loadout must be a list of at most 6" end
        for i, w in ipairs(m.loadout) do
            if type(w) ~= "table" or not isNum(w.id) or not isNum(w.ammo) then return false, "mission.loadout[" .. i .. "] needs id and ammo" end
        end
    end
    local sets, err = {}
    sets.zones, err = idList(m.zones, LIMITS.zones, "zones", { "x", "y", "z", "radius" }) if not sets.zones then return false, err end
    sets.peds, err = idList(m.peds, LIMITS.peds, "peds", { "skin", "x", "y", "z" }) if not sets.peds then return false, err end
    sets.vehicles, err = idList(m.vehicles, LIMITS.vehicles, "vehicles", { "model", "x", "y", "z" }) if not sets.vehicles then return false, err end
    sets.items, err = idList(m.items, LIMITS.items, "items", { "x", "y", "z" }) if not sets.items then return false, err end
    sets.points, err = idList(m.points, LIMITS.points, "points", { "x", "y", "z" }) if not sets.points then return false, err end
    for id, item in pairs(sets.items) do
        if not isId(item.item) then return false, "items." .. id .. " needs an item type" end
    end
    if type(m.stages) ~= "table" or #m.stages == 0 or #m.stages > LIMITS.stages then return false, "mission.stages needs 1.." .. LIMITS.stages .. " stages" end
    local stageIds = {}
    for i, s in ipairs(m.stages) do
        local where = "stages[" .. i .. "]"
        if type(s) ~= "table" or not isId(s.id) then return false, where .. " needs an id" end
        if stageIds[s.id] then return false, "duplicate stage id '" .. s.id .. "'" end
        stageIds[s.id] = true
        if type(s.title) ~= "string" or s.title == "" then return false, where .. " needs a title" end
        if type(s.objectives) ~= "table" or #s.objectives == 0 or #s.objectives > LIMITS.objectives then
            return false, where .. " needs 1.." .. LIMITS.objectives .. " objectives"
        end
        for j, o in ipairs(s.objectives) do
            if type(o) ~= "table" or not MISSION_OBJECTIVE_TYPES[o.type] then return false, where .. ".objectives[" .. j .. "]: unknown type '" .. tostring(type(o) == "table" and o.type) .. "'" end
            local ok, rerr = checkRefs(o, sets, where .. ".objectives[" .. j .. "]")
            if not ok then return false, rerr end
        end
        if s.fail ~= nil then
            if type(s.fail) ~= "table" or #s.fail > LIMITS.fails then return false, where .. ".fail must be a list of at most " .. LIMITS.fails end
            for j, f in ipairs(s.fail) do
                if type(f) ~= "table" or not MISSION_FAIL_TYPES[f.type] then return false, where .. ".fail[" .. j .. "]: unknown type" end
                local ok, rerr = checkRefs(f, sets, where .. ".fail[" .. j .. "]")
                if not ok then return false, rerr end
            end
        end
        if s.respawnPoint ~= nil and not validatePoints({ s.respawnPoint }, 3, 1) then return false, where .. ".respawnPoint must be {x,y,z,rot}" end
        if s.timeLimit ~= nil and (not isNum(s.timeLimit) or s.timeLimit < 5) then return false, where .. ".timeLimit must be at least 5 s" end
    end
    for _, s in ipairs(m.stages) do
        if s.next ~= nil and not stageIds[s.next] then return false, "stage '" .. s.id .. "': next stage '" .. tostring(s.next) .. "' does not exist" end
        for _, id in ipairs(s.despawn or {}) do
            if not (sets.peds[id] or sets.vehicles[id] or sets.items[id]) then return false, "stage '" .. s.id .. "' removes unknown '" .. tostring(id) .. "'" end
        end
    end
    for _, set in ipairs({ "peds", "vehicles", "items" }) do
        for id, e in pairs(sets[set]) do
            if e.stage ~= nil and not stageIds[e.stage] then return false, set .. "." .. id .. ": stage '" .. tostring(e.stage) .. "' does not exist" end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- players
--------------------------------------------------------------------------------

local function giveLoadout(match, player)
    local m = match.job.mission
    local list = {}
    for i, w in ipairs(m.loadout or {}) do list[i] = { id = w.id, ammo = w.ammo } end
    if weaponManagerRunning() then
        exports.wp_manager:setPlayerTempLoadout(player, list, list[1] and list[1].id or nil)
    else
        takeAllWeapons(player)
        for i, w in ipairs(list) do giveWeapon(player, w.id, w.ammo, i == 1) end
    end
    setPedArmor(player, m.armour or 0)
end

local function playerIndex(match, player)
    for i, p in ipairs(match.players) do if p == player then return i end end
    return 1
end

local function spawnAt(match, player, point)
    spawnPlayer(player, point[1], point[2], point[3] + 0.3, point[4] or 0, getElementModel(player), 0, match.dimension)
    setElementDimension(player, match.dimension)
    setElementInterior(player, 0)
    setCameraTarget(player, player)
    giveLoadout(match, player)
end

local function joinSquad(match, player)
    local st = match.mission
    st.isCrew[player] = true
    if isElement(st.team) then setPlayerTeam(player, st.team) end
    setElementData(player, "jobs.squad", match.id)
    if MissionEntities.aiReady() then exports.ai_peds:setPlayerAIGroup(player, (MissionEntities.groups(match))) end
end

local function leaveSquad(match, player)
    match.mission.isCrew[player] = nil
    match.mission.respawning[player] = nil
    if not isElement(player) then return end
    if getPlayerTeam(player) == match.mission.team then setPlayerTeam(player, nil) end
    removeElementData(player, "jobs.squad")
    if MissionEntities.aiReady() then exports.ai_peds:setPlayerAIGroup(player, false) end
end

local function activeCount(match)
    local n = 0
    for _, player in ipairs(match.players) do
        if isElement(player) and not match.left[player] then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

local function hudData(match, stageChanged)
    local st = match.mission
    local stage = match.job.mission.stages[st.stageIndex]
    local objectives, targets, points = {}, {}, {}
    local showEnemies = false
    for i, o in ipairs(st.objectives) do
        local T = MissionObjectives[o.def.type]
        objectives[i] = { type = o.def.type, label = o.def.label or false, done = o.done, progress = (not o.done and T.progress and T.progress(match, o)) or false }
        if not o.done then
            local t = T.target and T.target(match, o)
            if t then targets[#targets + 1] = t end
            if T.point then
                local p = MissionPoint(match, o.def.point)
                if p then points[#points + 1] = { id = p.id, x = p.x, y = p.y, z = p.z, label = p.label or false, holdMs = p.holdMs or 3000 } end
            end
            if T.enemies then showEnemies = true end
        end
    end
    local enemies = {}
    for _, entry in pairs(st.ents.peds) do
        if not entry.dead and isElement(entry.el) and entry.def.behaviour ~= "civilian" then enemies[#enemies + 1] = entry.el end
    end
    for _, entry in pairs(st.ents.vehicles) do
        if entry.def.role == "enemy" and not entry.crewOut and isElement(entry.el) then enemies[#enemies + 1] = entry.el end
    end
    local deadline = st.deadline
    if st.stageDeadline and (not deadline or st.stageDeadline < deadline) then deadline = st.stageDeadline end
    return {
        stage = st.stageIndex, total = #match.job.mission.stages, title = stage and stage.title or "",
        stageChanged = stageChanged or false, objectives = objectives, lives = st.lives,
        timeLeft = deadline and math.max(0, deadline - now()) or false,
        targets = targets, points = points, enemies = enemies, highlightEnemies = showEnemies,
    }
end

function Mission.sendHud(match, stageChanged, only)
    if match.ended then return end
    local data = hudData(match, stageChanged)
    for _, player in ipairs(only and { only } or match.players) do
        if isElement(player) and not match.left[player] then
            triggerClientEvent(player, "jobmanager:missionHud", resourceRoot, data)
        end
    end
end

--------------------------------------------------------------------------------
-- stages
--------------------------------------------------------------------------------

local function stageIndexOf(match, id)
    for i, s in ipairs(match.job.mission.stages) do
        if s.id == id then return i end
    end
end

-- result: "success" | "fail" | "aborted"; reasonKey: v_jobmanager.mission.<key>
local function finish(match, result, reasonKey, aborted)
    if match.ended then return end
    local st = match.mission
    st.result, st.reason = result, reasonKey
    jobEndMatch(match, L.msg("v_jobmanager.mission." .. reasonKey), aborted)
end
Mission.finish = finish

function Mission.startStage(match, index)
    local st = match.mission
    local stage = match.job.mission.stages[index]
    if not stage then return finish(match, "success", "passed") end
    st.stageIndex, st.stageId, st.stageStart = index, stage.id, now()
    MissionEntities.despawn(match, stage.despawn)
    MissionEntities.spawnFor(match, stage.id)
    st.objectives = {}
    for i, def in ipairs(stage.objectives) do st.objectives[i] = { def = def, done = false } end
    st.fails = stage.fail or {}
    st.interacted = {}
    st.stageDeadline = stage.timeLimit and (now() + stage.timeLimit * 1000) or nil
    Mission.sendHud(match, true)
    triggerEvent("onJobMissionStage", root, match.id, match.job.id, stage.id, match.opts.tag)
end

local function completeStage(match)
    local st = match.mission
    local stage = match.job.mission.stages[st.stageIndex]
    st.stagesDone = st.stagesDone + 1
    local nextIndex = stage.next and stageIndexOf(match, stage.next) or (st.stageIndex + 1)
    if nextIndex > #match.job.mission.stages then return finish(match, "success", "passed") end
    Mission.startStage(match, nextIndex)
end

local FAIL_REASON = { vehicleDestroyed = "vehicle_destroyed", pedDied = "ped_died", leaveZone = "left_area" }

function Mission.tick(match, dt)
    if match.ended then return end
    local st = match.mission
    local t = now()
    if (st.deadline and t >= st.deadline) or (st.stageDeadline and t >= st.stageDeadline) then
        return finish(match, "fail", "time_up")
    end
    for _, f in ipairs(st.fails) do
        if MissionFails[f.type](match, f) then return finish(match, "fail", FAIL_REASON[f.type] or "failed") end
    end
    local stage = match.job.mission.stages[st.stageIndex]
    local done, changed = 0, false
    for _, o in ipairs(st.objectives) do
        if not o.done and MissionObjectives[o.def.type].check(match, o, dt) then
            o.done, changed = true, true
        end
        if o.done then done = done + 1 end
    end
    if (stage.complete == "any" and done > 0) or done == #st.objectives then
        return completeStage(match)
    end
    if changed then Mission.sendHud(match) end
end

-- jobmanagerMissionSignal
function Mission.signal(match, name)
    match.mission.signals[name] = true
    return true
end

--------------------------------------------------------------------------------
-- deaths and Team lives
--------------------------------------------------------------------------------

local function respawn(match, player)
    local st = match.mission
    if match.ended or not isElement(player) or match.left[player] or jobPlayerMatch(player) ~= match then return end
    Spectate.stop(match, player)
    st.respawning[player] = nil
    local stage = match.job.mission.stages[st.stageIndex]
    local point = stage and stage.respawnPoint
    if not point then
        local spawns = match.job.mission.spawnpoints
        point = spawns[(playerIndex(match, player) - 1) % #spawns + 1]
    end
    spawnAt(match, player, point)
    joinSquad(match, player)
    Mission.sendHud(match)
    if next(match.spectators) then Spectate.refresh(match) end
end

addEventHandler("onPlayerWasted", root, function(_, killer)
    local match = jobPlayerMatch(source)
    if not match or match.job.type ~= JOB_TYPE_MISSION or match.ended then return end
    local st = match.mission
    if st.respawning[source] then return end
    match.deaths[source] = (match.deaths[source] or 0) + 1
    if st.lives <= 0 then return finish(match, "fail", "no_lives") end
    st.lives = st.lives - 1
    st.respawning[source] = true
    local player = source
    Spectate.start(match, player, 2500)
    table.insert(match.timers, setTimer(function() respawn(match, player) end, CFG.respawnMs, 1))
    Mission.sendHud(match)
    if next(match.spectators) then Spectate.refresh(match) end
end)

-- kills of mission peds (ai_peds or plain): kill credit + killPeds progress
addEventHandler("onPedWasted", root, function(_, killer)
    local id = getElementData(source, "jobs.mission")
    local match = id and jobMatchById(id)
    if not match or match.ended or not match.mission then return end
    local entry = MissionEntities.pedEntry(match, source)
    if not entry or entry.dead then return end
    entry.dead = true
    if isElement(killer) and getElementType(killer) == "vehicle" then killer = getVehicleController(killer) end
    if isElement(killer) and getElementType(killer) == "player" and match.mission.isCrew[killer] then
        match.kills[killer] = (match.kills[killer] or 0) + 1
    end
end)

-- hold-to-interact points (the client counts the hold, the server checks the distance)
addEvent("jobmanager:missionInteract", true)
addEventHandler("jobmanager:missionInteract", resourceRoot, function(pointId)
    local match = jobPlayerMatch(client)
    if not match or match.job.type ~= JOB_TYPE_MISSION or match.ended or type(pointId) ~= "string" then return end
    local st = match.mission
    if not st.isCrew[client] or st.respawning[client] then return end
    for _, o in ipairs(st.objectives) do
        if not o.done and o.def.type == "interact" and o.def.point == pointId then
            local p = MissionPoint(match, pointId)
            local x, y, z = getElementPosition(client)
            if p and getDistanceBetweenPoints3D(x, y, z, p.x, p.y, p.z) < 3.5 then st.interacted[pointId] = true end
            return
        end
    end
end)

--------------------------------------------------------------------------------
-- mode
--------------------------------------------------------------------------------

JobModes[JOB_TYPE_MISSION] = {
    validate = validate,

    start = function(match)
        local m = match.job.mission
        local crewGroup, enemyGroup, civGroup = MissionEntities.groups(match)
        local st = {
            stageIndex = 0, lives = m.teamLives or 3, stagesDone = 0, objectives = {}, fails = {},
            ents = { peds = {}, vehicles = {}, items = {} },
            respawning = {}, isCrew = {}, interacted = {}, signals = {},
            deadline = m.timeLimit and (now() + m.timeLimit * 1000) or nil,
        }
        match.mission = st
        st.team = createTeam("Mission #" .. match.id, 90, 170, 255)
        if st.team then setTeamFriendlyFire(st.team, false) end
        if MissionEntities.aiReady() then
            local ai = exports.ai_peds
            ai:setAIGroupRelation(crewGroup, enemyGroup, "hostile")
            ai:setAIGroupRelation(crewGroup, civGroup, "neutral")
            ai:setAIGroupRelation(enemyGroup, civGroup, "neutral")
        end
        for index, player in ipairs(match.players) do
            spawnAt(match, player, m.spawnpoints[index])
            joinSquad(match, player)
        end
        MissionEntities.spawnFor(match, nil)
        Mission.startStage(match, match.opts.startStage and stageIndexOf(match, match.opts.startStage) or 1)
        local dt = CFG.tickMs / 1000
        table.insert(match.timers, setTimer(function() Mission.tick(match, dt) end, CFG.tickMs, 0))
        table.insert(match.timers, setTimer(function()
            if match.ended then return end
            MissionEntities.tick(match)
            Mission.sendHud(match)
        end, 1000, 0))
    end,

    onPlayerGone = function(match, player, endMatch, quit)
        leaveSquad(match, player)
        if isElement(player) then triggerClientEvent(player, "jobmanager:missionHud", resourceRoot, false) end
        if activeCount(match) == 0 then
            finish(match, "fail", "abandoned", true)
        end
    end,

    onEnd = function(match, aborted)
        local st = match.mission
        if not st then return end
        if not st.result then st.result, st.reason = aborted and "aborted" or "fail", st.reason or "aborted" end
        MissionEntities.clear(match)
        for _, player in ipairs(match.players) do
            leaveSquad(match, player)
            if isElement(player) then triggerClientEvent(player, "jobmanager:missionHud", resourceRoot, false) end
        end
        if isElement(st.team) then destroyElement(st.team) end
    end,

    -- the script that started the mission (and the creator test) hears how it went
    afterEnd = function(match)
        local st = match.mission
        if not st then return end
        local players = {}
        for _, player in ipairs(match.players) do if isElement(player) then players[#players + 1] = player end end
        triggerEvent("onJobMissionFinished", root, match.id, match.job.id, st.result, {
            stagesDone = st.stagesDone, stagesTotal = #match.job.mission.stages, reason = st.reason,
            timeMs = now() - match.startTick, players = players,
        }, match.opts.tag)
    end,

    canBeSpectated = function(match, player)
        return match.mission.isCrew[player] and not match.mission.respawning[player]
    end,
    spectateInfo = function(match, player)
        return L.msg("v_jobmanager.spectate.mission_info", { health = math.floor(getElementHealth(player)) })
    end,
}

addEvent("onJobMissionStage")
addEvent("onJobMissionFinished")
