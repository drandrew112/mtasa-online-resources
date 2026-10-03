-- ECG and pleth (SpO2 pulse wave) signal of the monitor, generated at a fixed sample rate into
-- ring buffers, so the trace scrolls smoothly and rate changes do not make it jump.
-- The examination panel feeds it the patient's rhythm and draws it (panel.lua, lifepak.lua);
-- on every QRS complex the monitor beeps (only while the panel is open, see ecgSetBeep).
--
-- Waveforms (MEDIC_RHYTHMS[rhythm].wave):
--   sinus  P wave, narrow QRS, T wave (sinus / bradycardia / tachycardia by the rate)
--   vt     wide, regular, sine-like complexes without P waves (VT with pulse / pulseless VT)
--   pea    slow, broad, low bumps without an R wave - electrical activity without a pulse (no beep)
--   vf     chaotic irregular waves, no complexes
--   flat   asystole: an almost flat line

local SAMPLE_RATE = 100     -- samples per second
local BUFFER_SECONDS = 5    -- the longest window a trace can show
local SIZE = SAMPLE_RATE * BUFFER_SECONDS
local DT = 1 / SAMPLE_RATE
local PLETH_DELAY = 0.2     -- seconds from the QRS to the pulse wave at the finger
local BEEP_FILE = "sounds/ecg_beep.wav"
local BEEP_VOLUME = 0.5

local ecgBuffer, plethBuffer = {}, {}
local head, filled = 0, 0
local signalTime = 0        -- seconds of signal generated
local beatTime = 0          -- seconds since the last QRS
local lastTick
local input = { wave = "flat", rate = 0, pulse = false, spo2 = 0 }
local beepOn = false
local beepSound

---------------------------------------------------------------------------
-- Waveforms: one value (baseline 0, R peak 1) at tb seconds after the QRS, rr = beat length
---------------------------------------------------------------------------

-- The R peak (0.04 s) falls exactly on a sample: every beat starts on a sample (generateSample),
-- so every QRS is drawn the same height.
local function sinusWave(tb, rr)
    if tb < 0.02 then return -0.12 * tb / 0.02 end                      -- Q
    if tb < 0.04 then return -0.12 + 1.12 * (tb - 0.02) / 0.02 end      -- R
    if tb < 0.07 then return 1.0 - 1.3 * (tb - 0.04) / 0.03 end         -- S
    if tb < 0.09 then return -0.3 + 0.3 * (tb - 0.07) / 0.02 end
    local tStart, tLength = 0.09 + math.min(0.13, rr * 0.15), math.min(0.18, rr * 0.3)
    if tb >= tStart and tb < tStart + tLength then                    -- T
        return 0.28 * math.sin(math.pi * (tb - tStart) / tLength)
    end
    local toNext = rr - tb
    local pEnd, pLength = math.min(0.12, rr * 0.18), math.min(0.09, rr * 0.15)
    if toNext > pEnd and toNext < pEnd + pLength then                 -- P
        return 0.13 * math.sin(math.pi * (toNext - pEnd) / pLength)
    end
    return 0
end

local function vtWave(tb, rr)
    local x = tb / rr
    if x < 0.55 then return 0.95 * math.sin(math.pi * x / 0.55) end
    return -0.4 * math.sin(math.pi * (x - 0.55) / 0.45)
end

-- no sharp R wave: a low, broad, slurred deflection and a shallow inverted wave after it
local function peaWave(tb)
    if tb < 0.16 then return 0.16 * math.sin(math.pi * tb / 0.16) end
    if tb < 0.22 then return -0.05 * math.sin(math.pi * (tb - 0.16) / 0.06) end
    if tb >= 0.3 and tb < 0.62 then return -0.07 * math.sin(math.pi * (tb - 0.3) / 0.32) end
    return 0
end

local TWO_PI = math.pi * 2

local function vfWave(t)
    local v = math.sin(TWO_PI * 4.6 * t) * 0.5 + math.sin(TWO_PI * 6.9 * t + 1.7) * 0.3
        + math.sin(TWO_PI * 3.1 * t + 0.4) * 0.35
    return v * (0.55 + 0.45 * math.sin(TWO_PI * 0.31 * t)) * 0.75 + (math.random() - 0.5) * 0.06
end

local function flatWave(t)
    return 0.025 * math.sin(TWO_PI * 0.25 * t) + (math.random() - 0.5) * 0.02
end

-- Pulse wave at the finger: quick rise, slow fall with a small dicrotic notch (0..1)
local function plethWave(tb, rr)
    local tp = tb - PLETH_DELAY
    if tp < 0 then tp = tp + rr end
    local x = tp / rr
    if x < 0.18 then return math.sin(math.pi / 2 * x / 0.18) end
    local v = math.exp(-(x - 0.18) * 3.2)
    if x > 0.35 and x < 0.5 then v = v + 0.1 * math.sin(math.pi * (x - 0.35) / 0.15) end
    return v
end

---------------------------------------------------------------------------
-- Generator
---------------------------------------------------------------------------

local BEATING = { sinus = true, vt = true, pea = true }
local BEEPING = { sinus = true, vt = true } -- the monitor detects these as QRS complexes (PEA: no)

local function onBeat()
    if not beepOn then return end
    if isElement(beepSound) then stopSound(beepSound) end
    beepSound = playSound(BEEP_FILE)
    if beepSound then setSoundVolume(beepSound, BEEP_VOLUME) end
end

local function generateSample()
    signalTime = signalTime + DT
    local wave, rate = input.wave, input.rate
    local ecg, pleth = 0, 0
    if BEATING[wave] and rate > 0 then
        local rr = 60 / rate
        beatTime = beatTime + DT
        if beatTime >= rr - DT / 2 then
            beatTime = 0 -- a new beat starts on this sample: same shape for every complex
            if BEEPING[wave] then onBeat() end
        end
        if wave == "sinus" then
            ecg = sinusWave(beatTime, rr)
        elseif wave == "vt" then
            ecg = vtWave(beatTime, rr)
        else
            ecg = peaWave(beatTime)
        end
        if input.pulse and input.spo2 > 0 then
            pleth = plethWave(beatTime, rr) * (wave == "vt" and 0.4 or 1)
        end
    else
        beatTime = 60 -- the first complex comes right when the heart starts beating again
        ecg = wave == "vf" and vfWave(signalTime) or flatWave(signalTime)
    end
    head = head % SIZE + 1
    ecgBuffer[head], plethBuffer[head] = ecg, pleth
    if filled < SIZE then filled = filled + 1 end
end

-- New patient: empty traces
function ecgReset()
    head, filled, beatTime, lastTick = 0, 0, 0, nil
end

-- rhythm: MEDIC_RHYTHMS key, rate: ECG complexes per minute, spo2: for the pleth amplitude
function ecgSetInput(rhythm, rate, spo2)
    local def = MEDIC_RHYTHMS[rhythm] or MEDIC_RHYTHMS.ASYSTOLE
    input.wave = def.wave
    input.rate = tonumber(rate) or 0
    input.pulse = def.pulse == true
    input.spo2 = tonumber(spo2) or 0
end

-- The monitor beeps on every QRS (the panel turns it on while it is open with a monitor attached)
function ecgSetBeep(enabled)
    beepOn = enabled == true
    if not beepOn and isElement(beepSound) then
        stopSound(beepSound)
        beepSound = nil
    end
end

-- Generates the samples due since the last call (call it every frame while a trace is shown)
function ecgUpdate()
    local now = getTickCount()
    if not lastTick then lastTick = now end
    local due = math.floor((now - lastTick) * SAMPLE_RATE / 1000)
    if due <= 0 then return end
    lastTick = lastTick + due * 1000 / SAMPLE_RATE
    for _ = 1, math.min(due, SIZE) do generateSample() end
end

-- Draws the last `seconds` of a channel ("ecg" | "pleth"), newest sample at the right edge.
-- baseline: 0..1 height fraction of the zero line, gain: height fraction of an amplitude of 1
function ecgDraw(channel, x, y, w, h, seconds, color, width, baseline, gain)
    local buffer = channel == "pleth" and plethBuffer or ecgBuffer
    local span = math.min(SIZE, math.floor(seconds * SAMPLE_RATE))
    local count = math.min(filled, span)
    if count < 2 then return end
    local step = w / span
    local zero, amp = y + h * baseline, h * gain
    local lastX, lastY
    for k = 0, count - 1 do
        local index = (head - count + k) % SIZE + 1
        local px = x + w - (count - 1 - k) * step
        local py = math.max(y, math.min(y + h, zero - buffer[index] * amp))
        if lastX then dxDrawLine(lastX, lastY, px, py, color, width) end
        lastX, lastY = px, py
    end
end
