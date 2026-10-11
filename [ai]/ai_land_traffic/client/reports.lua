-- Crashes and shots by the local player: reported to the server, which releases the traffic vehicle
-- (it leaves the simulation and becomes a normal physics vehicle). Only the involved player reports.

local lastSent = {}

local function report(veh, kind)
    local now = getTickCount()
    if lastSent[veh] and now - lastSent[veh] < 1000 then return end
    lastSent[veh] = now
    triggerServerEvent(EV_REPORT, resourceRoot, veh, kind)
end

local function isMine(veh)
    return isElement(veh) and getVehicleController(veh) == localPlayer
end

addEventHandler("onClientVehicleCollision", root, function(hit, force)
    if force < TRAFFIC.CRASH_FORCE then return end
    if Puppets.state(source) and hit and (hit == localPlayer or isMine(hit)) then
        report(source, "crash")
    elseif isMine(source) and hit and Puppets.state(hit) then
        report(hit, "crash")
    end
end)

addEventHandler("onClientVehicleDamage", root, function(attacker, weapon)
    if attacker == localPlayer and weapon and Puppets.state(source) then report(source, "damage") end
end)

addEventHandler("onClientPedDamage", root, function(attacker)
    if attacker ~= localPlayer then return end
    local veh = getPedOccupiedVehicle(source)
    if veh and Puppets.state(veh) then report(veh, "damage") end
end)

addEventHandler("onClientElementDestroy", root, function()
    lastSent[source] = nil
end)

------------------------------------------------------------------------ debug view (/traffic debug)

addEvent("ai_traffic:debug", true)
addEventHandler("ai_traffic:debug", resourceRoot, function()
    Puppets.debug = not Puppets.debug
end)

addEventHandler("onClientRender", root, function()
    if not Puppets.debug then return end
    local cx, cy, cz = getCameraMatrix()
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        local st = Puppets.state(veh)
        if st then
            local x, y, z = getElementPosition(veh)
            if getDistanceBetweenPoints3D(cx, cy, cz, x, y, z) < 120 then
                local sx, sy = getScreenFromWorldPosition(x, y, z + 2)
                if sx then
                    dxDrawText(string.format("%s%d  %.0f km/h  a %.1f  lat %.1f", st.code > 0 and "L" or "C",
                        math.abs(st.code), st.v * 3.6, st.a, st.lat), sx, sy, sx, sy, tocolor(255, 255, 255),
                        1, "default-bold", "center", "center")
                end
                -- planned path
                local px, py, pz
                for d = 0, 30, 3 do
                    local chain, n = { st.code, st.next ~= 0 and st.next or nil }, st.next ~= 0 and 2 or 1
                    local qx, qy, qz = Geo.poseOnChain(chain, n, st.s + d, st.lat)
                    if px and qx then dxDrawLine3D(px, py, pz + 0.3, qx, qy, qz + 0.3, tocolor(0, 200, 255), 2) end
                    px, py, pz = qx, qy, qz
                end
            end
        end
    end
end)
