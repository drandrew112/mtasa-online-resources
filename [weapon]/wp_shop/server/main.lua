-- wp_shop / server/main.lua
-- Registers the shop interiors in world_interiors (on start and on world_interiors:ready), puts a
-- blip on every entrance, creates the clerk peds and shop markers inside and sells weapons + ammo
-- through wp_manager (never giveWeapon).

addEvent("world_interiors:ready", false)
addEvent("wp_shop:buy", true)

local blips   = {}   -- entrance blips
local markers = {}   -- shop marker -> shop id

-- reason: optional code for the client ("no_money" = alert instead of a notification)
local function result(player, ok, msg, id, reason)
    triggerClientEvent(player, "wp_shop:result", resourceRoot, ok, msg, id, reason)
end

---------------------------------------------------------------- marker cards (ui_core)

-- The cards above the shop markers are ui_core marker UIs (hidden by the client while the weapon
-- browser is open).
local uiDefs = {}   -- ui id -> def (sent again when ui_core restarts)

local function markerUI(uid, def)
    uiDefs[uid] = def
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then exports.ui_core:createMarkerUI(uid, def) end
end

addEvent("onMarkerUISystemStart")
addEventHandler("onMarkerUISystemStart", root, function()
    for uid, def in pairs(uiDefs) do
        if isElement(def.element) then exports.ui_core:createMarkerUI(uid, def) else uiDefs[uid] = nil end
    end
end)

---------------------------------------------------------------- interiors

local function registerShops()
    local wi = getResourceFromName("world_interiors")
    if not wi or getResourceState(wi) ~= "running" then
        outputDebugString("[wp_shop] world_interiors is not running", 2)
        return
    end
    for _, shop in ipairs(WS.shops) do
        local int = WS.interiors[shop.interior]
        if WS.isComplete(int) then
            local e, ex, ins = shop.enter, int.exit, int.inside
            exports.world_interiors:registerInterior(shop.id, {
                name      = int.name,
                dimension = shop.dimension,
                enter   = { x = e.x, y = e.y, z = e.z, rot = e.rot or 0, interior = 0, dimension = 0 },
                exit    = { x = ex.x, y = ex.y, z = ex.z, rot = ex.rot or 0, interior = int.interior },
                inside  = ins and { x = ins.x, y = ins.y, z = ins.z, rot = ins.rot or 0 } or nil,
                outside = shop.outside,
            })
        end
    end
end

local function createWorld()
    for _, shop in ipairs(WS.shops) do
        local int = WS.interiors[shop.interior]
        if not WS.isComplete(int) then
            outputDebugString("[wp_shop] shop '" .. shop.id .. "': interior template " .. tostring(shop.interior) .. " is incomplete", 2)
        else
            local e = shop.enter
            local blip = createBlip(e.x, e.y, e.z, WS.blip, 2, 255, 255, 255, 255, 0, WS.blipRange)
            setElementData(blip, "tooltipText", int.name)
            blips[#blips + 1] = blip

            local c = int.clerk
            local ped = createPed(WS.clerkModel, c.x, c.y, c.z, c.rot or 0)
            setElementInterior(ped, int.interior)
            setElementDimension(ped, shop.dimension)
            setElementFrozen(ped, true)
            setElementData(ped, "wp_shop:clerk", shop.id)

            local p, col = int.counter, WS.markerColor
            local m = createMarker(p.x, p.y, p.z - 1, "cylinder", WS.markerSize, col[1], col[2], col[3], col[4])
            setElementInterior(m, int.interior)
            setElementDimension(m, shop.dimension)
            setElementData(m, "wp_shop:shop", shop.id)
            markers[m] = shop.id
            local LBL = WS.label
            markerUI("s" .. shop.id, {
                element = m, type = "shop_weapon", color = LBL.color,
                name = int.name or L.msg("wp_shop.title"), title = L.msg("wp_shop.label.title"),
                hint = L.msg("wp_shop.label.hint"), hintActive = L.msg("wp_shop.label.press", { key = WS.key:upper() }),
                radius = LBL.distance, fullRadius = LBL.fullDistance, minScale = LBL.minScale, height = LBL.height,
            })
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    createWorld()
    registerShops()
end)
addEventHandler("world_interiors:ready", root, registerShops)

---------------------------------------------------------------- buying

-- Distance check, not isElementWithinMarker: the cylinder's colshape is only markerSize tall, so
-- a player standing on the floor is right at its top edge and often counts as outside.
local function inShopMarker(player, shopId)
    local px, py, pz = getElementPosition(player)
    for m, id in pairs(markers) do
        if id == shopId and isElement(m) and getElementDimension(m) == getElementDimension(player)
            and getElementInterior(m) == getElementInterior(player) then
            local mx, my, mz = getElementPosition(m)
            if getDistanceBetweenPoints2D(px, py, mx, my) <= WS.markerSize + 0.5 and math.abs(pz - mz) < 2.5 then
                return true
            end
        end
    end
    return false
end

local function ownedAmmo(player, id)
    for _, w in ipairs(exports.wp_manager:getPlayerWeapons(player) or {}) do
        if tonumber(w.id or w[1]) == id then return tonumber(w.ammo or w[2]) or 0 end
    end
    return nil
end

-- Cash, or the bank account when the cash is not enough (v_bank payMoney, key shop.weapon; the
-- money disappears). -> "cash" | "bank" | false
local function pay(player, price, item)
    local bank = getResourceFromName("v_bank")
    if not bank or getResourceState(bank) ~= "running" then return false end
    local ok, from = exports.v_bank:payMoney(player, price, "shop.weapon", { item = item })
    return ok == true and from or false
end

local function refund(player, price, from, item)
    if from == "bank" then
        exports.v_bank:giveBankMoney(player, price, "shop.weapon_refund", { item = item }) -- v_bank shows it itself
    else
        givePlayerMoney(player, price)
        exports.ui_core:showMoney(player, "add", price, "cash")
    end
end

-- kind: "weapon" | "ammo" | "thrown"; count: magazines / pieces
addEventHandler("wp_shop:buy", resourceRoot, function(shopId, id, kind, count)
    local player = client
    local shop = WS.shopById[shopId]
    id, count = tonumber(id), math.floor(tonumber(count) or 0)
    local def = id and WS.weapons[id]
    if not shop or not def or not WS.sells(shop, id) then return end
    if not inShopMarker(player, shopId) or isPedDead(player) then return end

    local wm = getResourceFromName("wp_manager")
    if not wm or getResourceState(wm) ~= "running" or not exports.wp_manager:isPlayerWeaponsLoaded(player) then
        result(player, false, L.msg("wp_shop.msg.not_loaded"))
        return
    end
    if exports.wp_manager:hasPlayerTempLoadout(player) then
        result(player, false, L.msg("wp_shop.msg.temp_loadout"))
        return
    end

    local have = ownedAmmo(player, id)
    local price, ammo

    if kind == "weapon" and not def.thrown then
        if have then result(player, false, L.msg("wp_shop.msg.already_owned")) return end
        price, ammo = def.price, 0
    elseif kind == "ammo" and def.mag then
        if count < 1 or count > 50 then return end
        if not have then result(player, false, L.msg("wp_shop.msg.buy_weapon_first")) return end
        price, ammo = def.magPrice * count, def.mag * count
    elseif kind == "thrown" and def.thrown then
        if count < 1 or count > 50 then return end
        price, ammo = def.price * count, count
    else
        return
    end

    if ammo > 0 and (have or 0) + ammo > WS.maxAmmo then
        result(player, false, L.msg("wp_shop.msg.too_much_ammo"))
        return
    end
    local item = getWeaponNameFromID(id) or tostring(id)
    local net, vat = price, 0
    price, vat = VAT.split("weapons", net)   -- the VAT is on top of the list price
    local paidFrom = pay(player, price, item)
    if not paidFrom then
        result(player, false, L.msg("wp_shop.msg.no_money"), id, "no_money")
        return
    end

    if not exports.wp_manager:givePlayerWeapon(player, id, ammo, false) then
        refund(player, price, paidFrom, item)
        result(player, false, L.msg("wp_shop.msg.failed"))
        return
    end
    VAT.book("weapons", net, vat, item)
    local msg = kind == "weapon" and L.msg("wp_shop.msg.bought_weapon", { price = price })
        or L.msg("wp_shop.msg.bought_ammo", { ammo = ammo, price = price })
    result(player, true, msg, id)
end)
