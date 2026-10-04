-- Vigilance device (Sifa). While the train moves faster than LOCO.SIFA.MIN_SPEED the driver
-- has to press the acknowledge key every INTERVAL_MIN..MAX seconds, and whenever the signal
-- in front of the train changes its aspect. Sequence: lamp (silent) -> alarm sound ->
-- emergency stop. After a forced stop the brake releases once the train stands and the key
-- is pressed. A signal passed at danger (server) triggers the same emergency stop.
-- Sifa.state: idle | lamp | alarm | brake ; Sifa.braking: an emergency stop is running.

Sifa = { state = "idle", braking = false }
local M = {}
local S = LOCO.SIFA
local due = 0                 -- tick of the next check
local phaseT = 0              -- tick the current phase started
local sound = nil
local watched = { id = nil, aspect = nil }
local lastPoll = 0
local brakeReason = nil

local function schedule()
    due = getTickCount() + math.random(S.INTERVAL_MIN * 1000, S.INTERVAL_MAX * 1000)
end

local function stopSound()
    if sound and isElement(sound) then destroyElement(sound) end
    sound = nil
end

local function setPhase(p)
    Sifa.state = p
    phaseT = getTickCount()
    if p == "alarm" then
        stopSound()
        sound = playSound(S.SOUND, true)
        if sound then setSoundVolume(sound, S.VOLUME) end
    elseif p ~= "brake" then
        stopSound()
    end
end

local function notify(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then exports.ui_core:addNotification("Locomotive", text)
    else outputChatBox("[Locomotive] " .. text, 255, 120, 80) end
end

-- forced stop (Sifa timeout or a signal passed at danger)
function Sifa.emergency(reason)
    if Sifa.braking then return end
    Sifa.braking = true
    brakeReason = reason
    Loco.lock("emergency", true)
    Loco.emergency(true)
    if reason then notify(reason .. " Emergency brake applied.") end
end

local function trigger()
    if Sifa.state == "idle" then setPhase("lamp") end
end

function Sifa.acknowledge()
    if not Loco.active then return end
    if Sifa.braking then
        if Loco.speed() < 1 then
            Sifa.braking = false
            brakeReason = nil
            Loco.lock("emergency", false)
            Loco.emergency(false)
            setPhase("idle")
            schedule()
        end
        return
    end
    if Sifa.state ~= "idle" then setPhase("idle") end
    schedule()
end

-- the emergency brake itself is applied by the network train (Loco.emergency)
local function brakeStep() end

local lastT = getTickCount()
local function update()
    local now = getTickCount()
    local dt = math.min(0.1, (now - lastT) / 1000)
    lastT = now
    if Sifa.braking then brakeStep(dt) end

    local st = Loco.state()
    local active = st.eng == "running" and Loco.speed() > S.MIN_SPEED
    if not active and not Sifa.braking then
        if Sifa.state ~= "idle" then setPhase("idle") end
        if now > due then schedule() end
        return
    end

    -- signal in front changed its aspect -> check
    if now - lastPoll > 250 then
        lastPoll = now
        local track, _, dir, head = Loco.trackInfo()
        if track then
            local ok, id, _, aspect = pcall(function() return exports.rw_signals:getSignalAhead(track, head, dir) end)
            if ok and id then
                if watched.id == id and watched.aspect ~= aspect then trigger() end
                watched.id, watched.aspect = id, aspect
            else
                watched.id, watched.aspect = nil, nil
            end
        end
    end

    if Sifa.state == "idle" and now >= due and not Sifa.braking then setPhase("lamp")
    elseif Sifa.state == "lamp" and now - phaseT > S.LAMP_TIME * 1000 then setPhase("alarm")
    elseif Sifa.state == "alarm" and now - phaseT > S.ALARM_TIME * 1000 then
        setPhase("brake")
        Loco.send("sifa")
        Sifa.emergency("Vigilance device not acknowledged!")
    end
end

-- the panel button and the key both call acknowledge; a held key does not count again
addCommandHandler("rw_sifa", function() Sifa.acknowledge() end)
bindKey(LOCO.KEYS.sifa, "down", "rw_sifa")

addEvent("rw:loco:emergency", true)
addEventHandler("rw:loco:emergency", resourceRoot, function(reason)
    if Loco.active then
        setPhase("brake")
        Sifa.emergency(reason)
    end
end)

function M.update()
    update()
end

function M.enter()
    Sifa.state, Sifa.braking = "idle", false
    watched.id, watched.aspect = nil, nil
    lastT = getTickCount()
    schedule()
end

function M.leave()
    stopSound()
    Sifa.state, Sifa.braking = "idle", false
end

registerLocoModule("sifa", M)

-- client export: Sifa state of the local driver (for other scripts / tests)
function getSifaState()
    return Sifa.state, Sifa.braking, math.max(0, (due - getTickCount()) / 1000)
end
