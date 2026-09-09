-- v_ownveh :: SQLite layer
--
-- One table, `vehicles`, in Vehicles.config.dbFile. Every owned vehicle is a
-- row; the id is the vehicle's permanent identifier used by every export and
-- stored on the owner's account as "owned_vehicle_ids" ("1,2,3").
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
-- All helpers are synchronous (dbPoll(-1)); the data set is tiny and only
-- touched on summon / store / give / delete, never per frame.

OwnVeh = OwnVeh or {}

local db

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS vehicles (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    account_name TEXT    NOT NULL,
    model        INTEGER NOT NULL,
    colors       TEXT    NOT NULL DEFAULT '',
    paintjob     INTEGER NOT NULL DEFAULT 3,
    upgrades     TEXT    NOT NULL DEFAULT '',
    handling     TEXT    NOT NULL DEFAULT '{}',
    customs      TEXT    NOT NULL DEFAULT '{}',
    plate        TEXT,
    isDestroyed  INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL DEFAULT 0,
    updated_at   INTEGER NOT NULL DEFAULT 0
)
]]

db = dbConnect("sqlite", Vehicles.config.dbFile)
if db then
    dbExec(db, SCHEMA)
    dbExec(db, "CREATE INDEX IF NOT EXISTS idx_vehicles_account ON vehicles (account_name)")

    -- Migration: add `customs` to databases created before it existed.
    local hasCustoms = false
    for _, col in ipairs(dbPoll(dbQuery(db, "PRAGMA table_info(vehicles)"), -1) or {}) do
        if col.name == "customs" then hasCustoms = true end
    end
    if not hasCustoms then
        dbExec(db, "ALTER TABLE vehicles ADD COLUMN customs TEXT NOT NULL DEFAULT '{}'")
    end
else
    outputServerLog("[v_ownveh] FATAL: could not open " .. tostring(Vehicles.config.dbFile))
end

local function query(sql, ...)
    if not db then return {} end
    local handle = dbQuery(db, sql, ...)
    local result = dbPoll(handle, -1)
    return result or {}
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
    if not db then return nil end
    data = data or {}
    local ts = now()
    local ok = dbExec(db,
        "INSERT INTO vehicles " ..
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
    if not ok then return nil end

    local row = query("SELECT last_insert_rowid() AS id")
    return row[1] and tonumber(row[1].id) or nil
end

-- Full row for an id, or nil.
function OwnVeh.dbGetById(id)
    local row = query("SELECT * FROM vehicles WHERE id = ? LIMIT 1", tonumber(id))
    return row[1]
end

-- Every row owned by an account (ascending id).
function OwnVeh.dbGetByAccount(accountName)
    return query("SELECT * FROM vehicles WHERE account_name = ? ORDER BY id ASC", accountName)
end

-- Overwrites the mutable state columns. `state` = { colors, paintjob, upgrades,
-- handling, customs, plate } (all serialised). Missing keys are left untouched.
function OwnVeh.dbUpdateState(id, state)
    if not db or not state then return end
    dbExec(db,
        "UPDATE vehicles SET " ..
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
    if not db then return end
    dbExec(db, "UPDATE vehicles SET isDestroyed = ?, updated_at = ? WHERE id = ?",
        destroyed and 1 or 0, now(), tonumber(id))
end

function OwnVeh.dbDelete(id)
    if not db then return end
    dbExec(db, "DELETE FROM vehicles WHERE id = ?", tonumber(id))
end
