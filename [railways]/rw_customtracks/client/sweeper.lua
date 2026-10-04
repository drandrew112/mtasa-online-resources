-- Pushes peds and vehicles out of the way of a moving train (the puppet cars are teleported every
-- frame, so GTA physics never pushes anything). Each client only handles what it controls: the
-- local player, the vehicle it drives and the peds / vehicles it syncs.

local COOLDOWN = 400
local last = {}            -- [element] = tick of the last hit

local function controlledHere(el)
    if el == localPlayer then return true end
    local et = getElementType(el)
    if et == "vehicle" then
        local drv = getVehicleController(el)
        if drv then return drv == localPlayer end
        return isElementSyncer(el)
    end
    if et == "ped" then return isElementSyncer(el) end
    return false
end

local function hit(el, mx, my, speed)
    local now = getTickCount()
    if last[el] and now - last[el] < COOLDOWN then return end
    last[el] = now
    local push = (speed * 1.1 + 2) / 50
    if getElementType(el) == "vehicle" then
        setElementVelocity(el, mx * push, my * push, 0.12)
        setVehicleTurnVelocity(el, 0, 0, (math.random() - 0.5) * 0.05)
        setElementHealth(el, math.max(0, getElementHealth(el) - speed * 20))
    else
        if isPedInVehicle(el) then return end
        setElementVelocity(el, mx * push, my * push, 0.2)
        if el == localPlayer then
            setElementHealth(el, math.max(0, getElementHealth(el) - speed * 6))
        end
    end
end

addEventHandler("onClientRender", root, function()
    if not NET.CLIENT.SWEEP or not NetClient.ready then return end
    for _, t in pairs(TrainsClient.list()) do
        local v = t.vNow or t.v
        local speed = math.abs(v)
        if speed > 0.5 then
            -- the leading end: front of car 1 going forwards, back of the last car going backwards
            local k = v > 0 and 1 or #t.cars
            local car = t.cars[k]
            local pose = t.poses[k]
            if car and pose then
                local x, y, z, fx, fy, _, rx, ry = unpack(pose)
                local fl = math.sqrt(fx * fx + fy * fy)
                if car.flip then fx, fy = -fx, -fy end     -- path direction, not the model's
                fx, fy = fx / fl, fy / fl
                local mx, my = fx * (v > 0 and 1 or -1), fy * (v > 0 and 1 or -1)
                local half = car.def.length / 2
                local ex, ey = x + mx * half, y + my * half
                local reach = 1.5 + speed * 0.12
                for _, typ in ipairs({ "ped", "player", "vehicle" }) do
                    for _, el in ipairs(getElementsWithinRange(ex, ey, z + 1, reach + 6, typ, 0, t.dim or 0)) do
                        if not getElementData(el, "rwn.train") and controlledHere(el) and not getElementAttachedTo(el) then
                            local px, py, pz = getElementPosition(el)
                            local dx, dy = px - ex, py - ey
                            local along = dx * mx + dy * my
                            local lateral = math.abs(dx * rx + dy * ry)
                            local width = typ == "vehicle" and 2.6 or 1.8
                            if along > -3 and along < reach and lateral < width and math.abs(pz - z - 1) < 3 then
                                hit(el, mx, my, speed)
                            end
                        end
                    end
                end
            end
        end
    end
end)
