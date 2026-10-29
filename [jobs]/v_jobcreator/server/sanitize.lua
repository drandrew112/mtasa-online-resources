if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Rebuilds a game sent by a client from scratch: only known fields, clamped
-- numbers, catalog models, list limits. The result is in the v_jobmanager game
-- format (README "Game files"); id / createdBy / image are added by the storage.

local LIM = CREATOR.LIMITS

local function num(v, min, max)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return math.max(min, math.min(max, v))
end

local function round(v, digits)
    local m = 10 ^ (digits or 3)
    return math.floor(v * m + 0.5) / m
end

-- {x, y, z[, extra]} inside the map; `extraMin/Max` clamp the 4th value
local function point(p, withExtra, extraMin, extraMax, extraDefault)
    if type(p) ~= "table" then return nil end
    local x, y, z = num(p[1], -3000, 3000), num(p[2], -3000, 3000), num(p[3], -100, 2000)
    if not (x and y and z) then return nil end
    local out = { round(x), round(y), round(z) }
    if withExtra then
        local extra = num(p[4], extraMin, extraMax) or extraDefault
        if extraMin < 0 then extra = extra % 360 end   -- rotations
        out[4] = round(extra, 2)
    end
    return out
end

local function points(list, max, withExtra, extraMin, extraMax, extraDefault)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, p in ipairs(list) do
        if #out >= max then break end
        local clean = point(p, withExtra, extraMin, extraMax, extraDefault)
        if clean then out[#out + 1] = clean end
    end
    return out
end

local function text(v, max, default)
    if type(v) ~= "string" then return default end
    v = v:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then return default end
    return utf8.sub(v, 1, max)
end

-- Official games (admin-only) may use any model and have bigger limits,
-- like the hand-written games/*.json files.
local OFFICIAL = { objects = 1000, checkpoints = 300 }

local function objectAllowed(model, official)
    if official then return model >= 321 and model <= 20000 and math.floor(model) == model end
    return CATALOG.objectName[model] ~= nil
end

local function objects(list, official)
    local out = {}
    if type(list) ~= "table" then return out end
    local max = official and OFFICIAL.objects or LIM.objects
    for _, o in ipairs(list) do
        if #out >= max then break end
        local model = type(o) == "table" and tonumber(o.model)
        local pos = model and objectAllowed(model, official) and point({ o.x, o.y, o.z })
        if pos then
            local clean = { model = model, x = pos[1], y = pos[2], z = pos[3] }
            for _, key in ipairs({ "rx", "ry", "rz" }) do
                local r = num(o[key], -360, 360)
                if r and r ~= 0 then clean[key] = round(r, 2) end
            end
            local scale = num(o.scale, 0.2, 3)
            if scale and scale ~= 1 then clean.scale = round(scale, 2) end
            local alpha = num(o.alpha, 0, 255)
            if alpha and alpha < 255 then clean.alpha = math.floor(alpha) end
            if o.collisions == false then clean.collisions = false end
            if o.doublesided == true then clean.doublesided = true end
            out[#out + 1] = clean
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- missions (v_jobmanager mode_mission; the references are checked by its validator)
--------------------------------------------------------------------------------

local function ident(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[^%w_]", "")
    if v == "" then return nil end
    return v:sub(1, 24)
end

local function oneOf(v, list, default)
    for _, x in ipairs(list) do if x == v then return v end end
    return default
end

local function vehicleOk(model, official)
    return model and (CATALOG.vehicleAllowed[model] or (official and model >= 400 and model <= 611))
end

local function weaponOk(id, official)
    return id and (CATALOG.weaponAllowed[id] or (official and id >= 1 and id <= 46))
end

-- list of entities with a unique id each; fn(entry, clean) fills the rest, returns false to drop it
local function entities(list, max, fn)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if #out >= max then break end
        local id = type(e) == "table" and ident(e.id)
        local pos = id and not seen[id] and point({ e.x, e.y, e.z })
        if pos then
            local clean = { id = id, x = pos[1], y = pos[2], z = pos[3] }
            local stage = ident(e.stage)
            if stage then clean.stage = stage end
            if fn(e, clean) ~= false then
                seen[id] = true
                out[#out + 1] = clean
            end
        end
    end
    return out
end

local function objective(o, fail, official)
    if type(o) ~= "table" then return nil end
    local types = fail and CATALOG.failTypes or CATALOG.objectiveTypes
    local t = oneOf(o.type, types, nil)
    if not t then return nil end
    local clean = { type = t }
    for _, key in ipairs({ "zone", "vehicle", "item", "point", "ped" }) do
        local v = ident(o[key])
        if v then clean[key] = v end
    end
    if o.who == "all" then clean.who = "all" end
    if t == "stayInZone" or t == "survive" then clean.seconds = math.floor(num(o.seconds, 5, 3600) or 30) end
    if t == "killPeds" then
        if o.all == true then
            clean.all = true
        else
            clean.peds = {}
            for _, id in ipairs(type(o.peds) == "table" and o.peds or {}) do
                local v = ident(id)
                if v and #clean.peds < 40 then clean.peds[#clean.peds + 1] = v end
            end
        end
    end
    if t == "scriptEvent" then clean.name = ident(o.name) or "signal" end
    local label = text(o.label, 60, nil)
    if label then clean.label = label end
    return clean
end

local function missionBlock(doc, official)
    local m = type(doc.mission) == "table" and doc.mission or {}
    local LM = official and CREATOR.OFFICIAL_MISSION or LIM.mission
    local out = {
        spawnpoints = points(m.spawnpoints, LIM.spawnpoints, true, -360, 360, 0),
        teamLives = math.floor(num(m.teamLives, 0, 20) or 3),
        armour = math.floor(num(m.armour, 0, 100) or 0),
        loadout = {},
    }
    local timeLimit = num(m.timeLimit, 0, 7200)
    if timeLimit and timeLimit >= 10 then out.timeLimit = math.floor(timeLimit) end
    if type(m.reward) == "table" then
        local money, xp = num(m.reward.money, 0, official and 1000000 or 100000), num(m.reward.xp, 0, official and 50000 or 8000)
        if money and xp and (money > 0 or xp > 0) then out.reward = { money = math.floor(money), xp = math.floor(xp) } end
    end
    for _, w in ipairs(type(m.loadout) == "table" and m.loadout or {}) do
        local id = type(w) == "table" and tonumber(w.id)
        if #out.loadout < 4 and weaponOk(id, official) then
            out.loadout[#out.loadout + 1] = { id = id, ammo = math.floor(num(w.ammo, 1, 9999) or 300) }
        end
    end

    out.zones = entities(m.zones, LM.zones, function(e, c)
        c.radius = round(num(e.radius, 1, 200) or 8, 1)
        c.height = round(num(e.height, 1, 100) or 8, 1)
    end)
    out.peds = entities(m.peds, LM.peds, function(e, c)
        c.skin = math.floor(num(e.skin, 0, 312) or 0)
        c.rot = round(num(e.rot, -360, 360) or 0, 1) % 360
        local weapon = tonumber(e.weapon)
        if weaponOk(weapon, official) then c.weapon, c.ammo = weapon, math.floor(num(e.ammo, 1, 9999) or 300) end
        c.health = math.floor(num(e.health, 1, 1000) or 100)
        c.armor = math.floor(num(e.armor, 0, 100) or 0)
        c.accuracy = round(num(e.accuracy, 0, 1) or 0.4, 2)
        c.aggroRadius = math.floor(num(e.aggroRadius, 5, 150) or 35)
        c.behaviour = oneOf(e.behaviour, CATALOG.pedBehaviours, "guard")
        if c.behaviour == "patrol" then
            c.patrol = points(e.patrol, LM.patrol, false)
            if #c.patrol < 2 then c.behaviour, c.patrol = "guard", nil end
        end
    end)
    out.vehicles = entities(m.vehicles, LM.vehicles, function(e, c)
        local model = tonumber(e.model)
        if not vehicleOk(model, official) then return false end
        c.model = model
        c.rot = round(num(e.rot, -360, 360) or 0, 1) % 360
        c.role = oneOf(e.role, CATALOG.vehicleRoles, "loot")
        if e.locked == true then c.locked = true end
        if c.role == "enemy" then
            c.behaviour = e.behaviour == "pursue" and "pursue" or "park"
            local d = type(e.driver) == "table" and e.driver or {}
            local weapon = tonumber(d.weapon)
            c.driver = { skin = math.floor(num(d.skin, 0, 312) or 0), weapon = weaponOk(weapon, official) and weapon or 28 }
            c.crew = math.floor(num(e.crew, 0, 3) or 1)
        end
    end)
    out.items = entities(m.items, LM.items, function(e, c)
        if not CATALOG.missionItem[e.item] then return false end
        c.item = e.item
        c.label = text(e.label, 40, nil)
    end)
    out.points = entities(m.points, LM.points, function(e, c)
        c.label = text(e.label, 40, nil)
        c.holdMs = math.floor((num(e.holdMs, 500, 20000) or 3000) / 100) * 100
    end)

    out.stages = {}
    local seen = {}
    for _, s in ipairs(type(m.stages) == "table" and m.stages or {}) do
        if #out.stages >= LM.stages then break end
        local id = type(s) == "table" and ident(s.id)
        if id and not seen[id] then
            seen[id] = true
            local stage = { id = id, title = text(s.title, 80, "Stage"), objectives = {} }
            for _, o in ipairs(type(s.objectives) == "table" and s.objectives or {}) do
                local clean = #stage.objectives < LM.objectives and objective(o, false, official)
                if clean then stage.objectives[#stage.objectives + 1] = clean end
            end
            local fails = {}
            for _, f in ipairs(type(s.fail) == "table" and s.fail or {}) do
                local clean = #fails < LM.fails and objective(f, true, official)
                if clean then fails[#fails + 1] = clean end
            end
            if #fails > 0 then stage.fail = fails end
            if s.complete == "any" then stage.complete = "any" end
            local limit = num(s.timeLimit, 0, 3600)
            if limit and limit >= 5 then stage.timeLimit = math.floor(limit) end
            local respawn = point(s.respawnPoint, true, -360, 360, 0)
            if respawn then stage.respawnPoint = respawn end
            local despawn = {}
            for _, eid in ipairs(type(s.despawn) == "table" and s.despawn or {}) do
                local v = ident(eid)
                if v and #despawn < 40 then despawn[#despawn + 1] = v end
            end
            if #despawn > 0 then stage.despawn = despawn end
            local nextId = ident(s.next)
            if nextId then stage.next = nextId end
            out.stages[#out.stages + 1] = stage
        end
    end
    return out
end

-- marker: "keep" = take the client's value (admins), otherwise the given stored
-- marker (or nil) replaces whatever the client sent.
-- official: an official game edited by an admin (any model, bigger limits)
-- scriptOk: the player may make scriptOnly missions (CREATOR.OFFICIAL_LEVEL)
function sanitizeGame(doc, gameType, marker, official, scriptOk)
    if type(doc) ~= "table" then return nil end
    local maxPlayers = math.floor(num(doc.maxPlayers, 1, LIM.maxPlayers) or 8)
    local game = {
        name = text(doc.name, LIM.name, L.msg("v_jobcreator.sanitize.untitled")),
        type = gameType,
        description = text(doc.description, LIM.description, ""),
        minPlayers = math.min(math.floor(num(doc.minPlayers, 1, LIM.maxPlayers) or 1), maxPlayers),
        maxPlayers = maxPlayers,
        objects = objects(doc.objects, official),
    }
    if marker == "keep" then
        game.marker = point(doc.marker)
    elseif type(marker) == "table" then
        game.marker = point(marker)
    end

    if gameType == "race" then
        local race = type(doc.race) == "table" and doc.race or {}
        local vehicle = type(race.vehicles) == "table" and tonumber(race.vehicles[1])
        game.race = {
            vehicles = { (CATALOG.vehicleAllowed[vehicle] or (official and vehicle and vehicle >= 400 and vehicle <= 611)) and vehicle or 411 },
            spawnpoints = points(race.spawnpoints, LIM.spawnpoints, true, -360, 360, 0),
            checkpoints = points(race.checkpoints, official and OFFICIAL.checkpoints or LIM.checkpoints, true, 2, 15, 5),
            finish = point(race.finish, true, 2, 15, 5),
        }
        local cam = race.finishCamera
        if type(cam) == "table" and point(cam.pos) and point(cam.lookAt) then
            game.race.finishCamera = { pos = point(cam.pos), lookAt = point(cam.lookAt), roll = 0, fov = round(num(cam.fov, 40, 120) or 70, 1) }
        end
        if race.offRoute ~= nil then game.race.offRoute = oneOf(tonumber(race.offRoute), CATALOG.offRoute, nil) end
    elseif gameType == "mission" then
        game.mission = missionBlock(doc, official or scriptOk)
        -- scriptOnly missions are official games that only other resources start
        if doc.scriptOnly == true and scriptOk then game.scriptOnly = true end
    else
        local dm = type(doc.deathmatch) == "table" and doc.deathmatch or {}
        local weapon = tonumber(dm.weapon)
        game.deathmatch = {
            weapon = (CATALOG.weaponAllowed[weapon] or (official and weapon and weapon >= 1 and weapon <= 46)) and weapon or 24,
            ammo = math.floor(num(dm.ammo, 1, 9999) or 120),
            armour = math.floor(num(dm.armour, 0, 100) or 0),
            spawnpoints = points(dm.spawnpoints, LIM.spawnpoints, true, -360, 360, 0),
        }
    end
    return game
end
