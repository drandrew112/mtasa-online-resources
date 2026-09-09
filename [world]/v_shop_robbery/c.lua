uicore = exports.ui_core

function isPedAiming (thePedToCheck)
	if isElement(thePedToCheck) then
		if getElementType(thePedToCheck) == "player" or getElementType(thePedToCheck) == "ped" then
			if getPedTask(thePedToCheck, "secondary", 0) == "TASK_SIMPLE_USE_GUN" or isPedDoingGangDriveby(thePedToCheck) then
				return true
			end
		end
	end
	return false
end



local sw,sh = guiGetScreenSize()

-- Only watch aim direction / shots when the player is close to a shop NPC.
local SHOP_WATCH_RANGE = 30
local lastRobTrigger = 0

local function isNearAnyShop()
    if type(shops) ~= "table" then return false end
    local px, py, pz = getElementPosition(localPlayer)
    for _, shop in ipairs(shops) do
        if shop.npc and shop.npc.pos then
            local d = getDistanceBetweenPoints3D(px, py, pz, shop.npc.pos.x, shop.npc.pos.y, shop.npc.pos.z)
            if d <= SHOP_WATCH_RANGE then
                return true
            end
        end
    end
    return false
end

setElementData(localPlayer, "isRobbing", false)

function drawRobProgress()
    if getElementData(localPlayer, "isRobbing") then
        -- UI
        local progress = (tonumber(getElementData(localPlayer, "robbingProgress")) or 0) * 100
        dxDrawRectangle(sw/2-122, sh*0.8-2, 244, 34, tocolor(0, 0, 0, 150), true)
        dxDrawRectangle(sw/2-120, sh*0.8, 2.4 * progress, 30, tocolor(150, 150, 150, 150), true)
        dxDrawText(math.ceil(progress).."%", sw/2, sh*0.8+15, _,_, tocolor(255,255,255,255), 1.5, "default", "center", "center")
        return
    end

    -- Check weapon target (only around shops)
    if not isNearAnyShop() then return end
    if not isPedAiming(localPlayer) then return end

    local x, y, z = getPedWeaponMuzzlePosition(localPlayer)
    if not x then return end

    local tX, tY, tZ = getPedTargetCollision(localPlayer)
    if not tX then return end

    local hit, hitX, hitY, hitZ, hitElement = processLineOfSight(x, y, z, tX, tY, tZ)
    if not hit or not isElement(hitElement) then return end
    if getElementType(hitElement) ~= "ped" then return end

    local shopID = getElementData(hitElement, "shopID")
    if not shopID or type(shops) ~= "table" or type(shops[shopID]) ~= "table" then return end

    if shops[shopID].isAvail and (getTickCount() - lastRobTrigger) > 1000 then
        lastRobTrigger = getTickCount()
        triggerServerEvent("startRobbing", resourceRoot, localPlayer, hitElement)
    end
end
addEventHandler("onClientRender", root, drawRobProgress)

function stopRobbing()
    if getElementData(localPlayer, "isRobbing") then
        triggerServerEvent("stopRobbing", resourceRoot, localPlayer)
    end
end
addEventHandler("onClientPlayerWasted", localPlayer, stopRobbing)

-- A bolt friss rablas miatt zarva van - visszajelzes a jatekosnak (max 3 mp-enkent)
local lastClosedNotify = 0
addEvent("v_shop_robbery:storeClosed", true)
addEventHandler("v_shop_robbery:storeClosed", resourceRoot, function()
    if (getTickCount() - lastClosedNotify) < 3000 then return end
    lastClosedNotify = getTickCount()
    uicore:setInfobox("The store is closed")
end)
