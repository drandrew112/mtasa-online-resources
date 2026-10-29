-- Forced patient animations. The server writes the key (MEDFX.DATA_ANIM) by the consciousness;
-- every client keeps it on the players / peds it streams, so it survives late joins, streaming
-- and other scripts resetting it (e.g. a med_scenemanager pose that does not fit the state).
--
-- Not forced: dead, in a vehicle, attached (stretcher, carried), on a stretcher, or blocked
-- through setAnimationBlocked. An animation listed in `accept` is left alone.

local applied = {} -- element -> { key, tick } of the animation this client put on it

local function lower(s) return s and s:lower() or nil end

local function isExcepted(element)
    return isPedDead(element) or getPedOccupiedVehicle(element) or isElementAttached(element)
        or getElementData(element, MEDFX.DATA_STRETCHER) or getElementData(element, MEDFX.DATA_BLOCK) == true
end

local function isAccepted(def, block, name)
    if not block then return false end
    block, name = lower(block), lower(name)
    if block == lower(def.anim[1]) and name == lower(def.anim[2]) then return true end
    for _, a in ipairs(def.accept or {}) do
        if block == lower(a[1]) and name == lower(a[2]) then return true end
    end
    return false
end

local function enforce(element)
    local key = getElementData(element, MEDFX.DATA_ANIM)
    local def = key and MEDFX_ANIMS[key]
    if not def then return end
    if isExcepted(element) then
        applied[element] = nil -- somebody else owns the element now, no get-up later
        return
    end

    local mine = applied[element]
    -- a held (non-looped) animation is left to settle on its last frame
    if mine and mine.key == key and not def.loop and getTickCount() - mine.tick < 3000 then return end
    if isAccepted(def, getPedAnimation(element)) then return end

    setPedAnimation(element, def.anim[1], def.anim[2], -1, def.loop == true, false, false, def.hold == true)
    applied[element] = { key = key, tick = getTickCount() }
end

-- The state ended: the element gets up, if it still plays the state's animation (ours, or an
-- accepted one, e.g. the stretcher laid it down)
local function release(element, oldKey)
    local mine = applied[element]
    applied[element] = nil
    if not isElement(element) or isExcepted(element) then return end
    local def = MEDFX_ANIMS[oldKey] or (mine and MEDFX_ANIMS[mine.key])
    if not def or (not mine and not isAccepted(def, getPedAnimation(element))) then return end
    if def.release then
        setPedAnimation(element, def.release[1], def.release[2], -1, false, false, true, false)
    else
        setPedAnimation(element)
    end
end

local function check()
    local x, y, z = getElementPosition(localPlayer)
    local range = MEDFX.ANIM_STREAM_RANGE
    for _, elementType in ipairs({ "player", "ped" }) do
        for _, element in ipairs(getElementsByType(elementType, root, true)) do
            if getElementData(element, MEDFX.DATA_ANIM) then
                local ex, ey, ez = getElementPosition(element)
                if getDistanceBetweenPoints3D(x, y, z, ex, ey, ez) <= range then enforce(element) end
            end
        end
    end
    if getElementData(localPlayer, MEDFX.DATA_ANIM) then enforce(localPlayer) end
end
setTimer(check, MEDFX.ANIM_CHECK, 0)

addEventHandler("onClientElementDataChange", root, function(key, oldValue, newValue)
    if key ~= MEDFX.DATA_ANIM then return end
    local elementType = getElementType(source)
    if elementType ~= "player" and elementType ~= "ped" then return end
    if newValue then
        if isElementStreamedIn(source) or source == localPlayer then enforce(source) end
    elseif oldValue then
        release(source, oldValue)
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementData(source, MEDFX.DATA_ANIM) then enforce(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    applied[source] = nil
end)

addEventHandler("onClientElementDestroy", root, function()
    applied[source] = nil
end)

addEventHandler("onClientPlayerWasted", root, function() applied[source] = nil end)
addEventHandler("onClientPedWasted", root, function() applied[source] = nil end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for element in pairs(applied) do
        if isElement(element) and not isPedDead(element) then setPedAnimation(element) end
    end
    applied = {}
end)
