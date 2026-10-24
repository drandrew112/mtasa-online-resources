-- v_bank / server/accounts.lua
-- The account cache (DESIGN.md 5).
--   * state + company accounts: all of them, loaded on start and re-read every BANK.RESYNC_MS
--   * personal accounts: the ones of the players logged in on this server (created on first login)
-- The database is the truth; every booking is a delta, so the cache only needs the deltas booked
-- here since the last re-read (acc.sync) to stay exact (same trick as biz_core CO.resync).
--
-- ACC[id] = { id, number, kind, ownerRef, name, balance, status, allowNegative, sync, player }

ACC = {}         -- [id] = account
local OWNER = {} -- ["kind:ref"] = id
PLAYER_ACC = {}  -- [player] = id of the personal account
ACCESS = {}      -- [player] = { [accountId] = role }

addEvent("onBankBalanceChanged", false)  -- (accountId, balance, amount, key, params), source = resourceRoot
addEvent("onBankAccountReady", false)    -- (accountId, kind, ownerRef), source = resourceRoot

local function ownerKey(kind, ref) return kind .. ":" .. tostring(ref):lower() end

--- account from a DB row (adds or updates the cache entry, keeps acc.sync / acc.player)
local function fromRow(r)
    local id = DB.int(r.id)
    local a = ACC[id]
    if not a then
        a = { id = id, sync = 0 }
        ACC[id] = a
    end
    a.number = r.number and tostring(r.number) or ""
    a.kind = tostring(r.kind)
    a.ownerRef = tostring(r.owner_ref)
    a.name = tostring(r.name or "")
    a.status = tostring(r.status or "active")
    a.allowNegative = DB.int(r.allow_negative) == 1
    if a.balance == nil then a.balance = DB.int(r.balance) end
    OWNER[ownerKey(a.kind, a.ownerRef)] = id
    return a
end

local function forget(a)
    ACC[a.id] = nil
    OWNER[ownerKey(a.kind, a.ownerRef)] = nil
end

--- mirrors a personal balance to its player and announces the change
function ACCOUNTS_changed(a, amount, key, params)
    if a.player and isElement(a.player) then
        setElementData(a.player, "bank_money", a.balance)
        -- every booking on the own account shows on the money HUD (not the re-read corrections)
        if key ~= "resync" and amount and amount ~= 0 then
            BOOK.showMoney(a.player, amount > 0 and "add" or "take", math.abs(amount), "bank")
        end
    end
    triggerEvent("onBankBalanceChanged", resourceRoot, a.id, a.balance, amount or 0, key or "", params or {})
end

function getAcc(id) return ACC[tonumber(id) or -1] end

function findAcc(kind, ref)
    local id = OWNER[ownerKey(kind, ref)]
    return id and ACC[id] or nil
end

--------------------------------------------------------------------------------
-- creating accounts
--------------------------------------------------------------------------------

local SELECT_COLS = "id, number, kind, owner_ref, name, balance, allow_negative, status"

--- creates the account when missing (idempotent: uq_owner) and loads it. cb(acc | false)
function createAccount(kind, ref, name, allowNegative, createdBy, cb)
    cb = cb or function() end
    ref = tostring(ref):lower()
    local existing = findAcc(kind, ref)
    if existing then return cb(existing) end
    DB.query(function(ok, err)
        if ok == false then
            outputDebugString("[v_bank] create " .. kind .. " " .. ref .. " failed: " .. tostring(err), 1)
            return cb(false)
        end
        DB.query(function()
            DB.query(function(rows)
                local r = rows and rows[1]
                if not r then return cb(false) end
                local a = fromRow(r)
                triggerEvent("onBankAccountReady", resourceRoot, a.id, a.kind, a.ownerRef)
                cb(a)
            end, "SELECT " .. SELECT_COLS .. " FROM bank_accounts WHERE kind = ? AND owner_ref = ?", kind, ref)
        end, "UPDATE bank_accounts SET number = " .. BANK.numberSql() .. " WHERE number IS NULL")
    end, "INSERT IGNORE INTO bank_accounts (kind, owner_ref, name, allow_negative, created_at, created_by) VALUES (?, ?, ?, ?, ?, ?)",
        kind, ref, DB.clip(name, 64), allowNegative and 1 or 0, BANK.now(), DB.clip(createdBy, 64))
end

--------------------------------------------------------------------------------
-- personal accounts of the players on this server
--------------------------------------------------------------------------------

local loading = {}  -- [player] = account name being loaded

local function bindPlayer(player, a)
    a.player = player
    PLAYER_ACC[player] = a.id
    setElementData(player, "bank_money", a.balance)
    setElementData(player, "bank_account", a.number)
end

--- the bank accounts (not personal) this player may use, from bank_account_access
function loadAccess(player, cb)
    local name = BANK.accountOf(player)
    if not name then return cb and cb(false) end
    DB.query(function(rows)
        if not isElement(player) then return end
        local map = {}
        for _, r in ipairs(rows or {}) do map[DB.int(r.account_id)] = tostring(r.role) end
        ACCESS[player] = map
        if cb then cb(map) end
    end, "SELECT account_id, role FROM bank_account_access WHERE account_name = ?", name)
end

function loadPlayer(player)
    local name = BANK.accountOf(player)
    if not name or PLAYER_ACC[player] or loading[player] == name then return end
    -- not before the migration: an account created here first would block the migrated balance
    if not BANK.started then return end
    loading[player] = name

    local function done(a)
        if loading[player] ~= name then return end
        loading[player] = nil
        if not isElement(player) or BANK.accountOf(player) ~= name then return end
        if not a then
            outputDebugString("[v_bank] personal account of " .. name .. " could not be loaded", 1)
            return
        end
        bindPlayer(player, a)
        loadAccess(player)
    end

    DB.query(function(rows)
        local r = rows and rows[1]
        if r then return done(fromRow(r)) end
        if rows == false then return done(false) end
        createAccount("personal", name, getElementData(player, "accName") or name, false, "login", done)
    end, "SELECT " .. SELECT_COLS .. " FROM bank_accounts WHERE kind = 'personal' AND owner_ref = ?", name)
end

local function unloadPlayer(player)
    loading[player] = nil
    ACCESS[player] = nil
    local id = PLAYER_ACC[player]
    PLAYER_ACC[player] = nil
    local a = id and ACC[id]
    if a and a.kind == "personal" then forget(a) end
end

addEvent("onPlayerAccountLogin")
addEventHandler("onPlayerAccountLogin", root, function() loadPlayer(source) end)

-- fallback: the account may have been loaded before v_bank started
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function() loadPlayer(source) end)

addEventHandler("onPlayerQuit", root, function() unloadPlayer(source) end)

-- bank_money / bank_account are synced element data: a client must not change them
addEventHandler("onElementDataChange", root, function(key, old)
    if (key == "bank_money" or key == "bank_account") and client then
        if old == nil then removeElementData(source, key) else setElementData(source, key, old) end
    end
end)

--------------------------------------------------------------------------------
-- re-read of the shared accounts (and the cached personal ones)
--------------------------------------------------------------------------------

function resyncAccounts(cb)
    if not DB.ready then return cb and cb(false) end
    local personal = {}
    local before = {}   -- [id] = account cached when the re-read started
    for id, a in pairs(ACC) do
        a.sync = 0
        before[id] = a
        if a.kind == "personal" then personal[#personal + 1] = id end
    end
    local where = "kind <> 'personal'"
    if #personal > 0 then where = where .. " OR id IN (" .. table.concat(personal, ",") .. ")" end
    DB.query(function(rows)
        if not rows then return cb and cb(false) end
        for _, r in ipairs(rows) do
            local id = DB.int(r.id)
            before[id] = nil
            local a = ACC[id]
            if a or tostring(r.kind) ~= "personal" then
                local isNew = not a
                a = fromRow(r)
                local fresh = DB.int(r.balance) + (a.sync or 0)
                if not isNew and fresh ~= a.balance then
                    local delta = fresh - a.balance
                    a.balance = fresh
                    ACCOUNTS_changed(a, delta, "resync")
                end
                if a.player and isElement(a.player) then setElementData(a.player, "bank_account", a.number) end
            end
        end
        -- rows deleted from the database by hand: drop them, a player gets a fresh personal account
        for id, a in pairs(before) do
            if ACC[id] == a then
                forget(a)
                local player = a.player
                if player and PLAYER_ACC[player] == id then
                    PLAYER_ACC[player] = nil
                    if isElement(player) then loadPlayer(player) end
                end
            end
        end
        -- the state accounts of BANK.STATE (the treasury) come back without a restart
        for _, s in ipairs(BANK.STATE) do
            if not findAcc("state", s.code) then createAccount("state", s.code, s.name, s.allowNegative, "resync") end
        end
        if cb then cb(true) end
    end, "SELECT " .. SELECT_COLS .. " FROM bank_accounts WHERE " .. where)
end

--- after the migration: shared accounts, then every logged-in player
function startAccounts()
    BANK.started = true
    resyncAccounts(function()
        for _, player in ipairs(getElementsByType("player")) do loadPlayer(player) end
        triggerEvent("v_bank:ready", resourceRoot)
    end)
    setTimer(resyncAccounts, BANK.RESYNC_MS, 0)
end
addEvent("v_bank:ready", false)

--------------------------------------------------------------------------------
-- access
--------------------------------------------------------------------------------

--- role of a player on an account: "owner" for the own personal account, else the access row
function roleOf(player, id)
    id = tonumber(id)
    if not id then return nil end
    if PLAYER_ACC[player] == id then return "owner" end
    local map = ACCESS[player]
    return map and map[id] or nil
end

--- need = "view" (any role) | "use" (owner / manager)
function hasAccessRole(player, id, need)
    local role = roleOf(player, id)
    if not role then return false end
    if need == "use" then return role == "owner" or role == "manager" end
    return true
end
