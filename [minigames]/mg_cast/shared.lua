-- mg_cast: plaster cast (HK-S09 / HK-S10). Roll the bandage on with SPACE when the rhythm dot is in
-- the window, keep the overlap about 50 % with the mouse (left / right). Three layers. Off rhythm =
-- wrinkle, too little overlap = gap, too much = tight. Too many tight turns: the circulation check
-- fails afterwards and the cast has to be redone (success = false).

CAST = {
    LAYERS = 3,
    WRAP_W = 0.20,             -- one turn covers this part of the limb length (about 9 turns a layer)
    OVERLAP_BAND = { 0.40, 0.60 },
    GAP_BELOW = 0.28,          -- overlap below: gap
    TIGHT_ABOVE = 0.70,        -- overlap above: tight turn
    RHYTHM_HZ = 0.75,          -- rhythm dot oscillations per second
    RHYTHM_WINDOW = 0.16,      -- half width of the good window (0-1)
    TIGHT_FAIL = 3,            -- this many tight turns: too tight, redo
    KEY = "space",
}

MGDEF = {
    res = "mg_cast", serverEvent = "onCastGameFinish", clientEvent = "onClientCastGameFinish",
    testCommand = "casttest",
    details = { turns = "number", wrinkles = "number", gaps = "number", tight = "number", layers = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { part = "" (label), speed = 1 (rhythm), time = 60, passPercent = 65, stand = nil }
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    return {
        part = type(o.part) == "string" and o.part:sub(1, 40) or "",
        speed = clamp(tonumber(o.speed) or 1, 0.6, 1.8),
        time = clamp(tonumber(o.time) or 60, 20, 150),
        passPercent = clamp(tonumber(o.passPercent) or 65, 0, 100),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
    }
end

function MGDEF.minDuration(o) return CAST.LAYERS * 4 * 0.3 end

function MGDEF.pass(percent, details, o)
    return percent >= o.passPercent and (tonumber(details.tight) or 99) < CAST.TIGHT_FAIL
        and (tonumber(details.layers) or 0) >= CAST.LAYERS
end
