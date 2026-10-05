SPLINT = {
    DEFAULT_COUNT = 8,     -- bandage wraps needed to secure the splint
    MIN_COUNT = 1,
    MAX_COUNT = 20,

    DEFAULT_TIME = 40,     -- seconds allowed to finish all the wraps (the countdown is not included)
    MIN_TIME = 10,
    MAX_TIME = 120,

    PASS_PERCENT = 70,     -- the game is won when the hit ratio is strictly above this

    NEEDLE_HZ = 0.45,      -- needle oscillations/second at speed = 1
    GOOD_WINDOW = 0.18,    -- half-width (0-1) of the "good" zone around the gauge's centre

    MIN_SPEED_MULT = 0.6,
    MAX_SPEED_MULT = 1.8,

    KEY = "space",
    COUNTDOWN = 3,         -- seconds of "get ready" before the timer starts
    RESULT_TIME = 2.0,     -- seconds the result is shown before the game closes

    ANIM_BLOCK = "BOMBER", -- kneeling animation used next to a ped
    ANIM_NAME = "BOM_Plant_Loop",
    PED_SIDE_OFFSET = 0.85, -- the player is placed this far to the right of the ped...
    PED_FORWARD_OFFSET = 0.2, -- ...and this far along the ped's forward axis

    TEST_COMMAND = true,   -- /splinttest [count] [speed] [ped 0/1] for testing, disable in production
}

function splintClampCount(count)
    count = math.floor(tonumber(count) or SPLINT.DEFAULT_COUNT)
    return math.max(SPLINT.MIN_COUNT, math.min(SPLINT.MAX_COUNT, count))
end

-- Normalises the options table passed to startSplintGame
function splintNormalizeOptions(options)
    options = type(options) == "table" and options or {}
    local speed = tonumber(options.speed) or 1
    local pass = tonumber(options.passPercent) or SPLINT.PASS_PERCENT
    local time = tonumber(options.time) or SPLINT.DEFAULT_TIME
    return {
        speed = math.max(SPLINT.MIN_SPEED_MULT, math.min(SPLINT.MAX_SPEED_MULT, speed)),
        passPercent = math.max(0, math.min(100, pass)),
        time = math.max(SPLINT.MIN_TIME, math.min(SPLINT.MAX_TIME, time)),
    }
end

function splintPercent(hits, total)
    if total <= 0 then return 0 end
    return math.floor(hits / total * 100 + 0.5)
end

function splintIsSuccess(hits, total, passPercent)
    return total > 0 and (hits / total * 100) > (passPercent or SPLINT.PASS_PERCENT)
end

-- Loose lower bound on the play time of a real game, used by the server to sanity check results
function splintMinDuration(count, speed)
    return SPLINT.COUNTDOWN + count * (0.5 / (SPLINT.NEEDLE_HZ * speed)) * 0.5
end
