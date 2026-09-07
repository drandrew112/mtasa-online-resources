-- ui_browser :: server.lua
-- Server-side export wrappers plus the minimal Liberty Bank logic (deposit /
-- withdraw against player cash, balance stored in account data "bank_money").
-- A dedicated bank resource can later take over the "bank_*" actions.

addEvent("ui_browser:action", true)

-- ui_core:addNotification is a client export, so push notifications over an event.
local function notify(player, title, text)
    triggerClientEvent(player, "ui_browser:notify", resourceRoot, title, text)
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

-- exports.ui_browser:openBrowser(player)
function openBrowser(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "ui_browser:open", resourceRoot)
    return true
end

-- exports.ui_browser:openBrowserSite(player, "lvcars.vm")
function openBrowserSite(player, url)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "ui_browser:open", resourceRoot, tostring(url or "home"))
    return true
end

--------------------------------------------------------------------------------
-- bank
--------------------------------------------------------------------------------

local function getBank(player)
    return math.max(0, math.floor(tonumber(getElementData(player, "bank_money")) or 0))
end

local function setBank(player, amount)
    amount = math.max(0, math.floor(amount))
    setElementData(player, "bank_money", amount)
    local acc = getPlayerAccount(player)
    if acc and not isGuestAccount(acc) then
        setAccountData(acc, "bank_money", amount)
    end
end

local function resolveAmount(arg, available)
    if arg == "all" then return available end
    local n = math.floor(tonumber(arg) or 0)
    return n
end

local function bankDeposit(player, arg)
    local cash = getPlayerMoney(player)
    local amount = resolveAmount(arg, cash)
    if amount <= 0 then return end
    if cash < amount then
        notify(player, "Liberty Bank", "You do not have that much cash.")
        return
    end
    takePlayerMoney(player, amount)
    setBank(player, getBank(player) + amount)
    notify(player, "Liberty Bank", "Deposited $" .. amount .. ".")
end

local function bankWithdraw(player, arg)
    local bank = getBank(player)
    local amount = resolveAmount(arg, bank)
    if amount <= 0 then return end
    if bank < amount then
        notify(player, "Liberty Bank", "Your balance is too low.")
        return
    end
    setBank(player, bank - amount)
    givePlayerMoney(player, amount)
    notify(player, "Liberty Bank", "Withdrew $" .. amount .. ".")
end

--------------------------------------------------------------------------------
-- action router
--------------------------------------------------------------------------------

addEventHandler("ui_browser:action", root, function(url, verb, arg, category)
    local player = client
    if not isElement(player) then return end

    if verb == "bank_deposit" then
        bankDeposit(player, arg)
        triggerClientEvent(player, "ui_browser:refresh", resourceRoot)
        return
    elseif verb == "bank_withdraw" then
        bankWithdraw(player, arg)
        triggerClientEvent(player, "ui_browser:refresh", resourceRoot)
        return
    end

    if verb == "buy" then
        -- arg is "model" or "model:colour"
        local model, colour = arg:match("^([^:]+):?(.*)$")
        model = model or arg
        if category == "vehicles" then
            -- TODO: hook up [vehicles]/v_ownveh export once it exists, e.g.
            --   exports.v_ownveh:giveVehicle(player, model, colour)
            notify(player, "Dealership",
                "Order noted: " .. model .. (colour ~= "" and (" (" .. colour .. ")") or ""))
        else
            notify(player, "Purchase", "Request noted: " .. model)
        end
        outputServerLog(("[ui_browser] %s buy %s / %s colour=%s (%s)")
            :format(getPlayerName(player), tostring(category), model, tostring(colour), tostring(url)))
        return
    end

    outputServerLog(("[ui_browser] %s -> %s:%s (%s)")
        :format(getPlayerName(player), tostring(verb), tostring(arg), tostring(url)))
end)

--------------------------------------------------------------------------------
-- load stored balance
--------------------------------------------------------------------------------

local function loadBalance(player)
    local acc = getPlayerAccount(player)
    if acc and not isGuestAccount(acc) then
        setElementData(player, "bank_money", tonumber(getAccountData(acc, "bank_money")) or 0)
    end
end

addEventHandler("onPlayerLogin", root, function()
    loadBalance(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        loadBalance(player)
    end
end)
