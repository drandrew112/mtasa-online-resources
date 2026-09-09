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

    Friends themselves stay in account data (exports.v_mysql:getAccData /
    setAccData, key SP.KEY_FRIENDS) - only friend *requests* moved to a table.

    All helpers are synchronous (mysqlQuerySync / mysqlInsert / mysqlExec block
    for the round trip). The data set is small and only touched on social
    actions, never per frame.
]]

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

local function insert(sql, ...)
    if not mysqlReady() then return nil end
    local id = exports.v_mysql:mysqlInsert(sql, ...)
    return (type(id) == "number") and id or nil
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

-- Insert helpers return the new row id (or nil when the DB is unavailable).
function SPDB.insertDm(from, to, text, time, read)
    return insert(
        "INSERT INTO `messages` (kind, sender, recipient, body, is_read, created_at) " ..
        "VALUES ('dm', ?, ?, ?, ?, ?)",
        from, to, text, read and 1 or 0, tonumber(time) or now())
end

function SPDB.insertCrewMsg(from, crew, text, time)
    return insert(
        "INSERT INTO `messages` (kind, sender, recipient, body, is_read, created_at) " ..
        "VALUES ('crew', ?, ?, ?, 0, ?)",
        from, crew, text, tonumber(time) or now())
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

-- Sender account names of the requests addressed to `recipient` (newest first).
function SPDB.getRequestsFor(recipient)
    local out = {}
    if type(recipient) ~= "string" or recipient == "" then return out end
    for _, row in ipairs(query(
        "SELECT sender FROM `friendRequests` WHERE recipient = ? ORDER BY id DESC", recipient)) do
        if row.sender then out[#out + 1] = row.sender end
    end
    return out
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
