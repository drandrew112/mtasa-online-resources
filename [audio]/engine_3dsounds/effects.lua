DEBUG = false

local SOUND_SPEED_OF_SOUND = 343.0

-- Játékra optimalizált Doppler
local DOPPLER_STRENGTH = 1.0
local DOPPLER_MIN_SPEED = 0.70
local DOPPLER_MAX_SPEED = 1.30
local DOPPLER_SMOOTHING = 0.15

local OCCLUSION_VOLUME = 0.25

local soundStates = {}

-- ============================================================
-- GENERAL HELPERS
-- ============================================================

local cameraVelocityState = {
    x = nil,
    y = nil,
    z = nil,
    tick = nil
}

local function getListenerVelocity(cx, cy, cz, now)
    local state = cameraVelocityState

    if not state.tick then
        state.x = cx
        state.y = cy
        state.z = cz
        state.tick = now

        return 0, 0, 0
    end

    local dt = (now - state.tick) / 1000.0

    if dt <= 0 or dt > 1.0 then
        state.x = cx
        state.y = cy
        state.z = cz
        state.tick = now

        return 0, 0, 0
    end

    local vx = (cx - state.x) / dt
    local vy = (cy - state.y) / dt
    local vz = (cz - state.z) / dt

    state.x = cx
    state.y = cy
    state.z = cz
    state.tick = now

    return vx, vy, vz
end

local function getSourceVelocity(sound, sx, sy, sz)
    local attachedTo = getElementAttachedTo(sound)

    if attachedTo then
        local vx, vy, vz = getElementVelocity(attachedTo)

        if vx then
            return vx * 50.0, vy * 50.0, vz * 50.0
        end
    end

    -- Fallback: estimate velocity from the sound's position changes.
    local state = soundStates[sound]
    local now = getTickCount()

    if state and state.lastX and state.lastTick then
        local dt = (now - state.lastTick) / 1000.0

        if dt > 0 and dt < 1.0 then
            return
                (sx - state.lastX) / dt,
                (sy - state.lastY) / dt,
                (sz - state.lastZ) / dt
        end
    end

    return 0, 0, 0
end

local function getSoundState(sound)
    local state = soundStates[sound]

    if not state then
        state = {
            originalVolume = getSoundVolume(sound) or 1.0,
            appliedVolume = getSoundVolume(sound) or 1.0,

            originalSpeed = getSoundSpeed(sound) or 1.0,
            appliedSpeed = getSoundSpeed(sound) or 1.0,
            dopplerSpeed = getSoundSpeed(sound) or 1.0,

            lastX = nil,
            lastY = nil,
            lastZ = nil,
            lastTick = getTickCount(),

            obstructed = false,
            radialVelocity = 0,
            inRange = false,
            dopplerEnabled = false,
            isStream = false
        }

        soundStates[sound] = state
    end

    return state
end

-- ============================================================
-- EFFECT: OCCLUSION
-- ============================================================

local function getSoundOcclusion(sound, cx, cy, cz, sx, sy, sz)
    local attachedTo = getElementAttachedTo(sound)

    local hit = processLineOfSight(
        cx, cy, cz,
        sx, sy, sz,
        true,   -- checkBuildings
        true,   -- checkVehicles
        true,   -- checkPlayers
        true,   -- checkObjects
        true,   -- checkDummies
        false,  -- seeThroughStuff
        false,  -- shootThroughStuff
        false,  -- ignoreSomeObjectsForCamera
        attachedTo
    )

    return hit == true
end

local function applyOcclusion(sound, state, isObstructed, inRange)
    state.obstructed = isObstructed
    state.inRange = inRange

    local targetVolume = state.originalVolume

    if inRange and isObstructed then
        targetVolume = state.originalVolume * OCCLUSION_VOLUME
    end

    if math.abs(targetVolume - state.appliedVolume) > 0.001 then
        setSoundVolume(sound, targetVolume)
        state.appliedVolume = targetVolume
    end
end

-- ============================================================
-- EFFECT: DOPPLER
-- ============================================================

local function applyDoppler(
    sound,
    state,
    sx, sy, sz,
    cx, cy, cz,
    listenerVX, listenerVY, listenerVZ,
    now,
    inRange
)
    local isStream = getElementData(sound, "isStream") == true
    state.isStream = isStream

    -- Streamelt hangon nem alkalmazunk Dopplert.
    if isStream then
        state.radialVelocity = 0
        state.dopplerEnabled = false

        if math.abs(state.appliedSpeed - state.originalSpeed) > 0.001 then
            setSoundSpeed(sound, state.originalSpeed)
            state.appliedSpeed = state.originalSpeed
            state.dopplerSpeed = state.originalSpeed
        end

        return
    end

    state.dopplerEnabled = true

    if not inRange then
        state.radialVelocity = 0

        if math.abs(state.appliedSpeed - state.originalSpeed) > 0.001 then
            setSoundSpeed(sound, state.originalSpeed)
            state.appliedSpeed = state.originalSpeed
            state.dopplerSpeed = state.originalSpeed
        end

        return
    end

    local currentSpeed = getSoundSpeed(sound)

    -- Más resource által módosított playback speedet új alapértékként kezelünk.
    if currentSpeed and math.abs(currentSpeed - state.appliedSpeed) > 0.002 then
        state.originalSpeed = currentSpeed
        state.appliedSpeed = currentSpeed
        state.dopplerSpeed = currentSpeed
    end

    local sourceVX, sourceVY, sourceVZ =
        getSourceVelocity(sound, sx, sy, sz)

    local dirX = sx - cx
    local dirY = sy - cy
    local dirZ = sz - cz

    local distance = math.sqrt(
        dirX * dirX +
        dirY * dirY +
        dirZ * dirZ
    )

    if distance < 0.001 then
        state.radialVelocity = 0
        return
    end

    dirX = dirX / distance
    dirY = dirY / distance
    dirZ = dirZ / distance

    -- Pozitív = távolodik, negatív = közeledik.
    local radialVelocity =
        (sourceVX - listenerVX) * dirX +
        (sourceVY - listenerVY) * dirY +
        (sourceVZ - listenerVZ) * dirZ

    state.radialVelocity = radialVelocity

    -- Játékra optimalizált Doppler: az erősséget szándékosan
    -- felskálázzuk, hogy GTA/MTA környezetben is hallható legyen.
    local effectiveVelocity = radialVelocity * DOPPLER_STRENGTH

    local denominator = SOUND_SPEED_OF_SOUND + effectiveVelocity
    denominator = math.max(80.0, denominator)

    local dopplerFactor =
        SOUND_SPEED_OF_SOUND / denominator

    local targetSpeed = state.originalSpeed * dopplerFactor

    targetSpeed = math.max(
        state.originalSpeed * DOPPLER_MIN_SPEED,
        math.min(
            state.originalSpeed * DOPPLER_MAX_SPEED,
            targetSpeed
        )
    )

    state.dopplerSpeed = state.dopplerSpeed +
        (targetSpeed - state.dopplerSpeed) *
        DOPPLER_SMOOTHING

    if math.abs(state.dopplerSpeed - state.appliedSpeed) > 0.001 then
        setSoundSpeed(sound, state.dopplerSpeed)
        state.appliedSpeed = state.dopplerSpeed
    end
end

-- ============================================================
-- EFFECT: DEBUG DRAWING
-- ============================================================

local function drawDebugSound(sound, state, sx, sy, sz, cx, cy, cz, distance, maxDistance)
    if not DEBUG then
        return
    end

    local status

    if not state.inRange then
        status = "OUT OF RANGE"
    elseif state.obstructed then
        status = "OCCLUDED"
    else
        status = "CLEAR"
    end

    local lineColor

    if not state.inRange then
        lineColor = tocolor(140, 140, 140, 130)
    elseif state.obstructed then
        lineColor = tocolor(255, 60, 60, 220)
    else
        lineColor = tocolor(60, 255, 100, 220)
    end

    -- Camera -> sound
    dxDrawLine3D(
        cx, cy, cz,
        sx, sy, sz,
        lineColor,
        2
    )

    -- Sound position marker
    dxDrawLine3D(
        sx - 0.3, sy, sz,
        sx + 0.3, sy, sz,
        tocolor(255, 220, 50, 255),
        3
    )

    dxDrawLine3D(
        sx, sy - 0.3, sz,
        sx, sy + 0.3, sz,
        tocolor(255, 220, 50, 255),
        3
    )

    dxDrawLine3D(
        sx, sy, sz - 0.3,
        sx, sy, sz + 0.3,
        tocolor(255, 220, 50, 255),
        3
    )

    local screenX, screenY = getScreenFromWorldPosition(
        sx, sy, sz + 0.6,
        300
    )

    if not screenX or not screenY then
        return
    end

    local elementID = getElementID(sound)

    if not elementID or elementID == "" then
        elementID = tostring(sound)
    end

    local attachedTo = getElementAttachedTo(sound)
    local attachedType = attachedTo and getElementType(attachedTo) or "none"

    local text = string.format(
        "3D SOUND\nID: %s\nAttached: %s\nDistance: %.1f / %.1f m\nStatus: %s\nVolume: %.2f\nDoppler: %s\nSpeed: %.3f\nRadial velocity: %.1f km/h",
        elementID,
        attachedType,
        distance,
        maxDistance,
        status,
        state.appliedVolume,
        state.isStream and "OFF (STREAM)" or "ON",
        state.appliedSpeed,
        state.radialVelocity * 3.6
    )

    dxDrawText(
        text,
        screenX + 8,
        screenY,
        screenX + 420,
        screenY + 150,
        tocolor(255, 255, 255, 235),
        1,
        "default",
        "left",
        "top",
        false,
        false,
        false,
        true
    )
end

local function drawDebugHeader(registeredCount)
    if not DEBUG then
        return
    end

    dxDrawText(
        "Registered 3D sounds: " .. registeredCount,
        20,
        85,
        500,
        115,
        tocolor(255, 255, 255, 255),
        1.2,
        "default-bold"
    )
end

-- ============================================================
-- SINGLE RENDER LOOP
-- ============================================================

addEventHandler("onClientRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    local registeredCount = 0
    local now = getTickCount()
    local listenerVX, listenerVY, listenerVZ = getListenerVelocity(cx, cy, cz, now)

    for sound in pairs(active3DSounds) do
        if not isElement(sound) then
            active3DSounds[sound] = nil
            soundStates[sound] = nil
        else
            registeredCount = registeredCount + 1

            local state = getSoundState(sound)
            local sx, sy, sz = getElementPosition(sound)
            local maxDistance = getSoundMaxDistance(sound) or 20

            local distance = getDistanceBetweenPoints3D(
                cx, cy, cz,
                sx, sy, sz
            )

            local inRange = distance <= maxDistance
            local isObstructed = false

            -- EFFECT 1: Occlusion
            if inRange then
                isObstructed = getSoundOcclusion(
                    sound,
                    cx, cy, cz,
                    sx, sy, sz
                )
            end

            applyOcclusion(
                sound,
                state,
                isObstructed,
                inRange
            )

            -- EFFECT 2: Doppler
            applyDoppler(
                sound,
                state,
                sx, sy, sz,
                cx, cy, cz,
                listenerVX,
                listenerVY,
                listenerVZ,
                now,
                inRange
            )

            -- Update fallback velocity tracking after the effects have run.
            state.lastX = sx
            state.lastY = sy
            state.lastZ = sz
            state.lastTick = now

            -- DEBUG
            drawDebugSound(
                sound,
                state,
                sx, sy, sz,
                cx, cy, cz,
                distance,
                maxDistance
            )
        end
    end

    drawDebugHeader(registeredCount)
end)

addEventHandler("onClientElementDestroy", root, function()
    if soundStates[source] then
        soundStates[source] = nil
    end
end)

addEventHandler("onClientSoundStopped", root, function()
    soundStates[source] = nil
end)
