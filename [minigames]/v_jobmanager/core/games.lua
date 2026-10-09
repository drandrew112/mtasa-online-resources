-- Game loader. Every game (race / deathmatch) lives in its own JSON file under
-- games/ and is listed in games/index.json. The same file format is meant to be
-- produced by the future creator mode, so the structure is the contract:
--
--   id, name, type, createdBy, description, image, minPlayers, maxPlayers   (common)
--   marker = {x, y, z}                         optional - without it the game is
--                                              only reachable from the browser/phone/quickjob
--   objects    = [{model, x, y, z, rx?, ry?, rz?, scale?, alpha?, collisions?, doublesided?}]  optional,
--                                              spawned in the match dimension for every match
--   race       = {vehicles, spawnpoints, checkpoints, finish, finishCamera?}   (type "race")
--   deathmatch = {weapon, ammo, armour?, spawnpoints}                          (type "deathmatch")
--
-- Each mode validates its own block through JobModes[type].validate(game).

local INDEX_PATH = "games/index.json"

function readJson(path)
    if not fileExists(path) then return nil, "file not found" end
    local file = fileOpen(path, true)
    if not file then return nil, "cannot open" end
    local text = fileRead(file, fileGetSize(file))
    fileClose(file)
    local data = fromJSON(text)
    if data == nil then return nil, "invalid JSON" end
    return data
end

local function isPoint(p, n)
    if type(p) ~= "table" then return false end
    for i = 1, n do if type(p[i]) ~= "number" then return false end end
    return true
end

-- Helpers shared with the mode validators.
function validatePoints(list, n, minCount)
    if type(list) ~= "table" or #list < minCount then return false end
    for _, p in ipairs(list) do if not isPoint(p, n) then return false end end
    return true
end

local MAX_OBJECTS = 1000
COMMUNITY_MAX_OBJECTS = 300

local function validateObjects(list, maxObjects)
    if list == nil then return true end
    if type(list) ~= "table" or #list > maxObjects then return false, "objects must be a list of at most " .. maxObjects end
    for i, o in ipairs(list) do
        if type(o) ~= "table" or type(o.model) ~= "number" or not isPoint({ o.x, o.y, o.z }, 3) then
            return false, "objects[" .. i .. "] needs model, x, y, z"
        end
        for _, key in ipairs({ "rx", "ry", "rz", "scale", "alpha" }) do
            if o[key] ~= nil and type(o[key]) ~= "number" then return false, "objects[" .. i .. "]." .. key .. " must be a number" end
        end
        for _, key in ipairs({ "collisions", "doublesided" }) do
            if o[key] ~= nil and type(o[key]) ~= "boolean" then return false, "objects[" .. i .. "]." .. key .. " must be a boolean" end
        end
    end
    return true
end

-- `replacing` = the id may already be registered (a community game being re-published).
local function validateCommon(game, replacing)
    if type(game) ~= "table" then return false, "not an object" end
    if type(game.id) ~= "string" or game.id == "" then return false, "missing id" end
    if jobsById[game.id] and not replacing then return false, "duplicate id" end
    if type(game.name) ~= "string" or game.name == "" then return false, "missing name" end
    if type(game.createdBy) ~= "string" or game.createdBy == "" then return false, "missing createdBy" end
    if type(game.minPlayers) ~= "number" or type(game.maxPlayers) ~= "number"
        or game.minPlayers < 1 or game.maxPlayers < game.minPlayers then
        return false, "invalid minPlayers/maxPlayers"
    end
    if game.marker ~= nil and not isPoint(game.marker, 3) then return false, "invalid marker" end
    local okObjects, objErr = validateObjects(game.objects, game.community and COMMUNITY_MAX_OBJECTS or MAX_OBJECTS)
    if not okObjects then return false, objErr end
    local mode = JobModes and JobModes[game.type]
    if not mode then return false, "unknown type '" .. tostring(game.type) .. "'" end
    if mode.validate then
        local ok, err = mode.validate(game)
        if not ok then return false, err or "invalid game data" end
    end
    return true
end

-- Validation without registering (the creator's publish check).
function validateGame(game)
    return validateCommon(game, true)
end

-- Registers a game. A community game that is already registered is swapped in
-- place: running lobbies / matches keep their own reference to the old table,
-- only new lobbies get the new version.
function registerJob(game)
    local ok, err = validateCommon(game, game.community)
    if not ok then return false, err end
    local old = jobsById[game.id]
    jobsById[game.id] = game
    local replaced = false
    if old then
        for index, job in ipairs(jobs) do
            if job == old then jobs[index], replaced = game, true break end
        end
    end
    if not replaced then table.insert(jobs, game) end
    if onJobRegistered then onJobRegistered(game, old) end
    return true
end

function unregisterJob(id)
    local old = jobsById[id]
    if not old then return false end
    jobsById[id] = nil
    for index, job in ipairs(jobs) do
        if job == old then table.remove(jobs, index) break end
    end
    if onJobUnregistered then onJobUnregistered(old) end
    return true
end

function loadGames()
    local index, err = readJson(INDEX_PATH)
    if type(index) ~= "table" or type(index.games) ~= "table" then
        outputDebugString("[v_jobmanager] cannot read " .. INDEX_PATH .. ": " .. tostring(err or "no 'games' list"), 1)
        return
    end
    for _, id in ipairs(index.games) do
        local game, readErr = readJson("games/" .. tostring(id) .. ".json")
        local ok, regErr = false, readErr
        if game then ok, regErr = registerJob(game) end
        if not ok then
            outputDebugString("[v_jobmanager] game '" .. tostring(id) .. "' skipped: " .. tostring(regErr), 2)
        end
    end
    if loadCommunityGames then loadCommunityGames() end
    outputDebugString("[v_jobmanager] loaded " .. #jobs .. " games")
end
