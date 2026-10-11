-- Traffic lights (server): one global cycle (TRAFFIC.SIGNAL_CYCLE). It also drives GTA's own
-- traffic light objects through setTrafficLightState, so what players see matches the AI.
-- Connection phase 1 = north-south arms (GTA state 0/1 green/yellow), 2 = east-west (3/4).

Signals = {}

local step, stepEnd = 1, 0
local LIGHT = {
    [1] = { [0] = "green", [1] = "yellow" },
    [2] = { [3] = "green", [4] = "yellow" },
}

local function apply()
    local s = TRAFFIC.SIGNAL_CYCLE[step]
    setTrafficLightState(s.state)
end

function Signals.start()
    setTrafficLightsLocked(true)
    step, stepEnd = 1, getTickCount() + TRAFFIC.SIGNAL_CYCLE[1].time
    apply()
end

function Signals.stop()
    setTrafficLightsLocked(false)
    setTrafficLightState("auto")
end

function Signals.update(now)
    if now < stepEnd then return end
    step = step % #TRAFFIC.SIGNAL_CYCLE + 1
    stepEnd = now + TRAFFIC.SIGNAL_CYCLE[step].time
    apply()
end

-- "green" | "yellow" | "red" for a connection phase (0 = unsignalled -> "green")
function Signals.light(phase)
    if not phase or phase == 0 then return "green" end
    local p = LIGHT[phase]
    if not p then return "green" end
    return p[TRAFFIC.SIGNAL_CYCLE[step].state] or "red"
end
