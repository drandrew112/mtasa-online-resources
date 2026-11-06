-- mg_blooddraw: venous blood sampling (HK-L01). Tourniquet on (T), palpate the vein (hold the left
-- mouse button on the arm until it shows), set the needle angle with the wheel (15-30 degrees) and
-- click on the vein, then attach the tubes in the right order (click one in the rack) and fill each
-- one to the mark (hold SPACE), finally tourniquet off (T).
-- The mistakes have lab consequences (details): hemolysis (tourniquet > 60 s, several punctures),
-- EDTA contamination (EDTA before a citrate / serum / heparin tube: K high, Ca low), underfilled
-- citrate (false high INR).

BLOOD = {
    ORDER = { "citrate", "serum", "heparin", "edta", "fluoride" },   -- order of draw
    COLORS = { citrate = { 42, 111, 209 }, serum = { 212, 160, 23 }, heparin = { 47, 158, 90 },
               edta = { 142, 91, 198 }, fluoride = { 140, 148, 155 } },
    ANGLE = { 15, 30 },          -- good needle angle
    START_ANGLE = 40,
    WHEEL_DEG = 2.5,
    TOURNIQUET_MAX = 60,         -- s: longer -> hemolysis / haemoconcentration
    FILL_RATE = 0.42,            -- tube fill per second while SPACE is held
    FILL_OK = { 0.85, 1.0 },     -- the mark
    PALPATE_TIME = 0.9,          -- s on the vein to find it
    MAX_ATTEMPTS = 3,
    KEY_FILL = "space",
    KEY_TOURNIQUET = "t",
}

MGDEF = {
    res = "mg_blooddraw", serverEvent = "onBloodDrawGameFinish", clientEvent = "onClientBloodDrawGameFinish",
    testCommand = "blooddrawtest",
    details = { hemolysis = "boolean", edta = "boolean", citrate = "boolean", attempts = "number",
                tubes = "number", filled = "number", tourniquet = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { tubes = { "serum", "edta", ... } (default: all five), time = 60, passPercent = 60, stand = nil }
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    local want, tubes = {}, {}
    if type(o.tubes) == "table" then for _, id in ipairs(o.tubes) do want[id] = true end end
    for _, id in ipairs(BLOOD.ORDER) do
        if want[id] or type(o.tubes) ~= "table" then tubes[#tubes + 1] = id end
    end
    if #tubes == 0 then tubes = { "serum" } end
    return {
        tubes = tubes,
        time = clamp(tonumber(o.time) or 60, 25, 150),
        passPercent = clamp(tonumber(o.passPercent) or 60, 0, 100),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
    }
end

function MGDEF.minDuration(o) return 2 + #o.tubes * 1.5 end

function MGDEF.pass(percent, details, o)
    return percent >= o.passPercent and (tonumber(details.filled) or 0) >= #o.tubes and details.edta ~= true
end
