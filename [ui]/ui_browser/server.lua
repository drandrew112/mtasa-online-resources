-- ui_browser :: server.lua
-- Server-side export wrappers + the action router. Liberty Bank goes through the
-- v_bank exports; balance persistence is entirely v_bank's job.

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

-- exports.ui_browser:openBrowserSite(player, "lvcars.eu")
function openBrowserSite(player, url)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    triggerClientEvent(player, "ui_browser:open", resourceRoot, tostring(url or "home"))
    return true
end

--------------------------------------------------------------------------------
-- Liberty Bank (via v_bank exports)
--------------------------------------------------------------------------------

local function bankReady()
    local res = getResourceFromName("v_bank")
    return res and getResourceState(res) == "running"
end

-- kind = "bank_deposit" | "bank_withdraw"; arg = "<amount>" | "all"
local function bankTransaction(player, kind, arg)
    if not bankReady() then
        outputServerLog("[ui_browser] Liberty Bank: v_bank resource is not running")
        return
    end

    local amount
    if arg == "all" then
        if kind == "bank_deposit" then
            amount = getPlayerMoney(player)
        else
            amount = tonumber(getElementData(player, "bank_money")) or 0
        end
    else
        amount = tonumber(arg)
    end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local result
    if kind == "bank_deposit" then
        result = exports.v_bank:depositMoney(player, amount)
    else
        result = exports.v_bank:withdrawMoney(player, amount)
    end

    -- Only report + refresh when the transaction actually went through.
    if result == true then
        notify(player, "Liberty Bank",
            (kind == "bank_deposit" and "Deposited $" or "Withdrew $") .. amount .. ".")
        triggerClientEvent(player, "ui_browser:refresh", resourceRoot)
    else
        outputServerLog(("[ui_browser] Liberty Bank %s %s failed: %s")
            :format(kind, amount, tostring(result)))
    end
end

--------------------------------------------------------------------------------
-- action router
--------------------------------------------------------------------------------

addEventHandler("ui_browser:action", root, function(url, verb, arg, category)
    local player = client
    if not isElement(player) then return end

    if verb == "bank_deposit" or verb == "bank_withdraw" then
        bankTransaction(player, verb, arg)
        return
    end

    if verb == "buy" then
        -- arg is "<productId>" or "<productId>:<colour>"
        local id, colour = arg:match("^([^:]+):?(.*)$")
        id = id or arg
        if colour == "" then colour = nil end

        if category == "vehicles" and Dealership and Dealership.isVehicleProduct(id) then
            Dealership.purchase(player, id, colour, url)
        elseif category == "vehicles" then
            -- A vehicles site registered by another resource: it owns the sale.
            notify(player, "Dealership",
                "Order noted: " .. id .. (colour and (" (" .. colour .. ")") or ""))
        else
            notify(player, "Purchase", "Request noted: " .. id)
        end
        outputServerLog(("[ui_browser] %s buy %s / %s colour=%s (%s)")
            :format(getPlayerName(player), tostring(category), id, tostring(colour), tostring(url)))
        return
    end

    outputServerLog(("[ui_browser] %s -> %s:%s (%s)")
        :format(getPlayerName(player), tostring(verb), tostring(arg), tostring(url)))
end)
