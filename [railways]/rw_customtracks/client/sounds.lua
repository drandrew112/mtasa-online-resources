-- Train sounds near the camera: running loop (pitch / volume by speed), brake loop, a clack for
-- every bogie passing a rail joint, and flange squeal in tight curves.

local C = NET.CLIENT
local loops = {}           -- [train id] = { run, brake, squeal }
local MAX_CLACKS = 6       -- per frame

local function loop(file, x, y, z, maxDist)
    local s = playSound3D(file, x, y, z, true)
    if s then
        setSoundMaxDistance(s, maxDist)
        setSoundMinDistance(s, 8)
        setSoundVolume(s, 0)
    end
    return s
end

local function stopAll(id)
    local l = loops[id]
    if not l then return end
    for _, s in pairs(l) do if isElement(s) then destroyElement(s) end end
    loops[id] = nil
end

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

addEventHandler("onClientRender", root, function()
    if not NetClient.ready then return end
    local cx, cy, cz = getCameraMatrix()
    local clacks = 0
    local list = TrainsClient.list()
    for id in pairs(loops) do if not list[id] then stopAll(id) end end

    for id, t in pairs(list) do
        local lead = t.poses[1]
        local near = lead and getDistanceBetweenPoints3D(cx, cy, cz, lead[1], lead[2], lead[3]) < C.SOUND_DIST
        if not near or getElementDimension(localPlayer) ~= (t.dim or 0) then
            stopAll(id)
        else
            local v = math.abs(t.vNow or t.v)
            local l = loops[id]
            if not l then
                l = {
                    run = loop("sounds/run.wav", lead[1], lead[2], lead[3], C.SOUND_DIST),
                    brake = loop("sounds/brake.wav", lead[1], lead[2], lead[3], 90),
                    squeal = loop("sounds/squeal.wav", lead[1], lead[2], lead[3], 110),
                }
                loops[id] = l
            end
            local x, y, z = lead[1], lead[2], lead[3] + 1
            for _, s in pairs(l) do if isElement(s) then setElementPosition(s, x, y, z) end end

            if isElement(l.run) then
                setSoundVolume(l.run, clamp(v / 8, 0, 1) * 0.9)
                setSoundSpeed(l.run, clamp(0.55 + v / 25, 0.55, 1.6))
            end
            if isElement(l.brake) then
                local b = t.emergency and 1 or clamp(-t.ctrl, 0, 1)
                setSoundVolume(l.brake, (b > 0.2 and v > 1) and b * clamp(v / 10, 0, 1) * 0.8 or 0)
            end
            if isElement(l.squeal) then
                local seg, s = t.path:at(t.uNow or t.u)
                local r = Net.radiusAt(seg, s, 6)
                local k = clamp(1 - r / C.SQUEAL_RADIUS, 0, 1)
                setSoundVolume(l.squeal, v > 4 and k * clamp(v / 12, 0, 1) * 0.5 or 0)
            end

            -- rail joints: every bogie passing a multiple of JOINT
            if v > 1 then
                t.joints = t.joints or {}
                for k, car in ipairs(t.cars) do
                    local pose = t.poses[k]
                    if pose and getDistanceBetweenPoints3D(cx, cy, cz, pose[1], pose[2], pose[3]) < 80 then
                        for b = -1, 1, 2 do
                            local key = k * 2 + (b > 0 and 1 or 0)
                            local u = (t.uNow or t.u) - car.offset + b * car.def.bogie / 2
                            local j = math.floor(u / C.JOINT)
                            local old = t.joints[key]
                            t.joints[key] = j
                            if old and old ~= j and clacks < MAX_CLACKS then
                                clacks = clacks + 1
                                local px, py, pz = t.path:point(u)
                                local s = playSound3D("sounds/clack.wav", px, py, pz + 0.5)
                                if s then
                                    setSoundMaxDistance(s, 70)
                                    setSoundMinDistance(s, 5)
                                    setSoundVolume(s, clamp(0.25 + v / 25, 0, 1))
                                    setSoundSpeed(s, clamp(0.85 + v / 80, 0.85, 1.3))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)
