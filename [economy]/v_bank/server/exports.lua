-- v_bank / server/exports.lua
-- The bank API for other resources (DESIGN.md 6, README.md). Every booking takes a transaction
-- key of shared/keys.lua.

local function valid(player)
    return isElement(player) and getElementType(player) == "player"
end

--------------------------------------------------------------------------------
-- accounts
--------------------------------------------------------------------------------

--- the accounts are loaded (bookings work)
function isBankReady()
    return BANK.started == true
end

--- keys that count as legal company income for the hourly company tax (gov_tax)
function getTaxableKeys()
    local out = {}
    for key, def in pairs(TX_KEYS) do
        if def.taxable then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

function getPlayerAccount(player)
    return valid(player) and PLAYER_ACC[player] or false
end

function getPlayerBalance(player)
    local a = valid(player) and getAcc(PLAYER_ACC[player])
    return a and a.balance or false
end

function getCompanyAccount(companyId)
    local a = findAcc("company", tostring(tonumber(companyId) or companyId))
    return a and a.id or false
end

function getStateAccount(code)
    local a = findAcc("state", tostring(code or ""))
    return a and a.id or false
end

function getAccountInfo(id)
    local a = getAcc(id)
    if not a then return false end
    return { id = a.id, number = a.number, kind = a.kind, ownerRef = a.ownerRef, name = a.name,
             balance = a.balance, status = a.status, allowNegative = a.allowNegative }
end

function getBalance(id)
    local a = getAcc(id)
    return a and a.balance or false
end

--- every cached state account: { info, ... } (gov_core)
function getStateAccounts()
    local out = {}
    for _, a in pairs(ACC) do
        if a.kind == "state" then out[#out + 1] = getAccountInfo(a.id) end
    end
    table.sort(out, function(x, y) return x.id < y.id end)
    return out
end

--- creates the account of a biz_core organization (async: onBankAccountReady) -> true
function createCompanyAccount(companyId, name, founderAccountName)
    companyId = tostring(tonumber(companyId) or "")
    if companyId == "" then return false end
    createAccount("company", companyId, name, false, "biz_core", function(a)
        if a and type(founderAccountName) == "string" and founderAccountName ~= "" then
            setAccess(a.id, founderAccountName, "owner", "biz_core")
        end
    end)
    return true
end

--- creates a state company account (gov_core; async: onBankAccountReady) -> true | false, err
function createStateAccount(code, name, allowNegative, actor)
    code = tostring(code or ""):lower()
    if not code:match("^[a-z0-9_]+$") or #code < 3 or #code > 24 then return false, "bad_code" end
    if findAcc("state", code) then return false, "code_taken" end
    createAccount("state", code, tostring(name or code), allowNegative == true, actor or "")
    return true
end

function renameAccount(id, name)
    local a = getAcc(id)
    name = tostring(name or "")
    if not a or name == "" then return false end
    a.name = DB.clip(name, 64)
    DB.exec("UPDATE bank_accounts SET name = ? WHERE id = ?", a.name, a.id)
    return true
end

--- status = "active" | "frozen"
function setAccountStatus(id, status)
    local a = getAcc(id)
    if not a or (status ~= "active" and status ~= "frozen") or a.status == "closed" then return false end
    a.status = status
    DB.exec("UPDATE bank_accounts SET status = ? WHERE id = ?", status, a.id)
    return true
end

--- the overdraft list (DESIGN.md 3.2)
function setAllowNegative(id, allow)
    local a = getAcc(id)
    if not a then return false end
    a.allowNegative = allow == true
    DB.exec("UPDATE bank_accounts SET allow_negative = ? WHERE id = ?", a.allowNegative and 1 or 0, a.id)
    return true
end

--- closes an empty account -> true | false, "not_empty" | "unknown" | "protected"
function closeAccount(id)
    local a = getAcc(id)
    if not a then return false, "unknown" end
    if a.kind == "state" and a.ownerRef == BANK.TREASURY then return false, "protected" end
    if a.balance ~= 0 then return false, "not_empty" end
    a.status = "closed"
    DB.exec("UPDATE bank_accounts SET status = 'closed', closed_at = ? WHERE id = ?", BANK.now(), a.id)
    return true
end

--- role = "owner" | "manager" | "viewer" | nil (remove)
function setAccess(id, accountName, role, actor)
    id = tonumber(id)
    accountName = tostring(accountName or ""):lower()
    if not id or accountName == "" then return false end
    if role ~= nil and role ~= "owner" and role ~= "manager" and role ~= "viewer" then return false end
    if role then
        DB.exec("INSERT INTO bank_account_access (account_id, account_name, role, granted_by, granted_at) VALUES (?, ?, ?, ?, ?) "
            .. "ON DUPLICATE KEY UPDATE role = VALUES(role), granted_by = VALUES(granted_by), granted_at = VALUES(granted_at)",
            id, accountName, role, DB.clip(actor, 64), BANK.now())
    else
        DB.exec("DELETE FROM bank_account_access WHERE account_id = ? AND account_name = ?", id, accountName)
    end
    for player, map in pairs(ACCESS) do
        if BANK.accountOf(player) == accountName then map[id] = role end
    end
    return true
end

function hasAccess(player, id, need)
    return valid(player) and hasAccessRole(player, id, need or "view") or false
end

--------------------------------------------------------------------------------
-- bookings
--------------------------------------------------------------------------------

function credit(id, amount, key, params, actor, fromId)
    return BOOK.move(fromId, id, amount, key, params, actor)
end

function debit(id, amount, key, params, actor, toId)
    return BOOK.move(id, toId, amount, key, params, actor)
end

function transfer(fromId, toId, amount, key, params, actor)
    return BOOK.move(fromId, toId, amount, key, params, actor)
end

--------------------------------------------------------------------------------
-- player wrappers (the old API, now with a key)
--------------------------------------------------------------------------------

local function actorOf(player) return BANK.accountOf(player) or "" end

--- adds bank money -> true | err ("player_not_found" | "unavailable" | "bad_key" | ...)
function giveBankMoney(player, amount, key, params, payerId)
    if not valid(player) then return "player_not_found" end
    local id = PLAYER_ACC[player]
    if not id then return "unavailable" end
    local ok, err = BOOK.move(payerId, id, amount, key, params, actorOf(player))
    return ok or err
end

--- removes bank money -> true | "not_enough_money" | err
function takeBankMoney(player, amount, key, params, payeeId)
    if not valid(player) then return "player_not_found" end
    local id = PLAYER_ACC[player]
    if not id then return "unavailable" end
    local def = TX_KEYS[key]
    if def and def.force then return "bad_key" end  -- forced keys go through forceTakeMoney
    local ok, err = BOOK.move(id, payeeId, amount, key, params, actorOf(player))
    return ok or err
end

--- takes it whatever the balance is (debt); only for force keys -> true, newBalance | err
function forceTakeMoney(player, amount, key, params, payeeId)
    if not valid(player) then return "player_not_found" end
    local id = PLAYER_ACC[player]
    if not id then return "unavailable" end
    local def = TX_KEYS[key]
    if not def or not def.force then return "bad_key" end
    local ok, err = BOOK.move(id, payeeId, amount, key, params, actorOf(player))
    if not ok then return err end
    return true, getAcc(id).balance
end

--- cash -> bank -> true | "not_enough_cash" | err
function depositMoney(player, amount)
    if not valid(player) then return "player_not_found" end
    local id = PLAYER_ACC[player]
    if not id then return "unavailable" end
    amount = BOOK.amountOf(amount)
    if not amount then return "bad_amount" end
    if getPlayerMoney(player) < amount then return "not_enough_cash" end
    local ok, err = BOOK.move(nil, id, amount, "cash.deposit", nil, actorOf(player))
    if not ok then return err end
    takePlayerMoney(player, amount)
    BOOK.showMoney(player, "take", amount, "cash")
    return true
end

--- bank -> cash -> true | "not_enough_money" | err
function withdrawMoney(player, amount)
    if not valid(player) then return "player_not_found" end
    local id = PLAYER_ACC[player]
    if not id then return "unavailable" end
    amount = BOOK.amountOf(amount)
    if not amount then return "bad_amount" end
    local ok, err = BOOK.move(id, nil, amount, "cash.withdraw", nil, actorOf(player))
    if not ok then return err end
    givePlayerMoney(player, amount)
    BOOK.showMoney(player, "add", amount, "cash")
    return true
end

--- pays from the cash when it covers the amount, else from the bank (only that is booked)
--- -> true, "cash" | true, "bank" | false, "not_enough_money" | false, err
function payMoney(player, amount, key, params)
    if not valid(player) then return false, "player_not_found" end
    amount = BOOK.amountOf(amount)
    if not amount then return false, "bad_amount" end
    if getPlayerMoney(player) >= amount then
        takePlayerMoney(player, amount)
        BOOK.showMoney(player, "take", amount, "cash")
        return true, "cash"
    end
    local id = PLAYER_ACC[player]
    if not id then return false, "not_enough_money" end
    local ok, err = BOOK.move(id, nil, amount, key, params, actorOf(player))
    if not ok then return false, err end
    return true, "bank"
end
