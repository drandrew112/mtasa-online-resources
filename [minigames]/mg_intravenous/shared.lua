IV = {
    DEFAULT_TIME = 45,      -- seconds for the whole procedure (the countdown is not included)
    MIN_TIME = 10,
    MAX_TIME = 300,
    DEFAULT_ATTEMPTS = 2,   -- punctures allowed before the game is failed
    MAX_ATTEMPTS = 5,
    DEFAULT_DIFFICULTY = 2, -- 1 = easy, 2 = normal, 3 = hard

    -- per difficulty: vein radius (mm), hand tremor (mm), push speed (depth mm/s),
    -- max safe withdraw speed (mm/s)
    DIFFICULTY = {
        { veinRadius = 2.8, tremor = 0.5, pushSpeed = 3.5, pullSpeed = 22 },
        { veinRadius = 2.2, tremor = 0.9, pushSpeed = 4.5, pullSpeed = 16 },
        { veinRadius = 1.7, tremor = 1.4, pushSpeed = 5.5, pullSpeed = 12 },
    },

    VEIN_DEPTH_MIN = 4.0,   -- depth of the vein centre below the skin surface (mm), random per attempt
    VEIN_DEPTH_MAX = 6.0,
    MAX_DEPTH = 12.0,       -- pushing this deep without hitting the vein = missed
    NEEDLE_ANGLE = 25,      -- insertion angle (degrees), used for the insertion length
    NEEDLE_LENGTH = 35,     -- mm the needle has to be pulled back to leave the cannula (tip gap + cannula + hub)
    VIEW_MM = 26,           -- skin width (mm) visible in the top view

    COUNTDOWN = 3,          -- seconds of "get ready" before the timer starts
    FLASHBACK_TIME = 0.6,   -- seconds between a good release and the withdraw phase
    RETRY_TIME = 1.6,       -- seconds the mistake is shown before the next attempt
    RESULT_TIME = 2.0,      -- seconds the result is shown before the game closes

    ANIM_BLOCK = "BOMBER",  -- kneeling animation used next to a ped
    ANIM_NAME = "BOM_Plant_Loop",
    PED_SIDE_OFFSET = 0.85, -- the player is placed this far to the right of the ped...
    PED_FORWARD_OFFSET = 0.2, -- ...and this far along the ped's forward axis

    TEST_COMMAND = true,    -- /ivtest [difficulty] [ped 0/1] for testing, disable in production
}

-- Reasons a client may report (anything else is rejected by the server)
IV_CLIENT_REASONS = {
    completed = true, -- cannula placed, needle removed
    missed = true,    -- needle went past the vein (bad aim) on the last attempt
    through = true,   -- needle pierced the back wall of the vein on the last attempt
    dislodged = true, -- needle pulled too fast, the cannula came out on the last attempt
    expired = true,   -- the time ran out
}

-- Normalises the options table passed to startIVGame
function ivNormalizeOptions(options)
    options = type(options) == "table" and options or {}
    local difficulty = math.floor(tonumber(options.difficulty) or IV.DEFAULT_DIFFICULTY)
    local time = tonumber(options.time) or IV.DEFAULT_TIME
    local attempts = math.floor(tonumber(options.attempts) or IV.DEFAULT_ATTEMPTS)
    return {
        difficulty = math.max(1, math.min(#IV.DIFFICULTY, difficulty)),
        time = math.max(IV.MIN_TIME, math.min(IV.MAX_TIME, time)),
        attempts = math.max(1, math.min(IV.MAX_ATTEMPTS, attempts)),
        showDepth = options.showDepth ~= false, -- vein visible in the cross-section view
    }
end

function ivDifficulty(options)
    return IV.DIFFICULTY[options.difficulty]
end

-- Half height of the vein at a given sideways offset from its centre line (0 = not hit)
function ivVeinChord(radius, offset)
    local d = math.abs(offset)
    if d >= radius then return 0 end
    return math.sqrt(radius * radius - d * d)
end

-- 0-100 quality of a successful cannulation:
-- how centred the puncture was, how deep inside the vein the tip stopped, how gently it was withdrawn
function ivQuality(offset, radius, depthError, chord, peakStress)
    local lateral = math.max(0, 1 - math.abs(offset) / radius)
    local depth = chord > 0 and math.max(0, 1 - math.abs(depthError) / chord) or 0
    local pull = math.max(0, 1 - (peakStress or 0))
    return math.floor((0.4 * lateral + 0.4 * depth + 0.2 * pull) * 100 + 0.5)
end

-- Loose lower bound on the play time of a real game, used by the server to sanity check results
function ivMinDuration(reason, options)
    if reason == "expired" then return IV.COUNTDOWN + options.time * 0.9 end
    return IV.COUNTDOWN + 1.0
end
