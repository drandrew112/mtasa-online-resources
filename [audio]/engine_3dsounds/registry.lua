active3DSounds = {}
debugSounds = {}

local function register3DSound(sound)
    if not isElement(sound) then return end
    if getElementType(sound) ~= "sound" then return end

    local minDistance = getSoundMinDistance(sound)

    if minDistance and minDistance > 0 then
        active3DSounds[sound] = true

        outputDebugString(
            "[Better3DSounds] Registered sound: " .. tostring(sound)
        )
    end
end

-- Resource indulásakor már létező hangok
for _, sound in ipairs(getElementsByType("sound")) do
    register3DSound(sound)
end

-- Újonnan elinduló hangok
addEventHandler("onClientSoundStarted", root, function()
    register3DSound(source)
end)

-- Takarítás
addEventHandler("onClientSoundStopped", root, function()
    active3DSounds[source] = nil
end)