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

setElementData(localPlayer, "isRobbing", false)

function drawRobProgress()
    if getElementData(localPlayer, "isRobbing") then
        -- UI
        local progress = (getElementData(localPlayer, "robbingProgress")*100) or 0
        dxDrawRectangle(sw/2-122, sh*0.8-2, 244, 34, tocolor(0, 0, 0, 150), true)
        dxDrawRectangle(sw/2-120, sh*0.8, 2.4 * progress, 30, tocolor(150, 150, 150, 150), true)
        dxDrawText(math.ceil(progress).."%", sw/2, sh*0.8+15, _,_, tocolor(255,255,255,255), 1.5, "default", "center", "center")
    else
        -- Check weapon target
        if isPedAiming(localPlayer) then
            local x, y, z = getPedWeaponMuzzlePosition(localPlayer)
            local tX, tY, tZ = getPedTargetCollision(localPlayer)

            local hit, hitX, hitY, hitZ, hitElement = processLineOfSight(x, y, z, tX, tY, tZ)
            --dxDrawLine3D(x, y, z, tX, tY, tZ, tocolor(255,0,0,255), 3)

            if hit and getElementType(hitElement) == "ped" then
                if getElementData(hitElement, "shopID") then
                    if (shops[getElementData(hitElement, "shopID")].isAvail) then
                        triggerServerEvent("startRobbing", resourceRoot, localPlayer, hitElement)
                    end
                end
            end
        end
    end
end
addEventHandler("onClientRender", root, drawRobProgress)

function stopRobbing()
    if getElementData(localPlayer, "isRobbing") then
        triggerServerEvent("stopRobbing", resourceRoot, localPlayer)
    end
end
addEventHandler("onClientPlayerWasted", localPlayer, stopRobbing)

addEvent("shp:moneyCollected", true)
addEventHandler("shp:moneyCollected", root, function(money)
    uicore:setInfobox("You received $" .. money .. "!")
end)
