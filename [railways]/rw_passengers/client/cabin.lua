-- Client side of a ride: notifications, standing on the real ground after leaving, and the
-- cabin dressing (the double door closing the cockpit) created locally in the coach's
-- dimension while the local player is inside.

local I = RWP.INTERIORS.coach

------------------------------------------------------------------ notifications

addEvent("rwp:notify", true)
addEventHandler("rwp:notify", resourceRoot, function(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then exports.ui_core:addNotification("Sunline Rail", text)
    else outputChatBox("[Sunline Rail] " .. text, 120, 180, 255) end
end)

------------------------------------------------------------------ leaving: onto the platform

-- the server put us down beside the coach, rail height + 1.2 m. The world around has to stream
-- in first (we come from the interior), so the ground is searched for a short while; the
-- player is frozen meanwhile so it does not fall.
local placing
addEvent("rwp:placed", true)
addEventHandler("rwp:placed", resourceRoot, function(x, y, z, rz)
    placing = { x = x, y = y, z = z, rz = rz, untilT = getTickCount() + 2500 }
    setElementFrozen(localPlayer, true)
end)

addEventHandler("onClientRender", root, function()
    if not placing then return end
    local p = placing
    local gz = getGroundPosition(p.x, p.y, p.z + 3)
    local found = gz and gz ~= 0 and gz > p.z - 4
    if found or getTickCount() > p.untilT then
        placing = nil
        setElementPosition(localPlayer, p.x, p.y, found and gz + 1 or p.z)
        if p.rz then setElementRotation(localPlayer, 0, 0, p.rz, "default", true) end
        setElementFrozen(localPlayer, false)
    end
end)

------------------------------------------------------------------ cabin dressing

local dressing = {}      -- created objects
local dressedDim

local function undress()
    for _, o in ipairs(dressing) do if isElement(o) then destroyElement(o) end end
    dressing, dressedDim = {}, nil
end

local function dress(dim)
    undress()
    for _, b in ipairs(I.blockers) do
        local o = createObject(b.model, b.x, b.y, b.z, 0, 0, b.rz or 0)
        if o then
            setElementInterior(o, I.interior)
            setElementDimension(o, dim)
            setElementFrozen(o, true)
            if b.doubleSided then setElementDoubleSided(o, true) end
            dressing[#dressing + 1] = o
        end
    end
    dressedDim = dim
end

-- the ride this client is on -> dim | nil
function rwpMyCoach()
    local r = getElementData(localPlayer, "rwp.ride")
    return type(r) == "table" and r[1] or nil
end

local function update()
    local dim = rwpMyCoach()
    if dim and getElementDimension(localPlayer) == dim and getElementInterior(localPlayer) == I.interior then
        if dressedDim ~= dim then dress(dim) end
    elseif dressedDim then
        undress()
    end
end

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "rwp.ride" then setTimer(update, 50, 1) end
end)
setTimer(update, 500, 0)
addEventHandler("onClientResourceStop", resourceRoot, undress)

------------------------------------------------------------------ client exports

function isInTrain() return rwpMyCoach() ~= nil end

function getMyRide()
    local r = getElementData(localPlayer, "rwp.ride")
    if type(r) ~= "table" then return false end
    return { coach = r[1], train = r[2], car = r[3] }
end
