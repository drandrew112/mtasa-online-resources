-- NPC roles of the live scenes (fighter / hostile / suspect = ai_peds scripted peds) and the criminal records.
--
-- fighter  two sides (ai.side a / b) of one scene fight each other: groups vsm<id>.a <-> vsm<id>.b hostile. The fight
--          starts at spawn or when a player on duty (police / EMS) gets within ai.startRadius ("unit_near": a ped
--          without a syncer stands still, the fight would be over before anyone arrives). An officer within
--          NPC.POLICE_REACT_RADIUS: ai.onPolice = stop (they stand, detained) | flee | continue.
-- hostile  group vsm<id>.h, hostile to the police group (on-duty officers, AI cops) or with targets "all" to every
--          player (ai_peds hostilePlayers). guard / idle task, aggro, leash; below ai.surrenderHealth it gives up
--          (detained + hands up, cuffable); ai.flee = chance to run when an officer comes near.
-- suspect  stands where it was placed; ai.flee = chance to run (scared) when an officer comes near; armed = a threat.
-- Every AI ped is kept + protected (only this script removes it) and has medev.saveLethal: a lethal hit puts it
-- down (medsys) instead of killing it, so the fight's injured are patients of the EMS.
--
-- Records: Npc.roll draws the ranges once per spawn (age, BAC) into element data VSM.DATA_ROLLED; the profile goes to
-- police_system as server element data "pol.profile" (used at the first police contact instead of the random past).
-- announce = police_system registers the citizen right now (searchable on the MDC, warrants listed).

Npc = { scenes = {} }   -- [instance id] = { fightStarted, reacted = { [ped] = true } }

local random = math.random

local function ai() return vsmResourceRunning(VSM.AIPEDS) and exports[VSM.AIPEDS] or nil end
local function police() return vsmResourceRunning(VSM.POLICE) and exports[VSM.POLICE] or nil end

local function group(scene, suffix) return ("vsm%d.%s"):format(scene.id, suffix) end

local function rollRange(value, decimals)
    local a, b = vsmRange(value)
    if not a then return nil end
    if a == b then return a end
    return vsmRound(a + random() * (b - a), decimals or 0)
end

---------------------------------------------------------------- records

-- rolled values of a ped entry (nil without a record)
function Npc.roll(entry)
    local r = entry.record
    if not r then return nil end
    local f = r.flags or {}
    return {
        age = r.age and math.floor(rollRange(r.age) or 30) or nil,
        bac = f.bac and rollRange(f.bac, 2) or 0,
        drug = f.drug or false,
    }
end

-- the profile police_system reads (history/npc.lua)
local function profile(scene, entry, rolled)
    local r = entry.record
    local f = r.flags or {}
    local past = {}
    for _, p in ipairs(r.past or {}) do
        past[#past + 1] = { type = p.type, btk = p.btk, daysAgo = math.floor(rollRange(p.daysAgo) or 30) }
    end
    local warrants = {}
    for _, w in ipairs(r.warrants or {}) do
        warrants[#warrants + 1] = { reasons = vsmCopy(w.reasons), description = vsmCopy(w.description) }
    end
    return {
        name = r.name, age = rolled.age, birth = r.birth,
        flags = { licence = f.licence, bac = rolled.bac, drug = rolled.drug and true or false, drugType = rolled.drug or nil,
                  flee = f.flee },
        past = past, warrants = warrants,
        key = r.persistent and ("scene:" .. scene.name .. ":" .. entry.id) or nil,
        source = "v_scenemanager",
    }
end

function Npc.applyRecord(scene, ped, entry, rolled)
    if not entry.record or not rolled then return end
    setElementData(ped, VSM.DATA_ROLLED, rolled, false)
    setElementData(ped, "pol.profile", profile(scene, entry, rolled), false)
    if entry.record.announce then
        local p = police()
        if p then pcall(function() p:registerNPC(ped) end) end
    end
end

-- vehicle record -> "pol.vprofile" (owner = a scene ped element, "random" or "none")
function Npc.applyVehicleRecord(scene, vehicle, entry, pedsById)
    local r = entry.record
    if not r then return end
    local owner = r.owner or "random"
    if owner ~= "random" and owner ~= "none" then owner = pedsById[owner] or "random" end
    setElementData(vehicle, "pol.vprofile", { stolen = r.stolen == true, owner = owner, inspection = r.inspection or "valid" }, false)
end

---------------------------------------------------------------- AI peds

-- creates the ai_peds ped of an AI role entry -> ped | nil (nil: ai_peds missing, the caller makes a static ped)
function Npc.create(scene, entry, data)
    local A = ai()
    local role = vsmRoleById(entry.role)
    if not A or not role or not role.ai then return nil end
    local a = entry.ai or {}
    local p = entry.pos
    local opts = { rot = entry.rot, dimension = data.dimension, interior = data.interior, keepBody = true }
    if entry.role == "fighter" then
        opts.behaviour = "enemy"
        opts.group = group(scene, a.side or "a")
        opts.weapon, opts.ammo = (a.weapon or 0) ~= 0 and a.weapon or nil, 1
        opts.aggroRadius, opts.leash = 30, 40
    elseif entry.role == "hostile" then
        opts.behaviour = "enemy"
        opts.group = group(scene, "h")
        opts.weapon, opts.ammo = (a.weapon or 0) ~= 0 and a.weapon or nil, a.ammo
        opts.accuracy, opts.aggroRadius, opts.leash = a.accuracy, a.aggroRadius, a.leash
        opts.hostilePlayers = a.targets == "all" or nil
        if a.task == "guard" then
            opts.task, opts.taskOpts = "guard", { x = p[1], y = p[2], z = p[3] }
        end
    else -- suspect
        opts.behaviour = "civilian"
        opts.task = "idle"
        opts.weapon, opts.ammo = (a.weapon or 0) ~= 0 and a.weapon or nil, a.ammo
    end
    local ok, ped = pcall(function() return A:createAIPed(entry.skin, p[1], p[2], p[3], opts) end)
    if not ok or not isElement(ped) then
        vsmLog("scene '%s': ai_peds could not create %s (%s)", scene.name, entry.id, tostring(ped))
        return nil
    end
    pcall(function()
        A:setAIPedKeep(ped, true)
        A:setAIPedProtected(ped, true)
    end)
    setElementData(ped, "medev.saveLethal", true, false)
    return ped
end

-- relations of a new scene (hostiles against the police right away; the fight waits for its start)
function Npc.setup(scene)
    local A = ai()
    local st = { fightStarted = false, reacted = {}, fleeRolled = {}, hasFight = false, needsUnit = false }
    Npc.scenes[scene.id] = st
    if not A then return end
    for ped, entry in pairs(scene.pedEntries) do
        if entry.role == "hostile" then
            pcall(function() A:setAIGroupRelation(group(scene, "h"), "police", "hostile") end)
        elseif entry.role == "fighter" then
            st.hasFight = true
            if entry.ai and entry.ai.start == "unit_near" then st.needsUnit = true end
        end
    end
    if st.hasFight and not st.needsUnit then Npc.startFight(scene) end
end

function Npc.startFight(scene)
    local st = Npc.scenes[scene.id]
    local A = ai()
    if not st or st.fightStarted or not A then return end
    st.fightStarted = true
    pcall(function() A:setAIGroupRelation(group(scene, "a"), group(scene, "b"), "hostile") end)
    vsmLog("scene '%s' #%d: fight started", scene.name, scene.id)
end

-- relations dropped (scene removed)
function Npc.cleanup(scene)
    local A = ai()
    Npc.scenes[scene.id] = nil
    if not A then return end
    pcall(function()
        A:setAIGroupRelation(group(scene, "a"), group(scene, "b"), "neutral")
        A:setAIGroupRelation(group(scene, "h"), "police", "neutral")
    end)
end

function Npc.destroy(ped)
    local A = ai()
    if A and isElement(ped) then
        local ok = pcall(function() A:setAIPedProtected(ped, false) end)
        if ok and pcall(function() A:destroyAIPed(ped) end) and not isElement(ped) then return end
    end
    if isElement(ped) then destroyElement(ped) end
end

---------------------------------------------------------------- state of a ped

local DOWN = { dazed = true, unconscious = true, clinical_death = true, dead = true }

function Npc.isDown(ped)
    if not isElement(ped) or isPedDead(ped) then return true end
    return DOWN[getElementData(ped, "medic.status")] == true
end

function Npc.isCuffed(ped)
    local p = police()
    if not p or not isElement(ped) then return false end
    local ok, res = pcall(function() return p:isElementCuffed(ped) end)
    return ok and res == true
end

function Npc.isSurrendered(ped) return isElement(ped) and getElementData(ped, "vsm.surrendered") == true end

-- an officer on duty (police_system) / a medic in an ERM unit
function Npc.isOfficer(player)
    local p = police()
    if not p then return false end
    local ok, res = pcall(function() return p:isOfficerOnDuty(player) end)
    return ok and res == true
end

local function isMedic(player)
    if not vsmResourceRunning(VSM.ERM) then return false end
    local ok, res = pcall(function() return exports[VSM.ERM]:getUnitData(player) end)
    return ok and res and true or false
end

-- nearest officer on duty within r of a point -> player, distance | nil
function Npc.nearestOfficer(x, y, z, r, dimension, interior)
    local best, bd
    for _, pl in ipairs(getElementsWithinRange(x, y, z, r, "player", interior, dimension)) do
        if Npc.isOfficer(pl) then
            local px, py, pz = getElementPosition(pl)
            local d = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
            if not bd or d < bd then best, bd = pl, d end
        end
    end
    return best, bd
end

local function surrender(scene, ped, officer)
    local A = ai()
    if not A or Npc.isSurrendered(ped) or Npc.isDown(ped) then return end
    setElementData(ped, "vsm.surrendered", true, false)
    pcall(function()
        A:setAIPedCombat(ped, { hostilePlayers = false, retaliate = false })
        A:setAIPedTarget(ped, false)
        A:setAIPedGroup(ped, group(scene, "s"))
        A:setAIPedBehaviour(ped, "detained", { officer = isElement(officer) and officer or nil })
    end)
    local anim = VSM.NPC.SURRENDER_ANIM
    setTimer(function()
        if isElement(ped) and not Npc.isDown(ped) and not Npc.isCuffed(ped) then
            setPedAnimation(ped, anim[1], anim[2], -1, false, false, false, true)
        end
    end, 300, 1)
    vsmLog("scene '%s' #%d: %s surrendered", scene.name, scene.id, tostring(scene.pedEntries[ped] and scene.pedEntries[ped].id))
end

local function flee(ped, officer)
    local A = ai()
    if not A or Npc.isDown(ped) or Npc.isCuffed(ped) then return end
    pcall(function()
        A:setAIPedCombat(ped, { hostilePlayers = false })
        A:setAIPedTarget(ped, false)
        A:setAIPedBehaviour(ped, "scared", { threat = officer })
    end)
end

local function stop(scene, ped, officer)
    local A = ai()
    if not A or Npc.isDown(ped) or Npc.isCuffed(ped) then return end
    pcall(function()
        A:setAIPedCombat(ped, { hostilePlayers = false })
        A:setAIPedTarget(ped, false)
        A:setAIPedGroup(ped, group(scene, "s"))
        A:setAIPedBehaviour(ped, "detained", { officer = officer })
    end)
end

addEvent("onAIPedDamaged")
addEventHandler("onAIPedDamaged", root, function(attacker)
    local id = getElementData(source, VSM.DATA_SCENE)
    local scene = id and Live.scenes[id]
    local entry = scene and scene.pedEntries[source]
    if not entry or entry.role ~= "hostile" then return end
    local limit = entry.ai and entry.ai.surrenderHealth or 0
    if limit > 0 and getElementHealth(source) <= limit then surrender(scene, source, attacker) end
end)

---------------------------------------------------------------- tick

local function anyUnitNear(scene, r)
    local c = scene.center
    for _, pl in ipairs(getElementsWithinRange(c[1], c[2], c[3], r, "player", scene.interior, scene.dimension)) do
        if Npc.isOfficer(pl) or isMedic(pl) then return true end
    end
    return false
end

local function tickScene(scene, st)
    if st.hasFight and not st.fightStarted then
        local r = 0
        for _, entry in pairs(scene.pedEntries) do
            if entry.role == "fighter" and entry.ai then r = math.max(r, entry.ai.startRadius or 0) end
        end
        if anyUnitNear(scene, r) then Npc.startFight(scene) end
    end
    for ped, entry in pairs(scene.pedEntries) do
        if isElement(ped) and not st.reacted[ped] and not Npc.isDown(ped) and not Npc.isCuffed(ped) then
            local a = entry.ai or {}
            local x, y, z = getElementPosition(ped)
            if entry.role == "fighter" and st.fightStarted and a.onPolice ~= "continue" then
                local officer = Npc.nearestOfficer(x, y, z, VSM.NPC.POLICE_REACT_RADIUS, scene.dimension, scene.interior)
                if officer then
                    st.reacted[ped] = true
                    if a.onPolice == "flee" then flee(ped, officer) else stop(scene, ped, officer) end
                end
            elseif (entry.role == "suspect" or entry.role == "hostile") and (a.flee or 0) > 0 and not st.fleeRolled[ped] then
                local radius = entry.role == "hostile" and (a.aggroRadius or 35) or VSM.NPC.FLEE_SEEN_RADIUS
                local officer = Npc.nearestOfficer(x, y, z, radius, scene.dimension, scene.interior)
                if officer then
                    st.fleeRolled[ped] = true
                    if random() < a.flee then
                        st.reacted[ped] = true
                        flee(ped, officer)
                    end
                end
            end
        end
    end
end

setTimer(function()
    for id, st in pairs(Npc.scenes) do
        local scene = Live.scenes[id]
        if scene then tickScene(scene, st) else Npc.scenes[id] = nil end
    end
end, VSM.NPC.TICK, 0)
