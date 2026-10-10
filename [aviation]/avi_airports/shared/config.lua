AP = {
    -- Wind (direction it blows FROM, degrees; knots). The runway in use is the end with the most
    -- headwind, unless an admin / ATC sets it with setActiveRunway. Same wind everywhere for now.
    WIND = { dir = 250, speed = 8 },

    -- taxi routing: runway centre lines are usable for taxiing (backtrack), but cost this much more
    RUNWAY_TAXI_COST = 3,
    -- taxiway points closer than this are the same junction
    JOIN_DIST = 1.5,
}
