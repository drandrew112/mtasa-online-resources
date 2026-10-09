-- Community games (made in v_jobcreator). Storage layout under games/community/:
--
--   index.json          { games = [ { id, name, type, owner, published, pending,
--                                     imageVersion, updated } ] }
--   private/<id>.json   the working copy, written by every Save (never loaded)
--   <id>.json           the live copy, written by Publish (loaded at start)
--   img/<id>.jpg        the thumbnail (640x360 JPEG)
--
-- Clients get thumbnails on demand: the game's `image` is "community_img/<id>_<v>.jpg",
-- a path inside this resource's client folder that core/client/images.lua downloads
-- into, so every `fileExists(image) or default` consumer (lobby, scoreboard,
-- ui_pause) just starts showing it once it has arrived.
--
-- Permissions are the caller's job (v_jobcreator); these exports trust their input.

local DIR = "games/community/"
local INDEX = DIR .. "index.json"
local MAX_IMAGE_BYTES = 400 * 1024

local index = { games = {} }

local function writeFile(path, data)
    if fileExists(path) then fileDelete(path) end
    local file = fileCreate(path)
    if not file then return false end
    fileWrite(file, data)
    fileClose(file)
    return true
end

local function readFile(path)
    if not fileExists(path) then return nil end
    local file = fileOpen(path, true)
    if not file then return nil end
    local data = fileRead(file, fileGetSize(file))
    fileClose(file)
    return data
end

local function writeJson(path, data)
    return writeFile(path, toJSON(data, false, "spaces"):sub(2, -2))
end

local function saveIndex()
    return writeJson(INDEX, index)
end

local function entryOf(id)
    for i, entry in ipairs(index.games) do
        if entry.id == id then return entry, i end
    end
end

local function imagePath(entry)
    return "community_img/" .. entry.id .. "_" .. (entry.imageVersion or 0) .. ".jpg"
end

-- The live copy, as the loader / clients see it.
local function prepareLive(game, entry)
    game.community = true
    game.createdBy = entry.owner
    game.image = (entry.imageVersion or 0) > 0 and imagePath(entry) or nil
    return game
end

function loadCommunityGames()
    local data = readJson(INDEX)
    if type(data) == "table" and type(data.games) == "table" then index = data end
    for _, entry in ipairs(index.games) do
        if entry.published then
            local game, err = readJson(DIR .. entry.id .. ".json")
            local ok = false
            if type(game) == "table" then ok, err = registerJob(prepareLive(game, entry)) end
            if not ok then
                outputDebugString("[v_jobmanager] community game '" .. tostring(entry.id) .. "' skipped: " .. tostring(err), 2)
            end
        end
    end
end

local function newId()
    local id
    repeat
        id = "c" .. getRealTime().timestamp .. math.random(100, 999)
    until not entryOf(id) and not jobsById[id]
    return id
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

-- List of index entries (copies). `owner` filters to one account.
function jobmanagerCommunityList(owner)
    local list = {}
    for _, entry in ipairs(index.games) do
        if not owner or entry.owner == owner then
            local copy = {}
            for k, v in pairs(entry) do copy[k] = v end
            list[#list + 1] = copy
        end
    end
    return list
end

-- The working copy (falls back to the live copy) + its index entry.
function jobmanagerCommunityLoad(id)
    local entry = entryOf(id)
    if not entry then return false, "not found" end
    local game = readJson(DIR .. "private/" .. id .. ".json") or readJson(DIR .. id .. ".json")
    if type(game) ~= "table" then return false, "cannot read" end
    game.id = id
    local copy = {}
    for k, v in pairs(entry) do copy[k] = v end
    return game, copy
end

-- Saves the working copy. `game.id` nil = new game (an id is assigned).
-- image: nil = keep, false = remove, string = new JPEG bytes.
-- Returns id, entry or false, error.
function jobmanagerCommunitySave(game, owner, image)
    if type(game) ~= "table" or type(owner) ~= "string" or owner == "" then return false, "bad arguments" end
    local entry = game.id and entryOf(game.id)
    if game.id and not entry then return false, "not found" end
    if not entry then
        entry = { id = newId(), owner = owner, published = false, pending = false, imageVersion = 0 }
        table.insert(index.games, entry)
    end
    game.id = entry.id
    game.createdBy = entry.owner
    game.community, game.image = nil, nil

    if image == false and (entry.imageVersion or 0) > 0 then
        if fileExists(DIR .. "img/" .. entry.id .. ".jpg") then fileDelete(DIR .. "img/" .. entry.id .. ".jpg") end
        entry.imageVersion = 0
    elseif type(image) == "string" then
        if #image > MAX_IMAGE_BYTES or image:sub(1, 2) ~= "\255\216" then return false, "invalid image" end
        if not writeFile(DIR .. "img/" .. entry.id .. ".jpg", image) then return false, "cannot write image" end
        entry.imageVersion = (entry.imageVersion or 0) + 1
    end

    if not writeJson(DIR .. "private/" .. entry.id .. ".json", game) then return false, "cannot write game" end
    entry.name, entry.type = game.name, game.type
    entry.updated = getRealTime().timestamp
    if entry.published then entry.pending = true end
    saveIndex()
    return entry.id, entry
end

-- Validates the working copy and makes it live (replacing the old live version).
function jobmanagerCommunityPublish(id)
    local entry = entryOf(id)
    if not entry then return false, "not found" end
    local game = readJson(DIR .. "private/" .. id .. ".json")
    if type(game) ~= "table" then return false, "no saved copy" end
    game.id = id
    local live = prepareLive(game, entry)
    local ok, err = validateGame(live)
    if not ok then return false, err end
    local stored = {}
    for k, v in pairs(game) do stored[k] = v end
    stored.community, stored.image = nil, nil
    if not writeJson(DIR .. id .. ".json", stored) then return false, "cannot write game" end
    ok, err = registerJob(live)
    if not ok then return false, err end
    entry.published, entry.pending = true, false
    saveIndex()
    return true
end

function jobmanagerCommunityUnpublish(id)
    local entry = entryOf(id)
    if not entry then return false, "not found" end
    if fileExists(DIR .. id .. ".json") then fileDelete(DIR .. id .. ".json") end
    unregisterJob(id)
    entry.published, entry.pending = false, false
    saveIndex()
    return true
end

function jobmanagerCommunityDelete(id)
    local entry, position = entryOf(id)
    if not entry then return false, "not found" end
    unregisterJob(id)
    for _, path in ipairs({ DIR .. id .. ".json", DIR .. "private/" .. id .. ".json", DIR .. "img/" .. id .. ".jpg" }) do
        if fileExists(path) then fileDelete(path) end
    end
    table.remove(index.games, position)
    saveIndex()
    return true
end

-- The full validator (spawnpoints vs maxPlayers, mode blocks ...) for the creator.
function jobmanagerValidateGame(game)
    if type(game) ~= "table" then return false, "not an object" end
    local copy = {}
    for k, v in pairs(game) do copy[k] = v end
    copy.id = copy.id or "draft"
    copy.createdBy = copy.createdBy or "?"
    copy.community = true
    return validateGame(copy)
end

-- Thumbnail bytes of a game (the creator shows the saved one while editing).
function jobmanagerCommunityImage(id)
    return readFile(DIR .. "img/" .. tostring(id) .. ".jpg") or false
end

--------------------------------------------------------------------------------
-- thumbnail download
--------------------------------------------------------------------------------

addEvent("jobmanager:requestImage", true)
addEventHandler("jobmanager:requestImage", resourceRoot, function(path)
    if type(path) ~= "string" then return end
    local id, version = path:match("^community_img/([%w]+)_(%d+)%.jpg$")
    local entry = id and entryOf(id)
    if not entry or tostring(entry.imageVersion) ~= version then return end
    local data = readFile(DIR .. "img/" .. id .. ".jpg")
    if data then triggerLatentClientEvent(client, "jobmanager:image", 200000, false, resourceRoot, path, data) end
end)

loadGames()
