if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- world_clothes-shop / server/main.lua
-- Registers the shop interiors in world_interiors (on start and on world_interiors:ready),
-- puts a blip on every entrance, creates the changer markers inside and sells outfits.

addEvent("world_interiors:ready", false)
addEvent("clothes:buy", true)

local blips    = {}   -- array of entrance blips
local changers = {}   -- marker -> shop id

local function status(player, text)
    triggerClientEvent(player, "clothes:status", resourceRoot, text)
end

---------------------------------------------------------------- interiors

local function registerShops()
    local wi = getResourceFromName("world_interiors")
    if not wi or getResourceState(wi) ~= "running" then
        outputDebugString("[world_clothes-shop] world_interiors is not running", 2)
        return
    end
    for _, shop in ipairs(CLOTHES.shops) do
        local int = CLOTHES.interiors[shop.interior]
        if int then
            exports.world_interiors:registerInterior(shop.id, {
                name      = int.name,
                dimension = shop.dimension,
                enter = { x = shop.x, y = shop.y, z = shop.z, rot = shop.rot, interior = 0, dimension = 0 },
                exit  = int.inside,
            })
        end
    end
end

local function createWorld()
    for _, shop in ipairs(CLOTHES.shops) do
        local int = CLOTHES.interiors[shop.interior]
        if int then
            local blip = createBlip(shop.x, shop.y, shop.z, CLOTHES.blip, 2, 255, 255, 255, 255, 0, CLOTHES.blipRange)
            setElementData(blip, "tooltipText", int.name)
            blips[#blips + 1] = blip

            local c = CLOTHES.markerColor
            for i, p in ipairs(int.changers) do
                local m = createMarker(p.x, p.y, p.z - 1, "cylinder", CLOTHES.markerSize, c[1], c[2], c[3], c[4])
                setElementInterior(m, int.inside.interior)
                setElementDimension(m, shop.dimension)
                setElementData(m, "clothes:shop", shop.id)
                setElementData(m, "clothes:changer", i)
                changers[m] = shop.id
            end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    createWorld()
    registerShops()
end)
addEventHandler("world_interiors:ready", root, registerShops)

---------------------------------------------------------------- buying

local function inChanger(player)
    for m in pairs(changers) do
        if isElement(m) and getElementDimension(m) == getElementDimension(player)
            and getElementInterior(m) == getElementInterior(player) and isElementWithinMarker(player, m) then
            return true
        end
    end
    return false
end

local function onDuty(player)
    local wc = getResourceFromName("work_core")
    return wc and getResourceState(wc) == "running" and exports.work_core:isPlayerOnDuty(player)
end

addEventHandler("clothes:buy", resourceRoot, function(skin)
    local player = client
    skin = tonumber(skin)
    if not skin or not CLOTHES.forSale[skin] then return end
    if not inChanger(player) or isPedDead(player) then return end

    if onDuty(player) then
        status(player, L.msg("world_clothes_shop.main.go_off_duty_before_changing_your"))
        return
    end
    if getElementModel(player) == skin then
        status(player, L.msg("world_clothes_shop.main.you_are_already_wearing_this_outfit"))
        return
    end
    if getPlayerMoney(player) < CLOTHES.price then
        status(player, L.msg("world_clothes_shop.main.you_don_t_have_enough_money"))
        return
    end

    takePlayerMoney(player, CLOTHES.price)
    setElementModel(player, skin)
    triggerClientEvent(player, "clothes:bought", resourceRoot, skin)
end)
