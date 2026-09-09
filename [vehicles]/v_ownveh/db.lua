-- v_ownveh :: database layer
--
-- Owned vehicles live in the shared MySQL database, table `vehicles` (see
-- database.sql / ../../main.sql). Every access goes through v_mysql's exports -
-- this resource never opens its own connection.
--
-- Serialisation of the wider fields:
--   colors    "r,g,b,r,g,b,..."  (all values getVehicleColor(veh, true) returns)
--   upgrades  "id,id,id"         (getVehicleUpgrades)
--   handling  JSON object        (only properties that differ from stock)
--   customs   JSON object        (v_customs extras that live on element data and
--                                 cannot be read back off the vehicle: nitro
--                                 level, neon colour, air-ride, bulletproof
--                                 tyres, LSD doors). Empty "{}" when v_customs
--                                 is not installed / nothing applied.
--
-- All helpers are synchronous (exports.v_mysql:mysqlQuerySync blocks for the
-- round trip); the data set is tiny and only touched on summon / store / give /
-- delete, never per frame.

OwnVeh = OwnVeh or {}

local TABLE = "vehicles"

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

local function now()
    return getRealTime().timestamp
end

--------------------------------------------------------------------------------
-- CRUD
--------------------------------------------------------------------------------

-- Inserts a new vehicle for an account. `data` may carry colors / paintjob /
-- upgrades / handling / customs / plate (all optional, already serialised).
-- Returns the new id, or nil on failure.
function OwnVeh.dbInsert(accountName, data)
    if not mysqlReady() then return nil end
    data = data or {}
    local ts = now()
    local id = exports.v_mysql:mysqlInsert(
        "INSERT INTO `" .. TABLE .. "` " ..
        "(account_name, model, colors, paintjob, upgrades, handling, customs, plate, isDestroyed, created_at, updated_at) " ..
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)",
        accountName,
        tonumber(data.model) or 0,
        data.colors or "",
        tonumber(data.paintjob) or 3,
        data.upgrades or "",
        data.handling or "{}",
        data.customs or "{}",
        data.plate,
        ts, ts)
    return (type(id) == "number") and id or nil
end

-- Full row for an id, or nil.
function OwnVeh.dbGetById(id)
    local row = query("SELECT * FROM `" .. TABLE .. "` WHERE id = ? LIMIT 1", tonumber(id))
    return row[1]
end

-- Every row owned by an account (ascending id).
function OwnVeh.dbGetByAccount(accountName)
    return query("SELECT * FROM `" .. TABLE .. "` WHERE account_name = ? ORDER BY id ASC", accountName)
end

-- Overwrites the mutable state columns. `state` = { colors, paintjob, upgrades,
-- handling, customs, plate } (all serialised). Missing keys are left untouched.
function OwnVeh.dbUpdateState(id, state)
    if not state then return end
    exec(
        "UPDATE `" .. TABLE .. "` SET " ..
        "colors = COALESCE(?, colors), " ..
        "paintjob = COALESCE(?, paintjob), " ..
        "upgrades = COALESCE(?, upgrades), " ..
        "handling = COALESCE(?, handling), " ..
        "customs = COALESCE(?, customs), " ..
        "plate = COALESCE(?, plate), " ..
        "updated_at = ? " ..
        "WHERE id = ?",
        state.colors, tonumber(state.paintjob), state.upgrades, state.handling, state.customs, state.plate,
        now(), tonumber(id))
end

function OwnVeh.dbSetDestroyed(id, destroyed)
    exec("UPDATE `" .. TABLE .. "` SET isDestroyed = ?, updated_at = ? WHERE id = ?",
        destroyed and 1 or 0, now(), tonumber(id))
end

function OwnVeh.dbDelete(id)
    exec("DELETE FROM `" .. TABLE .. "` WHERE id = ?", tonumber(id))
end
