-- mg_irrigation: wound irrigation (HK-S01). Hold the left mouse button to spray, keep the stream on
-- the debris until it is gone. The pressure (mouse wheel) drifts while spraying and has to stay in the
-- green band: too low does not clean, too high damages the tissue. It has to reach 100 % before the
-- wound is sutured (less: infection risk).

IRRIG = {
    BAND = { 0.40, 0.62 },     -- good pressure band (0-1)
    START_PRESSURE = 0.30,
    WHEEL_STEP = 0.035,
    DRIFT = 0.22,              -- random drift of the pressure per second while spraying
    CLEAN_RATE = 0.85,         -- debris hp per second inside the band
    LOW_RATE = 0.12,           -- below the band (scaled by pressure / band start)
    HIGH_RATE = 1.0,           -- above the band: cleans, but damages
    DAMAGE_RATE = 0.10,        -- damage per second at full pressure above the band
    RADIUS = 38,               -- design px around the aim point that the stream cleans
    PASS_DAMAGE = 25,          -- percent damage at most for a success
}

MGDEF = {
    res = "mg_irrigation", serverEvent = "onIrrigationGameFinish", clientEvent = "onClientIrrigationGameFinish",
    testCommand = "irrigationtest",
    details = { clean = "number", damage = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { debris = 8 (4-14), part = "" (label), time = 40, stand = nil }
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    return {
        debris = clamp(math.floor(tonumber(o.debris) or 8), 4, 14),
        part = type(o.part) == "string" and o.part:sub(1, 40) or "",
        time = clamp(tonumber(o.time) or 40, 15, 120),
        passPercent = clamp(tonumber(o.passPercent) or 100, 0, 100),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
    }
end

function MGDEF.minDuration(o) return o.debris * 0.4 end

-- success: the wound is clean (clean >= passPercent, default 100) and the damage is small
function MGDEF.pass(percent, details, o)
    return (tonumber(details.clean) or 0) >= o.passPercent and (tonumber(details.damage) or 100) <= IRRIG.PASS_DAMAGE
end
