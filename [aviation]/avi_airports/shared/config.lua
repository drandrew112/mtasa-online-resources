AP = {
    -- Wind (direction it blows FROM, degrees; knots). The runway in use is the end with the most
    -- headwind, unless an admin / ATC sets it with setActiveRunway. Same wind everywhere for now.
    WIND = { dir = 250, speed = 8 },

    -- taxi routing: runway centre lines are usable for taxiing (backtrack), but cost this much more
    RUNWAY_TAXI_COST = 6,
    -- taxiway points closer than this are the same junction
    JOIN_DIST = 1.5,
    -- taxiway points this far past a runway end still join the runway centre line chain
    RUNWAY_CHAIN_EXT = 35,
    -- corner radius (m) of taxi routes and of the drawn taxiways (shorter on short segments)
    TURN_RADIUS = 25,
}
