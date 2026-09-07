local streamURL = "http://dsl.tb-stream.net:80"

local soundX, soundY, soundZ = 2024.65759, -1640.88159, 14.34938

local ped1X, ped1Y, ped1Z = 2024.86438, -1639.50769, 14.34938
local ped2X, ped2Y, ped2Z = 2023.32458, -1639.63159, 14.34938

local sound
local ped1
local ped2

local function createDancingPed(model, x, y, z)
    local ped = createPed(model, x, y, z)

    if ped then
        setElementData(ped, "hide_nametag", true)
        setElementFrozen(ped, true)
        setElementRotation(ped, 0, 0, 180)
        setPedAnimation(
            ped,
            "DANCING",
            "dnce_M_a",
            -1,
            true,
            false,
            false,
            false
        )
    end

    return ped
end

addEventHandler("onClientResourceStart", resourceRoot, function()

    -- 3D stream
    sound = playSound3D(streamURL, soundX, soundY, soundZ, true, false)

    if sound then
        setSoundMaxDistance(sound, 100)
        setSoundVolume(sound, 1.0)
    else
        outputDebugString("Nem sikerült elindítani a streamet!", 1)
    end

    -- 1. ped - Skin ID 33
    ped1 = createDancingPed(
        33,
        ped1X, ped1Y, ped1Z
    )

    -- 2. ped - Skin ID 101
    ped2 = createDancingPed(
        101,
        ped2X, ped2Y, ped2Z
    )

end)

addEventHandler("onClientResourceStop", resourceRoot, function()

    if isElement(sound) then
        destroyElement(sound)
    end

    if isElement(ped1) then
        destroyElement(ped1)
    end

    if isElement(ped2) then
        destroyElement(ped2)
    end

end)