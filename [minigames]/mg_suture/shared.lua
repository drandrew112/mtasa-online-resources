-- mg_suture: wound suturing (HK-S04 / HK-S05). Stitch pairs across the wound: press the mouse on one
-- edge, drag the needle across, release on the other edge. Scored: bite depth (3-6 mm from the edge),
-- the same depth on both sides, stitches perpendicular to the wound, even spacing along it.

SUTURE = {
    DEFAULT_LENGTH = 4,       -- cm
    MM_PER_STITCH = 6.5,      -- default stitch count = length / this (3-10)
    DEPTH_MM = { 3, 6 },      -- good bite depth from the wound edge
    DEPTH_PX = { 22, 95 },    -- design px (1080p) clamp of the depth window
    MISS_PENALTY = 6,         -- percent off per stitch that did not cross the wound
    TREMOR_PX = 7,            -- design px of the scene shake at tremor = 1 (no local anaesthesia)
}

MGDEF = {
    res = "mg_suture", serverEvent = "onSutureGameFinish", clientEvent = "onClientSutureGameFinish",
    testCommand = "suturetest",
    details = { stitches = "number", placed = "number", misses = "number", depth = "number", spacing = "number", angle = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { length = cm, stitches, part = "left forearm" (label), time = 45, passPercent = 60,
--            tremor = 0-1 (patient moves: no local anaesthesia), stand = true|false|nil (auto) }
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    local length = clamp(tonumber(o.length) or SUTURE.DEFAULT_LENGTH, 1, 12)
    local stitches = tonumber(o.stitches) or math.floor(length * 10 / SUTURE.MM_PER_STITCH + 0.5)
    return {
        length = length,
        stitches = clamp(math.floor(stitches), 3, 10),
        part = type(o.part) == "string" and o.part:sub(1, 40) or "",
        time = clamp(tonumber(o.time) or 45, 15, 120),
        passPercent = clamp(tonumber(o.passPercent) or 60, 0, 100),
        tremor = clamp(tonumber(o.tremor) or 0, 0, 1),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
    }
end

function MGDEF.minDuration(o) return o.stitches * 0.5 end

function MGDEF.pass(percent, details, o)
    return percent >= o.passPercent and (tonumber(details.placed) or 0) >= o.stitches
end
