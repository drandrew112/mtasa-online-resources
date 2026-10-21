-- News storage: the MySQL `news` table (through v_mysql) with an in-memory copy.
--
-- An article is { id, date, title, body, author }; `date` is a unix timestamp
-- the admin may set freely. An article whose date is in the future is
-- "scheduled": it is listed in the editor but getLatestNews() leaves it out
-- until the date passes. Deleting is soft (deleted_at > 0).

STORE = {}

local articles = {}   -- sorted newest first: { id, date, title, body, author }
local loaded = false
local publicIds = ""  -- ids of the published articles, to notice a scheduled one going live

addEvent("onNewsChanged")

local function dbReady()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql:mysqlIsConnected() == true
end

local function now() return getRealTime().timestamp end

local function sortArticles()
    table.sort(articles, function(a, b)
        if a.date ~= b.date then return a.date > b.date end
        return a.id > b.id
    end)
end

local function copy(a)
    return { id = a.id, date = a.date, title = a.title, body = a.body, author = a.author }
end

local function currentPublicIds()
    local t, ids = now(), {}
    for _, a in ipairs(articles) do
        if a.date <= t then ids[#ids + 1] = a.id end
    end
    return table.concat(ids, ",")
end

local function changed()
    publicIds = currentPublicIds()
    triggerEvent("onNewsChanged", resourceRoot)
end

function STORE.isLoaded() return loaded end

function STORE.load()
    if not dbReady() then return false end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. NEWS.TABLE .. [[` (
        `id`           INT AUTO_INCREMENT PRIMARY KEY,
        `published_at` INT          NOT NULL DEFAULT 0,
        `title`        VARCHAR(255) NOT NULL DEFAULT '',
        `body`         TEXT         NOT NULL,
        `author`       VARCHAR(64)  NOT NULL DEFAULT '',
        `created_at`   INT          NOT NULL DEFAULT 0,
        `updated_at`   INT          NOT NULL DEFAULT 0,
        `deleted_at`   INT          NOT NULL DEFAULT 0,
        KEY `idx_published` (`published_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows = exports.v_mysql:mysqlQuerySync("SELECT id, published_at, title, body, author FROM `"
        .. NEWS.TABLE .. "` WHERE deleted_at = 0")
    if type(rows) ~= "table" then return false end
    articles = {}
    for _, row in ipairs(rows) do
        articles[#articles + 1] = {
            id = tonumber(row.id), date = tonumber(row.published_at) or 0,
            title = tostring(row.title or ""), body = tostring(row.body or ""), author = tostring(row.author or ""),
        }
    end
    sortArticles()
    loaded = true
    publicIds = currentPublicIds()
    return true
end

-- Every article (scheduled ones too), newest first.
function STORE.all()
    local out = {}
    for i, a in ipairs(articles) do out[i] = copy(a) end
    return out
end

-- The newest `n` published articles.
function STORE.latest(n)
    n = math.max(1, math.floor(tonumber(n) or 5))
    local t, out = now(), {}
    for _, a in ipairs(articles) do
        if a.date <= t then
            out[#out + 1] = copy(a)
            if #out >= n then break end
        end
    end
    return out
end

local function find(id)
    for i, a in ipairs(articles) do
        if a.id == id then return a, i end
    end
end

-- Creates (id = nil) or updates an article. Returns the id or false.
function STORE.save(id, date, title, body, author)
    if not dbReady() then return false end
    local t = now()
    if id then
        local a = find(id)
        if not a then return false end
        if not exports.v_mysql:mysqlExec("UPDATE `" .. NEWS.TABLE
            .. "` SET published_at = ?, title = ?, body = ?, updated_at = ? WHERE id = ?",
            date, title, body, t, id) then return false end
        a.date, a.title, a.body = date, title, body
    else
        id = exports.v_mysql:mysqlInsert("INSERT INTO `" .. NEWS.TABLE
            .. "` (published_at, title, body, author, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            date, title, body, author, t, t)
        if type(id) ~= "number" then return false end
        articles[#articles + 1] = { id = id, date = date, title = title, body = body, author = author }
    end
    sortArticles()
    changed()
    return id
end

function STORE.delete(id)
    local _, i = find(id)
    if not i or not dbReady() then return false end
    if not exports.v_mysql:mysqlExec("UPDATE `" .. NEWS.TABLE .. "` SET deleted_at = ? WHERE id = ?", now(), id) then
        return false
    end
    table.remove(articles, i)
    changed()
    return true
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function getLatestNews(n) return STORE.latest(n) end
function getAllNews() return STORE.all() end

--------------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    if not STORE.load() then
        outputServerLog("[v_news] could not load the news table (v_mysql not connected?)")
    end
end)

-- v_mysql (re)started after us
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "v_mysql" and not loaded then
        setTimer(function() if STORE.load() then changed() end end, 2000, 1)
    end
end)

-- a scheduled article became public
setTimer(function()
    if loaded and currentPublicIds() ~= publicIds then changed() end
end, NEWS.DUE_CHECK, 0)
