--[[
    v_socialpanel / db.lua
    Database layer for crews, messages and friend requests.

    Everything global this resource owns now lives in the shared MySQL database
    (schema: database.sql / ../../main.sql), reached through v_mysql's exported
    helpers - this resource never opens its own connection and no longer keeps
    any XML data file.

      - crews          one row per crew (members serialised, newline separated)
      - messages       one row per message (kind = 'dm' | 'crew')
      - friendRequests one row per pending incoming request
      - friends        one row per friendship (both accounts on the same row)

    A friendship is ONE row, so it always exists for both accounts or for
    neither. The old per-account lists (account data, SP.KEY_FRIENDS) could end
    up one-sided when one of the two writes was lost; SPDB.migrateFriends moves
    them into the table (union of both sides) and deletes the key.

    The start-up loads and the friend-request checks of the friend actions are
    synchronous (mysqlQuerySync blocks for the round trip). Everything a player
    can trigger often - the snapshot's request list, message inserts - is async
    through v_mysql's async lib (PERF-01). Writes (mysqlExec) never block.
]]

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib (PERF-01)

SPDB = SPDB or {}

--------------------------------------------------------------------------------
-- v_mysql plumbing
--------------------------------------------------------------------------------

local function mysqlReady()
    local res = getResourceFromName("v_mysql")
    return (res and getResourceState(res) == "running") and true or false
end

local function query(sql, ...)
    if not mysqlReady() then return {} end
    return exports.v_mysql:mysqlQuerySync(sql, ...) or {}
end

local function exec(sql, ...)
    if not mysqlReady() then return false end
    return exports.v_mysql:mysqlExec(sql, ...) ~= false
end

-- Async INSERT; cb(id) with the new row id, or cb(nil) on failure.
local function insertAsync(cb, sql, ...)
    MYSQL.insert(function(id)
        cb((type(id) == "number") and id or nil)
    end, sql, ...)
end

local function now()
    return getRealTime().timestamp
end

--------------------------------------------------------------------------------
-- Crews
--------------------------------------------------------------------------------

-- Returns { [name:lower()] = { name, tag, color={r,g,b}, founder, desc, members={...} } }
function SPDB.loadCrews()
    local out = {}
    for _, row in ipairs(query("SELECT * FROM `crews`")) do
        local name = row.name
        if type(name) == "string" and name ~= "" then
            out[name:lower()] = {
                name    = name,
                tag     = row.tag or "CREW",
                color   = {
                    tonumber(row.color_r) or 255,
                    tonumber(row.color_g) or 200,
                    tonumber(row.color_b) or 0,
                },
                founder = row.founder or "",
                desc    = row.description or "",
                members = SP.split(row.members or ""),
            }
        end
    end
    return out
end

-- Upserts a single crew row (keyed by the unique `name`).
function SPDB.saveCrew(crew)
    if type(crew) ~= "table" or not crew.name then return end
    local c = crew.color or {}
    exec(
        "INSERT INTO `crews` " ..
        "(name, tag, founder, description, color_r, color_g, color_b, members, created_at, updated_at) " ..
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) " ..
        "ON DUPLICATE KEY UPDATE " ..
        "tag = VALUES(tag), founder = VALUES(founder), description = VALUES(description), " ..
        "color_r = VALUES(color_r), color_g = VALUES(color_g), color_b = VALUES(color_b), " ..
        "members = VALUES(members), updated_at = VALUES(updated_at)",
        crew.name,
        crew.tag or "CREW",
        crew.founder or "",
        crew.desc or "",
        math.max(0, math.min(255, tonumber(c[1]) or 255)),
        math.max(0, math.min(255, tonumber(c[2]) or 200)),
        math.max(0, math.min(255, tonumber(c[3]) or 0)),
        SP.join(crew.members or {}),
        now(), now())
end

function SPDB.deleteCrew(name)
    if type(name) ~= "string" or name == "" then return end
    exec("DELETE FROM `crews` WHERE name = ?", name)
end

--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------

-- Returns dms, crewMsgs (the server keeps these cached in memory):
--   dms[pairKey]           = { { id, from, to, text, time, read }, ... }
--   crewMsgs[crew:lower()] = { { id, from, text, time, crew }, ... }
function SPDB.loadMessages()
    local dms, crewMsgs = {}, {}
    for _, row in ipairs(query("SELECT * FROM `messages` ORDER BY id ASC")) do
        local time = tonumber(row.created_at) or 0
        local body = row.body or ""
        if row.kind == "dm" and row.sender and row.recipient and body ~= "" then
            local key = SP.pairKey(row.sender, row.recipient)
            dms[key] = dms[key] or {}
            dms[key][#dms[key] + 1] = {
                id   = tonumber(row.id),
                from = row.sender, to = row.recipient, text = body, time = time,
                read = tonumber(row.is_read) == 1,
            }
        elseif row.kind == "crew" and row.sender and row.recipient and body ~= "" then
            local key = row.recipient:lower()
            crewMsgs[key] = crewMsgs[key] or {}
            crewMsgs[key][#crewMsgs[key] + 1] = {
                id   = tonumber(row.id),
                from = row.sender, text = body, time = time, crew = row.recipient,
            }
        end
    end
    return dms, crewMsgs
end

-- The message is already in the in-memory list; its row id arrives later and
-- is stored on it (msg.id). What happened to the message meanwhile is applied
-- then: msg.dropped (trimmed from the history) deletes the new row, msg.read
-- (DM opened) flags it read. On failure the message stays memory-only, as it
-- did when the database was unavailable.
local function onInserted(msg)
    return function(id)
        if not id then return end
        msg.id = id
        if msg.dropped then
            SPDB.deleteMessage(id)
        elseif msg.read then
            SPDB.markMessagesRead({ id })
        end
    end
end

-- msg = { from, to, text, time, read }
function SPDB.insertDm(msg)
    insertAsync(onInserted(msg),
        "INSERT INTO `messages` (kind, sender, recipient, body, is_read, created_at) " ..
        "VALUES ('dm', ?, ?, ?, ?, ?)",
        msg.from, msg.to, msg.text, msg.read and 1 or 0, tonumber(msg.time) or now())
end

-- msg = { from, crew, text, time }
function SPDB.insertCrewMsg(msg)
    insertAsync(onInserted(msg),
        "INSERT INTO `messages` (kind, sender, recipient, body, is_read, created_at) " ..
        "VALUES ('crew', ?, ?, ?, 0, ?)",
        msg.from, msg.crew, msg.text, tonumber(msg.time) or now())
end

function SPDB.deleteMessage(id)
    id = tonumber(id)
    if not id then return end
    exec("DELETE FROM `messages` WHERE id = ?", id)
end

-- Flags a set of DM rows read. `ids` is a plain array of numeric message ids.
function SPDB.markMessagesRead(ids)
    if type(ids) ~= "table" or #ids == 0 then return end
    local clean = {}
    for _, id in ipairs(ids) do
        local n = tonumber(id)
        if n then clean[#clean + 1] = tostring(n) end
    end
    if #clean == 0 then return end
    exec("UPDATE `messages` SET is_read = 1 WHERE id IN (" .. table.concat(clean, ",") .. ")")
end

-- Drops a disbanded crew's whole message history.
function SPDB.deleteCrewMessages(crew)
    if type(crew) ~= "string" or crew == "" then return end
    exec("DELETE FROM `messages` WHERE kind = 'crew' AND recipient = ?", crew)
end

--------------------------------------------------------------------------------
-- Friend requests
--------------------------------------------------------------------------------

local REQUESTS_SQL = "SELECT sender FROM `friendRequests` WHERE recipient = ? ORDER BY id DESC"

local function senders(rows)
    local out = {}
    for _, row in ipairs(rows) do
        if row.sender then out[#out + 1] = row.sender end
    end
    return out
end

-- Sender account names of the requests addressed to `recipient` (newest first).
-- Blocking: only for the friend actions, which must check before they write.
function SPDB.getRequestsFor(recipient)
    if type(recipient) ~= "string" or recipient == "" then return {} end
    return senders(query(REQUESTS_SQL, recipient))
end

-- Non-blocking variant: cb(list); an empty list when the database fails.
function SPDB.getRequestsForAsync(cb, recipient)
    if type(recipient) ~= "string" or recipient == "" then return cb({}) end
    MYSQL.query(function(rows)
        cb(type(rows) == "table" and senders(rows) or {})
    end, REQUESTS_SQL, recipient)
end

-- Non-blocking account search for the player search: cb(names) with up to
-- `limit` account names containing `needle` (case-insensitive, ascending), or
-- cb(false) when the database fails. `#`-prefixed (system) accounts are left out.
function SPDB.searchAccountsAsync(cb, needle, limit)
    local pattern = "%" .. needle:gsub("[\\%%_]", "\\%0") .. "%"
    MYSQL.query(function(rows)
        if type(rows) ~= "table" then return cb(false) end
        local out = {}
        for _, row in ipairs(rows) do
            if type(row.account_name) == "string" then out[#out + 1] = row.account_name end
        end
        cb(out)
    end, "SELECT account_name FROM `accounts` WHERE account_name LIKE ? AND account_name NOT LIKE '#%' " ..
         "ORDER BY account_name ASC LIMIT ?", pattern, limit)
end

function SPDB.addRequest(sender, recipient)
    if type(sender) ~= "string" or type(recipient) ~= "string" then return end
    exec("INSERT INTO `friendRequests` (sender, recipient, created_at) VALUES (?, ?, ?) " ..
         "ON DUPLICATE KEY UPDATE created_at = VALUES(created_at)", sender, recipient, now())
end

function SPDB.removeRequest(sender, recipient)
    if type(sender) ~= "string" or type(recipient) ~= "string" then return end
    exec("DELETE FROM `friendRequests` WHERE sender = ? AND recipient = ?", sender, recipient)
end

--------------------------------------------------------------------------------
-- Friends
--------------------------------------------------------------------------------

-- Row order of a pair: account_a is the one that sorts first (case-insensitive),
-- so (a, b) and (b, a) hit the same UNIQUE key.
local function ordered(a, b)
    if a:lower() <= b:lower() then return a, b end
    return b, a
end

local FRIENDS_SQL =
    "SELECT IF(account_a = ?, account_b, account_a) AS friend FROM `friends` " ..
    "WHERE account_a = ? OR account_b = ?"

local function friendNames(rows)
    local out = {}
    for _, row in ipairs(rows) do
        if type(row.friend) == "string" then out[#out + 1] = row.friend end
    end
    return out
end

function SPDB.ensureFriendsTable()
    if not mysqlReady() then return false end
    return exports.v_mysql:mysqlQuerySync([[CREATE TABLE IF NOT EXISTS `friends` (
        `id`         INT AUTO_INCREMENT PRIMARY KEY,
        `account_a`  VARCHAR(50) NOT NULL,
        `account_b`  VARCHAR(50) NOT NULL,
        `created_at` INT         NOT NULL DEFAULT 0,
        UNIQUE KEY `unique_friendship` (`account_a`, `account_b`),
        KEY `idx_friends_b` (`account_b`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]) ~= false
end

-- Account names `name` is friends with. Blocking: only for the friend actions,
-- which must check before they write.
function SPDB.getFriends(name)
    if type(name) ~= "string" or name == "" then return {} end
    return friendNames(query(FRIENDS_SQL, name, name, name))
end

-- Non-blocking variant: cb(list), or cb(false) when the database fails.
function SPDB.getFriendsAsync(cb, name)
    if type(name) ~= "string" or name == "" then return cb({}) end
    MYSQL.query(function(rows)
        cb(type(rows) == "table" and friendNames(rows) or false)
    end, FRIENDS_SQL, name, name, name)
end

-- One row for both accounts; a pair that already exists is left alone.
function SPDB.addFriend(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or a:lower() == b:lower() then return false end
    a, b = ordered(a, b)
    return exec("INSERT IGNORE INTO `friends` (account_a, account_b, created_at) VALUES (?, ?, ?)", a, b, now())
end

function SPDB.removeFriend(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    a, b = ordered(a, b)
    return exec("DELETE FROM `friends` WHERE account_a = ? AND account_b = ?", a, b)
end

-- The SP.KEY_FRIENDS value of a raw account_data blob (v_mysql's shapes: a plain
-- object or one wrapped in an array, a record or one wrapped in an array).
local function blobFriends(raw)
    local obj = fromJSON(tostring(raw or ""))
    if type(obj) == "table" and type(obj[1]) == "table" and obj[1].v == nil and #obj == 1 then obj = obj[1] end
    local rec = type(obj) == "table" and obj[SP.KEY_FRIENDS]
    if type(rec) == "table" and rec.v == nil and type(rec[1]) == "table" then rec = rec[1] end
    return SP.split(type(rec) == "table" and tostring(rec.v or "") or "")
end

-- Moves every per-account friend list into `friends` (a pair listed on either
-- side becomes a friendship), then deletes the key from those accounts. Only
-- deletes when every insert went through, so a failed run is redone next start.
function SPDB.migrateFriends()
    local rows = exports.v_mysql:mysqlQuerySync(
        "SELECT account_name, account_data FROM `accounts` WHERE account_data LIKE ?", "%" .. SP.KEY_FRIENDS .. "%")
    if type(rows) ~= "table" or #rows == 0 then return end

    local pairs_, owners = {}, {}
    for _, row in ipairs(rows) do
        local owner = row.account_name
        if type(owner) == "string" and owner ~= "" then
            owners[#owners + 1] = owner
            for _, friend in ipairs(blobFriends(row.account_data)) do
                if friend:lower() ~= owner:lower() then
                    local a, b = ordered(owner, friend)
                    pairs_[a:lower() .. "|" .. b:lower()] = { a, b }
                end
            end
        end
    end

    local list, ts = {}, now()
    for _, p in pairs(pairs_) do list[#list + 1] = p end
    for i = 1, #list, 200 do
        local values, args = {}, {}
        for j = i, math.min(i + 199, #list) do
            values[#values + 1] = "(?, ?, ?)"
            args[#args + 1], args[#args + 2], args[#args + 3] = list[j][1], list[j][2], ts
        end
        local ok = exports.v_mysql:mysqlInsert(
            "INSERT IGNORE INTO `friends` (account_a, account_b, created_at) VALUES " .. table.concat(values, ", "), unpack(args))
        if ok == false then
            outputDebugString("[v_socialpanel] friend migration failed, the old lists are kept", 2)
            return
        end
    end

    for i = 1, #owners, 200 do
        local chunk = { unpack(owners, i, math.min(i + 199, #owners)) }
        local marks = ("?, "):rep(#chunk):sub(1, -3)
        exports.v_mysql:mysqlInsert(
            "UPDATE `accounts` SET account_data = IF(JSON_TYPE(account_data) = 'ARRAY', " ..
            "JSON_REMOVE(account_data, '$[0].\"" .. SP.KEY_FRIENDS .. "\"'), " ..
            "JSON_REMOVE(account_data, '$.\"" .. SP.KEY_FRIENDS .. "\"')) " ..
            "WHERE account_name IN (" .. marks .. ")", unpack(chunk))
    end
    -- v_mysql's session cache of online accounts still holds the old value
    for _, owner in ipairs(owners) do
        for _, p in ipairs(getElementsByType("player")) do
            if getElementData(p, "accName") == owner then exports.v_mysql:setAccData(owner, SP.KEY_FRIENDS, nil) end
        end
    end
    outputDebugString(("[v_socialpanel] %d friendships moved from %d friend lists into `friends`"):format(#list, #owners))
end
