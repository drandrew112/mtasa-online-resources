-- Rebuilds a game sent by a client from scratch: only known fields, clamped
-- numbers, catalog models, list limits. The result is in the v_jobmanager game
-- format (README "Game files"); id / createdBy / image are added by the storage.

local L = CREATOR.LIMITS

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
    if withExtra then out[4] = round(num(p[4], extraMin, extraMax) or extraDefault, 2) end
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

local function objects(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, o in ipairs(list) do
        if #out >= L.objects then break end
        local model = type(o) == "table" and tonumber(o.model)
        local pos = model and CATALOG.objectName[model] and point({ o.x, o.y, o.z })
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

-- marker: "keep" = take the client's value (admins), otherwise the given stored
-- marker (or nil) replaces whatever the client sent.
function sanitizeGame(doc, gameType, marker)
    if type(doc) ~= "table" then return nil end
    local maxPlayers = math.floor(num(doc.maxPlayers, 1, L.maxPlayers) or 8)
    local game = {
        name = text(doc.name, L.name, "Untitled"),
        type = gameType,
        description = text(doc.description, L.description, ""),
        minPlayers = math.min(math.floor(num(doc.minPlayers, 1, L.maxPlayers) or 1), maxPlayers),
        maxPlayers = maxPlayers,
        objects = objects(doc.objects),
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
            vehicles = { CATALOG.vehicleAllowed[vehicle] and vehicle or 411 },
            spawnpoints = points(race.spawnpoints, L.spawnpoints, true, -360, 360, 0),
            checkpoints = points(race.checkpoints, L.checkpoints, true, 2, 15, 5),
            finish = point(race.finish, true, 2, 15, 5),
        }
        local cam = race.finishCamera
        if type(cam) == "table" and point(cam.pos) and point(cam.lookAt) then
            game.race.finishCamera = { pos = point(cam.pos), lookAt = point(cam.lookAt), roll = 0, fov = round(num(cam.fov, 40, 120) or 70, 1) }
        end
    else
        local dm = type(doc.deathmatch) == "table" and doc.deathmatch or {}
        local weapon = tonumber(dm.weapon)
        game.deathmatch = {
            weapon = CATALOG.weaponAllowed[weapon] and weapon or 24,
            ammo = math.floor(num(dm.ammo, 1, 9999) or 120),
            armour = math.floor(num(dm.armour, 0, 100) or 0),
            spawnpoints = points(dm.spawnpoints, L.spawnpoints, true, -360, 360, 0),
        }
    end
    return game
end
