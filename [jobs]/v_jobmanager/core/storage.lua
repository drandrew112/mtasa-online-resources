-- Game storage in MySQL (v_mysql). Three tables with (almost) the same columns:
--
--   jobs_official    live official games (the server's own)
--   jobs_community   live community games (player made, published by an admin)
--   jobs_draft       working copies: every creator Save writes here, a draft is
--                    never loaded as a game. A draft next to a live row = unpublished
--                    changes; a draft alone = a private (or unpublished) game.
--
--   id, name, type, created_by, data (the game JSON without id / createdBy /
--   community / image), image (base64 JPEG thumbnail; without one clients show
--   assets/jobs/default.jpg), image_version, created_at, updated_at
--   + jobs_official / jobs_community: published_by
--   + jobs_draft: target ('official' | 'community' - the table Publish writes)
--   jobs_draft.image: NULL = same as the live copy, '' = removed, else the new photo.
--
-- Every row is cached here without its image; thumbnails are read on demand.
-- Writes change the cache at once and go to the database in order (async), so the
-- exports below answer right away. The tables are shared by every server instance:
-- SYNC_INTERVAL polls updated_at and reloads what another instance changed.
--
-- Clients get thumbnails on demand: the game's `image` is "community_img/<id>_<v>.jpg",
-- a path inside this resource's client folder that core/client/images.lua downloads
-- into, so every `fileExists(image) or default` consumer (lobby, scoreboard,
-- ui_pause) just starts showing it once it has arrived.
--
-- Permissions are the caller's job (v_jobcreator); these exports trust their input.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

local TABLES = { official = "jobs_official", community = "jobs_community", draft = "jobs_draft" }
local MAX_IMAGE_BYTES = 400 * 1024
local SYNC_INTERVAL = 30000

-- rows[kind][id] = { id, name, type, owner, data, imageVersion, imageState, publishedBy,
--                    target, created, updated }
-- imageState: "none" | "set" | "removed" (draft only: "none" = same as the live copy)
local rows = { official = {}, community = {}, draft = {} }
local loaded = false
local busy = {}         -- id -> writes in flight (the sync leaves these rows alone)
local imageCache = {}   -- "<kind>:<id>" -> { version, bytes }

local COLUMNS = [[
    id VARCHAR(64) NOT NULL PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    type VARCHAR(16) NOT NULL,
    created_by VARCHAR(50) NOT NULL,
    %s
    data MEDIUMTEXT NOT NULL,
    image MEDIUMTEXT NULL,
    image_version INT NOT NULL DEFAULT 0,
    created_at INT NOT NULL DEFAULT 0,
    updated_at INT NOT NULL DEFAULT 0,
    KEY idx_created_by (created_by)
]]

local function ensureTables()
    for kind, name in pairs(TABLES) do
        local extra = kind == "draft" and "target VARCHAR(16) NOT NULL DEFAULT 'community',"
            or "published_by VARCHAR(50) DEFAULT NULL,"
        exports.v_mysql:mysqlExec(("CREATE TABLE IF NOT EXISTS %s (%s) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
            :format(name, COLUMNS:format(extra)))
    end
end

local function log(text, level)
    outputDebugString("[v_jobmanager] " .. text, level or 3)
end

local function encode(data)
    return toJSON(data, true):sub(2, -2)
end

local function copyTable(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copyTable(v) end
    return out
end

local function now() return getRealTime().timestamp end

--------------------------------------------------------------------------------
-- writes: steps run one after the other, the next only when the previous succeeded
--------------------------------------------------------------------------------

-- step = { sql, arg1, arg2, ... }  (no nil arguments: NULL is written into the SQL)
local function persist(id, steps)
    busy[id] = (busy[id] or 0) + 1
    local i = 0
    local function nextStep()
        i = i + 1
        local step = steps[i]
        if not step then
            busy[id] = busy[id] - 1
            if busy[id] <= 0 then busy[id] = nil end
            return
        end
        MYSQL.query(function(result, err)
            if result == false then
                log("saving game '" .. id .. "' failed (step " .. i .. "): " .. tostring(err), 1)
                busy[id] = busy[id] - 1
                if busy[id] <= 0 then busy[id] = nil end
                return
            end
            nextStep()
        end, unpack(step))
    end
    nextStep()
end

--------------------------------------------------------------------------------
-- entries + live games
--------------------------------------------------------------------------------

local function liveOf(id)
    if rows.official[id] then return rows.official[id], "official" end
    if rows.community[id] then return rows.community[id], "community" end
end

-- { id, name, type, owner, official, published, pending, imageVersion, updated }
local function entryOf(id)
    local live, kind = liveOf(id)
    local draft = rows.draft[id]
    local base = draft or live
    if not base then return nil end
    return {
        id = id, name = base.name, type = base.type, owner = base.owner,
        official = (kind or draft.target) == "official",
        published = live ~= nil, pending = live ~= nil and draft ~= nil,
        imageVersion = base.imageVersion, updated = base.updated,
        scriptOnly = type(base.data) == "table" and base.data.scriptOnly == true or false,
    }
end

local function imagePath(id, version)
    return "community_img/" .. id .. "_" .. version .. ".jpg"
end

-- The game as the lobby / clients see it.
local function gameOf(row, kind)
    local game = copyTable(row.data)
    game.id = row.id
    game.createdBy = row.owner
    game.community = kind == "community" or nil
    if (row.imageVersion or 0) > 0 then game.image = imagePath(row.id, row.imageVersion) end
    return game
end

-- (Re)registers / unregisters one id from the cache (official wins over community).
local function refreshGame(id)
    local live, kind = liveOf(id)
    if not live then
        if jobsById[id] then unregisterJob(id) end
        return true
    end
    local ok, err = registerJob(gameOf(live, kind), true)
    if not ok then log(kind .. " game '" .. id .. "' skipped: " .. tostring(err), 2) end
    return ok, err
end

local function newId()
    local id
    repeat
        id = "c" .. now() .. math.random(100, 999)
    until not entryOf(id) and not jobsById[id]
    return id
end

--------------------------------------------------------------------------------
-- loading + sync between server instances
--------------------------------------------------------------------------------

local SELECT = [[SELECT id, name, type, created_by, data, image_version, created_at, updated_at, %s,
    CASE WHEN image IS NULL THEN 0 WHEN image = '' THEN 2 ELSE 1 END AS image_state FROM %s]]

local function rowFromDb(kind, r)
    local data = type(r.data) == "string" and fromJSON(r.data)
    if type(data) ~= "table" then return nil end
    local state = tonumber(r.image_state) or 0
    return {
        id = tostring(r.id), name = r.name, type = r.type, owner = r.created_by, data = data,
        imageVersion = tonumber(r.image_version) or 0,
        imageState = state == 1 and "set" or (state == 2 and "removed" or "none"),
        publishedBy = kind ~= "draft" and r.published_by or nil,
        target = kind == "draft" and (r.target == "official" and "official" or "community") or nil,
        created = tonumber(r.created_at) or 0, updated = tonumber(r.updated_at) or 0,
    }
end

local function selectSql(kind, where)
    return SELECT:format(kind == "draft" and "target" or "published_by", TABLES[kind]) .. (where or "")
end

-- cb(changedIds | false)
local function loadAll(kind, cb)
    MYSQL.query(function(result, err)
        if not result then log("cannot read " .. TABLES[kind] .. ": " .. tostring(err), 1) return cb(false) end
        local fresh, changed = {}, {}
        for _, r in ipairs(result) do
            local row = rowFromDb(kind, r)
            if row then fresh[row.id] = row else log(TABLES[kind] .. " '" .. tostring(r.id) .. "' has invalid data", 2) end
        end
        for id in pairs(rows[kind]) do changed[id] = true end
        for id in pairs(fresh) do changed[id] = true end
        rows[kind] = fresh
        cb(changed)
    end, selectSql(kind))
end

-- Reloads the rows another instance changed, leaves the ones this one is writing alone.
local function syncTable(kind, cb)
    MYSQL.query(function(result)
        if not result then return cb({}) end
        local seen, reload, changed = {}, {}, {}
        for _, r in ipairs(result) do
            local id = tostring(r.id)
            seen[id] = true
            local row = rows[kind][id]
            if not busy[id] and (not row or row.updated ~= tonumber(r.updated_at)
                or row.imageVersion ~= tonumber(r.image_version)) then
                reload[#reload + 1] = id
            end
        end
        for id in pairs(rows[kind]) do
            if not seen[id] and not busy[id] then rows[kind][id], changed[id] = nil, true end
        end
        if #reload == 0 then return cb(changed) end
        local marks = ("?,"):rep(#reload):sub(1, -2)
        MYSQL.query(function(full)
            for _, r in ipairs(full or {}) do
                local row = not busy[tostring(r.id)] and rowFromDb(kind, r)
                if row then rows[kind][row.id], changed[row.id] = row, true end
            end
            cb(changed)
        end, selectSql(kind, " WHERE id IN (" .. marks .. ")"), unpack(reload))
    end, "SELECT id, updated_at, image_version FROM " .. TABLES[kind])
end

local function eachKind(fn, done)
    local all = {}
    fn("official", function(a)
        fn("community", function(b)
            fn("draft", function(c)
                if not (a and b and c) then return done(false) end
                for _, set in ipairs({ a, b, c }) do for id in pairs(set) do all[id] = true end end
                done(all)
            end)
        end)
    end)
end

local syncing = false
local function sync()
    if not loaded or syncing then return end
    syncing = true
    eachKind(syncTable, function(changed)
        syncing = false
        for id in pairs(changed or {}) do
            imageCache["official:" .. id], imageCache["community:" .. id] = nil, nil
            refreshGame(id)
        end
    end)
end

local bootTimer
local function boot()
    if not exports.v_mysql:mysqlIsConnected() then return end
    killTimer(bootTimer)
    ensureTables()
    eachKind(loadAll, function(changed)
        if not changed then
            -- the tables may have just been created: try again a bit later
            bootTimer = setTimer(boot, 5000, 0)
            return
        end
        loaded = true
        for id in pairs(rows.official) do refreshGame(id) end
        for id in pairs(rows.community) do refreshGame(id) end
        setTimer(sync, SYNC_INTERVAL, 0)
        log("loaded " .. #jobs .. " games from MySQL")
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    bootTimer = setTimer(boot, 1000, 0)
end)

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function jobmanagerStorageReady() return loaded end

function jobmanagerGameEntry(id)
    return type(id) == "string" and entryOf(id) or false
end

-- Community games (drafts + live). `owner` filters to one account.
function jobmanagerCommunityList(owner)
    local list, seen = {}, {}
    for _, kind in ipairs({ "community", "draft" }) do
        for id in pairs(rows[kind]) do
            local entry = not seen[id] and entryOf(id)
            seen[id] = true
            if entry and not entry.official and (not owner or entry.owner == owner) then list[#list + 1] = entry end
        end
    end
    return list
end

-- Official games (live + official drafts).
function jobmanagerOfficialList()
    local list, seen = {}, {}
    for _, kind in ipairs({ "official", "draft" }) do
        for id in pairs(rows[kind]) do
            local entry = not seen[id] and entryOf(id)
            seen[id] = true
            if entry and entry.official then list[#list + 1] = entry end
        end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return list
end

-- The newest copy (draft, else live) + its entry.
function jobmanagerGameLoad(id)
    local entry = type(id) == "string" and entryOf(id)
    if not entry then return false, "not found" end
    local row = rows.draft[id] or liveOf(id)
    local game = copyTable(row.data)
    game.id, game.createdBy, game.image = id, row.owner, nil
    return game, entry
end

-- Writes the draft. `game.id` nil = new game (an id is assigned, `target` =
-- "official" | "community" is where it will be published). Fields the creator does
-- not edit (createdBy) are kept from the current copy.
-- image: nil = keep, false = remove, string = new JPEG bytes.
-- Returns id, entry or false, error.
function jobmanagerGameSave(game, owner, image, target)
    if not loaded then return false, "storage not ready" end
    if type(game) ~= "table" or type(owner) ~= "string" or owner == "" then return false, "bad arguments" end
    local id = game.id
    if id and not entryOf(id) then return false, "not found" end
    if type(image) == "string" and (#image > MAX_IMAGE_BYTES or image:sub(1, 2) ~= "\255\216") then
        return false, "invalid image"
    end
    local live, liveKind = nil, nil
    if id then live, liveKind = liveOf(id) else id = newId() end
    local old = rows.draft[id]
    local base = old or live
    local t = now()

    local data = copyTable(game)
    data.id, data.createdBy, data.community, data.image = nil, nil, nil, nil

    local row = {
        id = id, name = data.name, type = data.type, owner = base and base.owner or owner, data = data,
        imageVersion = base and base.imageVersion or 0, imageState = old and old.imageState or "none",
        target = liveKind or (old and old.target) or (target == "official" and "official" or "community"),
        created = base and base.created or t, updated = t,
    }
    local imageSql
    if image == false then
        row.imageVersion, row.imageState, imageSql = 0, "removed", "''"
    elseif type(image) == "string" then
        row.imageVersion = math.max(row.imageVersion, live and live.imageVersion or 0) + 1
        row.imageState, imageSql = "set", "?"
    end
    rows.draft[id] = row

    local sql = ([[INSERT INTO jobs_draft (id, name, type, created_by, target, data, image, image_version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, %s, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), type = VALUES(type), target = VALUES(target), data = VALUES(data),
        image_version = VALUES(image_version), updated_at = VALUES(updated_at)%s]])
        :format(imageSql or "NULL", imageSql and ", image = VALUES(image)" or "")
    local step = { sql, id, row.name, row.type, row.owner, row.target, encode(data) }
    if imageSql == "?" then step[#step + 1] = base64Encode(image) end
    for _, v in ipairs({ row.imageVersion, row.created, row.updated }) do step[#step + 1] = v end
    persist(id, { step })
    return id, entryOf(id)
end

-- Makes the draft live. target: nil = the game's own table, "official" = publish
-- (or promote a community game) as an official game. Running lobbies keep the old version.
function jobmanagerGamePublish(id, target, by)
    if not loaded then return false, "storage not ready" end
    local entry = type(id) == "string" and entryOf(id)
    if not entry then return false, "not found" end
    local draft = rows.draft[id]
    local live, from = liveOf(id)
    local to = target == "official" and "official" or (from or draft.target)
    if not draft and from == to then return true end   -- nothing pending
    local src = draft or live

    local row = {
        id = id, name = src.name, type = src.type, owner = src.owner, data = copyTable(src.data),
        imageVersion = src.imageVersion, publishedBy = type(by) == "string" and by or (live and live.publishedBy) or "",
        created = src.created, updated = now(),
    }
    -- the image of the new live row: the draft's own photo, or the live one it inherited
    local imageFrom
    if draft and draft.imageState == "set" then imageFrom = "jobs_draft"
    elseif draft and draft.imageState == "removed" then imageFrom = false
    elseif live and live.imageState == "set" then imageFrom = TABLES[from] end
    row.imageState = imageFrom and "set" or "none"
    if imageFrom == false then row.imageVersion = 0 end

    local ok, err = validateGame(gameOf(row, to))
    if not ok then return false, err end

    local steps = { {
        ([[INSERT INTO %s (id, name, type, created_by, published_by, data, image, image_version, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name), type = VALUES(type), created_by = VALUES(created_by),
            published_by = VALUES(published_by), data = VALUES(data), image_version = VALUES(image_version),
            updated_at = VALUES(updated_at)]]):format(TABLES[to]),
        id, row.name, row.type, row.owner, row.publishedBy, encode(row.data), row.imageVersion, row.created, row.updated,
    } }
    if imageFrom == false then
        steps[#steps + 1] = { ("UPDATE %s SET image = NULL WHERE id = ?"):format(TABLES[to]), id }
    elseif imageFrom and imageFrom ~= TABLES[to] then
        steps[#steps + 1] = { ("UPDATE %s t JOIN %s s ON s.id = t.id SET t.image = s.image WHERE t.id = ?")
            :format(TABLES[to], imageFrom), id }
    end
    if from and from ~= to then steps[#steps + 1] = { ("DELETE FROM %s WHERE id = ?"):format(TABLES[from]), id } end
    if draft then steps[#steps + 1] = { "DELETE FROM jobs_draft WHERE id = ?", id } end

    if from and from ~= to then rows[from][id] = nil end
    rows[to][id], rows.draft[id] = row, nil
    imageCache["official:" .. id], imageCache["community:" .. id] = nil, nil
    persist(id, steps)
    ok, err = refreshGame(id)
    if not ok then return false, err end
    return true
end

-- Takes a live game out of the job list; it stays as a draft (nothing is lost).
function jobmanagerGameUnpublish(id)
    if not loaded then return false, "storage not ready" end
    local live, kind = liveOf(id)
    if not live then return false, "not published" end
    local draft = rows.draft[id]
    local t = now()
    local steps = {}
    if not draft then
        steps[1] = { ([[INSERT INTO jobs_draft (id, name, type, created_by, target, data, image, image_version, created_at, updated_at)
            SELECT id, name, type, created_by, ?, data, image, image_version, created_at, ? FROM %s WHERE id = ?]])
            :format(TABLES[kind]), kind, t, id }
        rows.draft[id] = {
            id = id, name = live.name, type = live.type, owner = live.owner, data = copyTable(live.data),
            imageVersion = live.imageVersion, imageState = live.imageState, target = kind,
            created = live.created, updated = t,
        }
    elseif draft.imageState == "none" and live.imageState == "set" then
        -- the draft inherited the live photo: it needs its own copy now
        steps[1] = { ("UPDATE jobs_draft d JOIN %s l ON l.id = d.id SET d.image = l.image, d.updated_at = ? WHERE d.id = ?")
            :format(TABLES[kind]), t, id }
        draft.imageState, draft.updated = "set", t
    end
    steps[#steps + 1] = { ("DELETE FROM %s WHERE id = ?"):format(TABLES[kind]), id }
    rows[kind][id] = nil
    imageCache[kind .. ":" .. id] = nil
    persist(id, steps)
    refreshGame(id)
    return true
end

-- Deletes a game that is not live (or a live community game) for good.
function jobmanagerGameDelete(id)
    if not loaded then return false, "storage not ready" end
    if not (type(id) == "string" and entryOf(id)) then return false, "not found" end
    if rows.official[id] then return false, "unpublish the official game first" end
    rows.draft[id], rows.community[id] = nil, nil
    imageCache["community:" .. id] = nil
    persist(id, { { "DELETE FROM jobs_draft WHERE id = ?", id }, { "DELETE FROM jobs_community WHERE id = ?", id } })
    refreshGame(id)
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

--------------------------------------------------------------------------------
-- thumbnails
--------------------------------------------------------------------------------

-- cb(bytes | false); kind = "official" | "community" | "draft"
local function readImage(kind, id, version, cb)
    local key = kind .. ":" .. id
    local cached = imageCache[key]
    if cached and cached.version == version then return cb(cached.bytes) end
    MYSQL.query(function(result)
        local b64 = result and result[1] and result[1].image
        local bytes = type(b64) == "string" and b64 ~= "" and base64Decode(b64) or false
        if bytes and kind ~= "draft" then imageCache[key] = { version = version, bytes = bytes } end
        cb(bytes)
    end, ("SELECT image FROM %s WHERE id = ?"):format(TABLES[kind]), id)
end

-- The editor's preview of the saved thumbnail: sent to `player` as
-- eventName(bytes) on the calling resource's root.
function jobmanagerSendImage(player, id, eventName)
    if not isElement(player) or type(id) ~= "string" or type(eventName) ~= "string" or not sourceResource then return false end
    local target = getResourceRootElement(sourceResource)
    local draft = rows.draft[id]
    local live, kind = liveOf(id)
    local function send(bytes)
        if bytes and isElement(player) and isElement(target) then
            triggerLatentClientEvent(player, eventName, 200000, false, target, bytes)
        end
    end
    if draft and draft.imageState == "set" then readImage("draft", id, draft.imageVersion, send)
    elseif draft and draft.imageState == "removed" then return false
    elseif live and live.imageState == "set" then readImage(kind, id, live.imageVersion, send)
    else return false end
    return true
end

addEvent("jobmanager:requestImage", true)
addEventHandler("jobmanager:requestImage", resourceRoot, function(path)
    if type(path) ~= "string" then return end
    -- an older version (the client saw an old list) gets the current file
    local id = path:match("^community_img/([%w_]+)_%d+%.jpg$")
    local live, kind = liveOf(id or "")
    if not live or live.imageState ~= "set" or (live.imageVersion or 0) == 0 then return end
    local player = client
    readImage(kind, id, live.imageVersion, function(bytes)
        if bytes and isElement(player) then
            triggerLatentClientEvent(player, "jobmanager:image", 200000, false, resourceRoot, path, bytes)
        end
    end)
end)
