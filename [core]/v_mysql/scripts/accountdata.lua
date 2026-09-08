-- v_mysql :: account data sync
--
-- Mirrors every player's MTA account data 1:1 into the shared
-- `global_account_data` table so the localhost dev server and the hosted
-- server work off one source of truth.
--
--   * on login  -> the row is pulled, decoded and pushed back into the
--                  account with setAccountData(), then v_accounts is told the
--                  "accountdata" loading step is done.
--   * periodically / on save -> v_accounts calls the exported
--                  updateAccountData(player), which upserts the whole snapshot.
--
-- Stored format (account_data column, JSON):
--   [ {"key":"money","value":"1500","valueType":"int"},
--     {"key":"name","value":"Joe","valueType":"string"}, ... ]

local TABLE     = "global_account_data"
local LOAD_TYPE = "accountdata"          -- v_accounts loading-gate id

--------------------------------------------------------------------------------
-- Value (de)serialisation
--------------------------------------------------------------------------------

local function packValue(v)
    local t = type(v)
    if t == "boolean" then
        return tostring(v), "boolean"
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return ("%d"):format(v), "int"
        end
        return tostring(v), "float"
    end
    return tostring(v), "string"
end

local function unpackValue(value, valueType)
    if valueType == "boolean" then
        return value == "true"
    elseif valueType == "int" or valueType == "float" then
        return tonumber(value)
    end
    return tostring(value)
end

local function encodeAccount(account)
    local rows = {}
    local all = getAllAccountData(account) or {}
    for key, value in pairs(all) do
        local packed, valueType = packValue(value)
        rows[#rows + 1] = { key = key, value = packed, valueType = valueType }
    end
    return toJSON(rows, true)
end

local function applyEncoded(account, jsonStr)
    local rows = fromJSON(jsonStr)
    if type(rows) ~= "table" then
        mysqlLog("account_data JSON could not be decoded for %s", getAccountName(account))
        return 0
    end
    local n = 0
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.key) == "string" then
            setAccountData(account, row.key, unpackValue(row.value, row.valueType))
            n = n + 1
        end
    end
    return n
end

--------------------------------------------------------------------------------
-- Load on login
--------------------------------------------------------------------------------

local function finishLoading(player)
    if not isElement(player) then return end
    local accountsRes = getResourceFromName("v_accounts")
    if accountsRes and getResourceState(accountsRes) == "running" then
        exports.v_accounts:loadingComplete(player, LOAD_TYPE)
    end
end

addEventHandler("onPlayerLogin", root, function(_, account)
    local player = source

    -- Sync off: don't touch the database, just tell v_accounts it can proceed.
    if not MYSQL_ENABLE_SYNC then
        finishLoading(player)
        return
    end

    if not account or isGuestAccount(account) then
        finishLoading(player)
        return
    end

    local accountName = getAccountName(account)

    mysqlQuery(function(result)
        if isElement(player) and getPlayerAccount(player) == account then
            if type(result) == "table" and result[1] and type(result[1].account_data) == "string" then
                local applied = applyEncoded(account, result[1].account_data)
                mysqlLog("Loaded %d account-data keys for %s", applied, accountName)
            else
                mysqlLog("No stored account data for %s (new account)", accountName)
            end
        end
        finishLoading(player)
    end, "SELECT account_data FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", accountName)
end)

--------------------------------------------------------------------------------
-- Push snapshot  (exported: updateAccountData)
--------------------------------------------------------------------------------

-- Upserts the player's complete current account data into the shared table.
-- Called by v_accounts' save system (periodic autosave, logout, quit, resource
-- stop). Returns whether the write was queued.
function updateAccountData(player)
    if not MYSQL_ENABLE_SYNC then return false end
    if not isElement(player) then return false end

    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return false end

    local accountName = getAccountName(account)
    local encoded     = encodeAccount(account)

    mysqlLog("Saving account data for %s (%s)", accountName, getPlayerName(player) or "?")

    return mysqlExec(
        "INSERT INTO `" .. TABLE .. "` (account_name, account_data) VALUES (?, ?) " ..
        "ON DUPLICATE KEY UPDATE account_data = VALUES(account_data)",
        accountName, encoded)
end
