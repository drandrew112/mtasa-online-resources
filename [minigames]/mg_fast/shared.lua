-- mg_fast: FAST / eFAST bedside ultrasound (HK-K20 / HK-K21). Hold the left mouse button to put the
-- probe on the torso, move it into a window (dashed circle) and keep it there; the mouse wheel tilts
-- the probe until the picture clears. A window is read after 3 s of a clear picture. Windows not read
-- in time are "not evaluable". The result per window comes from options.positives (the patient).

FAST = {
    WINDOWS = { "ruq", "luq", "pelvis", "cardiac" },
    EFAST = { "lung_r", "lung_l" },
    HOLD = 3.0,                 -- s of a clear picture to read a window
    CLEAR = 0.72,               -- clarity needed
    TILT_RANGE = 28,            -- the target tilt of a window is random within +-this
    TILT_FALLOFF = 22,          -- degrees off the target where the clarity reaches 0
    WHEEL_DEG = 3,
    RADIUS = 30,                -- design px of a window
}

MGDEF = {
    res = "mg_fast", serverEvent = "onFastGameFinish", clientEvent = "onClientFastGameFinish",
    testCommand = "fasttest",
    details = { windows = "table", evaluated = "number", total = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { efast = false, positives = { luq = true, ... }, time = 50, passPercent = 75, stand = nil }
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    local pos = {}
    if type(o.positives) == "table" then
        for _, id in ipairs(FAST.WINDOWS) do pos[id] = o.positives[id] == true end
        for _, id in ipairs(FAST.EFAST) do pos[id] = o.positives[id] == true end
    end
    return {
        efast = o.efast == true,
        positives = pos,
        time = clamp(tonumber(o.time) or (o.efast and 70 or 50), 20, 150),
        passPercent = clamp(tonumber(o.passPercent) or 75, 0, 100),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
    }
end

function FAST.windowList(o)
    local list = {}
    for _, id in ipairs(FAST.WINDOWS) do list[#list + 1] = id end
    if o.efast then for _, id in ipairs(FAST.EFAST) do list[#list + 1] = id end end
    return list
end

function MGDEF.minDuration(o) return #FAST.windowList(o) * FAST.HOLD * 0.9 end

function MGDEF.pass(percent, details, o) return percent >= o.passPercent end
