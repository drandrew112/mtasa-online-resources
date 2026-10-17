if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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

local lastRobTrigger = 0

setElementData(localPlayer, "isRobbing", false)

function drawRobProgress()
    if getElementData(localPlayer, "isRobbing") then
        -- UI
        local progress = (tonumber(getElementData(localPlayer, "robbingProgress")) or 0) * 100
        dxDrawRectangle(sw/2-122, sh*0.8-2, 244, 34, tocolor(0, 0, 0, 150), true)
        dxDrawRectangle(sw/2-120, sh*0.8, 2.4 * progress, 30, tocolor(150, 150, 150, 150), true)
        dxDrawText(math.ceil(progress).."%", sw/2, sh*0.8+15, _,_, tocolor(255,255,255,255), 1.5, "default", "center", "center")
    end
end

-- the progress bar is attached only while robbing
local progressShown = false
local function syncProgress()
    local on = getElementData(localPlayer, "isRobbing") and true or false
    if on == progressShown then return end
    progressShown = on
    if on then
        addEventHandler("onClientRender", root, drawRobProgress)
    else
        removeEventHandler("onClientRender", root, drawRobProgress)
    end
end
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "isRobbing" then syncProgress() end
end, false)
syncProgress()

-- Aiming at a shop NPC starts the robbery: GTA reports the target change, so there is no
-- per-frame line-of-sight check (the server re-checks the shop and answers "store closed")
addEventHandler("onClientPlayerTarget", localPlayer, function(target)
    if not isElement(target) or getElementType(target) ~= "ped" then return end
    if getElementData(localPlayer, "isRobbing") or not isPedAiming(localPlayer) then return end

    local shopID = getElementData(target, "shopID")
    if not shopID or type(shops) ~= "table" or type(shops[shopID]) ~= "table" then return end

    if shops[shopID].isAvail and (getTickCount() - lastRobTrigger) > 1000 then
        lastRobTrigger = getTickCount()
        triggerServerEvent("startRobbing", resourceRoot, localPlayer, target)
    end
end)

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
    uicore:setInfobox(L("v_shop_robbery.c.store_is_closed"))
end)
