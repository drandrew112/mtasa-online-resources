-- Stun gun (server): validates the hits the shooters' clients report, lays the victim down for
-- WP.STUN.DURATION ms (player: weapon holstered + controls off on its client; ai_peds ped: setAIPedStunned).
-- Event onElementStunned (source = victim; shooter, ms) and onElementStunEnd (source = victim).

local ST = WP.STUN

addEvent("wp:stunHit", true)
addEvent("wp:stunAnim", true)
addEvent("onElementStunned")   -- source: player / ped; (shooter, ms)
addEvent("onElementStunEnd")   -- source: player / ped

Stunned = {}          -- element -> { timer, by }
local lastHit = {}    -- shooter -> tick

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function medicallyDown(el)
    return ST.DOWN_STATUS[getElementData(el, ST.MEDIC_STATUS)] == true
end

local function playAnim(el)
    if not medicallyDown(el) then
        setPedAnimation(el, ST.ANIM[1], ST.ANIM[2], -1, true, false, false, false)
    end
end

local function isAIPed(el)
    if getElementType(el) ~= "ped" or not running("ai_peds") then return false end
    local ok, r = pcall(function() return exports.ai_peds:isAIPed(el) end)
    return ok and r == true
end

local function unstun(el)
    local st = Stunned[el]
    if not st then return end
    Stunned[el] = nil
    if isTimer(st.timer) then killTimer(st.timer) end
    if not isElement(el) then return end
    removeElementData(el, ST.DATA)
    if not isPedDead(el) and not medicallyDown(el) then setPedAnimation(el, false) end
    if getElementType(el) == "player" then
        triggerClientEvent(el, "wp:stunned", resourceRoot, 0)
    elseif isAIPed(el) then
        pcall(function() exports.ai_peds:setAIPedStunned(el, 0) end)
    end
    triggerEvent("onElementStunEnd", el)
end

-- Stuns a player / ped for ms (default WP.STUN.DURATION); a stunned one gets the time again
function stunElement(el, ms, by)
    if not isElement(el) then return false end
    local kind = getElementType(el)
    if (kind ~= "player" and kind ~= "ped") or isPedDead(el) or getPedOccupiedVehicle(el) then return false end
    ms = math.max(1000, tonumber(ms) or ST.DURATION)
    local st = Stunned[el]
    if st then
        if isTimer(st.timer) then killTimer(st.timer) end
    else
        st = {}
        Stunned[el] = st
    end
    st.by = by
    st.timer = setTimer(unstun, ms, 1, el)
    setElementData(el, ST.DATA, true)
    playAnim(el)
    if kind == "player" then
        if Players[el] and Players[el].current then equip(el, 0) end
        triggerClientEvent(el, "wp:stunned", resourceRoot, ms)
        notify(el, "wp_manager.msg.stunned")
    elseif isAIPed(el) then
        pcall(function() exports.ai_peds:setAIPedStunned(el, ms) end)
    end
    triggerEvent("onElementStunned", el, by or false, ms)
    return true
end

function isElementStunned(el)
    return Stunned[el] ~= nil
end

function unstunElement(el)
    if not Stunned[el] then return false end
    unstun(el)
    return true
end

-- A hit reported by the shooter's client
addEventHandler("wp:stunHit", resourceRoot, function(target)
    local shooter = client
    local s = Players[shooter]
    if not s or s.current ~= ST.WEAPON or isPedDead(shooter) then return end
    if not isElement(target) or target == shooter then return end
    local kind = getElementType(target)
    if kind ~= "player" and kind ~= "ped" then return end
    if getElementDimension(target) ~= getElementDimension(shooter) or getElementInterior(target) ~= getElementInterior(shooter) then return end
    local now = getTickCount()
    if lastHit[shooter] and now - lastHit[shooter] < ST.SHOT_GAP then return end
    local x, y, z = getElementPosition(shooter)
    local tx, ty, tz = getElementPosition(target)
    if getDistanceBetweenPoints3D(x, y, z, tx, ty, tz) > ST.RANGE + ST.TOLERANCE then return end
    lastHit[shooter] = now
    stunElement(target, ST.DURATION, shooter)
end)

-- The victim's client saw the animation stop (another script, GTA): it is played again
addEventHandler("wp:stunAnim", resourceRoot, function()
    if Stunned[client] and not isPedDead(client) then playAnim(client) end
end)

-- No weapon in the hand while stunned
addEventHandler("onPlayerWeaponEquip", root, function(newId)
    if Stunned[source] and newId ~= 0 then cancelEvent() end
end)

addEventHandler("onPlayerWasted", root, function() unstun(source) end)
addEventHandler("onPedWasted", root, function() unstun(source) end)
addEventHandler("onPlayerQuit", root, function()
    lastHit[source] = nil
    unstun(source)
end)
addEventHandler("onElementDestroy", root, function()
    if Stunned[source] then unstun(source) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for el in pairs(Stunned) do unstun(el) end
end)
