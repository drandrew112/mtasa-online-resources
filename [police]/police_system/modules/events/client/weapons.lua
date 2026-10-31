-- police_system / modules/events/client/weapons.lua
-- Weapon draw and use of an officer on duty, for the event log: a switch to a weapon is reported, the shots are
-- added up and sent as one line every 10 s ("fired 12 shots"). Only while signed in to a unit.

local shots, weapon, timer = 0, 0, nil

local function flush()
    if shots > 0 then POL.send("evt:shots", weapon, shots) end
    shots = 0
    timer = nil
end

addEventHandler("onClientPlayerWeaponSwitch", localPlayer, function(_, slot)
    if not POL.onDuty() then return end
    local w = getPedWeapon(localPlayer, slot)
    if w and w > 15 then POL.send("evt:weapon", w) end
end)

addEventHandler("onClientPlayerWeaponFire", localPlayer, function(w)
    if not POL.onDuty() or not w or w < 22 then return end
    weapon = w
    shots = shots + 1
    if not timer then timer = setTimer(flush, 10000, 1) end
end)
