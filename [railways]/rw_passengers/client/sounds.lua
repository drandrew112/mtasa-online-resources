-- Ride sounds inside the coach (2D, muffled): running loop by speed, wheel clacks at the rail
-- joints, brake squeal when stopping, a chime when the doors open / close. The sound files of
-- rw_customtracks are reused.

local S = RWP.SOUNDS
local run, squeal
local lastJoint
local lastDoors

local function stopAll()
    if isElement(run) then destroyElement(run) end
    if isElement(squeal) then destroyElement(squeal) end
    run, squeal, lastJoint, lastDoors = nil, nil, nil, nil
end

-- tunnels and covered stations are louder (Windows.tunnel is set by windows.lua)
local function envGain()
    return 1 + 0.35 * ((Windows and Windows.tunnel) or 0)
end

local function clack(vol)
    local s = playSound(S.CLACK)
    if s then
        setSoundVolume(s, vol)
        setSoundSpeed(s, 0.9 + math.random() * 0.2)
    end
end

function rwpChime()
    local s = playSound(S.CHIME)
    if s then setSoundVolume(s, 0.7) end
end

addEventHandler("onClientRender", root, function()
    if not Ride.active then
        if run or squeal then stopAll() end
        return
    end
    local v = math.abs(Ride.vNow)
    local gain = S.VOLUME * envGain()

    -- running loop
    if v > 0.3 then
        if not isElement(run) then
            run = playSound(S.RUN, true)
        end
        if run then
            setSoundVolume(run, math.min(1, v / 22) * 0.7 * gain)
            setSoundSpeed(run, 0.55 + math.min(v, 40) / 45)
        end
    elseif isElement(run) then
        destroyElement(run)
        run = nil
    end

    -- rail joints: a pair of clacks (the two bogies) every CLACK_EVERY metres
    local joint = math.floor(Ride.dist / S.CLACK_EVERY)
    if lastJoint and joint ~= lastJoint and v > 1.5 then
        local vol = math.min(1, 0.25 + v / 30) * 0.6 * gain
        clack(vol)
        local gap = 14.5 / v * 1000
        if gap < 1500 then setTimer(clack, gap, 1, vol * 0.9) end
    end
    lastJoint = joint

    -- squeal: braking hard at low speed
    local braking = Ride.accel < -0.45 and v > 0.4 and v < 9
    if braking then
        if not isElement(squeal) then squeal = playSound(S.SQUEAL, true) end
        if squeal then setSoundVolume(squeal, math.min(1, -Ride.accel / 1.2) * 0.45 * gain) end
    elseif isElement(squeal) then
        destroyElement(squeal)
        squeal = nil
    end

    -- door chime
    local doors = Ride.doors or "closed"
    if lastDoors and doors ~= lastDoors and (doors == "closed" or lastDoors == "closed") then
        local s = playSound(S.CLACK)      -- door mechanism thump
        if s then setSoundVolume(s, 0.35) setSoundSpeed(s, 0.6) end
    end
    lastDoors = doors
end)

addEventHandler("onClientResourceStop", resourceRoot, stopAll)
