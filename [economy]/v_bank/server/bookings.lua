-- v_bank / server/bookings.lua
-- Every balance change goes through BOOK.move (DESIGN.md 4-5): key check, funds check, cache
-- update, then a delta UPDATE + one ledger row per account side (fire and forget, retried by
-- v_mysql after a reconnect; same connection = in order).
--
-- BOOK.move(fromId, toId, amount, key, params, actor) -> true, ref | false, err
--   fromId / toId = account id, or nil for an outside side (system / cash / settled; "treasury"
--   and "payer" are filled in here). err: "bad_amount" | "bad_key" | "unavailable" |
--   "not_enough_money" | "account_closed" | "frozen" | "same_account"

BOOK = {}

local seq = 0
local function newRef()
    seq = seq + 1
    return DB.clip(("%s-%d-%d"):format(BANK.instance(), getTickCount(), seq), 32)
end

local function amountOf(v)
    v = math.floor(tonumber(v) or 0)
    if v <= 0 or v > BANK.MAX_AMOUNT then return nil end
    return v
end
BOOK.amountOf = amountOf

--- params JSON (+ the kept params table): only the keys the transaction key allows, short values
local function paramsJson(def, params)
    if type(params) ~= "table" or not def.params then return "", {} end
    local out, any = {}, false
    for _, k in ipairs(def.params) do
        local v = params[k]
        if v ~= nil then
            if type(v) == "number" then out[k] = v
            elseif type(v) == "boolean" then out[k] = v
            else out[k] = DB.clip(v, 48) end
            any = true
        end
    end
    if not any then return "", out end
    local json = toJSON(out, true) or ""
    if #json > 255 then return "", out end
    return json, out
end

--- does a side spec of a key accept this account (or nil = outside)?
local function sideAccepts(spec, a)
    if spec == "system" or spec == "cash" or spec == "settled" then return a == nil end
    if spec == "treasury" then return a ~= nil and a.kind == "state" and a.ownerRef == BANK.TREASURY end
    if spec == "payer" then return a == nil or a.kind == "state" or a.kind == "company" end
    if type(spec) == "table" then return a ~= nil and spec[a.kind] == true end
    return false
end

local function treasury() return findAcc("state", BANK.TREASURY) end

--- writes one side: cache, delta UPDATE, ledger row
local function bookSide(id, a, delta, key, json, kept, counterId, ref, actor)
    local balanceAfter
    if a then
        a.balance = a.balance + delta
        a.sync = (a.sync or 0) + delta
        balanceAfter = a.balance
    end
    DB.exec("UPDATE bank_accounts SET balance = balance + ? WHERE id = ?", delta, id)
    -- NULL written as a literal (no nil in the placeholder list)
    DB.exec(("INSERT INTO bank_ledger (account_id, ts, amount, balance_after, tx_key, params, counter_id, ref, actor, instance) VALUES (?, ?, ?, %s, ?, ?, %s, ?, ?, ?)")
        :format(balanceAfter and tostring(math.floor(balanceAfter)) or "NULL", counterId and tostring(math.floor(counterId)) or "NULL"),
        id, BANK.now(), delta, key, json, ref, DB.clip(actor, 64), DB.clip(BANK.instance(), 16))
    if a then ACCOUNTS_changed(a, delta, key, kept) end
end

--- id may be an id of an account that is not cached (offline personal account): then the side is
--- written blind (delta), which is only allowed for receiving or for admin bookings
function BOOK.move(fromId, toId, amount, key, params, actor)
    local def = TX_KEYS[key]
    if not def then
        outputDebugString(("[v_bank] unknown key %s (from %s)"):format(tostring(key),
            sourceResource and getResourceName(sourceResource) or "?"), 2)
        return false, "bad_key"
    end
    amount = amountOf(amount)
    if not amount then return false, "bad_amount" end

    fromId, toId = tonumber(fromId), tonumber(toId)
    if not fromId and def.from == "treasury" then local t = treasury(); fromId = t and t.id end
    if not toId and def.to == "treasury" then local t = treasury(); toId = t and t.id end
    if fromId and toId and fromId == toId then return false, "same_account" end

    local from, to = fromId and ACC[fromId], toId and ACC[toId]
    -- an uncached account: blind only where nothing has to be checked on it
    if fromId and not from and not def.admin then return false, "unavailable" end
    if toId and not to and type(def.to) ~= "table" and not def.admin then return false, "unavailable" end
    if (def.from == "treasury" and not fromId) or (def.to == "treasury" and not toId) then return false, "unavailable" end

    -- the key's sides (an uncached id is checked by kind when known, else accepted for admin keys)
    if fromId and from and not sideAccepts(def.from, from) then return false, "bad_key" end
    if not fromId and not sideAccepts(def.from, nil) then return false, "bad_key" end
    if toId and to and not sideAccepts(def.to, to) then return false, "bad_key" end
    if not toId and not sideAccepts(def.to, nil) then return false, "bad_key" end

    for _, a in ipairs({ from or false, to or false }) do
        if a and not def.admin then
            if a.status == "closed" then return false, "account_closed" end
            if a.status == "frozen" then return false, "frozen" end
        end
    end

    if from and not def.force and not from.allowNegative and from.balance < amount then
        return false, "not_enough_money"
    end

    local json, kept = paramsJson(def, params)
    local ref = newRef()
    if fromId then bookSide(fromId, from, -amount, key, json, kept, toId, ref, actor) end
    if toId then bookSide(toId, to, amount, key, json, kept, fromId, ref, actor) end
    return true, ref
end

--- the personal account id of a player, or nil
function BOOK.playerAccount(player)
    return isElement(player) and PLAYER_ACC[player] or nil
end

--- shows a money change on the player's HUD (ui_core money overlay)
function BOOK.showMoney(player, kind, amount, moneyType)
    if isElement(player) and isResourceRunning("ui_core") then
        exports.ui_core:showMoney(player, kind, amount, moneyType)
    end
end
