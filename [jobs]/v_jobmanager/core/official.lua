-- Editing the official games (games/<id>.json, listed in games/index.json) from
-- v_jobcreator. Only admins get here (the creator checks the rights).
--
--   games/drafts/<id>.json   saved but not live yet (never loaded)
--   games/<id>.json          the live game; Publish overwrites it and re-registers
--   games/img/<id>.jpg       a thumbnail taken in the creator; the game's image
--                            becomes "community_img/<id>_<v>.jpg" (see core/client/images.lua)

local DRAFTS = "games/drafts/"
local MAX_IMAGE_BYTES = 400 * 1024

local function writeFile(path, data)
    if fileExists(path) then fileDelete(path) end
    local file = fileCreate(path)
    if not file then return false end
    fileWrite(file, data)
    fileClose(file)
    return true
end

local function writeJson(path, data)
    return writeFile(path, toJSON(data, false, "spaces"):sub(2, -2))
end

local function officialIds()
    local index = readJson("games/index.json")
    local ids = {}
    for _, id in ipairs(type(index) == "table" and type(index.games) == "table" and index.games or {}) do
        ids[#ids + 1] = tostring(id)
    end
    return ids
end

local function isOfficial(id)
    for _, other in ipairs(officialIds()) do
        if other == id then return true end
    end
    return false
end

-- the newest copy: draft first, then the live file
local function current(id)
    return readJson(DRAFTS .. id .. ".json") or readJson("games/" .. id .. ".json")
end

function officialImagePath(id)
    if isOfficial(id) and fileExists("games/img/" .. id .. ".jpg") then return "games/img/" .. id .. ".jpg" end
end

-- { id, name, type, owner, official = true, published = true, pending = has a draft, imageVersion }
function jobmanagerOfficialList()
    local list = {}
    for _, id in ipairs(officialIds()) do
        local game = current(id)
        if type(game) == "table" then
            list[#list + 1] = {
                id = id, name = game.name, type = game.type, owner = game.createdBy, official = true,
                published = true, pending = fileExists(DRAFTS .. id .. ".json"),
                imageVersion = fileExists("games/img/" .. id .. ".jpg") and 1 or 0,
            }
        end
    end
    return list
end

function jobmanagerOfficialLoad(id)
    if not isOfficial(id) then return false, "not found" end
    local game = current(id)
    if type(game) ~= "table" then return false, "cannot read" end
    game.id = id
    return game
end

function jobmanagerOfficialImage(id)
    local path = officialImagePath(id)
    if not path then return false end
    local file = fileOpen(path, true)
    if not file then return false end
    local data = fileRead(file, fileGetSize(file))
    fileClose(file)
    return data
end

-- Writes the draft. Fields the creator does not edit (id, createdBy, image) are
-- kept from the current copy. image: nil = keep, false = remove, string = JPEG.
function jobmanagerOfficialSave(game, image)
    if type(game) ~= "table" or not isOfficial(game.id) then return false, "not found" end
    local id = game.id
    local old = current(id) or {}
    game.createdBy = old.createdBy or "DrAndrew112"
    game.image = old.image
    game.community = nil

    if image == false then
        if fileExists("games/img/" .. id .. ".jpg") then fileDelete("games/img/" .. id .. ".jpg") end
        game.image = fileExists("assets/jobs/" .. id .. ".jpg") and ("assets/jobs/" .. id .. ".jpg") or nil
    elseif type(image) == "string" then
        if #image > MAX_IMAGE_BYTES or image:sub(1, 2) ~= "\255\216" then return false, "invalid image" end
        if not writeFile("games/img/" .. id .. ".jpg", image) then return false, "cannot write image" end
        local version = tonumber(tostring(old.image or ""):match("^community_img/.+_(%d+)%.jpg$")) or 0
        game.image = "community_img/" .. id .. "_" .. (version + 1) .. ".jpg"
    end

    if not writeJson(DRAFTS .. id .. ".json", game) then return false, "cannot write game" end
    return id
end

-- Draft -> live file + live registration (running lobbies keep the old version).
function jobmanagerOfficialPublish(id)
    if not isOfficial(id) then return false, "not found" end
    local game = readJson(DRAFTS .. id .. ".json")
    if type(game) ~= "table" then return true end  -- nothing pending
    game.id = id
    local ok, err = validateGame(game)
    if not ok then return false, err end
    if not writeJson("games/" .. id .. ".json", game) then return false, "cannot write game" end
    ok, err = registerJob(game, true)
    if not ok then return false, err end
    fileDelete(DRAFTS .. id .. ".json")
    return true
end
