ARROWS = {
    DEFAULT_COUNT = 15,
    MIN_COUNT = 1,
    MAX_COUNT = 100,

    PASS_PERCENT = 70,      -- the game is won when the hit ratio is strictly above this

    SPEED_PX = 480,         -- arrow speed in pixels/second at 1080p (scaled with screen height)
    SPAWN_LEAD = 0.4,       -- seconds before the first arrow enters the screen
    SPAWN_MIN = 0.6,        -- min/max seconds between two arrows
    SPAWN_MAX = 1.0,
    RESULT_TIME = 2.0,      -- seconds the result is shown before the game closes

    MIN_SPEED_MULT = 0.5,
    MAX_SPEED_MULT = 2.5,

    TEST_COMMAND = true,    -- /arrowstest [count] [speed] for testing, disable in production
}

ARROW_DIRS = { "left", "up", "right", "down" }

function arrowsClampCount(count)
    count = math.floor(tonumber(count) or ARROWS.DEFAULT_COUNT)
    return math.max(ARROWS.MIN_COUNT, math.min(ARROWS.MAX_COUNT, count))
end

-- Normalises the options table passed to startArrowsGame
function arrowsNormalizeOptions(options)
    options = type(options) == "table" and options or {}
    local speed = tonumber(options.speed) or 1
    local pass = tonumber(options.passPercent) or ARROWS.PASS_PERCENT
    return {
        speed = math.max(ARROWS.MIN_SPEED_MULT, math.min(ARROWS.MAX_SPEED_MULT, speed)),
        passPercent = math.max(0, math.min(100, pass)),
    }
end

function arrowsPercent(hits, total)
    if total <= 0 then return 0 end
    return math.floor(hits / total * 100 + 0.5)
end

function arrowsIsSuccess(hits, total, passPercent)
    return total > 0 and (hits / total * 100) > (passPercent or ARROWS.PASS_PERCENT)
end

-- Loose timing bounds, used by the server to sanity check client results
function arrowsMinDuration(count, speed)
    return ((count - 1) * ARROWS.SPAWN_MIN / speed) * 0.9
end

function arrowsMaxDuration(count, speed)
    return ARROWS.SPAWN_LEAD + (count - 1) * ARROWS.SPAWN_MAX / speed + 10 / speed + ARROWS.RESULT_TIME
end
