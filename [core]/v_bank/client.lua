-- Bank kezelo - client side
--
-- Only job here is to play the "pickup money" sound effect. Exposed both as a
-- client export (for other client-side resources) and via a triggered event so
-- the server-side export can fire it for a specific player.

local SOUND_FILE = "sounds/pickup_money.wav"
local VOLUME     = 0.5

-- Plays the pickup money sound once. Returns the sound element, or false.
function playPickupMoneySound()
    local sound = playSound(SOUND_FILE)
    if isElement(sound) then
        setSoundVolume(sound, VOLUME)
        return sound
    end
    return false
end

addEvent("v_bank:playPickupMoneySound", true)
addEventHandler("v_bank:playPickupMoneySound", root, function(money)
    if money then
        exports.ui_core:showMoney("add", money)
    end
    playPickupMoneySound()
end)

-- Server-side forceTakeMoney: shows the full amount taken (cash + bank) in ui_core.
addEvent("v_bank:moneyTaken", true)
addEventHandler("v_bank:moneyTaken", root, function(amount)
    if tonumber(amount) then
        exports.ui_core:showMoney("take", amount)
    end
end)
