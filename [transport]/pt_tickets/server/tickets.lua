-- Ticket sales of every public transport mode. A mode adapter (server/rail.lua; buses later,
-- in this file or from another resource through openTicketSale) builds an offer = the stops the
-- player can travel to from where the vehicle stands now; this file prices it (gov_transport
-- getTransportFare), shows the DX panel (client/panel.lua), takes the money (v_bank pt.ticket,
-- cash first, then the bank) and books the same sum to the fare receiver (gov_transport bookFareIncome).
--
-- offer = {
--   mode = "rail", ref = <trip / run id>, line = "IC 2101", title = <name, text or message>,
--   category = "IC" | "RB" | ..., operator = "Sunline Rail",
--   from = <stop index>, fromName = <text or message>,
--   stops = { { index = <stop index>, name = <text or message>, km = <distance from `from`> }, ... },
--   ctx = { ... }          -- the adapter's own data (returned in onPlayerTicketBought)
-- }
-- ticket = { mode, ref, line, category, from, to, fromName, toName, price, km, bought }

PT = PT or {}
Tickets = {}            -- [player] = ticket (one at a time)
local offers = {}       -- [player] = offer (+ prices, expires)

PT.ADAPTERS = {}        -- [mode] = { check = function(player, offer) -> ok, reason }

addEvent("onPlayerTicketBought")    -- source: player, (mode, ticket, ctx)
addEvent("onPlayerTicketEnded")     -- source: player, (mode, ticket, reason)

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function now() return getRealTime().timestamp end

function PT.tell(player, text, title)
    if isElement(player) then triggerClientEvent(player, "pt:notify", resourceRoot, title or "", text) end
end

-- plain text of a name for the bank ledger (message objects resolved in the default language)
local function plain(x)
    if type(x) == "table" then
        local ok, s = pcall(L.resolveFor, "en", x)
        return ok and type(s) == "string" and s or "?"
    end
    return tostring(x or "")
end

------------------------------------------------------------------ prices

function PT.fare(mode, km, category)
    if running("gov_transport") then
        local ok, price = pcall(function() return exports.gov_transport:getTransportFare(mode, km, category) end)
        if ok and tonumber(price) then return math.floor(tonumber(price)) end
    end
    local f = PTT.FALLBACK[mode] or PTT.FALLBACK.rail
    local base = math.max(f.fare_min, math.floor(km * f.fare_km + 0.5))
    return base + (tostring(category):upper() == "IC" and f.ic_supplement or 0)
end

------------------------------------------------------------------ tickets

function PT.getTicket(player) return Tickets[player] end

function PT.endTicket(player, reason)
    local t = Tickets[player]
    if not t then return end
    Tickets[player] = nil
    triggerEvent("onPlayerTicketEnded", player, t.mode, t, reason or "ended")
end

------------------------------------------------------------------ the sale

local function closeSale(player)
    if offers[player] then
        offers[player] = nil
        if isElement(player) then triggerClientEvent(player, "pt:sale:close", resourceRoot) end
    end
end
PT.closeSale = closeSale

--- opens the ticket panel with this offer (see the top of the file) -> true | false
function PT.openSale(player, offer)
    if not isElement(player) or type(offer) ~= "table" or type(offer.stops) ~= "table" or #offer.stops == 0 then return false end
    local view = {}
    for i, st in ipairs(offer.stops) do
        st.price = PT.fare(offer.mode, st.km or 0, offer.category)
        view[i] = { name = st.name, km = math.floor((st.km or 0) * 10 + 0.5) / 10, price = st.price }
    end
    offer.expires = now() + PTT.OFFER_TIME
    offers[player] = offer
    local bank = running("v_bank") and tonumber(exports.v_bank:getPlayerBalance(player)) or nil
    triggerClientEvent(player, "pt:sale:open", resourceRoot, {
        operator = offer.operator, line = offer.line, title = offer.title, category = offer.category,
        fromName = offer.fromName, stops = view, cash = getPlayerMoney(player), bank = bank,
        supplement = tostring(offer.category):upper() == "IC",
    })
    return true
end

addEvent("pt:sale:buy", true)
addEventHandler("pt:sale:buy", resourceRoot, function(i)
    local player = client
    local offer = offers[player]
    if not offer then return end
    local st = offer.stops[tonumber(i) or 0]
    if not st then return end
    if now() > offer.expires then
        closeSale(player)
        PT.tell(player, L.msg("pt_tickets.sale.expired"))
        return
    end
    local adapter = PT.ADAPTERS[offer.mode]
    if adapter and adapter.check then
        local ok, reason = adapter.check(player, offer)
        if not ok then
            closeSale(player)
            if reason then PT.tell(player, reason) end
            return
        end
    end
    local price = st.price or 0
    local params = { line = offer.line, from = plain(offer.fromName), to = plain(st.name) }
    if price > 0 then
        if not running("v_bank") then PT.tell(player, L.msg("pt_tickets.sale.bank_offline")) return end
        local ok, err = exports.v_bank:payMoney(player, price, "pt.ticket", params)
        if not ok then
            PT.tell(player, err == "not_enough_money" and L.msg("pt_tickets.sale.not_enough_money", { price = price })
                or L.msg("pt_tickets.sale.payment_failed", { error = tostring(err) }))
            return
        end
        if running("gov_transport") then
            params.player = getPlayerName(player):gsub("#%x%x%x%x%x%x", "")
            pcall(function() exports.gov_transport:bookFareIncome(offer.mode, price, params) end)
        end
    end
    offers[player] = nil
    triggerClientEvent(player, "pt:sale:close", resourceRoot)
    if Tickets[player] then PT.endTicket(player, "replaced") end
    local ticket = { mode = offer.mode, ref = offer.ref, line = offer.line, category = offer.category,
        from = offer.from, to = st.index, fromName = offer.fromName, toName = st.name,
        price = price, km = st.km or 0, bought = now() }
    Tickets[player] = ticket
    PT.tell(player, L.msg("pt_tickets.sale.bought", { line = offer.line, to = st.name, price = price }), offer.operator)
    triggerEvent("onPlayerTicketBought", player, offer.mode, ticket, offer.ctx or {})
end)

addEvent("pt:sale:cancel", true)
addEventHandler("pt:sale:cancel", resourceRoot, function()
    offers[client] = nil
end)

addEventHandler("onPlayerQuit", root, function()
    offers[source] = nil
    Tickets[source] = nil
end)

addEventHandler("onPlayerWasted", root, function()
    closeSale(source)
end)

-- expired offers
setTimer(function()
    local t = now()
    for player, o in pairs(offers) do
        if not isElement(player) then offers[player] = nil
        elseif t > o.expires then closeSale(player) end
    end
end, 5000, 0)

------------------------------------------------------------------ exports

--- the player's ticket (a copy) or false
function getTicket(player)
    local t = Tickets[player]
    if not t then return false end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

--- is the player's ticket for this mode + ref (trip / run) and does it cover stop index `at`
function hasValidTicket(player, mode, ref, at)
    local t = Tickets[player]
    if not t or t.mode ~= mode or t.ref ~= ref then return false end
    at = tonumber(at)
    return not at or (at >= t.from and at < t.to)
end

function endTicket(player, reason)
    if not Tickets[player] then return false end
    PT.endTicket(player, reason)
    return true
end

--- another resource sells a ticket for its own mode (buses): the offer as described at the top;
--- listen to onPlayerTicketBought (source = player, mode, ticket, ctx) to continue
function openTicketSale(player, offer)
    return PT.openSale(player, offer)
end

function closeTicketSale(player)
    closeSale(player)
    return true
end
