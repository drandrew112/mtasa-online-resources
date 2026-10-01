AIRWAY = {
    DEFAULT_DIFFICULTY = "normal",

    -- per difficulty:
    --   tremor      hand tremor of the tube tip (px at 1080p)
    --   drift       how much the larynx wanders around in the scope view
    --   liftMin/Max laryngoscope lift zone (0..1) that gives a clear view
    --   openMin     how far the vocal cords close (1 = always fully open)
    --   spo2Start   fallback SpO2 (%) at the start, spo2Drain = % lost per second - only used when
    --               the patient has no SpO2 element data (e.g. no ped); normally the medic system owns it
    --   maxMistakes mistakes allowed; one more fails the procedure
    --   blood       seconds between blood drops in the view (false = none)
    DIFFICULTY = {
        easy      = { tremor = 4,  drift = 0.4, liftMin = 0.45, liftMax = 0.85, openMin = 0.60, spo2Start = 98, spo2Drain = 0.35, maxMistakes = 3, blood = false },
        normal    = { tremor = 8,  drift = 0.8, liftMin = 0.55, liftMax = 0.80, openMin = 0.30, spo2Start = 96, spo2Drain = 0.50, maxMistakes = 2, blood = false },
        hard      = { tremor = 13, drift = 1.3, liftMin = 0.60, liftMax = 0.77, openMin = 0.20, spo2Start = 94, spo2Drain = 0.65, maxMistakes = 1, blood = 6.0 },
        nightmare = { tremor = 18, drift = 1.8, liftMin = 0.63, liftMax = 0.75, openMin = 0.12, spo2Start = 91, spo2Drain = 0.80, maxMistakes = 0, blood = 3.5 },
    },

    -- Vitals are read from the patient ped's element data (written by the medic system).
    SPO2_DATA = "spo2",     -- number, 0-100
    HR_DATA = "heartRate",  -- number, optional (only shown on the HUD)
    FAIL_SPO2 = 80,         -- the procedure fails when the SpO2 drops below this
    MAX_TIME = 180,         -- hard limit in seconds (when the medic system keeps the SpO2 up)
    COUNTDOWN = 3,          -- seconds of "get ready" before the procedure starts
    RESULT_TIME = 3.0,      -- seconds the result is shown before the game closes
    MIN_TIME = 5,           -- fastest plausible successful intubation (server sanity check)
    PAR_TIME = 15,          -- seconds; slower than this costs score

    KEY_ACTION = "space",   -- lift / push tube / inflate cuff
    KEY_BACK = "s",         -- pull tube back / deflate cuff
    KEY_SUCTION = "e",      -- suction blood out of the view

    -- phase 1: laryngoscope
    LIFT_UP = 0.45,         -- lift gained per second while holding
    LIFT_DOWN = 0.60,       -- lift lost per second when released
    LIFT_TOOTH = 0.93,      -- levering this hard chips a tooth
    LIFT_HOLD = 1.5,        -- seconds in the zone needed

    -- phase 2: passing the vocal cords
    CORD_CYCLE = 3.2,       -- seconds for a full open/close cycle of the cords
    CORD_PASSABLE = 0.45,   -- cords must be at least this open to pass the tube
    PASS_SPEED = 0.65,      -- progress per second while the tip is in the opening
    ESOPHAGUS_SPEED = 0.9,  -- progress into the oesophagus per second (1 = mistake)
    TRAUMA_SPEED = 1.1,     -- tissue trauma per second when pushing against tissue (1 = mistake)

    -- phase 3: tube depth (cm at the teeth)
    DEPTH_START = 16,
    DEPTH_MIN = 20.5,
    DEPTH_MAX = 23.5,
    DEPTH_BRONCHUS = 25.5,  -- right mainstem intubation
    DEPTH_RESET = 19,
    DEPTH_SPEED = 2.6,      -- cm per second

    -- phase 4: cuff pressure (cmH2O)
    CUFF_MIN = 20,
    CUFF_MAX = 30,
    CUFF_BURST = 40,        -- overinflation damages the tracheal mucosa
    CUFF_UP = 14,
    CUFF_DOWN = 20,
    CUFF_LEAK = 0.6,

    LOCK_TIME = 0.8,        -- seconds released inside the zone to confirm depth / cuff

    ANIM_BLOCK = "BOMBER",  -- kneeling animation used at the patient's head
    ANIM_NAME = "BOM_Plant_Loop",
    HEAD_OFFSET = 0.75,     -- the player is placed this far behind the patient's head

    TEST_COMMAND = true,    -- /airwaytest [difficulty] [0] - disable in production
}

AIRWAY_MISTAKES = {
    teeth = "Chipped tooth",
    trauma = "Airway trauma",
    esophageal = "Oesophageal intubation",
    bronchus = "Right mainstem intubation",
    cuff = "Cuff overinflated",
}

-- Normalises the options table passed to startAirwayGame:
-- { difficulty = "normal", spo2Start, spo2Drain, maxMistakes, blood }
-- liveSpO2 is internal: set when the patient's SpO2 comes from element data
function airwayNormalizeOptions(options)
    options = type(options) == "table" and options or {}
    local name = AIRWAY.DIFFICULTY[options.difficulty] and options.difficulty or AIRWAY.DEFAULT_DIFFICULTY
    local preset = AIRWAY.DIFFICULTY[name]

    local result = { difficulty = name, liveSpO2 = options.liveSpO2 == true }
    for k, v in pairs(preset) do result[k] = v end

    if tonumber(options.spo2Start) then
        result.spo2Start = math.max(AIRWAY.FAIL_SPO2 + 2, math.min(100, tonumber(options.spo2Start)))
    end
    if tonumber(options.spo2Drain) then
        result.spo2Drain = math.max(0.05, math.min(5, tonumber(options.spo2Drain)))
    end
    if tonumber(options.maxMistakes) then
        result.maxMistakes = math.max(0, math.min(10, math.floor(tonumber(options.maxMistakes))))
    end
    if options.blood == false then
        result.blood = false
    elseif tonumber(options.blood) then
        result.blood = math.max(1, tonumber(options.blood))
    end
    return result
end

-- The patient's SpO2 from element data, or nil
function airwayGetPatientSpO2(ped)
    if not isElement(ped) then return nil end
    return tonumber(getElementData(ped, AIRWAY.SPO2_DATA))
end

-- Fallback simulation (no element data): seconds until the SpO2 drops below FAIL_SPO2
function airwayTimeLimit(options)
    return (options.spo2Start - AIRWAY.FAIL_SPO2) / options.spo2Drain
end

function airwaySpO2(options, t)
    return math.max(0, options.spo2Start - options.spo2Drain * math.max(0, t))
end

function airwayCountMistakes(details)
    local n = 0
    for key in pairs(AIRWAY_MISTAKES) do
        n = n + (tonumber(details[key]) or 0)
    end
    return n
end

-- 0-100, only meaningful for a successful intubation
function airwayScore(time, mistakes)
    local score = 100 - mistakes * 15 - math.max(0, time - AIRWAY.PAR_TIME) * 2
    return math.floor(math.max(10, math.min(100, score)) + 0.5)
end

function airwayClamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end
