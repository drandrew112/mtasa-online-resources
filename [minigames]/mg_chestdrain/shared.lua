-- mg_chestdrain: chest drain insertion (HK-R08). Steps:
--   1 site        click the safe triangle (5th intercostal space, mid-axillary line; the landmarks
--                 are drawn, the triangle is not)
--   2 anaesthesia hold the left mouse button on the site
--   3 incision    drag a cut just above the upper edge of the LOWER rib (not under the upper rib:
--                 the intercostal vessels run there)
--   4 dissection  blunt dissection: click when the shrinking ring meets the target ring (5 times)
--   5 tube        hold the left mouse button and push the tube along the arrow
--   6 fixation    SPACE: suture, connect the suction
-- Mistakes (details): wrongSpot (outside the triangle: organ / vessel injury), vessel (cut under the
-- upper rib: bleeding), mistimed (rough dissection), kink (the tube off the direction).

DRAIN = {
    ANAESTHESIA = 1.6,         -- s holding on the site
    DISSECT_HITS = 5,
    DISSECT_PERIOD = 1.3,      -- s per shrinking ring
    DISSECT_WINDOW = 0.13,     -- part of the period around the meeting point that counts
    TUBE_LEN = 150,            -- design px to push
    TUBE_DEV = 0.45,           -- allowed deviation (dot product below 1 - this = kink)
    KEY_FIX = "space",
}

MGDEF = {
    res = "mg_chestdrain", serverEvent = "onChestDrainGameFinish", clientEvent = "onClientChestDrainGameFinish",
    testCommand = "chestdraintest",
    details = { wrongSpot = "boolean", vessel = "boolean", mistimed = "number", kink = "boolean", steps = "number" },
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- options: { side = "right" | "left", time = 75, passPercent = 60, stand = nil }
function MGDEF.normalize(o)
    o = type(o) == "table" and o or {}
    return {
        side = o.side == "left" and "left" or "right",
        time = clamp(tonumber(o.time) or 75, 30, 180),
        passPercent = clamp(tonumber(o.passPercent) or 60, 0, 100),
        stand = (o.stand == true or o.stand == false) and o.stand or nil,
    }
end

function MGDEF.minDuration(o) return DRAIN.ANAESTHESIA + DRAIN.DISSECT_HITS * 0.4 + 1 end

function MGDEF.pass(percent, details, o) return percent >= o.passPercent and (tonumber(details.steps) or 0) >= 6 end
