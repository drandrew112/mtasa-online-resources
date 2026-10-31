-- Scripted peds (server exports): other resources (first: the gang war minigame) create peds and give them a
-- behaviour, a task, a group, weapons. They are never culled; they stand still while no player is near enough to
-- sync them (MTA ped_syncer_distance). See README.md for the reference.

local T = AIPEDS

local function getP(ped)
    return isElement(ped) and Peds.list[ped] or nil
end

local TASK_NAMES = { idle = true, wander = true, ["goto"] = true, patrol = true, guard = true, follow = true }
local BEHAVIOURS = { civilian = true, scared = true, enemy = true, police = true, detained = true, cuffed = true, patient = true }

-- createAIPed(skin, x, y, z, opts) -> ped | false, reason
-- opts: rot, dimension, interior, behaviour ("civilian" default | "scared" | "enemy"), task (name), taskOpts,
--       group, weapon, ammo, health, armor, accuracy (0..1), aggroRadius, leash, home ({x, y, z}; default: spawn point
--       for enemies with a patrol / guard task), retaliate (true), role (navmesh route role, "civilian" / "free"...),
--       speed ("walk" | "run" | "sprint": task moves), keepBody, target (enemy: attack now), fightBack (civilian)
function createAIPed(skin, x, y, z, opts)
    opts = type(opts) == "table" and opts or {}
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return false, "bad_position" end
    local beh = opts.behaviour or "civilian"
    if not BEHAVIOURS[beh] then return false, "unknown_behaviour" end
    if opts.task and not TASK_NAMES[opts.task] then return false, "unknown_task" end
    local p = Peds.create(tonumber(skin) or Peds.randomSkin(), x, y, z, "scripted", {
        rot = opts.rot, dimension = opts.dimension, interior = opts.interior, group = opts.group, role = opts.role,
        speed = opts.speed, aggroRadius = opts.aggroRadius, leash = opts.leash, accuracy = opts.accuracy,
        retaliate = opts.retaliate, home = opts.home,
    })
    if not p then return false, "create_failed" end
    p.keepBody = opts.keepBody and true or false
    if opts.health then setElementHealth(p.el, opts.health) end
    if opts.armor then setPedArmor(p.el, opts.armor) end
    if opts.weapon then Peds.giveWeapon(p, opts.weapon, opts.ammo) end
    if opts.task then
        p.task = opts.taskOpts or {}
        p.task.name = opts.task
    else
        p.task = { name = "idle" }
    end
    if beh == "enemy" and not p.combat.home and (p.task.name == "patrol" or p.task.name == "guard") then
        local t = p.task
        p.combat.home = { t.x or x, t.y or y, t.z or z }
    end
    Peds.setBehaviour(p, beh, { target = opts.target, fightBack = opts.fightBack })
    return p.el
end

function destroyAIPed(ped)
    local p = getP(ped)
    if not p then return false end
    Peds.remove(p, "export", not p.own)
    return true
end

-- "traffic" | "driver" | "scripted" | false
function isAIPed(ped)
    local p = getP(ped)
    return p and p.kind or false
end

function getAIPeds(kind)
    local out = {}
    for el, p in pairs(Peds.list) do
        if not kind or p.kind == kind then out[#out + 1] = el end
    end
    return out
end

-- setAIPedBehaviour(ped, "civilian" | "scared" | "enemy", args): args as the behaviour takes them
-- (civilian: task, taskOpts; scared: threat, x, y, z; enemy: target)
function setAIPedBehaviour(ped, name, args)
    local p = getP(ped)
    if not p or p.dead or not BEHAVIOURS[name] then return false end
    args = type(args) == "table" and args or {}
    if args.task and not TASK_NAMES[args.task] then return false end
    return Peds.setBehaviour(p, name, args)
end

function getAIPedBehaviour(ped)
    local p = getP(ped)
    if not p then return false end
    return p.behaviour, p.b and p.b.mode or false
end

-- setAIPedTask(ped, name, opts): the calm activity (see server/tasks.lua). A civilian / calm enemy starts it now;
-- a fighting or scared ped takes it up afterwards.
function setAIPedTask(ped, name, opts)
    local p = getP(ped)
    if not p or p.dead or not TASK_NAMES[name] then return false end
    opts = type(opts) == "table" and opts or {}
    opts.name = name
    p.task = opts
    if p.behaviour == "enemy" and opts.home ~= false and (name == "patrol" or name == "guard") and opts.x then
        p.combat.home = { opts.x, opts.y, opts.z }
    end
    if p.behaviour == "civilian" or (p.behaviour == "enemy" and p.b.mode ~= "engage") then Tasks.run(p) end
    return true
end

function getAIPedTask(ped)
    local p = getP(ped)
    return p and p.task and p.task.name or false
end

-- shorthand: setAIPedTask(ped, "goto", {x, y, z, ...})
function aiPedGoTo(ped, x, y, z, opts)
    opts = type(opts) == "table" and opts or {}
    opts.x, opts.y, opts.z = tonumber(x), tonumber(y), tonumber(z)
    if not opts.x then return false end
    return setAIPedTask(ped, "goto", opts)
end

-- attack this element now (makes the ped an enemy; false: stop attacking)
function setAIPedTarget(ped, target)
    local p = getP(ped)
    if not p or p.dead then return false end
    if not target then
        Behaviours.enemy.disengage(p)
        return true
    end
    if not Peds.alive(target) then return false end
    Groups.grudge(p, target, 24 * 3600 * 1000)
    if p.behaviour == "enemy" then Behaviours.enemy.engage(p, target)
    else Peds.setBehaviour(p, "enemy", { target = target }) end
    return true
end

function getAIPedTarget(ped)
    local p = getP(ped)
    return p and Behaviours.enemy.target(p) or false
end

function setAIPedGroup(ped, group)
    local p = getP(ped)
    if not p or type(group) ~= "string" then return false end
    p.group = group
    return true
end

function getAIPedGroup(ped)
    local p = getP(ped)
    return p and p.group or false
end

-- relation between two groups: "hostile" | "neutral" | "friendly" (mutual unless mutual == false)
function setAIGroupRelation(a, b, rel, mutual)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if rel ~= "hostile" and rel ~= "neutral" and rel ~= "friendly" then return false end
    Groups.set(a, b, rel, mutual)
    return true
end

function getAIGroupRelation(a, b) return Groups.get(a, b) end

-- the group a player counts in for the AI peds (nil / false: back to "player")
function setPlayerAIGroup(player, group)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    Groups.players[player] = type(group) == "string" and group or nil
    return true
end

function getPlayerAIGroup(player) return isElement(player) and Groups.of(player) or false end

function giveAIPedWeapon(ped, weapon, ammo)
    local p = getP(ped)
    if not p or p.dead then return false end
    Peds.giveWeapon(p, weapon, ammo)
    if p.behaviour == "enemy" and p.b.target then Behaviours.enemy.engage(p, p.b.target) end   -- new range
    return true
end

-- combat settings: { aggroRadius, leash, accuracy, retaliate, home = {x, y, z} | false }
function setAIPedCombat(ped, opts)
    local p = getP(ped)
    if not p or type(opts) ~= "table" then return false end
    local c = p.combat
    if opts.aggroRadius then c.aggro = tonumber(opts.aggroRadius) or c.aggro end
    if opts.leash then c.leash = tonumber(opts.leash) or c.leash end
    if opts.accuracy then c.accuracy = math.max(0, math.min(1, tonumber(opts.accuracy) or c.accuracy)) end
    if opts.retaliate ~= nil then c.retaliate = opts.retaliate and true or false end
    if opts.home == false then c.home = nil elseif type(opts.home) == "table" then c.home = opts.home end
    return true
end

function getAIPedState(ped)
    local p = getP(ped)
    if not p then return false end
    local t = p.behaviour == "enemy" and p.b.target or nil
    return {
        kind = p.kind, behaviour = p.behaviour, mode = p.b and p.b.mode or false, task = p.task and p.task.name or false,
        group = p.group, weapon = p.weapon, target = t or false, syncer = p.syncer or false, dead = p.dead or false,
        command = p.cmd.m, x = p.x, y = p.y, z = p.z, combat = p.combat,
    }
end

-- ai_land_traffic hands its drivers over (server/drivers.lua)
function adoptTrafficDriver(ped, veh, opts)
    return Drivers.adopt(ped, veh, type(opts) == "table" and opts or {})
end

function setAIPedTrafficEnabled(on)
    PedTraffic.enabled = on and true or false
    if not PedTraffic.enabled then PedTraffic.clear() end
    return true
end

function isAIPedTrafficEnabled() return PedTraffic.enabled end

function getAIPedStats() return AIPedsMain.stats() end

-- isPointSeenByPlayers(x, y, z [, maxDist [, dimension]]) -> bool: does the camera of any player (in that dimension,
-- within maxDist of the point) look towards it? Same test as the walker culling (Views.playerSees: view cone, no line
-- of sight; a player without a fresh camera report counts as seeing). Used by the gang war to remove peds unseen.
function isPointSeenByPlayers(x, y, z, maxDist, dimension)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return false end
    maxDist = tonumber(maxDist)
    local now = getTickCount()
    for _, pl in ipairs(getElementsByType("player")) do
        if not dimension or getElementDimension(pl) == dimension then
            local px, py = getElementPosition(pl)
            local v = Views.list[pl]
            local cx, cy = v and v.x or px, v and v.y or py
            if not maxDist or (cx - x) ^ 2 + (cy - y) ^ 2 < maxDist * maxDist then
                if Views.playerSees(pl, x, y, z, now) then return true end
            end
        end
    end
    return false
end

------------------------------------------------------------------------ police work (server/behaviours/police.lua, server/vehicles.lua)

-- the ped gets into veh at seat (0 = driver) with the enter animation (placed there after VEH_TASK_TIMEOUT).
-- Events onAIPedEnteredVehicle(veh, seat) / onAIPedVehicleTaskFailed("enter", reason)
function aiPedEnterVehicle(ped, veh, seat)
    local p = getP(ped)
    if not p or p.dead or not isElement(veh) or getElementType(veh) ~= "vehicle" then return false end
    return VehTasks.enter(p, veh, seat)
end

-- the ped gets out of its vehicle (exit animation). Event onAIPedExitedVehicle(veh)
function aiPedExitVehicle(ped)
    local p = getP(ped)
    if not p or p.dead then return false end
    return VehTasks.exit(p)
end

-- keep = true: never culled (walkers / drivers the police stopped); false: back to normal
function setAIPedKeep(ped, keep)
    local p = getP(ped)
    if not p then return false end
    p.keep = keep and true or nil
    return true
end
