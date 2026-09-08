local robberies = {}

-- Mennyi ideig NEM rabolhato a bolt egy sikeres rablas utan
local ROB_COOLDOWN = 5 * 60 * 1000 -- 5 perc

function createShop(shop, shopID)
    local blip = createBlip(shop.pos.x, shop.pos.y, shop.pos.z, 54, 1.5, 255,255,255,255, 0, 500)
    local ped = createPed(shop.npc.skin, shop.npc.pos.x, shop.npc.pos.y, shop.npc.pos.z, shop.npc.pos.rot_z)
    setElementData(ped, "shopID", shopID)
end

function startRobbing(_, npc)
    local player = client
    if not isElement(npc) or getElementType(npc) ~= "ped" then return end
    if getElementData(player, "isRobbing") then return end

    local shopID = getElementData(npc, "shopID")
    if not shopID or not shops[shopID] then return end
    if shops[shopID].isAvail ~= true then
        if shops[shopID].onCooldown then
            triggerClientEvent(player, "v_shop_robbery:storeClosed", resourceRoot)
        end
        return
    end

    shops[shopID].isAvail = false
    setElementData(player, "isRobbing", true)
    setElementData(player, "robbing_shop", shopID)
    setElementData(player, "robbingProgress", 0)
    robberies[player] = {npc = npc, robTimer = nil}
    robberies[player].robTimer = setTimer(updateRobProgress, 80, 0, player)

    setPedAnimation(npc, "shop", "shp_rob_givecash", 1, true, false, false)
end
addEvent("startRobbing", true)
addEventHandler("startRobbing", resourceRoot, startRobbing)

function updateRobProgress(player)
    if getElementData(player, "isRobbing") then
        local progress = getElementData(player, "robbingProgress") or 0
        progress = progress + 0.012
        setElementData(player, "robbingProgress", progress)
        if progress >= 1 then
            completeRobbery(player)
        end
    end
end

function cleanupRobbery(player)
    if not getElementData(player, "isRobbing") then return end

    local shopID = getElementData(player, "robbing_shop")
    setElementData(player, "isRobbing", false)
    setElementData(player, "robbing_shop", nil)
    setElementData(player, "robbingProgress", nil)

    local data = robberies[player]
    if data then
        if data.robTimer and isTimer(data.robTimer) then
            killTimer(data.robTimer)
        end
        robberies[player] = nil
    end

    if shopID and shops[shopID] then
        shops[shopID].isAvail = true
    end
end

function stopRobbing()
    cleanupRobbery(client)
end
addEvent("stopRobbing", true)
addEventHandler("stopRobbing", resourceRoot, stopRobbing)

addEventHandler("onPlayerQuit", root, function()
    cleanupRobbery(source)
end)

function completeRobbery(player)
    local data = robberies[player]
    if not data then return end

    local npc = data.npc
    local shopID = (isElement(npc) and getElementData(npc, "shopID")) or getElementData(player, "robbing_shop")
    local money = math.random(2000, 10000)

    if data.robTimer and isTimer(data.robTimer) then
        killTimer(data.robTimer)
    end
    robberies[player] = nil
    setElementData(player, "isRobbing", false)
    setElementData(player, "robbing_shop", nil)
    setElementData(player, "robbingProgress", nil)

    if isElement(npc) and shopID and shops[shopID] then
        -- Give XP for player
        exports.v_levelsys:giveXp(player, 200)
        -- Stop the NPC animation and create a money bag pickup in front of the NPC
        setPedAnimation(npc, "shop", "shp_rob_handsup", -1, true, false, false)
        local x, y, z = getPositionInFrontOfElement(npc, shops[shopID].npc.pickup_distance)
        exports.v_bank:createMoneyPickup(x, y, z, money, player)
    end

    if shopID and shops[shopID] then
        shops[shopID].onCooldown = true
        shops[shopID].cdTimer = setTimer(function()
            if isElement(npc) then
                setPedAnimation(npc)
            end
            shops[shopID].isAvail = true
            shops[shopID].onCooldown = false
            shops[shopID].cdTimer = nil
        end, ROB_COOLDOWN, 1)
    end
end

function initShops()
    for shopID, shop in ipairs(shops) do
        createShop(shop, shopID)
    end
end
addEventHandler("onResourceStart", resourceRoot, initShops)
