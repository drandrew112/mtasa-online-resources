-- Bank kezelo - server side
--
-- bank_money is kept on the player element data at runtime and mirrored into the
-- account data so it survives reconnects / restarts. Cash is GTA's own money and
-- is only touched through takePlayerMoney / givePlayerMoney.
--
-- Persistence:
--   * onPlayerLoaded / onResourceStart -> load bank_money from account -> element data
--   * onPlayerQuit / onPlayerLogout / onResourceStop -> save element data -> account
--   * every SAVE_INTERVAL ms -> save every logged in player
--   * every export that changes bank_money -> save that player immediately

local SAVE_INTERVAL = 300000 -- periodic autosave, in ms (5 minutes)
local DATA_KEY      = "bank_money"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Returns the account for a logged in, non-guest player, or nil.
local function getSaveAccount(player)
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return nil end
    return account
end

-- Current bank balance of a player (always a non-negative integer).
local function getBankMoney(player)
    local money = tonumber(getElementData(player, DATA_KEY)) or 0
    return math.max(0, math.floor(money))
end

-- Sets the runtime balance and, when possible, persists it to the account.
local function setBankMoney(player, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    setElementData(player, DATA_KEY, amount)

    local account = getSaveAccount(player)
    if account then
        setAccountData(account, DATA_KEY, amount)
    end
    return amount
end

-- Persists the current runtime balance into the account.
local function saveBankMoney(player)
    local account = getSaveAccount(player)
    if not account then return end
    setAccountData(account, DATA_KEY, getBankMoney(player))
end

-- Loads the balance from the account into element data. Seeds 0 on first login.
local function loadBankMoney(player)
    local account = getSaveAccount(player)
    if not account then
        setElementData(player, DATA_KEY, 0)
        return
    end

    local stored = tonumber(getAccountData(account, DATA_KEY))
    if stored then
        setElementData(player, DATA_KEY, math.max(0, math.floor(stored)))
    else
        setElementData(player, DATA_KEY, 0)
        setAccountData(account, DATA_KEY, 0)
    end
end

-- Validates that the first export argument is an online player element.
local function resolvePlayer(player)
    if isElement(player) and getElementType(player) == "player" then
        return player
    end
    return nil
end

-- Normalises an amount argument to a positive integer, or nil when invalid.
local function normaliseAmount(amount)
    amount = tonumber(amount)
    if not amount then return nil end
    amount = math.floor(amount)
    if amount <= 0 then return nil end
    return amount
end

--------------------------------------------------------------------------------
-- Load / save lifecycle
--------------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        loadBankMoney(player)
    end
end)

-- onPlayerLoaded (not onPlayerLogin): fires after v_accounts has synced the
-- account data from the shared MySQL store, so bank_money is up to date.
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    loadBankMoney(source)
end)

addEventHandler("onPlayerLogout", root, function()
    -- The account is still attached here (v_accounts cancels the event and logs
    -- out itself afterwards), so the save goes through.
    saveBankMoney(source)
end)

addEventHandler("onPlayerQuit", root, function()
    saveBankMoney(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        saveBankMoney(player)
    end
end)

setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do
        saveBankMoney(player)
    end
end, SAVE_INTERVAL, 0)

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

-- Removes bank money. -> true | "not_enough_money" | "player_not_found"
function takeBankMoney(player, amount)
    player = resolvePlayer(player)
    if not player then return "player_not_found" end

    amount = normaliseAmount(amount)
    if not amount then return "player_not_found" end

    local balance = getBankMoney(player)
    if balance < amount then
        return "not_enough_money"
    end

    setBankMoney(player, balance - amount)
    return true
end

-- Adds bank money. -> true | "player_not_found"
function giveBankMoney(player, amount)
    player = resolvePlayer(player)
    if not player then return "player_not_found" end

    amount = normaliseAmount(amount)
    if not amount then return "player_not_found" end

    setBankMoney(player, getBankMoney(player) + amount)
    return true
end

-- Moves money from cash to the bank account.
-- -> true | "player_not_found" | "not_enough_cash"
function depositMoney(player, amount)
    player = resolvePlayer(player)
    if not player then return "player_not_found" end

    amount = normaliseAmount(amount)
    if not amount then return "player_not_found" end

    if getPlayerMoney(player) < amount then
        return "not_enough_cash"
    end

    takePlayerMoney(player, amount)
    setBankMoney(player, getBankMoney(player) + amount)
    return true
end

-- Moves money from the bank account to cash.
-- -> true | "player_not_found" | "not_enough_money"
-- (the spec labels this "not_enough_cash"; the check is on the bank balance,
--  so the error is named accordingly - see README.)
function withdrawMoney(player, amount)
    player = resolvePlayer(player)
    if not player then return "player_not_found" end

    amount = normaliseAmount(amount)
    if not amount then return "player_not_found" end

    local balance = getBankMoney(player)
    if balance < amount then
        return "not_enough_money"
    end

    setBankMoney(player, balance - amount)
    givePlayerMoney(player, amount)
    return true
end

-- Plays the "pickup money" sound effect for a player (or everyone when omitted).
-- -> true | "player_not_found"
function playPickupMoneySound(player)
    if player == nil then
        triggerClientEvent(root, "v_bank:playPickupMoneySound", root)
        return true
    end

    player = resolvePlayer(player)
    if not player then return "player_not_found" end

    triggerClientEvent(player, "v_bank:playPickupMoneySound", player)
    return true
end

-- Creates a money bag pickup at a position. When a player walks into it they get
-- the cash, the pickup sound plays for them and the pickup is destroyed.
--   money  : cash to give, positive integer
--   player : optional - only this player can collect it; nil = anyone
-- -> pickup element | false (invalid arguments)
function createMoneyPickup(x, y, z, money, player)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    money = normaliseAmount(money)
    if not (x and y and z and money) then return false end

    if player ~= nil then
        player = resolvePlayer(player)
        if not player then return false end
    end

    local moneyBag = createPickup(x, y, z, 3, 1550)
    if not moneyBag then return false end

    local collected = false
    addEventHandler("onPickupHit", moneyBag, function(hitPlayer)
        if collected then return end
        if not isElement(hitPlayer) or getElementType(hitPlayer) ~= "player" then return end
        if player and hitPlayer ~= player then return end

        collected = true
        givePlayerMoney(hitPlayer, money)
        triggerClientEvent(hitPlayer, "v_bank:playPickupMoneySound", hitPlayer, money)
        destroyElement(moneyBag)
    end)

    return moneyBag
end
