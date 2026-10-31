-- police_system / modules/history/server/register.lua
-- Players and their vehicles are always in the police database (the "registered" citizens):
--   * start: one INSERT ... SELECT each for the accounts / owned vehicles that are missing (not row by row; this is
--     the exception from the id pool, it writes ids in order)
--   * a new account: onPlayerAccountLogin(accountName, isNewAccount) (v_accounts)
--   * a new vehicle: onOwnedVehicleCreated(id, accountName, model, plate) (v_ownveh giveVehicle)
--   * plates: re-read from v_ownveh at the start and every 12 h; an owned vehicle without a stored plate gets one
--     (saved in v_ownveh) unless it is out right now (its own plate is saved by v_ownveh then)
-- Birth date of a player = registration date - 18 years (later an account setting). Name = display name, read at
-- display time (accounts.display_name), never stored here. Their vehicle documents count as valid.

local H = POL.history
local plateTimer

local function registerAll()
    local inst = POL.db.instance()
    POL.db.query(function(ok, err)
        if ok == false then outputDebugString("[police_system] citizen registration failed: " .. tostring(err), 2) end
        POL.db.query(function(ok2, err2)
            if ok2 == false then outputDebugString("[police_system] vehicle registration failed: " .. tostring(err2), 2) end
            H.syncPlates()
        end, [[INSERT INTO pol_vehicles (kind, owner_citizen_id, ownveh_id, plate, model, created_at, is_pool, server)
            SELECT 'player', c.id, v.id, NULLIF(v.plate, ''), v.model, UNIX_TIMESTAMP(), 0, ?
            FROM vehicles v JOIN pol_citizens c ON c.kind = 'player' AND c.is_pool = 0 AND c.account_name = v.account_name
            WHERE NOT EXISTS (SELECT 1 FROM pol_vehicles pv WHERE pv.ownveh_id = v.id)]], inst)
    end, [[INSERT INTO pol_citizens (kind, account_name, birth_date, `generated`, created_at, last_seen, is_pool, server)
        SELECT 'player', a.account_name,
            DATE_SUB(DATE(FROM_UNIXTIME(IF(a.created_at > 0, a.created_at, UNIX_TIMESTAMP()))), INTERVAL 18 YEAR),
            0, UNIX_TIMESTAMP(), 0, 0, ?
        FROM accounts a
        WHERE NOT EXISTS (SELECT 1 FROM pol_citizens c WHERE c.kind = 'player' AND c.account_name = a.account_name)]], inst)
end

-- "AB-123-C": unique among the owned vehicles
local LETTERS = "ABCDEFGHJKLMNPRSTUVWXYZ"
local function newPlate(used)
    for _ = 1, 50 do
        local function l() local i = math.random(#LETTERS) return LETTERS:sub(i, i) end
        local p = l() .. l() .. "-" .. ("%03d"):format(math.random(0, 999)) .. "-" .. l()
        if not used[p] then used[p] = true return p end
    end
    return nil
end

function H.syncPlates()
    -- owned vehicles without a plate: one is given and saved (not while the vehicle is out)
    POL.db.query(function(rows)
        if type(rows) ~= "table" then return end
        POL.db.query(function(plates)
            local used = {}
            for _, r in ipairs(type(plates) == "table" and plates or {}) do used[r.plate] = true end
            for _, r in ipairs(rows) do
                local out = false
                if POL.running("v_ownveh") then
                    local ok, s = pcall(function() return exports.v_ownveh:isVehicleSpawned(tonumber(r.id)) end)
                    out = ok and s and true or false
                end
                local plate = not out and newPlate(used)
                if plate then
                    POL.db.exec("UPDATE vehicles SET plate = ? WHERE id = ? AND (plate IS NULL OR plate = '')", plate, r.id)
                end
            end
            -- then every changed plate into pol_vehicles
            setTimer(function()
                POL.db.exec([[UPDATE pol_vehicles pv JOIN vehicles v ON v.id = pv.ownveh_id
                    SET pv.plate = v.plate, pv.model = v.model
                    WHERE pv.kind = 'player' AND v.plate IS NOT NULL AND v.plate <> ''
                      AND (pv.plate IS NULL OR pv.plate <> v.plate OR pv.model <> v.model)]])
            end, 3000, 1)
        end, "SELECT plate FROM vehicles WHERE plate IS NOT NULL AND plate <> ''")
    end, "SELECT id FROM vehicles WHERE plate IS NULL OR plate = '' LIMIT 500")
end

-- the citizen row of a logged-in player (made now if missing): cb(row | false)
function H.player(player, cb)
    local acc = POL.accountOf(player)
    if not acc then return cb(false) end
    POL.db.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        if r then
            POL.records.cacheCitizen(r)
            return cb(r)
        end
        local row = { kind = "player", account_name = acc, generated = 0, created_at = POL.now(), last_seen = POL.now() }
        POL.db.query(function(acRows)
            local a = type(acRows) == "table" and acRows[1]
            local created = a and tonumber(a.created_at) or 0
            if created <= 0 then created = POL.now() end
            local t = getRealTime(created)
            row.birth_date = ("%04d-%02d-%02d"):format(t.year + 1900 - 18, t.month + 1, t.monthday)
            POL.db.create("pol_citizens", row, function(id)
                if not id then return cb(false) end
                row.id = id
                POL.records.cacheCitizen(row)
                cb(row)
            end)
        end, "SELECT created_at FROM accounts WHERE account_name = ? LIMIT 1", acc)
    end, "SELECT * FROM pol_citizens WHERE kind = 'player' AND account_name = ? AND is_pool = 0 LIMIT 1", acc)
end

addEvent("onPlayerAccountLogin")
addEventHandler("onPlayerAccountLogin", root, function()
    local player = source
    if not POL.db.ready then return end
    H.player(player, function(row)
        if row and row.id then POL.db.exec("UPDATE pol_citizens SET last_seen = ? WHERE id = ?", POL.now(), row.id) end
    end)
end)

addEvent("onOwnedVehicleCreated")
addEventHandler("onOwnedVehicleCreated", root, function(id, acc, model, plate)
    if not POL.db.ready or not acc then return end
    POL.db.query(function(rows)
        local c = type(rows) == "table" and rows[1]
        POL.db.create("pol_vehicles", { kind = "player", owner_citizen_id = c and c.id or nil, ownveh_id = tonumber(id),
            plate = (plate and plate ~= "") and plate or nil, model = tonumber(model), created_at = POL.now() })
    end, "SELECT id FROM pol_citizens WHERE kind = 'player' AND account_name = ? AND is_pool = 0 LIMIT 1", acc)
end)

POL.on("db.ready", function()
    registerAll()
    if plateTimer and isTimer(plateTimer) then killTimer(plateTimer) end
    plateTimer = setTimer(H.syncPlates, POLICE.HISTORY.PLATE_CHECK, 0)
end)
