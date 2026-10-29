if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Mission entities: enemy / civilian peds ([ai]/ai_peds), vehicles (parked, loot, enemy with a
-- crew, chasing) and pick-up items ([player]/v_inventory). Everything lives in the match
-- dimension and is removed when the mission ends. ai_peds and v_inventory are soft
-- dependencies: without them peds stand still (plain GTA peds) and items cannot be taken.
--
-- state.ents = { peds = {id -> {el, def, dead, ai}}, vehicles = {id -> {el, def, driver, crewOut}},
--                items = {id -> {uid, def}} }

MissionEntities = {}

local BAIL_DISTANCE = 14        -- m: a chasing / ambushing crew gets out this close to its target
local AMBUSH_RADIUS = 45        -- m: a parked enemy crew gets out when a player comes this near

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

function MissionEntities.aiReady() return running("ai_peds") end
function MissionEntities.inventoryReady() return running("v_inventory") end

function MissionEntities.groups(match)
    return "jm_crew_" .. match.id, "jm_enemy_" .. match.id, "jm_civ_" .. match.id
end

-- nearest crew player (alive, in the match) to a point
function MissionEntities.nearestPlayer(match, x, y, z)
    local best, bestDist
    for _, player in ipairs(match.players) do
        if isElement(player) and not match.left[player] and not isPedDead(player) and not Spectate.isSpectating(match, player) then
            local px, py, pz = getElementPosition(player)
            local d = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
            if not bestDist or d < bestDist then best, bestDist = player, d end
        end
    end
    return best, bestDist
end

--------------------------------------------------------------------------------
-- peds
--------------------------------------------------------------------------------

local function plainPed(match, def, x, y, z, rot)
    local ped = createPed(def.skin or 0, x, y, z, rot or 0)
    if not ped then return nil end
    setElementDimension(ped, match.dimension)
    if def.weapon and def.weapon > 0 then giveWeaponToPed(ped, def.weapon, def.ammo or 100, true) end
    if def.health then setElementHealth(ped, def.health) end
    if def.armor and def.armor > 0 then setPedArmor(ped, def.armor) end
    return ped
end

-- def = a mission.peds entry; at = { x, y, z, rot } overrides its position (crew getting out)
function MissionEntities.spawnPed(match, def, at, target)
    local state = match.mission
    local _, enemyGroup, civGroup = MissionEntities.groups(match)
    local x, y, z, rot = def.x, def.y, def.z, def.rot or 0
    if at then x, y, z, rot = at[1], at[2], at[3], at[4] or rot end
    local civilian = def.behaviour == "civilian"
    local ped, ai
    if MissionEntities.aiReady() then
        local opts = {
            rot = rot, dimension = match.dimension, behaviour = civilian and "civilian" or "enemy",
            group = civilian and civGroup or enemyGroup, weapon = def.weapon, ammo = def.ammo or 300,
            health = def.health, armor = def.armor, accuracy = def.accuracy or 0.4,
            aggroRadius = def.aggroRadius or 35, leash = (def.aggroRadius or 35) * 2.5, role = "free",
            retaliate = true, fightBack = not civilian,
        }
        if def.behaviour == "patrol" and type(def.patrol) == "table" and #def.patrol >= 2 then
            local points = {}
            for i, p in ipairs(def.patrol) do points[i] = { x = p[1], y = p[2], z = p[3] } end
            opts.task, opts.taskOpts = "patrol", { points = points, loop = true, wait = { 1500, 4000 } }
        elseif civilian then
            opts.task, opts.taskOpts = "idle", {}
        else
            opts.task, opts.taskOpts = "guard", { x = x, y = y, z = z, rot = rot }
        end
        if def.behaviour == "attack" or target then
            opts.target = target or MissionEntities.nearestPlayer(match, x, y, z)
        end
        ped = exports.ai_peds:createAIPed(def.skin or 0, x, y, z, opts)
        ai = ped and true or false
    end
    if not ped then ped = plainPed(match, def, x, y, z, rot) end
    if not ped then return nil end
    setElementData(ped, "jobs.mission", match.id, false)
    return ped, ai
end

local function addPed(match, def)
    local ped, ai = MissionEntities.spawnPed(match, def)
    match.mission.ents.peds[def.id] = { el = ped, def = def, ai = ai, dead = ped == nil }
end

-- every extra crew member of a vehicle gets an ai_peds ped next to it
local function bailOut(match, entry)
    if entry.crewOut then return end
    entry.crewOut = true
    local veh = entry.el
    if not isElement(veh) then return end
    local def = entry.def
    local x, y, z = getElementPosition(veh)
    local _, _, rz = getElementRotation(veh)
    local target = MissionEntities.nearestPlayer(match, x, y, z)
    removeElementData(veh, "jobs.chase")
    -- the GTA driver becomes a fighting ped
    if isElement(entry.driver) then
        removePedFromVehicle(entry.driver)
        destroyElement(entry.driver)
        entry.driver = nil
    end
    local members = (def.crew or 0) + (def.driver and 1 or 0)
    local r = math.rad(rz)
    for i = 1, members do
        local side = (i % 2 == 1) and -1 or 1
        local back = math.floor((i - 1) / 2) * 1.6 - 0.8
        local ox, oy = math.cos(r) * 2.2 * side - math.sin(r) * back, math.sin(r) * 2.2 * side + math.cos(r) * back
        local pedDef = {
            id = def.id .. "_crew" .. i, skin = def.driver and def.driver.skin or 0,
            weapon = def.driver and def.driver.weapon or 28, ammo = 300, health = 100,
            accuracy = 0.4, aggroRadius = 50, behaviour = "attack",
        }
        local ped, ai = MissionEntities.spawnPed(match, pedDef, { x + ox, y + oy, z, rz }, target)
        if ped then
            match.mission.ents.peds[pedDef.id] = { el = ped, def = pedDef, ai = ai, dead = false, crewOf = def.id }
        end
    end
end

--------------------------------------------------------------------------------
-- vehicles
--------------------------------------------------------------------------------

local function addVehicle(match, def)
    local veh = createVehicle(def.model, def.x, def.y, def.z, 0, 0, def.rot or 0)
    if not veh then return end
    setElementDimension(veh, match.dimension)
    table.insert(match.vehicles, veh)
    if def.locked then setVehicleLocked(veh, true) end
    setElementData(veh, "jobs.mission", match.id, false)
    local entry = { el = veh, def = def }
    if def.role == "enemy" then
        local driverDef = def.driver or { skin = 0 }
        local driver = createPed(driverDef.skin or 0, def.x, def.y, def.z + 2, def.rot or 0)
        if driver then
            setElementDimension(driver, match.dimension)
            warpPedIntoVehicle(driver, veh)
            setElementData(driver, "jobs.mission", match.id, false)
            entry.driver = driver
        end
        setVehicleLocked(veh, true)
        if def.behaviour == "pursue" then
            entry.chase = true
            local target = MissionEntities.nearestPlayer(match, def.x, def.y, def.z)
            if target then setElementData(veh, "jobs.chase", target) end
        end
    end
    match.mission.ents.vehicles[def.id] = entry
end

-- 1 Hz from the runner: chasing targets, ambushes, crews getting out
function MissionEntities.tick(match)
    for _, entry in pairs(match.mission.ents.vehicles) do
        local veh, def = entry.el, entry.def
        if def.role == "enemy" and not entry.crewOut and isElement(veh) then
            local x, y, z = getElementPosition(veh)
            local target, dist = MissionEntities.nearestPlayer(match, x, y, z)
            if isVehicleBlown(veh) or not isElement(entry.driver) or isPedDead(entry.driver) then
                entry.crewOut = true
                removeElementData(veh, "jobs.chase")
            elseif target then
                if entry.chase then
                    if getElementData(veh, "jobs.chase") ~= target then setElementData(veh, "jobs.chase", target) end
                    local vx, vy, vz = getElementVelocity(veh)
                    local speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
                    entry.slowFor = (dist < BAIL_DISTANCE and speed < 12) and (entry.slowFor or 0) + 1 or 0
                    if entry.slowFor >= 3 or getElementHealth(veh) < 400 then bailOut(match, entry) end
                elseif dist < AMBUSH_RADIUS then
                    bailOut(match, entry)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- items
--------------------------------------------------------------------------------

local function addItem(match, def)
    local entry = { def = def }
    match.mission.ents.items[def.id] = entry
    if not MissionEntities.inventoryReady() then
        outputDebugString("[v_jobmanager] mission " .. match.job.id .. ": v_inventory is not running, item " .. def.id .. " cannot be taken", 2)
        return
    end
    local uid = exports.v_inventory:createItem(def.item, { mission = match.id, label = def.label }, { type = "none" })
    if not uid then return end
    exports.v_inventory:dropItem(uid, def.x, def.y, def.z, 0, match.dimension, 0)
    entry.uid = uid
end

-- -> carrier player | nil, and the item's x, y, z | nil
function MissionEntities.itemState(match, id)
    local entry = match.mission.ents.items[id]
    if not entry or not entry.uid or not MissionEntities.inventoryReady() then return nil end
    local info = exports.v_inventory:getItem(entry.uid)
    if not info then return nil end
    local carrier = info.loc and info.loc.type == "slot" and info.loc.player or nil
    local x, y, z = exports.v_inventory:getItemPosition(entry.uid)
    return carrier, x, y, z
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

-- spawns everything that appears at `stageId` (nil = mission start)
function MissionEntities.spawnFor(match, stageId)
    local m = match.job.mission
    for _, def in ipairs(m.peds or {}) do
        if def.stage == stageId and not match.mission.ents.peds[def.id] then addPed(match, def) end
    end
    for _, def in ipairs(m.vehicles or {}) do
        if def.stage == stageId and not match.mission.ents.vehicles[def.id] then addVehicle(match, def) end
    end
    for _, def in ipairs(m.items or {}) do
        if def.stage == stageId and not match.mission.ents.items[def.id] then addItem(match, def) end
    end
end

local function removePed(entry)
    if not isElement(entry.el) then return end
    if entry.ai and MissionEntities.aiReady() then
        exports.ai_peds:destroyAIPed(entry.el)
    end
    if isElement(entry.el) then destroyElement(entry.el) end
end

function MissionEntities.despawn(match, ids)
    local ents = match.mission.ents
    for _, id in ipairs(ids or {}) do
        if ents.peds[id] then removePed(ents.peds[id]) ents.peds[id].dead, ents.peds[id].removed = true, true end
        local veh = ents.vehicles[id]
        if veh then
            if isElement(veh.driver) then destroyElement(veh.driver) end
            if isElement(veh.el) then destroyElement(veh.el) end
            veh.removed = true
        end
        local item = ents.items[id]
        if item and item.uid and MissionEntities.inventoryReady() then
            exports.v_inventory:destroyInventoryItem(item.uid)
            item.uid, item.removed = nil, true
        end
    end
end

function MissionEntities.clear(match)
    local ents = match.mission and match.mission.ents
    if not ents then return end
    for _, entry in pairs(ents.peds) do removePed(entry) end
    for _, entry in pairs(ents.vehicles) do
        if isElement(entry.driver) then destroyElement(entry.driver) end
    end
    if MissionEntities.inventoryReady() then
        for _, entry in pairs(ents.items) do
            if entry.uid then exports.v_inventory:destroyInventoryItem(entry.uid) end
        end
    end
    match.mission.ents = { peds = {}, vehicles = {}, items = {} }
end

-- the mission's ped entry of an element
function MissionEntities.pedEntry(match, ped)
    for id, entry in pairs(match.mission.ents.peds) do
        if entry.el == ped then return entry, id end
    end
end
