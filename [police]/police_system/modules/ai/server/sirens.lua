-- police_system / modules/ai/server/sirens.lua
-- AI siren: lights and siren (v_els) through the whole chase; every SIREN_SWITCH (6-15 s, random) it switches to
-- another tone of its siren type (setElsSiren(veh, true, index)), sometimes a short horn blast before a junction.
-- Evading phase: lights only. Retreat: everything off.

local S = {}
POL.ai.sirens = S
local A = POLICE.AI

local function els() return POL.running("v_els") and exports.v_els or nil end

function S.on(unit)
    local e = els()
    if not e or not isElement(unit.veh) or unit.tank then return end
    e:setElsLights(unit.veh, true)
    e:setElsSiren(unit.veh, true, 1)
    unit.sirenIndex = 1
    unit.sirenAt = getTickCount() + math.random(A.SIREN_SWITCH[1], A.SIREN_SWITCH[2])
end

-- lightsOff: true = everything off (retreat), false = lights only (evading)
function S.off(unit, lightsOff)
    local e = els()
    if not e or not isElement(unit.veh) or unit.tank then return end
    e:setElsSiren(unit.veh, false)
    if lightsOff then e:setElsLights(unit.veh, false) end
    unit.sirenAt = nil
end

function S.tick(unit, now)
    if not unit.sirenAt or now < unit.sirenAt or not isElement(unit.veh) then return end
    local e = els()
    if not e then return end
    unit.sirenAt = now + math.random(A.SIREN_SWITCH[1], A.SIREN_SWITCH[2])
    local idx = math.random(1, 3)
    if idx == unit.sirenIndex then idx = idx % 3 + 1 end
    if e:setElsSiren(unit.veh, true, idx) then unit.sirenIndex = idx end
    if math.random() < 0.3 then
        local veh = unit.veh
        e:setElsState(veh, "sirenHorn", true)
        setTimer(function() if isElement(veh) and els() then els():setElsState(veh, "sirenHorn", false) end end, 700, 1)
    end
end
