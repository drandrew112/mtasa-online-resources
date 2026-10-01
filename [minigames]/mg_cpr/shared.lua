CPR = {
    DEFAULT_DURATION = 30,  -- seconds of compressions (the countdown is not included)
    MIN_DURATION = 5,
    MAX_DURATION = 300,

    MIN_BPM = 90,           -- a compression is good when its rate is inside [MIN_BPM, MAX_BPM]
    MAX_BPM = 130,
    PASS_PERCENT = 70,      -- the game is won when the accuracy is at least this

    KEY = "space",
    COUNTDOWN = 3,          -- seconds of "get ready" before the timer starts
    START_GRACE = 1.5,      -- seconds allowed before the first compression without penalty
    RESULT_TIME = 2.0,      -- seconds the result is shown before the game closes

    ANIM_BLOCK = "MEDIC",
    ANIM_NAME = "CPR",
    PED_SIDE_OFFSET = 0.85,     -- the player is placed this far to the right of the ped...
    PED_FORWARD_OFFSET = 0.0,   -- ...and this far along the ped's forward axis

    TEST_COMMAND = true,    -- /cprtest [seconds] [ped 0/1] for testing, disable in production
}

-- Normalises the options table passed to startCPRGame
function cprNormalizeOptions(options)
    options = type(options) == "table" and options or {}
    local minBPM = math.max(20, math.min(300, tonumber(options.minBPM) or CPR.MIN_BPM))
    local maxBPM = math.max(minBPM + 1, math.min(300, tonumber(options.maxBPM) or CPR.MAX_BPM))
    local pass = tonumber(options.passPercent) or CPR.PASS_PERCENT
    return {
        minBPM = minBPM,
        maxBPM = maxBPM,
        passPercent = math.max(0, math.min(100, pass)),
        guide = options.guide ~= false, -- pulsing rhythm helper on the HUD
    }
end

function cprClampDuration(duration)
    duration = tonumber(duration) or CPR.DEFAULT_DURATION
    return math.max(CPR.MIN_DURATION, math.min(CPR.MAX_DURATION, duration))
end

-- Seconds between two compressions at the middle of the allowed range
function cprTargetInterval(options)
    return 60 / ((options.minBPM + options.maxBPM) / 2)
end

-- "good" | "fast" | "slow" for the time between two presses
function cprClassify(interval, options)
    if interval < 60 / options.maxBPM then return "fast" end
    if interval > 60 / options.minBPM then return "slow" end
    return "good"
end

local function round(x)
    return math.floor(x + 0.5)
end

-- Compressions skipped inside a gap that was closed by a (slow) press
function cprGapMissed(gap, options)
    if gap <= 60 / options.minBPM then return 0 end
    return math.max(0, round(gap / cprTargetInterval(options)) - 1)
end

-- Compressions skipped between the last press and the end of the game
function cprTrailingMissed(gap, options)
    if gap <= 60 / options.minBPM then return 0 end
    return round(gap / cprTargetInterval(options))
end

-- Compressions skipped between the start and the first press
function cprStartMissed(gap, options)
    return round(math.max(0, gap - CPR.START_GRACE) / cprTargetInterval(options))
end

function cprPercent(good, total)
    if total <= 0 then return 0 end
    return math.floor(good / total * 100 + 0.5)
end

function cprIsSuccess(good, total, passPercent)
    return total > 0 and (good / total * 100) >= (passPercent or CPR.PASS_PERCENT)
end

-- Loose bounds, used by the server to sanity check client results
function cprMaxGood(duration, options)
    return math.floor(duration * options.maxBPM / 60 * 1.05) + 2
end

function cprMinTotal(duration, options)
    return math.floor(math.max(0, duration - CPR.START_GRACE) / cprTargetInterval(options) * 0.5)
end
