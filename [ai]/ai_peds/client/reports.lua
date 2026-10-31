if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Reports (client): ready, camera, the local player's gunshots and the damage it does to AI peds, and the same for
-- the AI peds this client syncs (their shots scare civilians, their hits make victims react).

local T = AIPEDS
local lastShot = {}       -- [shooter] = tick
local lastDamage = {}     -- [victim] = tick

local function isAIPed(el)
    return isElement(el) and getElementType(el) == "ped" and getElementData(el, "ai_peds") ~= false
        and getElementData(el, "ai_peds") ~= nil
end

local function reportShot(shooter, hx, hy, hz)
    local now = getTickCount()
    if lastShot[shooter] and now - lastShot[shooter] < T.SHOT_REPORT_GAP then return end
    lastShot[shooter] = now
    triggerServerEvent(EV_THREAT, resourceRoot, "shot", shooter, hx, hy, hz)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent(EV_READY, resourceRoot)
    setTimer(function()
        local x, y, z, lx, ly, lz = getCameraMatrix()
        local dx, dy, dz = lx - x, ly - y, lz - z
        local l = math.sqrt(dx * dx + dy * dy + dz * dz)
        if l < 1e-4 then return end
        triggerServerEvent(EV_VIEW, resourceRoot, x, y, z, dx / l, dy / l, dz / l)
    end, T.VIEW_SEND, 0)
end)

-- gunshots (thrown weapons / tools excluded)
local function firearm(weapon) return weapon and weapon >= 22 and weapon <= 38 end

addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon, _, _, hx, hy, hz)
    if firearm(weapon) then reportShot(localPlayer, hx, hy, hz) end
end)

addEventHandler("onClientPedWeaponFire", root, function(weapon, _, _, hx, hy, hz)
    if firearm(weapon) and isAIPed(source) and isElementSyncer(source) then reportShot(source, hx, hy, hz) end
end)

-- damage to AI peds: reported by the attacker's client (local player, its vehicle, or an AI ped synced here)
addEventHandler("onClientPedDamage", root, function(attacker, weapon, _, loss)
    if not isAIPed(source) or not isElement(attacker) then return end
    local mine = attacker == localPlayer
    if not mine and getElementType(attacker) == "vehicle" then mine = getVehicleController(attacker) == localPlayer end
    if not mine and isAIPed(attacker) then mine = isElementSyncer(attacker) end
    if not mine then return end
    local now = getTickCount()
    if lastDamage[source] and now - lastDamage[source] < 300 then return end
    lastDamage[source] = now
    triggerServerEvent(EV_THREAT, resourceRoot, "damage", source, attacker, weapon or 0, loss or 0)
end)

addEventHandler("onClientElementDestroy", root, function()
    lastShot[source], lastDamage[source] = nil, nil
end)

addEvent(EV_NOTIFY, true)
addEventHandler(EV_NOTIFY, resourceRoot, function(text)
    local ui = getResourceFromName("ui_core")
    if ui and getResourceState(ui) == "running" then
        exports.ui_core:addNotification(L("ai_peds.main.title"), text)
    else
        outputDebugString("[ai_peds] " .. tostring(text))
    end
end)
