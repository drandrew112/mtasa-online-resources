-- v_customs :: configuration (shared)

Customs = Customs or {}

-- Multiplies every price in shared/tuning.lua. 1.0 = the stock SA Customs prices.
Customs.PRICE_MULT = 1.0

-- Workshop markers. A vehicle driven onto one can be tuned (press E). Rotation
-- is the yaw the vehicle is snapped to while on the lift.
--   { x, y, z, rotation }
Customs.MARKERS = {
    { 1322.966, 1396.456, 10.654, 268.0 },  -- LV Airport
    { 1320.463, 1380.753, 10.445, 342.0 },  -- LV Airport
}

Customs.MARKER_SIZE = 4.0

-- How long the lift-in / lift-out camera fade + freeze takes (ms).
Customs.ENTER_FADE = 700
