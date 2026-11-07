-- Stun gun (client): the stun gun never does damage (cancelled for every player, ped and vehicle on every
-- client), the local player's hits within WP.STUN.RANGE are reported to the server, and while the local
-- player is stunned its movement controls stay off and the lying animation is kept.

local ST = WP.STUN
local HANDS_KEY = "inv.slots" -- v_inventory locks "fire" itself while a hand is full

local function cancelStun(_, weapon)
    if weapon == ST.WEAPON then cancelEvent() end
end
addEventHandler("onClientPlayerDamage", root, cancelStun)
addEventHandler("onClientPedDamage", root, cancelStun)
addEventHandler("onClientVehicleDamage", root, cancelStun)

addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon, _, _, _, _, _, hit)
    if weapon ~= ST.WEAPON or not isElement(hit) then return end
    local kind = getElementType(hit)
    if kind ~= "player" and kind ~= "ped" then return end
    local x, y, z = getElementPosition(localPlayer)
    local tx, ty, tz = getElementPosition(hit)
    if getDistanceBetweenPoints3D(x, y, z, tx, ty, tz) > ST.RANGE then return end
    triggerServerEvent("wp:stunHit", resourceRoot, hit)
end)

--------------------------------------------------------------------------------
-- The local player is stunned
--------------------------------------------------------------------------------

local stunUntil = nil
local turnedOff = {}      -- control -> true (switched off by us)
local nextCheck = 0

local function handsBusy()
    local slots = getElementData(localPlayer, HANDS_KEY)
    return type(slots) == "table" and (slots.left or slots.right) and true or false
end

local function restore()
    for control in pairs(turnedOff) do
        if control ~= "fire" or not handsBusy() then toggleControl(control, true) end
    end
    turnedOff = {}
end

local function onRender()
    if not stunUntil then return end
    local now = getTickCount()
    if now >= stunUntil + 2000 or isPedDead(localPlayer) then -- the server's end never came
        stunUntil = nil
        removeEventHandler("onClientRender", root, onRender)
        restore()
        return
    end
    for _, control in ipairs(ST.CONTROLS) do
        if isControlEnabled(control) then
            toggleControl(control, false)
            turnedOff[control] = true
        end
    end
    if now >= nextCheck then
        nextCheck = now + ST.REAPPLY_MS
        local block, anim = getPedAnimation(localPlayer)
        if not getElementData(localPlayer, ST.MEDIC_STATUS) and (block ~= ST.ANIM[1] or anim ~= ST.ANIM[2]) then
            triggerServerEvent("wp:stunAnim", resourceRoot)
        end
    end
end

addEvent("wp:stunned", true)
addEventHandler("wp:stunned", resourceRoot, function(ms)
    ms = tonumber(ms) or 0
    if ms > 0 then
        if not stunUntil then addEventHandler("onClientRender", root, onRender) end
        stunUntil = getTickCount() + ms
        nextCheck = getTickCount() + ST.REAPPLY_MS
    elseif stunUntil then
        stunUntil = nil
        removeEventHandler("onClientRender", root, onRender)
        restore()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if stunUntil then restore() end
end)
