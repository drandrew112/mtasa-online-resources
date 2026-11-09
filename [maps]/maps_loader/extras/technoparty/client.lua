-- maps_loader extras: the techno party of map ls_technoparty (was map_ls_technoparty/client.lua):
-- an internet radio stream and two dancing peds at the stage.
-- PERF: the stream and the peds exist only while the camera is within ACTIVE_DIST of the stage
-- (before: every client kept the stream open all the time, the sound reaches 100 m only).

local streamURL = "http://dsl.tb-stream.net:80"

local soundX, soundY, soundZ = 2024.65759, -1640.88159, 14.34938

local ped1X, ped1Y, ped1Z = 2024.86438, -1639.50769, 14.34938
local ped2X, ped2Y, ped2Z = 2023.32458, -1639.63159, 14.34938

local ACTIVE_DIST, INACTIVE_DIST = 250, 300

local sound
local ped1
local ped2
local active = false

local function createDancingPed(model, x, y, z)
    local ped = createPed(model, x, y, z)

    if ped then
        setElementData(ped, "hide_nametag", true)
        setElementFrozen(ped, true)
        setElementRotation(ped, 0, 0, 180)
        setPedAnimation(ped, "DANCING", "dnce_M_a", -1, true, false, false, false)
    end

    return ped
end

local function start()
    active = true
    sound = playSound3D(streamURL, soundX, soundY, soundZ, true, false)
    if sound then
        setElementData(sound, "isStream", true)
        setSoundMaxDistance(sound, 100)
        setSoundVolume(sound, 1.0)
    else
        outputDebugString("[maps_loader] technoparty: the stream could not be started", 1)
    end
    ped1 = createDancingPed(33, ped1X, ped1Y, ped1Z)
    ped2 = createDancingPed(101, ped2X, ped2Y, ped2Z)
end

local function stop()
    active = false
    for _, e in ipairs({ sound, ped1, ped2 }) do
        if isElement(e) then destroyElement(e) end
    end
    sound, ped1, ped2 = nil, nil, nil
end

local function check()
    local cx, cy, cz = getCameraMatrix()
    local d = getDistanceBetweenPoints3D(cx, cy, cz, soundX, soundY, soundZ)
    if not active and d <= ACTIVE_DIST then
        start()
    elseif active and d > INACTIVE_DIST then
        stop()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    check()
    setTimer(check, 1000, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, stop)
