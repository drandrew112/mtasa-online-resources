-- ui_browser :: dealership.lua (server)
-- Turns a "buy" action fired on a vehicles-category site into a real purchase:
-- charges the player (cash first, then Liberty Bank) and registers the car with
-- [vehicles]/v_ownveh.
--
-- The catalog is built once on start by reading every sites/<name>/page.vhtml
-- listed in meta.xml and pulling out the <product> elements that carry a numeric
-- model="" attribute. Price and colours come straight from the markup, so the
-- .vhtml stays the single source of truth - the client and the server read the
-- same numbers.

Dealership = {}

-- [productId] = { model, price, name, site, colors = { key = {r,g,b}, ... } }
local catalog = {}

--------------------------------------------------------------------------------
-- Colours - RGB mirror of the swatch palette in core/home.lua (COLORS).
--------------------------------------------------------------------------------

local COLOR_RGB = {
    black  = { 20, 20, 20 },
    white  = { 242, 242, 242 },
    silver = { 196, 200, 204 },
    grey   = { 125, 131, 138 },
    red    = { 192, 57, 43 },
    blue   = { 37, 99, 235 },
    green  = { 30, 142, 62 },
    yellow = { 230, 184, 0 },
    orange = { 230, 126, 34 },
    purple = { 124, 58, 237 },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function readFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local s = fileRead(f, fileGetSize(f))
    fileClose(f)
    return s
end

local function parseAttrs(s)
    local a = {}
    for k, v in s:gmatch('([%w_%-:]+)%s*=%s*"([^"]*)"') do
        a[k:lower()] = v
    end
    return a
end

-- "$48,000" -> 48000
local function priceToNumber(s)
    return tonumber((tostring(s or ""):gsub("[^%d]", ""))) or 0
end

local function money(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return "$" .. s
end

-- ui_browser:notify is a client export; server.lua has its own local copy of
-- this one-liner, this is the server-side dealership's.
local function notify(player, title, text)
    triggerClientEvent(player, "ui_browser:notify", resourceRoot, title, text)
end

local function ownvehReady()
    local res = getResourceFromName("v_ownveh")
    return res and getResourceState(res) == "running"
end

local function bankReady()
    local res = getResourceFromName("v_bank")
    return res and getResourceState(res) == "running"
end

--------------------------------------------------------------------------------
-- Catalog build
--------------------------------------------------------------------------------

local function addProductsFrom(markupPath, siteName)
    local src = readFile(markupPath)
    if not src then return end
    src = src:gsub("<!%-%-.-%-%->", "")

    for attrStr in src:gmatch("<product%s+(.-)>") do
        local attrs = parseAttrs(attrStr)
        local id = attrs.id
        local model = tonumber(attrs.model)
        if id and model and getVehicleNameFromModel(model) then
            local colors = {}
            for key in (attrs.colors or ""):gmatch("[^,%s]+") do
                local k = key:lower()
                if COLOR_RGB[k] then colors[k] = COLOR_RGB[k] end
            end
            if catalog[id] then
                outputServerLog(("[ui_browser] dealership: duplicate product id '%s' (%s overrides %s)")
                    :format(id, tostring(siteName), tostring(catalog[id].site)))
            end
            catalog[id] = {
                model  = model,
                price  = priceToNumber(attrs.price),
                name   = attrs.name or ("Vehicle " .. model),
                site   = siteName,
                colors = colors,
            }
        end
    end
end

local function buildCatalog()
    catalog = {}
    local meta = readFile("meta.xml")
    if not meta then
        outputServerLog("[ui_browser] dealership: meta.xml unreadable, no vehicles for sale")
        return
    end

    local seen = {}
    for path in meta:gmatch('src%s*=%s*"(sites/[^"]-/page%.vhtml)"') do
        if not seen[path] then
            seen[path] = true
            addProductsFrom(path, path:match("sites/([^/]+)/"))
        end
    end

    local n = 0
    for _ in pairs(catalog) do n = n + 1 end
    outputServerLog(("[ui_browser] dealership: %d vehicle(s) for sale"):format(n))
end

addEventHandler("onResourceStart", resourceRoot, buildCatalog)

--------------------------------------------------------------------------------
-- Purchase
--------------------------------------------------------------------------------

-- Charge `amount` from cash first, then from the bank.
-- -> "cash" | "bank" | nil (could not pay in full from either)
local function charge(player, amount)
    if getPlayerMoney(player) >= amount then
        takePlayerMoney(player, amount)
        return "cash"
    end
    if bankReady() and exports.v_bank:takeBankMoney(player, amount) == true then
        return "bank"
    end
    return nil
end

local function refund(player, amount, from)
    if from == "bank" and bankReady() then
        exports.v_bank:giveBankMoney(player, amount)
    else
        givePlayerMoney(player, amount)
    end
end

-- Is this product id a vehicle the browser can actually sell?
function Dealership.isVehicleProduct(id)
    return catalog[tostring(id)] ~= nil
end

-- Runs a purchase for `player`. `colourKey` is a swatch key ("blue") or nil.
-- Sends the player a notification either way; returns true when it handled the
-- action (so server.lua does not fall through to the generic notice).
function Dealership.purchase(player, id, colourKey, url)
    local item = catalog[tostring(id)]
    if not item then return false end

    if not ownvehReady() then
        notify(player, "Dealership", "The vehicle registry is offline right now. Try again later.")
        return true
    end

    local colours
    if colourKey and item.colors[tostring(colourKey):lower()] then
        local c = item.colors[tostring(colourKey):lower()]
        colours = ("%d,%d,%d"):format(c[1], c[2], c[3])
    end

    local price = item.price
    local paidFrom = charge(player, price)
    if not paidFrom then
        notify(player, "Dealership",
            ("You cannot afford the %s (%s). Cash and bank balance together are not enough.")
                :format(item.name, money(price)))
        return true
    end

    local vehId, err = exports.v_ownveh:giveVehicle(player, item.model,
        colours and { colors = colours } or nil)

    if not vehId then
        refund(player, price, paidFrom)
        notify(player, "Dealership", "The sale could not be completed - you have not been charged.")
        outputServerLog(("[ui_browser] dealership: giveVehicle failed for %s (model %s): %s")
            :format(getPlayerName(player), item.model, tostring(err)))
        return true
    end

    notify(player, "Dealership",
        ("You bought a %s for %s. It is registered to your account - summon it from the MyVeh phone app.")
            :format(item.name, money(price)))
    triggerClientEvent(player, "ui_browser:refresh", resourceRoot)

    outputServerLog(("[ui_browser] %s bought %s (model %s) as vehicle #%s for %d from %s (%s)")
        :format(getPlayerName(player), item.name, item.model, tostring(vehId), price,
            paidFrom, tostring(url)))
    return true
end
