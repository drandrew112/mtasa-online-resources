-- mg_reduction: closed fracture reduction under fluoroscopy (HK-S08). Hold the left mouse button and
-- drag: down = traction, left / right = lateral shift of the distal fragment. The mouse wheel turns
-- it, but only under traction. Aligned = angulation < 3 degrees and displacement < 2 mm, held for a
-- moment. Every movement hurts: without analgesia / sedation the pain meter fills fast and when full
-- the patient jerks the limb (the fragment slips back, a new attempt).

REDUCTION = {
    PX_PER_MM = 5,              -- design px per mm in the fluoroscopy view
    ANGLE = { 10, 24 },         -- starting angulation (degrees, random sign)
    SHIFT = { 5, 10 },          -- starting lateral displacement (mm, random sign)
    TRACTION_MIN = 3,           -- mm of traction needed before the fragment can be turned
    TRACTION_MAX = 9,
    GOAL_ANGLE = 3,
    GOAL_SHIFT = 2,
    HOLD = 1.0,                 -- s aligned under traction to finish
    WHEEL_DEG = 1.5,
    PAIN_PER_MM = 0.016,        -- pain per mm of movement (x analgesia factor)
    PAIN_PER_TICK = 0.02,       -- pain per wheel tick
    PAIN_DECAY = 0.05,          -- per second
    ANALGESIA_FACTOR = 0.35,
    ATTEMPT_PENALTY = 15,
}

MGDEF = {
    res = "mg_reduction", serverEvent = "onReductionGameFinish", clientEvent = "onClientReductionGameFinish",
    testCommand = "reductiontest",
    details = { reduced = "boolean", angle = "number", shift = "number", attempts = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { part = "" (label), analgesia = false, time = 60, passPercent = 50, stand = nil }
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    return {
        part = type(o.part) == "string" and o.part:sub(1, 40) or "",
        analgesia = o.analgesia == true,
        time = clamp(tonumber(o.time) or 60, 20, 150),
        passPercent = clamp(tonumber(o.passPercent) or 50, 0, 100),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
    }
end

function MGDEF.minDuration(o) return 2 end

function MGDEF.pass(percent, details, o) return details.reduced == true and percent >= o.passPercent end
